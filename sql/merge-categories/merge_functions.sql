-- DHIS2 Metadata Deduplication — SQL Merge Functions
--
-- Run against the DHIS2 PostgreSQL database directly.
-- Usage:  psql -d <dbname> -f sql/merge_functions.sql
--         then call the functions as needed.
--
-- Always run inside a transaction so you can roll back on error:
--   BEGIN;
--   SELECT co_dup_merge('masterUID', ARRAY['dupUID1','dupUID2']);
--   -- inspect, then COMMIT or ROLLBACK;
--
-- Functions in this file:
--
--  DIAGNOSTIC (category level)
--   cat_dup_list()
--     Lists categories sharing the same sorted set of categoryOption IDs
--     (functionally identical categories even if they have different names).
--   cat_dup_count(cat_id_keep int, cat_id_remove int)
--     Shows the number of references to each of two categories across all
--     FK-dependent tables.
--
--  DIAGNOSTIC (categoryCombo level)
--   cc_dup_list()
--     Lists categoryCombos sharing the same sorted set of category IDs
--     (functionally identical combos).
--   cc_dup_count(cc_id_keep int, cc_id_remove int)
--     Shows the number of references to each of two categoryCombos across
--     all FK-dependent tables.
--
--  DIAGNOSTIC (categoryOptionCombo level)
--   coc_dup_list()
--     Lists all duplicate COCs (same option set) within each categoryCombo.
--   coc_dup_count(coc_id_keep int, coc_id_remove int)
--     Shows the number of references to each of two COCs across all tables,
--     plus merge-conflict counts.
--
--  MERGE (categoryOptionCombo level)
--   coc_dup_merge(coc_id_keep int, coc_id_remove int)
--     Merges two duplicate COC rows into one. Handles datavalues (conflict
--     resolution, keeping the most recent), expressions, indicators,
--     program indicators, data entry forms, validation rules, and all FK
--     references. Works on DHIS2 >= 2.36; handles all event-table generations
--     (programstageinstance, event, and 2.43's trackerevent/singleevent).
--
--  MERGE (higher-level metadata)
--   co_dup_merge(master_uid text, duplicate_uids text[])
--     Merges categoryOption rows: redirects all FK references then deletes.
--   cat_dup_merge(master_uid text, duplicate_uids text[])
--     Merges category (dataElementCategory) rows.
--   cc_dup_merge(master_uid text, duplicate_uids text[])
--     Merges categoryCombo rows, matching and merging their COCs first.


-- ─────────────────────────────────────────────────────────────────────────────
-- Helper aggregates: FIRST / LAST
-- Used to pick the first/last non-null value from a sorted set.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION first_element_state(ANYARRAY, ANYELEMENT)
    RETURNS ANYARRAY
    LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN array_upper($1,1) IS NULL THEN array_append($1,$2) ELSE $1 END;
$$;

CREATE OR REPLACE FUNCTION first_element(ANYARRAY)
    RETURNS ANYELEMENT
    LANGUAGE sql IMMUTABLE AS $$
    SELECT ($1)[1];
$$;

CREATE OR REPLACE FUNCTION last_element(ANYELEMENT, ANYELEMENT)
    RETURNS ANYELEMENT
    LANGUAGE sql IMMUTABLE AS $$
    SELECT $2;
$$;

CREATE OR REPLACE AGGREGATE first(ANYELEMENT) (
    SFUNC    = first_element_state,
    STYPE    = ANYARRAY,
    FINALFUNC = first_element
);

CREATE OR REPLACE AGGREGATE last(ANYELEMENT) (
    SFUNC = last_element,
    STYPE = ANYELEMENT
);


-- ─────────────────────────────────────────────────────────────────────────────
-- d2_dependencies(dep_table, dep_column)
-- Lists every table and column that has a FK pointing at the given table/column.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION d2_dependencies(dep_table text, dep_column text)
    RETURNS TABLE(dep_tbl text, dep_col text)
    LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        (SELECT r.relname FROM pg_class r WHERE r.oid = c.conrelid)::text,
        (SELECT array_agg(attname) FROM pg_attribute
         WHERE attrelid = c.conrelid AND ARRAY[attnum] <@ c.conkey)[1]::text
    FROM pg_constraint c
    WHERE c.confrelid = (SELECT oid FROM pg_class WHERE relname = dep_table)
      AND c.confkey @> (
          SELECT array_agg(attnum) FROM pg_attribute
          WHERE attname = dep_column AND attrelid = c.confrelid
      );
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- cat_dup_list()
-- Returns categories that have the same sorted set of categoryOption IDs —
-- functionally identical categories regardless of name.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION cat_dup_list()
    RETURNS TABLE(category_name text, cat_uid varchar, cat_id bigint,
                  cat_code varchar, member_options text)
    LANGUAGE plpgsql AS $$
DECLARE
    cat_table text;
BEGIN
    -- Table renamed from dataelementcategory to category in DHIS2 2.38
    SELECT CASE WHEN EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='category')
                THEN 'category' ELSE 'dataelementcategory' END
    INTO cat_table;

    RETURN QUERY EXECUTE format(
        'WITH members AS (
            SELECT categoryid,
                   array_to_string(array_agg(categoryoptionid ORDER BY categoryoptionid), '','') AS opts
            FROM   categories_categoryoptions
            GROUP  BY categoryid
        )
        SELECT c.name::text, c.uid::varchar, c.categoryid, c.code::varchar, m.opts
        FROM   members m
        JOIN   %I c USING (categoryid)
        WHERE  m.opts IN (
                   SELECT opts FROM members GROUP BY opts HAVING count(*) > 1
               )
        ORDER BY m.opts, c.categoryid',
        cat_table
    );
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- cat_dup_count(cat_id_keep, cat_id_remove)
-- Shows reference counts for two categories across all FK tables.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION cat_dup_count(cat_id_keep int, cat_id_remove int)
    RETURNS TABLE(description text, keep_count int, remove_count int)
    LANGUAGE plpgsql AS $$
DECLARE
    cat_table text;
    exists_count int;
BEGIN
    -- Table renamed from dataelementcategory to category in DHIS2 2.38
    SELECT CASE WHEN EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='category')
                THEN 'category' ELSE 'dataelementcategory' END
    INTO cat_table;

    EXECUTE format('SELECT count(*) FROM %I WHERE categoryid IN ($1,$2)', cat_table)
    INTO exists_count USING $1, $2;

    IF exists_count != 2 THEN
        RAISE WARNING 'One or both category IDs not found: % %', $1, $2;
        RETURN;
    END IF;

    RETURN QUERY SELECT '[*** categoryids ***]', $1::int, $2::int;

    RETURN QUERY SELECT 'categories_categoryoptions (option memberships)',
        (SELECT count(*)::int FROM categories_categoryoptions WHERE categoryid = $1),
        (SELECT count(*)::int FROM categories_categoryoptions WHERE categoryid = $2);

    RETURN QUERY SELECT 'categorycombos_categories (combo memberships)',
        (SELECT count(*)::int FROM categorycombos_categories WHERE categoryid = $1),
        (SELECT count(*)::int FROM categorycombos_categories WHERE categoryid = $2);

    RETURN QUERY SELECT 'categorydimension (visualization filters)',
        (SELECT count(*)::int FROM categorydimension WHERE categoryid = $1),
        (SELECT count(*)::int FROM categorydimension WHERE categoryid = $2);

    RETURN QUERY SELECT 'users_catdimensionconstraints (user restrictions)',
        (SELECT count(*)::int FROM users_catdimensionconstraints WHERE dataelementcategoryid = $1),
        (SELECT count(*)::int FROM users_catdimensionconstraints WHERE dataelementcategoryid = $2);
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- cc_dup_list()
-- Returns categoryCombos that have the same sorted set of category IDs —
-- functionally identical combos regardless of name.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION cc_dup_list()
    RETURNS TABLE(combo_name text, cc_uid varchar, cc_id bigint,
                  cc_code varchar, member_categories text)
    LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    WITH members AS (
        SELECT categorycomboid,
               array_to_string(array_agg(categoryid ORDER BY categoryid), ',') AS cats
        FROM   categorycombos_categories
        GROUP  BY categorycomboid
    )
    SELECT cc.name::text, cc.uid::varchar, cc.categorycomboid, cc.code::varchar, m.cats
    FROM   members m
    JOIN   categorycombo cc USING (categorycomboid)
    WHERE  m.cats IN (
               SELECT cats FROM members GROUP BY cats HAVING count(*) > 1
           )
    ORDER BY m.cats, cc.categorycomboid;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- cc_dup_count(cc_id_keep, cc_id_remove)
-- Shows reference counts for two categoryCombos across all FK tables.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION cc_dup_count(cc_id_keep int, cc_id_remove int)
    RETURNS TABLE(description text, keep_count int, remove_count int)
    LANGUAGE plpgsql AS $$
DECLARE
    has_pi_combos boolean;
BEGIN
    IF (SELECT count(*) FROM categorycombo WHERE categorycomboid IN ($1,$2)) != 2 THEN
        RAISE WARNING 'One or both categoryCombo IDs not found: % %', $1, $2;
        RETURN;
    END IF;

    -- programindicator.categorycomboid only exists in DHIS2 >= ~2.41 (sl)
    SELECT EXISTS(
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'programindicator' AND column_name = 'categorycomboid'
    ) INTO has_pi_combos;

    RETURN QUERY SELECT '[*** categorycomboids ***]', $1::int, $2::int;

    RETURN QUERY SELECT 'categorycombos_categories (category members)',
        (SELECT count(*)::int FROM categorycombos_categories WHERE categorycomboid = $1),
        (SELECT count(*)::int FROM categorycombos_categories WHERE categorycomboid = $2);

    RETURN QUERY SELECT 'categorycombos_optioncombos (COC members)',
        (SELECT count(*)::int FROM categorycombos_optioncombos WHERE categorycomboid = $1),
        (SELECT count(*)::int FROM categorycombos_optioncombos WHERE categorycomboid = $2);

    RETURN QUERY SELECT 'dataelement',
        (SELECT count(*)::int FROM dataelement WHERE categorycomboid = $1),
        (SELECT count(*)::int FROM dataelement WHERE categorycomboid = $2);

    RETURN QUERY SELECT 'dataset',
        (SELECT count(*)::int FROM dataset WHERE categorycomboid = $1),
        (SELECT count(*)::int FROM dataset WHERE categorycomboid = $2);

    RETURN QUERY SELECT 'datasetelement (override combos)',
        (SELECT count(*)::int FROM datasetelement WHERE categorycomboid = $1),
        (SELECT count(*)::int FROM datasetelement WHERE categorycomboid = $2);

    RETURN QUERY SELECT 'program',
        (SELECT count(*)::int FROM program WHERE categorycomboid = $1),
        (SELECT count(*)::int FROM program WHERE categorycomboid = $2);

    IF has_pi_combos THEN
        RETURN QUERY EXECUTE
            'SELECT ''programindicator (categorycomboid)'',
             (SELECT count(*)::int FROM programindicator WHERE categorycomboid = $1),
             (SELECT count(*)::int FROM programindicator WHERE categorycomboid = $2)'
        USING $1, $2;

        RETURN QUERY EXECUTE
            'SELECT ''programindicator (attributecomboid)'',
             (SELECT count(*)::int FROM programindicator WHERE attributecomboid = $1),
             (SELECT count(*)::int FROM programindicator WHERE attributecomboid = $2)'
        USING $1, $2;
    END IF;

    RETURN QUERY SELECT 'dataapprovalworkflow',
        (SELECT count(*)::int FROM dataapprovalworkflow WHERE categorycomboid = $1),
        (SELECT count(*)::int FROM dataapprovalworkflow WHERE categorycomboid = $2);
END;
$$;




CREATE OR REPLACE FUNCTION coc_dup_list()
    RETURNS TABLE(categorycombo varchar, cc_uid varchar,
                  categoryoptioncombo text, coc_uid varchar, coc_id bigint)
    LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    WITH m AS (
        SELECT k.categorycomboid, k.categoryoptioncomboid,
               array_to_string(array_agg(k.categoryoptionid ORDER BY k.categoryoptionid), ',') AS members
        FROM (
            SELECT j.categorycomboid, i.categoryoptioncomboid, i.categoryoptionid
            FROM   categoryoptioncombos_categoryoptions i
            JOIN   categorycombos_optioncombos j
                   ON i.categoryoptioncomboid = j.categoryoptioncomboid
            ORDER BY categorycomboid, categoryoptioncomboid, categoryoptionid
        ) k
        GROUP BY categorycomboid, categoryoptioncomboid
        ORDER BY members
    )
    SELECT cc.name::varchar, cc.uid::varchar,
           coc.name::text,  coc.uid::varchar, coc.categoryoptioncomboid
    FROM m
    JOIN (
        SELECT x.categorycomboid, x.members
        FROM (
            SELECT b.categorycomboid,
                   array_to_string(array_agg(a.categoryoptionid ORDER BY a.categoryoptionid), ',') AS members
            FROM   categoryoptioncombos_categoryoptions a
            JOIN   categorycombos_optioncombos b
                   ON a.categoryoptioncomboid = b.categoryoptioncomboid
            GROUP BY b.categorycomboid, b.categoryoptioncomboid
        ) x
        GROUP BY x.categorycomboid, x.members
        HAVING COUNT(*) > 1
    ) n ON m.categorycomboid = n.categorycomboid AND m.members = n.members
    JOIN categorycombo cc ON m.categorycomboid = cc.categorycomboid
    JOIN categoryoptioncombo coc ON m.categoryoptioncomboid = coc.categoryoptioncomboid;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- coc_dup_count(coc_uid_keep, coc_uid_remove)
-- Shows reference counts and potential merge conflicts for two COCs.
-- Accepts UIDs (character varying(11)).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION coc_dup_count(coc_uid_keep text, coc_uid_remove text)
    RETURNS TABLE(description text, first_coc text, second_coc text)
    LANGUAGE plpgsql AS $$
DECLARE
    deps           record;
    coc_id_keep    bigint;
    coc_id_remove  bigint;
BEGIN
    SELECT categoryoptioncomboid INTO coc_id_keep   FROM categoryoptioncombo WHERE uid = $1;
    SELECT categoryoptioncomboid INTO coc_id_remove FROM categoryoptioncombo WHERE uid = $2;

    IF coc_id_keep IS NULL OR coc_id_remove IS NULL THEN
        RAISE WARNING 'One or both COC UIDs not found: % %', $1, $2;
        RETURN;
    END IF;

    RETURN QUERY SELECT '[*** coc uids ***]', $1::text, $2::text;

    FOR deps IN SELECT * FROM d2_dependencies('categoryoptioncombo','categoryoptioncomboid') LOOP
        RETURN QUERY EXECUTE format(
            'SELECT %L, (SELECT count(*)::text FROM %I WHERE %I = %s),
                        (SELECT count(*)::text FROM %I WHERE %I = %s)',
            deps.dep_tbl,
            deps.dep_tbl, deps.dep_col, coc_id_keep,
            deps.dep_tbl, deps.dep_col, coc_id_remove
        );
    END LOOP;

    -- indirect dependencies via dataelementoperand
    RETURN QUERY
    SELECT 'datasetoperands',
        (SELECT count(*)::text FROM datasetoperands
         WHERE dataelementoperandid IN (
             SELECT dataelementoperandid FROM dataelementoperand WHERE categoryoptioncomboid = coc_id_keep)),
        (SELECT count(*)::text FROM datasetoperands
         WHERE dataelementoperandid IN (
             SELECT dataelementoperandid FROM dataelementoperand WHERE categoryoptioncomboid = coc_id_remove));

    RETURN QUERY
    SELECT 'sectiongreyedfields',
        (SELECT count(*)::text FROM sectiongreyedfields
         WHERE dataelementoperandid IN (
             SELECT dataelementoperandid FROM dataelementoperand WHERE categoryoptioncomboid = coc_id_keep)),
        (SELECT count(*)::text FROM sectiongreyedfields
         WHERE dataelementoperandid IN (
             SELECT dataelementoperandid FROM dataelementoperand WHERE categoryoptioncomboid = coc_id_remove));

    -- implicit (UID-based) dependencies
    RETURN QUERY
    SELECT '[uid] dataentryform (html)',
        (SELECT count(*)::text FROM dataentryform WHERE htmlcode LIKE '%' || $1 || '%'),
        (SELECT count(*)::text FROM dataentryform WHERE htmlcode LIKE '%' || $2 || '%');

    RETURN QUERY
    SELECT '[uid] indicator (numerator/denominator)',
        (SELECT count(*)::text FROM indicator
         WHERE numerator LIKE '%'||$1||'%' OR denominator LIKE '%'||$1||'%'),
        (SELECT count(*)::text FROM indicator
         WHERE numerator LIKE '%'||$2||'%' OR denominator LIKE '%'||$2||'%');

    RETURN QUERY
    SELECT '[uid] indicator (aggregateExportCategoryOptionCombo)',
        (SELECT count(*)::text FROM indicator WHERE aggregateexportcategoryoptioncombo = $1),
        (SELECT count(*)::text FROM indicator WHERE aggregateexportcategoryoptioncombo = $2);

    RETURN QUERY
    SELECT '[uid] programIndicator (aggregateExportCategoryOptionCombo)',
        (SELECT count(*)::text FROM programindicator WHERE aggregateexportcategoryoptioncombo = $1),
        (SELECT count(*)::text FROM programindicator WHERE aggregateexportcategoryoptioncombo = $2);

    RETURN QUERY
    SELECT '[uid] expression (predictor/validationRule)',
        (SELECT count(*)::text FROM expression WHERE expression LIKE '%'||$1||'%'),
        (SELECT count(*)::text FROM expression WHERE expression LIKE '%'||$2||'%');

    -- merge conflict counts
    RETURN QUERY
    SELECT '[conflicts] validationresult',
        count(vr1.*)::text, count(vr1.*)::text
    FROM validationresult vr1
    JOIN validationresult vr2 USING (validationruleid, periodid, organisationunitid, dayinperiod)
    WHERE vr1.attributeoptioncomboid = coc_id_remove AND vr2.attributeoptioncomboid = coc_id_keep;

    RETURN QUERY
    SELECT '[conflicts] dataapproval',
        count(da1.*)::text, count(da1.*)::text
    FROM dataapproval da1
    JOIN dataapproval da2 USING (dataapprovallevelid, workflowid, periodid, organisationunitid)
    WHERE da1.attributeoptioncomboid = coc_id_remove AND da2.attributeoptioncomboid = coc_id_keep;

    RETURN QUERY
    SELECT '[conflicts] completedatasetregistration',
        count(cds1.*)::text, count(cds1.*)::text
    FROM completedatasetregistration cds1
    JOIN completedatasetregistration cds2 USING (datasetid, periodid, sourceid)
    WHERE cds1.attributeoptioncomboid = coc_id_remove AND cds2.attributeoptioncomboid = coc_id_keep;

    RETURN QUERY
    SELECT '[conflicts] datavalue',
        count(dv1.*)::text, count(dv1.*)::text
    FROM datavalue dv1
    JOIN datavalue dv2 USING (dataelementid, periodid, sourceid)
    WHERE (dv1.categoryoptioncomboid  = coc_id_remove AND dv2.categoryoptioncomboid  = coc_id_keep AND dv1.attributeoptioncomboid = dv2.attributeoptioncomboid)
       OR (dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep AND dv1.categoryoptioncomboid  = dv2.categoryoptioncomboid)
       OR (dv1.categoryoptioncomboid  = coc_id_remove AND dv2.categoryoptioncomboid  = coc_id_keep AND dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep)
       OR (dv1.categoryoptioncomboid  = coc_id_keep   AND dv2.categoryoptioncomboid  = coc_id_remove AND dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep);

    RETURN QUERY
    SELECT '[conflicts] datavalue (different values)',
        count(dv1.*)::text, count(dv1.*)::text
    FROM datavalue dv1
    JOIN datavalue dv2 USING (dataelementid, periodid, sourceid)
    WHERE dv1.value != dv2.value
      AND ((dv1.categoryoptioncomboid  = coc_id_remove AND dv2.categoryoptioncomboid  = coc_id_keep AND dv1.attributeoptioncomboid = dv2.attributeoptioncomboid)
        OR (dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep AND dv1.categoryoptioncomboid  = dv2.categoryoptioncomboid)
        OR (dv1.categoryoptioncomboid  = coc_id_remove AND dv2.categoryoptioncomboid  = coc_id_keep AND dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep)
        OR (dv1.categoryoptioncomboid  = coc_id_keep   AND dv2.categoryoptioncomboid  = coc_id_remove AND dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep));
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- coc_dup_merge(coc_uid_keep, coc_uids_remove)
-- Merges one or more source categoryOptionCombos into a target.
--
-- Pre-conditions (validated before any changes are made):
--   • target COC must exist
--   • target must not appear in the source list
--   • each source must exist
--   • each source must belong to the same categoryCombo as the target
--   • each source must have the same set of categoryOptions as the target
--     (this is DHIS2 COC equality: same members → true duplicates)
--
-- Handles: datavalue (LAST_UPDATED conflict resolution), datavalueaudit,
-- completedatasetregistration, dataapproval, dataapprovalaudit,
-- validationresult, minmaxdataelement, dataelementoperand, datadimensionitem,
-- event/programstageinstance (attributeOptionCombo), smscodes, predictor,
-- dataentryform (UID in HTML), indicator and programindicator expressions,
-- expression table (predictor/validationRule formulas).
--
-- Compatible with DHIS2 >= 2.36. Handles all event-table generations
-- (programstageinstance, event, and 2.43's trackerevent/singleevent).
--
-- Returns TRUE on success, FALSE if pre-conditions are not met.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION coc_dup_merge(
    coc_uid_keep    text,
    coc_uids_remove text[]
)
    RETURNS bool
    LANGUAGE plpgsql AS $$
DECLARE
    coc_id_keep    bigint;
    coc_id_remove  bigint;
    uid_remove     text;
    event_table    text;
    keep_combo     bigint;
    remove_combo   bigint;
    keep_opts      bigint[];
    remove_opts    bigint[];
BEGIN
    -- ── RESOLVE TARGET ────────────────────────────────────────────────────────
    SELECT categoryoptioncomboid INTO coc_id_keep
    FROM categoryoptioncombo WHERE uid = coc_uid_keep;

    IF NOT FOUND THEN
        RAISE WARNING 'Target COC not found: %', coc_uid_keep;
        RETURN FALSE;
    END IF;

    IF coc_uid_keep = ANY(coc_uids_remove) THEN
        RAISE WARNING 'Target COC % is also in source list', coc_uid_keep;
        RETURN FALSE;
    END IF;

    SELECT categorycomboid INTO keep_combo
    FROM categorycombos_optioncombos WHERE categoryoptioncomboid = coc_id_keep;

    keep_opts := ARRAY(
        SELECT categoryoptionid
        FROM categoryoptioncombos_categoryoptions
        WHERE categoryoptioncomboid = coc_id_keep
        ORDER BY categoryoptionid
    );

    -- ── VALIDATE ALL SOURCES BEFORE TOUCHING ANYTHING ─────────────────────────
    FOREACH uid_remove IN ARRAY coc_uids_remove LOOP
        SELECT categoryoptioncomboid INTO coc_id_remove
        FROM categoryoptioncombo WHERE uid = uid_remove;

        IF NOT FOUND THEN
            RAISE WARNING 'Source COC not found: %', uid_remove;
            RETURN FALSE;
        END IF;

        SELECT categorycomboid INTO remove_combo
        FROM categorycombos_optioncombos WHERE categoryoptioncomboid = coc_id_remove;

        IF keep_combo IS DISTINCT FROM remove_combo THEN
            RAISE WARNING 'Source COC % belongs to a different categoryCombo than target %',
                uid_remove, coc_uid_keep;
            RETURN FALSE;
        END IF;

        remove_opts := ARRAY(
            SELECT categoryoptionid
            FROM categoryoptioncombos_categoryoptions
            WHERE categoryoptioncomboid = coc_id_remove
            ORDER BY categoryoptionid
        );

        IF keep_opts != remove_opts THEN
            RAISE WARNING 'Source COC % has different categoryOptions than target %',
                uid_remove, coc_uid_keep;
            RETURN FALSE;
        END IF;
    END LOOP;

    -- ── MERGE EACH SOURCE INTO TARGET ─────────────────────────────────────────
    -- Nested block creates an implicit savepoint; any unexpected error rolls back
    -- ALL writes in this block before re-raising.
    BEGIN
    FOREACH uid_remove IN ARRAY coc_uids_remove LOOP

        SELECT categoryoptioncomboid INTO coc_id_remove
        FROM categoryoptioncombo WHERE uid = uid_remove;

        RAISE NOTICE 'Merging % (id=%) -> % (id=%)',
            uid_remove, coc_id_remove, coc_uid_keep, coc_id_keep;

        -- ── DATAVALUES ────────────────────────────────────────────────────────
        -- Pre-materialise source rows once (avoids repeated full-table scans;
        -- datavalue has no standalone index on categoryoptioncomboid).
        DROP TABLE IF EXISTS _dv_src;
        CREATE TEMP TABLE _dv_src ON COMMIT DROP AS
            SELECT * FROM datavalue
            WHERE categoryoptioncomboid  = coc_id_remove
               OR attributeoptioncomboid = coc_id_remove;
        RAISE NOTICE 'datavalue: % source rows; removing deleted/duplicate rows',
            (SELECT COUNT(*) FROM _dv_src);

        -- Remove rows where either copy is already soft-deleted.
        -- dv1 comes from the small _dv_src; JOIN uses first-3-col PK prefix → fast.
        DELETE FROM datavalue
        WHERE deleted = true
          AND (dataelementid, periodid, sourceid, categoryoptioncomboid, attributeoptioncomboid) IN (
              SELECT dv1.dataelementid, dv1.periodid, dv1.sourceid,
                     dv1.categoryoptioncomboid, dv1.attributeoptioncomboid
              FROM _dv_src dv1
              JOIN datavalue dv2 USING (dataelementid, periodid, sourceid)
              WHERE (dv1.deleted = true OR dv2.deleted = true)
                AND ((dv1.categoryoptioncomboid  = coc_id_remove AND dv2.categoryoptioncomboid  = coc_id_keep AND dv1.attributeoptioncomboid = dv2.attributeoptioncomboid)
                  OR (dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep AND dv1.categoryoptioncomboid  = dv2.categoryoptioncomboid)
                  OR (dv1.categoryoptioncomboid  = coc_id_remove AND dv2.categoryoptioncomboid  = coc_id_keep AND dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep)
                  OR (dv1.categoryoptioncomboid  = coc_id_keep   AND dv2.categoryoptioncomboid  = coc_id_remove AND dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep))
              UNION ALL
              SELECT dv2.dataelementid, dv2.periodid, dv2.sourceid,
                     dv2.categoryoptioncomboid, dv2.attributeoptioncomboid
              FROM _dv_src dv1
              JOIN datavalue dv2 USING (dataelementid, periodid, sourceid)
              WHERE (dv1.deleted = true OR dv2.deleted = true)
                AND ((dv1.categoryoptioncomboid  = coc_id_remove AND dv2.categoryoptioncomboid  = coc_id_keep AND dv1.attributeoptioncomboid = dv2.attributeoptioncomboid)
                  OR (dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep AND dv1.categoryoptioncomboid  = dv2.categoryoptioncomboid)
                  OR (dv1.categoryoptioncomboid  = coc_id_remove AND dv2.categoryoptioncomboid  = coc_id_keep AND dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep)
                  OR (dv1.categoryoptioncomboid  = coc_id_keep   AND dv2.categoryoptioncomboid  = coc_id_remove AND dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep))
          );

        -- Remove source rows where both copies have the same value (keep either one)
        DELETE FROM datavalue
        WHERE (dataelementid, periodid, sourceid, categoryoptioncomboid, attributeoptioncomboid) IN (
            SELECT dv1.dataelementid, dv1.periodid, dv1.sourceid,
                   dv1.categoryoptioncomboid, dv1.attributeoptioncomboid
            FROM _dv_src dv1
            JOIN datavalue dv2 USING (dataelementid, periodid, sourceid, value)
            WHERE ((dv1.categoryoptioncomboid  = coc_id_remove AND dv2.categoryoptioncomboid  = coc_id_keep AND dv1.attributeoptioncomboid = dv2.attributeoptioncomboid)
                OR (dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep AND dv1.categoryoptioncomboid  = dv2.categoryoptioncomboid)
                OR (dv1.categoryoptioncomboid  = coc_id_remove AND dv2.categoryoptioncomboid  = coc_id_keep AND dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep)
                OR (dv1.categoryoptioncomboid  = coc_id_keep   AND dv2.categoryoptioncomboid  = coc_id_remove AND dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep))
            ORDER BY dv1.dataelementid, dv1.periodid, dv1.sourceid, dv1.lastupdated
        );

        -- Conflicting values: keep most recently updated, discard the other.
        -- Refresh _dv_src first to exclude already-deleted rows.
        DELETE FROM _dv_src s
        WHERE NOT EXISTS (
            SELECT 1 FROM datavalue dv
            WHERE  dv.dataelementid         = s.dataelementid
              AND  dv.periodid              = s.periodid
              AND  dv.sourceid              = s.sourceid
              AND  dv.categoryoptioncomboid  = s.categoryoptioncomboid
              AND  dv.attributeoptioncomboid = s.attributeoptioncomboid
              AND  (dv.categoryoptioncomboid = coc_id_remove OR dv.attributeoptioncomboid = coc_id_remove)
        );

        RAISE NOTICE 'datavalue: resolving value conflicts (keeping most recent)';
        DROP TABLE IF EXISTS _dv_duplicates;
        CREATE TEMP TABLE _dv_duplicates (LIKE datavalue) ON COMMIT DROP;

        INSERT INTO _dv_duplicates
        SELECT dv1.*
        FROM _dv_src dv1
        JOIN datavalue dv2 USING (dataelementid, periodid, sourceid)
        WHERE dv1.value != dv2.value
          AND ((dv1.categoryoptioncomboid  = coc_id_remove AND dv2.categoryoptioncomboid  = coc_id_keep AND dv1.attributeoptioncomboid = dv2.attributeoptioncomboid)
            OR (dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep AND dv1.categoryoptioncomboid  = dv2.categoryoptioncomboid)
            OR (dv1.categoryoptioncomboid  = coc_id_remove AND dv2.categoryoptioncomboid  = coc_id_keep AND dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep)
            OR (dv1.categoryoptioncomboid  = coc_id_keep   AND dv2.categoryoptioncomboid  = coc_id_remove AND dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep));

        INSERT INTO _dv_duplicates
        SELECT dv2.*
        FROM _dv_src dv1
        JOIN datavalue dv2 USING (dataelementid, periodid, sourceid)
        WHERE dv1.value != dv2.value
          AND ((dv1.categoryoptioncomboid  = coc_id_remove AND dv2.categoryoptioncomboid  = coc_id_keep AND dv1.attributeoptioncomboid = dv2.attributeoptioncomboid)
            OR (dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep AND dv1.categoryoptioncomboid  = dv2.categoryoptioncomboid)
            OR (dv1.categoryoptioncomboid  = coc_id_remove AND dv2.categoryoptioncomboid  = coc_id_keep AND dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep)
            OR (dv1.categoryoptioncomboid  = coc_id_keep   AND dv2.categoryoptioncomboid  = coc_id_remove AND dv1.attributeoptioncomboid = coc_id_remove AND dv2.attributeoptioncomboid = coc_id_keep));

        DELETE FROM datavalue
        WHERE (dataelementid, periodid, sourceid, categoryoptioncomboid, attributeoptioncomboid) IN (
            SELECT dataelementid, periodid, sourceid, categoryoptioncomboid, attributeoptioncomboid
            FROM _dv_duplicates);

        INSERT INTO datavalue (dataelementid, periodid, sourceid, categoryoptioncomboid,
                               value, storedby, lastupdated, comment, followup,
                               attributeoptioncomboid, created, deleted)
        SELECT dataelementid, periodid, sourceid,
               first(CASE WHEN categoryoptioncomboid  = coc_id_remove THEN coc_id_keep ELSE categoryoptioncomboid  END),
               first(value),
               first(storedby),
               first(lastupdated),
               first(comment),
               first(followup),
               first(CASE WHEN attributeoptioncomboid = coc_id_remove THEN coc_id_keep ELSE attributeoptioncomboid END),
               first(created),
               first(deleted)
        FROM (SELECT * FROM _dv_duplicates ORDER BY lastupdated DESC) s
        GROUP BY dataelementid, periodid, sourceid,
                 CASE WHEN categoryoptioncomboid  = coc_id_remove THEN coc_id_keep ELSE categoryoptioncomboid  END,
                 CASE WHEN attributeoptioncomboid = coc_id_remove THEN coc_id_keep ELSE attributeoptioncomboid END;

        -- Remaining rows: simple remap
        RAISE NOTICE 'datavalue: remapping remaining rows';
        UPDATE datavalue SET categoryoptioncomboid  = coc_id_keep WHERE categoryoptioncomboid  = coc_id_remove;
        UPDATE datavalue SET attributeoptioncomboid = coc_id_keep WHERE attributeoptioncomboid = coc_id_remove;


        -- ── DATAVALUEAUDIT ────────────────────────────────────────────────────
        RAISE NOTICE 'datavalueaudit';
        UPDATE datavalueaudit SET categoryoptioncomboid  = coc_id_keep WHERE categoryoptioncomboid  = coc_id_remove;
        UPDATE datavalueaudit SET attributeoptioncomboid = coc_id_keep WHERE attributeoptioncomboid = coc_id_remove;


        -- ── COMPLETEDATASETREGISTRATION ───────────────────────────────────────
        RAISE NOTICE 'completedatasetregistration';
        DROP TABLE IF EXISTS _tmp_duplicates;
        CREATE TEMP TABLE _tmp_duplicates (LIKE completedatasetregistration) ON COMMIT DROP;

        INSERT INTO _tmp_duplicates
        SELECT tbl1.* FROM completedatasetregistration tbl1
        JOIN completedatasetregistration tbl2 USING (datasetid, periodid, sourceid)
        WHERE tbl1.attributeoptioncomboid = coc_id_keep AND tbl2.attributeoptioncomboid = coc_id_remove;

        INSERT INTO _tmp_duplicates
        SELECT tbl2.* FROM completedatasetregistration tbl1
        JOIN completedatasetregistration tbl2 USING (datasetid, periodid, sourceid)
        WHERE tbl1.attributeoptioncomboid = coc_id_keep AND tbl2.attributeoptioncomboid = coc_id_remove;

        DELETE FROM completedatasetregistration
        WHERE (datasetid, periodid, sourceid, attributeoptioncomboid) IN (
            SELECT datasetid, periodid, sourceid, attributeoptioncomboid FROM _tmp_duplicates);

        INSERT INTO completedatasetregistration
                (datasetid, periodid, sourceid, date, storedby,
                 attributeoptioncomboid, lastupdatedby, lastupdated, completed)
        SELECT  datasetid, periodid, sourceid,
                first(date), first(storedby),
                coc_id_keep,
                first(lastupdatedby), first(lastupdated), first(completed)
        FROM (SELECT * FROM _tmp_duplicates ORDER BY lastupdated DESC NULLS LAST) s
        GROUP BY datasetid, periodid, sourceid;

        DROP TABLE _tmp_duplicates;
        UPDATE completedatasetregistration SET attributeoptioncomboid = coc_id_keep WHERE attributeoptioncomboid = coc_id_remove;


        -- ── DATAAPPROVAL ──────────────────────────────────────────────────────
        RAISE NOTICE 'dataapproval';
        DROP TABLE IF EXISTS _tmp_duplicates;
        CREATE TEMP TABLE _tmp_duplicates (LIKE dataapproval) ON COMMIT DROP;

        INSERT INTO _tmp_duplicates
        SELECT tbl1.* FROM dataapproval tbl1
        JOIN dataapproval tbl2 USING (dataapprovallevelid, workflowid, periodid, organisationunitid)
        WHERE tbl1.attributeoptioncomboid = coc_id_keep AND tbl2.attributeoptioncomboid = coc_id_remove;

        INSERT INTO _tmp_duplicates
        SELECT tbl2.* FROM dataapproval tbl1
        JOIN dataapproval tbl2 USING (dataapprovallevelid, workflowid, periodid, organisationunitid)
        WHERE tbl1.attributeoptioncomboid = coc_id_keep AND tbl2.attributeoptioncomboid = coc_id_remove;

        DELETE FROM dataapproval
        WHERE (dataapprovallevelid, workflowid, periodid, organisationunitid, attributeoptioncomboid) IN (
            SELECT dataapprovallevelid, workflowid, periodid, organisationunitid, attributeoptioncomboid
            FROM _tmp_duplicates);

        INSERT INTO dataapproval
                (dataapprovalid, periodid, organisationunitid, attributeoptioncomboid,
                 created, creator, dataapprovallevelid, accepted, workflowid,
                 lastupdated, lastupdatedby)
        SELECT  first(dataapprovalid), periodid, organisationunitid,
                coc_id_keep,
                first(created), first(creator), dataapprovallevelid, first(accepted), workflowid,
                first(lastupdated), first(lastupdatedby)
        FROM (SELECT * FROM _tmp_duplicates ORDER BY COALESCE(lastupdated, created) DESC NULLS LAST) s
        GROUP BY periodid, organisationunitid, dataapprovallevelid, workflowid;

        DROP TABLE _tmp_duplicates;
        UPDATE dataapproval SET attributeoptioncomboid = coc_id_keep WHERE attributeoptioncomboid = coc_id_remove;


        -- ── DATAAPPROVALAUDIT ─────────────────────────────────────────────────
        RAISE NOTICE 'dataapprovalaudit';
        UPDATE dataapprovalaudit SET attributeoptioncomboid = coc_id_keep WHERE attributeoptioncomboid = coc_id_remove;


        -- ── VALIDATIONRESULT ──────────────────────────────────────────────────
        RAISE NOTICE 'validationresult';
        DROP TABLE IF EXISTS _tmp_duplicates;
        CREATE TEMP TABLE _tmp_duplicates (LIKE validationresult) ON COMMIT DROP;

        INSERT INTO _tmp_duplicates
        SELECT tbl1.* FROM validationresult tbl1
        JOIN validationresult tbl2 USING (validationruleid, periodid, organisationunitid, dayinperiod)
        WHERE tbl1.attributeoptioncomboid = coc_id_keep AND tbl2.attributeoptioncomboid = coc_id_remove;

        INSERT INTO _tmp_duplicates
        SELECT tbl2.* FROM validationresult tbl1
        JOIN validationresult tbl2 USING (validationruleid, periodid, organisationunitid, dayinperiod)
        WHERE tbl1.attributeoptioncomboid = coc_id_keep AND tbl2.attributeoptioncomboid = coc_id_remove;

        DELETE FROM validationresult
        WHERE (validationruleid, periodid, organisationunitid, dayinperiod, attributeoptioncomboid) IN (
            SELECT validationruleid, periodid, organisationunitid, dayinperiod, attributeoptioncomboid
            FROM _tmp_duplicates);

        INSERT INTO validationresult
                (validationresultid, created, leftsidevalue, rightsidevalue,
                 validationruleid, periodid, organisationunitid, attributeoptioncomboid,
                 dayinperiod, notificationsent)
        SELECT  first(validationresultid), first(created),
                first(leftsidevalue), first(rightsidevalue),
                validationruleid, periodid, organisationunitid,
                coc_id_keep,
                dayinperiod, first(notificationsent)
        FROM (SELECT * FROM _tmp_duplicates ORDER BY created DESC NULLS LAST) s
        GROUP BY validationruleid, periodid, organisationunitid, dayinperiod;

        DROP TABLE _tmp_duplicates;
        UPDATE validationresult SET attributeoptioncomboid = coc_id_keep WHERE attributeoptioncomboid = coc_id_remove;


        -- ── MINMAXDATAELEMENT ─────────────────────────────────────────────────
        RAISE NOTICE 'minmaxdataelement';
        DROP TABLE IF EXISTS _tmp_duplicates;
        CREATE TEMP TABLE _tmp_duplicates (LIKE minmaxdataelement) ON COMMIT DROP;

        INSERT INTO _tmp_duplicates
        SELECT tbl1.* FROM minmaxdataelement tbl1
        JOIN minmaxdataelement tbl2 USING (sourceid, dataelementid)
        WHERE tbl1.categoryoptioncomboid = coc_id_keep AND tbl2.categoryoptioncomboid = coc_id_remove;

        INSERT INTO _tmp_duplicates
        SELECT tbl2.* FROM minmaxdataelement tbl1
        JOIN minmaxdataelement tbl2 USING (sourceid, dataelementid)
        WHERE tbl1.categoryoptioncomboid = coc_id_keep AND tbl2.categoryoptioncomboid = coc_id_remove;

        DELETE FROM minmaxdataelement
        WHERE (sourceid, dataelementid, categoryoptioncomboid) IN (
            SELECT sourceid, dataelementid, categoryoptioncomboid FROM _tmp_duplicates);

        INSERT INTO minmaxdataelement
                (minmaxdataelementid, sourceid, dataelementid, categoryoptioncomboid,
                 minimumvalue, maximumvalue, generatedvalue)
        SELECT  first(minmaxdataelementid), sourceid, dataelementid, coc_id_keep,
                min(minimumvalue), max(maximumvalue), max(generatedvalue::int)::bool
        FROM _tmp_duplicates
        GROUP BY sourceid, dataelementid;

        DROP TABLE _tmp_duplicates;
        UPDATE minmaxdataelement SET categoryoptioncomboid = coc_id_keep WHERE categoryoptioncomboid = coc_id_remove;


        -- ── DATAELEMENTOPERAND ────────────────────────────────────────────────
        RAISE NOTICE 'dataelementoperand';
        UPDATE dataelementoperand SET categoryoptioncomboid = coc_id_keep WHERE categoryoptioncomboid = coc_id_remove;


        -- ── EVENT TABLES ──────────────────────────────────────────────────────
        -- < 2.38: programstageinstance; 2.38-2.42: event;
        -- >= 2.43: trackerevent + singleevent (event was split in two)
        FOREACH event_table IN ARRAY ARRAY['programstageinstance', 'event', 'trackerevent', 'singleevent'] LOOP
            CONTINUE WHEN to_regclass('public.' || event_table) IS NULL;
            RAISE NOTICE '% (attributeoptioncomboid)', event_table;
            EXECUTE format(
                'UPDATE %I SET attributeoptioncomboid = $1 WHERE attributeoptioncomboid = $2',
                event_table
            ) USING coc_id_keep, coc_id_remove;
        END LOOP;


        -- ── CASEAGGREGATION (only present in some DB versions) ────────────────
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'caseaggregation') THEN
            RAISE NOTICE 'caseaggregation';
            UPDATE caseaggregation SET optioncomboid = coc_id_keep WHERE optioncomboid = coc_id_remove;
        END IF;


        -- ── SMSCODES ─────────────────────────────────────────────────────────
        RAISE NOTICE 'smscodes';
        UPDATE smscodes SET optionid = coc_id_keep WHERE optionid = coc_id_remove;


        -- ── PREDICTOR ────────────────────────────────────────────────────────
        RAISE NOTICE 'predictor';
        UPDATE predictor SET generatoroutputcombo = coc_id_keep WHERE generatoroutputcombo = coc_id_remove;


        -- ── DATADIMENSIONITEM ─────────────────────────────────────────────────
        RAISE NOTICE 'datadimensionitem';
        UPDATE datadimensionitem
        SET    dataelementoperand_categoryoptioncomboid = coc_id_keep
        WHERE  dataelementoperand_categoryoptioncomboid = coc_id_remove;


        -- ── DATA ENTRY FORM (UID in HTML) ──────────────────────────────────────
        RAISE NOTICE 'dataentryform (htmlcode)';
        UPDATE dataentryform
        SET    htmlcode = replace(htmlcode, uid_remove, coc_uid_keep)
        WHERE  htmlcode LIKE '%' || uid_remove || '%';


        -- ── INDICATOR (UID in numerator/denominator expressions) ──────────────
        RAISE NOTICE 'indicator (numerator/denominator)';
        UPDATE indicator SET numerator   = replace(numerator,   uid_remove, coc_uid_keep) WHERE numerator   LIKE '%' || uid_remove || '%';
        UPDATE indicator SET denominator = replace(denominator, uid_remove, coc_uid_keep) WHERE denominator LIKE '%' || uid_remove || '%';

        RAISE NOTICE 'indicator (aggregateExportCategoryOptionCombo)';
        UPDATE indicator SET aggregateexportcategoryoptioncombo = coc_uid_keep
        WHERE  aggregateexportcategoryoptioncombo = uid_remove;

        RAISE NOTICE 'indicator (aggregateExportAttributeOptionCombo)';
        UPDATE indicator SET aggregateexportattributeoptioncombo = coc_uid_keep
        WHERE  aggregateexportattributeoptioncombo = uid_remove;


        -- ── PROGRAM INDICATOR ──────────────────────────────────────────────────
        RAISE NOTICE 'programindicator (aggregateExport fields)';
        UPDATE programindicator SET aggregateexportcategoryoptioncombo  = coc_uid_keep WHERE aggregateexportcategoryoptioncombo  = uid_remove;
        UPDATE programindicator SET aggregateexportattributeoptioncombo = coc_uid_keep WHERE aggregateexportattributeoptioncombo = uid_remove;


        -- ── EXPRESSION (predictor / validation rule formulas) ──────────────────
        RAISE NOTICE 'expression (predictor/validationRule)';
        UPDATE expression
        SET    expression = replace(expression, uid_remove, coc_uid_keep)
        WHERE  expression LIKE '%' || uid_remove || '%';


        -- ── CLEAN UP COC MEMBERSHIP ROWS AND DELETE THE SOURCE COC ───────────
        RAISE NOTICE 'categoryoptioncombos_categoryoptions';
        DELETE FROM categoryoptioncombos_categoryoptions WHERE categoryoptioncomboid = coc_id_remove;

        RAISE NOTICE 'categorycombos_optioncombos';
        DELETE FROM categorycombos_optioncombos WHERE categoryoptioncomboid = coc_id_remove;

        RAISE NOTICE 'categoryoptioncombo (delete source)';
        DELETE FROM categoryoptioncombo WHERE categoryoptioncomboid = coc_id_remove;

        RAISE NOTICE 'coc_dup_merge: merged % (id=%) into % (id=%)',
            uid_remove, coc_id_remove, coc_uid_keep, coc_id_keep;

    END LOOP;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'coc_dup_merge: error mid-write, all changes rolled back: %', SQLERRM;
        RAISE;
    END;

    RETURN TRUE;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 1. co_dup_merge(target_uid, source_uids, delete_sources)
--    Merges one or more source categoryOptions into a target.
--
--    Pre-conditions (all validated before any writes):
--      • target must exist
--      • target must not appear in source list
--      • each source must exist
--
--    Affected tables (for each source):
--      categories_categoryoptions           (category ↔ option membership)
--      categoryoptioncombos_categoryoptions (COC ↔ option membership)
--      categoryoptiongroupmembers           (option-group membership)
--      categoryoption_organisationunits     (org-unit restrictions)
--      categorydimension_items              (visualization filter items)
--
--    COC deduplication: when replacing source → target in a COC's option
--    membership would create a COC identical to an already-existing one in the
--    same combo, this function first applies the option update and then calls
--    coc_dup_merge to merge the data (LAST_UPDATED conflict resolution).
--
--    delete_sources (default true): if false, categoryoption rows are left in
--    place after all associations have been transferred.
--
--    Returns TRUE on success, FALSE if pre-conditions are not met.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION co_dup_merge(
    target_uid     text,
    source_uids    text[],
    delete_sources bool DEFAULT true
)
RETURNS bool
LANGUAGE plpgsql AS $$
DECLARE
    opt_table        text;
    target_id        bigint;
    source_id        bigint;
    src_uid          text;
    src_coc_id       bigint;
    src_coc_uid      text;
    conflict_coc_id  bigint;
    conflict_coc_uid text;
BEGIN
    -- Table renamed from dataelementcategoryoption to categoryoption in DHIS2 2.38
    SELECT CASE WHEN EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='categoryoption')
                THEN 'categoryoption' ELSE 'dataelementcategoryoption' END
    INTO opt_table;

    -- ── RESOLVE TARGET ────────────────────────────────────────────────────────
    EXECUTE format('SELECT categoryoptionid FROM %I WHERE uid = $1', opt_table)
    INTO target_id USING target_uid;
    IF target_id IS NULL THEN
        RAISE WARNING 'Target category option not found: %', target_uid;
        RETURN FALSE;
    END IF;

    IF target_uid = ANY(source_uids) THEN
        RAISE WARNING 'Target category option % is also in source list', target_uid;
        RETURN FALSE;
    END IF;

    -- ── VALIDATE ALL SOURCES BEFORE TOUCHING ANYTHING ─────────────────────────
    FOREACH src_uid IN ARRAY source_uids LOOP
        EXECUTE format('SELECT categoryoptionid FROM %I WHERE uid = $1', opt_table)
        INTO source_id USING src_uid;
        IF source_id IS NULL THEN
            RAISE WARNING 'Source category option not found: %', src_uid;
            RETURN FALSE;
        END IF;
    END LOOP;

    -- ── MERGE EACH SOURCE INTO TARGET ─────────────────────────────────────────
    -- Nested block creates an implicit savepoint; any unexpected error rolls back
    -- ALL writes in this block before re-raising.
    BEGIN
    FOREACH src_uid IN ARRAY source_uids LOOP
        EXECUTE format('SELECT categoryoptionid FROM %I WHERE uid = $1', opt_table)
        INTO source_id USING src_uid;

        RAISE NOTICE 'Merging category option % (id=%) into % (id=%)',
            src_uid, source_id, target_uid, target_id;

        -- categories_categoryoptions  PK (categoryid, sort_order)
        -- Remove source membership when target is already in the same category.
        DELETE FROM categories_categoryoptions d
        WHERE d.categoryoptionid = source_id
          AND EXISTS (
              SELECT 1 FROM categories_categoryoptions m
              WHERE m.categoryid = d.categoryid AND m.categoryoptionid = target_id
          );
        UPDATE categories_categoryoptions
        SET    categoryoptionid = target_id
        WHERE  categoryoptionid = source_id;

        -- categoryoptioncombos_categoryoptions  PK (categoryoptioncomboid, categoryoptionid)
        --
        -- For each COC that contains the source option, check whether replacing
        -- source → target would create a COC with an identical option fingerprint
        -- to an existing COC in the same combo (a structural conflict).
        --
        -- If a conflict exists:
        --   1. Apply source → target on the source COC's membership row.
        --   2. Call coc_dup_merge so that data is merged (LAST_UPDATED wins).
        -- If no conflict:
        --   Just update the option membership.
        FOR src_coc_id, src_coc_uid IN
            SELECT co.categoryoptioncomboid, coc.uid
            FROM   categoryoptioncombos_categoryoptions co
            JOIN   categoryoptioncombo coc ON coc.categoryoptioncomboid = co.categoryoptioncomboid
            WHERE  co.categoryoptionid = source_id
        LOOP
            -- Find a COC in the same combo whose option fingerprint equals
            -- this COC's fingerprint after source → target substitution.
            SELECT tgt_link.categoryoptioncomboid, tgt_coc.uid
            INTO   conflict_coc_id, conflict_coc_uid
            FROM   categorycombos_optioncombos src_link
            JOIN   categorycombos_optioncombos tgt_link
                   ON  tgt_link.categorycomboid     = src_link.categorycomboid
                   AND tgt_link.categoryoptioncomboid != src_coc_id
            JOIN   categoryoptioncombo tgt_coc
                   ON  tgt_coc.categoryoptioncomboid = tgt_link.categoryoptioncomboid
            WHERE  src_link.categoryoptioncomboid = src_coc_id
              AND (   SELECT ARRAY_AGG(
                             CASE WHEN co2.categoryoptionid = source_id
                                  THEN target_id ELSE co2.categoryoptionid END
                             ORDER BY
                             CASE WHEN co2.categoryoptionid = source_id
                                  THEN target_id ELSE co2.categoryoptionid END)
                      FROM categoryoptioncombos_categoryoptions co2
                      WHERE co2.categoryoptioncomboid = src_coc_id
                  ) = (
                      SELECT ARRAY_AGG(co3.categoryoptionid ORDER BY co3.categoryoptionid)
                      FROM   categoryoptioncombos_categoryoptions co3
                      WHERE  co3.categoryoptioncomboid = tgt_link.categoryoptioncomboid
                  )
            LIMIT 1;

            IF conflict_coc_id IS NOT NULL THEN
                -- Apply the option update first so coc_dup_merge's identical-options
                -- validation passes (both COCs now have the same option fingerprint).
                UPDATE categoryoptioncombos_categoryoptions
                SET    categoryoptionid = target_id
                WHERE  categoryoptioncomboid = src_coc_id AND categoryoptionid = source_id;

                -- Merge data: keep conflict_coc (already has target option), remove src_coc.
                PERFORM coc_dup_merge(conflict_coc_uid, ARRAY[src_coc_uid]);
            ELSE
                -- No structural conflict; just remap the option.
                DELETE FROM categoryoptioncombos_categoryoptions
                WHERE  categoryoptioncomboid = src_coc_id
                  AND  categoryoptionid = source_id
                  AND  EXISTS (
                           SELECT 1 FROM categoryoptioncombos_categoryoptions
                           WHERE  categoryoptioncomboid = src_coc_id
                             AND  categoryoptionid = target_id
                       );
                UPDATE categoryoptioncombos_categoryoptions
                SET    categoryoptionid = target_id
                WHERE  categoryoptioncomboid = src_coc_id AND categoryoptionid = source_id;
            END IF;
        END LOOP;

        -- categoryoptiongroupmembers  PK (categoryoptiongroupid, categoryoptionid)
        DELETE FROM categoryoptiongroupmembers d
        WHERE d.categoryoptionid = source_id
          AND EXISTS (
              SELECT 1 FROM categoryoptiongroupmembers m
              WHERE m.categoryoptiongroupid = d.categoryoptiongroupid
                AND m.categoryoptionid = target_id
          );
        UPDATE categoryoptiongroupmembers
        SET    categoryoptionid = target_id
        WHERE  categoryoptionid = source_id;

        -- categoryoption_organisationunits  PK (categoryoptionid, organisationunitid)
        DELETE FROM categoryoption_organisationunits d
        WHERE d.categoryoptionid = source_id
          AND EXISTS (
              SELECT 1 FROM categoryoption_organisationunits m
              WHERE m.categoryoptionid = target_id AND m.organisationunitid = d.organisationunitid
          );
        UPDATE categoryoption_organisationunits
        SET    categoryoptionid = target_id
        WHERE  categoryoptionid = source_id;

        -- categorydimension_items  PK (categorydimensionid, sort_order)
        DELETE FROM categorydimension_items d
        WHERE d.categoryoptionid = source_id
          AND EXISTS (
              SELECT 1 FROM categorydimension_items m
              WHERE m.categorydimensionid = d.categorydimensionid
                AND m.categoryoptionid = target_id
          );
        UPDATE categorydimension_items
        SET    categoryoptionid = target_id
        WHERE  categoryoptionid = source_id;

        IF delete_sources THEN
            EXECUTE format('DELETE FROM %I WHERE categoryoptionid = $1', opt_table)
            USING source_id;
        END IF;

        RAISE NOTICE 'Merged category option % (id=%) into % (id=%)',
            src_uid, source_id, target_uid, target_id;
    END LOOP;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'co_dup_merge: error mid-write, all changes rolled back: %', SQLERRM;
        RAISE;
    END;

    RETURN TRUE;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. cat_dup_merge(target_uid, source_uids, delete_sources)
--
--    Pre-conditions (all validated before any writes):
--      • target must exist
--      • target must not appear in source list
--      • each source must exist
--      • each source must have the same set of categoryOptions as the target
--      • no source may share a CategoryCombo with the target
--      • no two sources may share a CategoryCombo with each other
--
--    Affected tables:
--      categories_categoryoptions     (option membership — delete source rows)
--      categorycombos_categories      (redirect source → target)
--      categorydimension              (redirect source → target)
--      users_catdimensionconstraints  (delete if user has target; else remap)
--
--    delete_sources (default true): if false, category rows are left in place
--    after all references are transferred.
--
--    Compatible with DHIS2 >= 2.37.  Automatically detects whether the category
--    table is named "category" (DHIS2 2.38+) or "dataelementcategory" (≤ 2.37).
--
--    Returns TRUE on success, FALSE if pre-conditions are not met.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION cat_dup_merge(
    target_uid     text,
    source_uids    text[],
    delete_sources bool DEFAULT true
)
RETURNS bool
LANGUAGE plpgsql AS $$
DECLARE
    cat_table         text;
    target_id         bigint;
    source_id         bigint;
    src_uid           text;
    target_opts       bigint[];
    source_opts       bigint[];
    target_combos     bigint[];
    source_combos     bigint[];
    all_source_combos bigint[] := '{}';
BEGIN
    -- Detect category table name (renamed from dataelementcategory in DHIS2 2.38)
    SELECT CASE WHEN EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='category')
                THEN 'category' ELSE 'dataelementcategory' END
    INTO cat_table;

    -- ── RESOLVE TARGET ────────────────────────────────────────────────────────
    EXECUTE format('SELECT categoryid FROM %I WHERE uid = $1', cat_table)
    INTO target_id USING target_uid;

    IF target_id IS NULL THEN
        RAISE WARNING 'Target category not found: %', target_uid;
        RETURN FALSE;
    END IF;

    IF target_uid = ANY(source_uids) THEN
        RAISE WARNING 'Target category % is also in source list', target_uid;
        RETURN FALSE;
    END IF;

    target_opts := ARRAY(
        SELECT categoryoptionid FROM categories_categoryoptions
        WHERE  categoryid = target_id ORDER BY categoryoptionid
    );

    target_combos := ARRAY(
        SELECT categorycomboid FROM categorycombos_categories
        WHERE  categoryid = target_id
    );

    -- ── VALIDATE ALL SOURCES BEFORE TOUCHING ANYTHING ─────────────────────────
    FOREACH src_uid IN ARRAY source_uids LOOP
        EXECUTE format('SELECT categoryid FROM %I WHERE uid = $1', cat_table)
        INTO source_id USING src_uid;

        IF source_id IS NULL THEN
            RAISE WARNING 'Source category not found: %', src_uid;
            RETURN FALSE;
        END IF;

        source_opts := ARRAY(
            SELECT categoryoptionid FROM categories_categoryoptions
            WHERE  categoryid = source_id ORDER BY categoryoptionid
        );

        IF target_opts != source_opts THEN
            RAISE WARNING 'Source category % has different categoryOptions than target %',
                src_uid, target_uid;
            RETURN FALSE;
        END IF;

        source_combos := ARRAY(
            SELECT categorycomboid FROM categorycombos_categories
            WHERE  categoryid = source_id
        );

        -- Source must not share a CategoryCombo with target
        IF target_combos && source_combos THEN
            RAISE WARNING 'Source category % shares a CategoryCombo with target %',
                src_uid, target_uid;
            RETURN FALSE;
        END IF;

        -- Source must not share a CategoryCombo with any other source
        IF all_source_combos && source_combos THEN
            RAISE WARNING 'Source category % shares a CategoryCombo with another source',
                src_uid;
            RETURN FALSE;
        END IF;

        all_source_combos := all_source_combos || source_combos;
    END LOOP;

    -- ── MERGE EACH SOURCE INTO TARGET ─────────────────────────────────────────
    -- Nested block creates an implicit savepoint; any unexpected error rolls back
    -- ALL writes in this block before re-raising.
    BEGIN
    FOREACH src_uid IN ARRAY source_uids LOOP
        EXECUTE format('SELECT categoryid FROM %I WHERE uid = $1', cat_table)
        INTO source_id USING src_uid;

        RAISE NOTICE 'Merging category % (id=%) into % (id=%)',
            src_uid, source_id, target_uid, target_id;

        -- categories_categoryoptions: source has identical options to target → delete
        DELETE FROM categories_categoryoptions WHERE categoryid = source_id;

        -- categorycombos_categories: redirect source → target
        -- Pre-check guarantees no combo is shared between source and target,
        -- so no PK conflict can occur.
        UPDATE categorycombos_categories
        SET    categoryid = target_id
        WHERE  categoryid = source_id;

        -- categorydimension: set as target
        UPDATE categorydimension
        SET    categoryid = target_id
        WHERE  categoryid = source_id;

        -- users_catdimensionconstraints:
        --   User has source AND target → delete source constraint
        --   User has source, no target → remap source to target
        -- Processing sources one at a time means: after the first iteration a
        -- user's source constraint becomes target; subsequent iterations see that
        -- target and correctly delete the remaining source constraints.
        DELETE FROM users_catdimensionconstraints udc
        WHERE  udc.dataelementcategoryid = source_id
          AND  EXISTS (
                   SELECT 1 FROM users_catdimensionconstraints
                   WHERE  userid = udc.userid
                     AND  dataelementcategoryid = target_id
               );

        UPDATE users_catdimensionconstraints
        SET    dataelementcategoryid = target_id
        WHERE  dataelementcategoryid = source_id;

        IF delete_sources THEN
            EXECUTE format('DELETE FROM %I WHERE categoryid = $1', cat_table)
            USING source_id;
        END IF;

        RAISE NOTICE 'Merged category % (id=%) into % (id=%)',
            src_uid, source_id, target_uid, target_id;
    END LOOP;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'cat_dup_merge: error mid-write, all changes rolled back: %', SQLERRM;
        RAISE;
    END;

    RETURN TRUE;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. cc_dup_merge(target_uid, source_uids, delete_sources)
--    Merges one or more source categoryCombos into a target.
--
--    Pre-conditions (all validated before any writes):
--      • target must exist
--      • target must not appear in source list
--      • each source must exist
--      • each source must have the same set of categories as the target
--      • each combo (target + all sources) must pass three integrity checks:
--          – no duplicate COCs (two COCs with the same option fingerprint)
--          – all COCs have the correct cardinality (options = #categories)
--          – all COC options are valid (members of a category in the combo)
--
--    COC deduplication: source COCs are matched to target COCs by identical
--    sorted option-id fingerprints and all data references are redirected before
--    the source COC rows are deleted.  Any unmatched source COCs (edge case) are
--    reassigned to the target combo.
--
--    Direct combo FK tables:
--      dataelement, dataset, datasetelement, program (+ enrollmentCategoryCombo
--      if the column exists), programindicator (categorycomboid +
--      attributecomboid if exists), dataapprovalworkflow
--
--    delete_sources (default true): if false, combo rows are left in place after
--    all references and COC rows are transferred.
--
--    Compatible with DHIS2 >= 2.36.  Detects event/programstageinstance,
--    caseaggregation, programindicator.attributecomboid, and
--    program.enrollmentcategorycomboid dynamically.
--
--    Returns TRUE on success, FALSE if pre-conditions or integrity checks fail.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION cc_dup_merge(
    target_uid     text,
    source_uids    text[],
    delete_sources bool DEFAULT true
)
RETURNS bool
LANGUAGE plpgsql AS $$
DECLARE
    target_id             bigint;
    source_id             bigint;
    src_uid               text;
    combo_uid             text;
    combo_id              bigint;
    dup_coc_id            bigint;
    master_coc_id         bigint;
    dup_coc_uid           text;
    master_coc_uid        text;
    target_cats           bigint[];
    source_cats           bigint[];
    has_case_agg          bool;
    has_pi_attr_combo     bool;
    has_pi_cat_combo      bool;
    has_prog_enroll_combo bool;
BEGIN
    -- ── RESOLVE TARGET ────────────────────────────────────────────────────────
    SELECT categorycomboid INTO target_id FROM categorycombo WHERE uid = target_uid;
    IF target_id IS NULL THEN
        RAISE WARNING 'Target combo not found: %', target_uid;
        RETURN FALSE;
    END IF;

    IF target_uid = ANY(source_uids) THEN
        RAISE WARNING 'Target combo % is also in source list', target_uid;
        RETURN FALSE;
    END IF;

    -- Detect optional tables / columns (vary across DHIS2 versions)
    SELECT EXISTS(SELECT 1 FROM information_schema.tables  WHERE table_name  ='caseaggregation')                                       INTO has_case_agg;
    SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name  ='programindicator' AND column_name='attributecomboid')    INTO has_pi_attr_combo;
    SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name  ='programindicator' AND column_name='categorycomboid')      INTO has_pi_cat_combo;
    SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name  ='program'          AND column_name='enrollmentcategorycomboid') INTO has_prog_enroll_combo;

    target_cats := ARRAY(
        SELECT categoryid FROM categorycombos_categories
        WHERE  categorycomboid = target_id ORDER BY categoryid
    );

    -- ── VALIDATE SOURCES ──────────────────────────────────────────────────────
    FOREACH src_uid IN ARRAY source_uids LOOP
        SELECT categorycomboid INTO source_id FROM categorycombo WHERE uid = src_uid;
        IF source_id IS NULL THEN
            RAISE WARNING 'Source combo not found: %', src_uid;
            RETURN FALSE;
        END IF;

        source_cats := ARRAY(
            SELECT categoryid FROM categorycombos_categories
            WHERE  categorycomboid = source_id ORDER BY categoryid
        );

        IF target_cats != source_cats THEN
            RAISE WARNING 'Source combo % has different categories than target %',
                src_uid, target_uid;
            RETURN FALSE;
        END IF;
    END LOOP;

    -- ── INTEGRITY CHECKS (target + all sources) ───────────────────────────────
    FOREACH combo_uid IN ARRAY (ARRAY[target_uid] || source_uids) LOOP
        SELECT categorycomboid INTO combo_id FROM categorycombo WHERE uid = combo_uid;

        -- No duplicate COCs within this combo
        IF EXISTS(
            SELECT opts
            FROM (
                SELECT ARRAY_AGG(co.categoryoptionid ORDER BY co.categoryoptionid) AS opts
                FROM   categorycombos_optioncombos link
                JOIN   categoryoptioncombos_categoryoptions co
                       ON co.categoryoptioncomboid = link.categoryoptioncomboid
                WHERE  link.categorycomboid = combo_id
                GROUP  BY link.categoryoptioncomboid
            ) fingerprints
            GROUP BY opts HAVING count(*) > 1
        ) THEN
            RAISE WARNING 'Combo % has duplicate CategoryOptionCombos — resolve with coc_dup_merge first',
                combo_uid;
            RETURN FALSE;
        END IF;

        -- All COCs have correct cardinality (#options = #categories in combo)
        IF EXISTS(
            SELECT 1
            FROM   categorycombos_optioncombos link
            LEFT JOIN (
                SELECT categoryoptioncomboid, count(*) AS opt_count
                FROM   categoryoptioncombos_categoryoptions
                GROUP  BY categoryoptioncomboid
            ) opt_cnt ON opt_cnt.categoryoptioncomboid = link.categoryoptioncomboid
            WHERE  link.categorycomboid = combo_id
              AND  COALESCE(opt_cnt.opt_count, 0) !=
                   (SELECT count(*) FROM categorycombos_categories WHERE categorycomboid = combo_id)
        ) THEN
            RAISE WARNING 'Combo % has COCs with wrong cardinality', combo_uid;
            RETURN FALSE;
        END IF;

        -- All COC options are valid members of the combo's categories
        IF EXISTS(
            SELECT 1
            FROM   categorycombos_optioncombos combo_link
            JOIN   categoryoptioncombos_categoryoptions coc
                   ON coc.categoryoptioncomboid = combo_link.categoryoptioncomboid
            WHERE  combo_link.categorycomboid = combo_id
              AND  coc.categoryoptionid NOT IN (
                       SELECT co.categoryoptionid
                       FROM   categorycombos_categories cc
                       JOIN   categories_categoryoptions co ON co.categoryid = cc.categoryid
                       WHERE  cc.categorycomboid = combo_id
                   )
        ) THEN
            RAISE WARNING 'Combo % has COCs containing invalid CategoryOptions', combo_uid;
            RETURN FALSE;
        END IF;
    END LOOP;

    -- ── MERGE EACH SOURCE INTO TARGET ─────────────────────────────────────────
    -- Nested block creates an implicit savepoint; any unexpected error rolls back
    -- ALL writes in this block before re-raising.
    BEGIN
    FOREACH src_uid IN ARRAY source_uids LOOP
        SELECT categorycomboid INTO source_id FROM categorycombo WHERE uid = src_uid;

        RAISE NOTICE 'Merging combo % (id=%) into % (id=%)',
            src_uid, source_id, target_uid, target_id;

        -- ── Step 1: build COC fingerprint map (source COC → target COC) ──────
        DROP TABLE IF EXISTS _coc_map;
        CREATE TEMP TABLE _coc_map ON COMMIT DROP AS
        SELECT src_cocs.categoryoptioncomboid  AS dup_coc_id,
               tgt_cocs.categoryoptioncomboid  AS master_coc_id
        FROM (
            SELECT link.categoryoptioncomboid,
                   ARRAY_AGG(rel.categoryoptionid ORDER BY rel.categoryoptionid) AS opts
            FROM   categorycombos_optioncombos link
            JOIN   categoryoptioncombos_categoryoptions rel
                   ON rel.categoryoptioncomboid = link.categoryoptioncomboid
            WHERE  link.categorycomboid = source_id
            GROUP  BY link.categoryoptioncomboid
        ) src_cocs
        JOIN (
            SELECT link.categoryoptioncomboid,
                   ARRAY_AGG(rel.categoryoptionid ORDER BY rel.categoryoptionid) AS opts
            FROM   categorycombos_optioncombos link
            JOIN   categoryoptioncombos_categoryoptions rel
                   ON rel.categoryoptioncomboid = link.categoryoptioncomboid
            WHERE  link.categorycomboid = target_id
            GROUP  BY link.categoryoptioncomboid
        ) tgt_cocs ON tgt_cocs.opts = src_cocs.opts;

        -- ── Step 2: redirect all data/metadata from matched source → target COCs
        -- Delegate to coc_dup_merge so data conflicts, UID-based expression
        -- references, validationresult, and all other associations are handled
        -- correctly (including conflict resolution for duplicate data values).
        -- coc_dup_merge requires both COCs to share the same combo, so we
        -- reassign dup_coc to the target combo first.
        FOR dup_coc_id, master_coc_id IN
            SELECT m.dup_coc_id, m.master_coc_id FROM _coc_map m
        LOOP
            SELECT uid INTO dup_coc_uid    FROM categoryoptioncombo WHERE categoryoptioncomboid = dup_coc_id;
            SELECT uid INTO master_coc_uid FROM categoryoptioncombo WHERE categoryoptioncomboid = master_coc_id;

            -- Temporarily move dup_coc into the target combo so coc_dup_merge
            -- validation (same-combo check) passes.
            UPDATE categorycombos_optioncombos
            SET    categorycomboid = target_id
            WHERE  categoryoptioncomboid = dup_coc_id;

            -- coc_dup_merge handles data conflict resolution, UID-based expression
            -- rewrites, validationresult, and deletes the source COC.
            PERFORM coc_dup_merge(master_coc_uid, ARRAY[dup_coc_uid]);
        END LOOP;

        -- Unmatched source COCs (edge case): reassign to target combo
        UPDATE categorycombos_optioncombos
        SET    categorycomboid = target_id
        WHERE  categorycomboid = source_id
          AND  categoryoptioncomboid NOT IN (SELECT m.dup_coc_id FROM _coc_map m);

        DROP TABLE _coc_map;

        -- ── Step 3: redirect direct combo FK references ───────────────────────
        UPDATE dataelement          SET categorycomboid = target_id WHERE categorycomboid = source_id;
        UPDATE dataset              SET categorycomboid = target_id WHERE categorycomboid = source_id;
        UPDATE datasetelement       SET categorycomboid = target_id WHERE categorycomboid = source_id;
        UPDATE program              SET categorycomboid = target_id WHERE categorycomboid = source_id;
        UPDATE dataapprovalworkflow SET categorycomboid = target_id WHERE categorycomboid = source_id;
        IF has_pi_cat_combo THEN
            EXECUTE 'UPDATE programindicator SET categorycomboid = $1 WHERE categorycomboid = $2'
            USING target_id, source_id;
        END IF;

        IF has_prog_enroll_combo THEN
            EXECUTE 'UPDATE program SET enrollmentcategorycomboid = $1 WHERE enrollmentcategorycomboid = $2'
            USING target_id, source_id;
        END IF;
        IF has_pi_attr_combo THEN
            EXECUTE 'UPDATE programindicator SET attributecomboid = $1 WHERE attributecomboid = $2'
            USING target_id, source_id;
        END IF;

        -- ── Step 4: remove category membership rows for source combo ──────────
        DELETE FROM categorycombos_categories WHERE categorycomboid = source_id;

        IF delete_sources THEN
            DELETE FROM categorycombo WHERE categorycomboid = source_id;
        END IF;

        RAISE NOTICE 'Merged combo % (id=%) into % (id=%)',
            src_uid, source_id, target_uid, target_id;
    END LOOP;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'cc_dup_merge: error mid-write, all changes rolled back: %', SQLERRM;
        RAISE;
    END;

    RETURN TRUE;
END;
$$;
