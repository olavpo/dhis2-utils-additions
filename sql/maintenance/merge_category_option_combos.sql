-- merge_category_option_combos.sql
--
-- Merges one category option combo into another: all data and references
-- are moved from the duplicate to the surviving combo, and the duplicate
-- is deleted. The typical use is repairing databases with duplicate
-- "default" category option combos (a classic import accident, flagged by
-- the built-in data integrity checks), but any two combos can be merged.
--
-- Where both combos hold a value for the same data element / period /
-- org unit (/attribute combo), the most recently updated value wins.
--
-- Function: merge_category_option_combos(keep_uid, remove_uid)
--   keep_uid     UID of the category option combo that survives
--   remove_uid   UID of the category option combo to merge away
--   returns      Text summary of what was moved
--
-- Run in a transaction and review the summary before committing:
--
--   BEGIN;
--   SELECT merge_category_option_combos('HllvX50cXC0', 'duplicate123');
--   COMMIT;
--
-- Afterwards, restart DHIS2 and run Analytics Tables export.

CREATE OR REPLACE FUNCTION merge_category_option_combos(keep_uid text, remove_uid text)
    RETURNS text
    LANGUAGE plpgsql
AS
$$
DECLARE
    KEEP_ID bigint;
    REMOVE_ID bigint;
    FK RECORD;
    ROWS_AFFECTED bigint;
    VALUES_MERGED bigint := 0;
    ROWS_REPOINTED bigint := 0;
BEGIN
    SELECT categoryoptioncomboid INTO KEEP_ID FROM categoryoptioncombo WHERE uid = keep_uid;
    SELECT categoryoptioncomboid INTO REMOVE_ID FROM categoryoptioncombo WHERE uid = remove_uid;

    IF KEEP_ID IS NULL OR REMOVE_ID IS NULL THEN
        RAISE EXCEPTION 'Category option combo not found (keep: %, remove: %)', keep_uid, remove_uid;
    END IF;
    IF KEEP_ID = REMOVE_ID THEN
        RAISE EXCEPTION 'keep_uid and remove_uid are the same combo';
    END IF;

    -- 1. datavalue: where both combos have a value for the same
    --    dimensions, keep the newest value on the surviving combo, then
    --    delete the duplicate row. Both the category dimension and the
    --    attribute dimension can collide.

    -- category option combo dimension
    UPDATE datavalue k
    SET value = r.value, storedby = r.storedby, lastupdated = r.lastupdated,
        comment = r.comment, followup = r.followup, deleted = r.deleted
    FROM datavalue r
    WHERE k.categoryoptioncomboid = KEEP_ID AND r.categoryoptioncomboid = REMOVE_ID
      AND k.dataelementid = r.dataelementid AND k.periodid = r.periodid
      AND k.sourceid = r.sourceid AND k.attributeoptioncomboid = r.attributeoptioncomboid
      AND r.lastupdated > k.lastupdated;

    DELETE FROM datavalue r
    WHERE r.categoryoptioncomboid = REMOVE_ID
      AND EXISTS (
        SELECT 1 FROM datavalue k
        WHERE k.categoryoptioncomboid = KEEP_ID
          AND k.dataelementid = r.dataelementid AND k.periodid = r.periodid
          AND k.sourceid = r.sourceid AND k.attributeoptioncomboid = r.attributeoptioncomboid);
    GET DIAGNOSTICS ROWS_AFFECTED = ROW_COUNT;
    VALUES_MERGED := VALUES_MERGED + ROWS_AFFECTED;

    -- attribute option combo dimension
    UPDATE datavalue k
    SET value = r.value, storedby = r.storedby, lastupdated = r.lastupdated,
        comment = r.comment, followup = r.followup, deleted = r.deleted
    FROM datavalue r
    WHERE k.attributeoptioncomboid = KEEP_ID AND r.attributeoptioncomboid = REMOVE_ID
      AND k.dataelementid = r.dataelementid AND k.periodid = r.periodid
      AND k.sourceid = r.sourceid AND k.categoryoptioncomboid = r.categoryoptioncomboid
      AND r.lastupdated > k.lastupdated;

    DELETE FROM datavalue r
    WHERE r.attributeoptioncomboid = REMOVE_ID
      AND EXISTS (
        SELECT 1 FROM datavalue k
        WHERE k.attributeoptioncomboid = KEEP_ID
          AND k.dataelementid = r.dataelementid AND k.periodid = r.periodid
          AND k.sourceid = r.sourceid AND k.categoryoptioncomboid = r.categoryoptioncomboid);
    GET DIAGNOSTICS ROWS_AFFECTED = ROW_COUNT;
    VALUES_MERGED := VALUES_MERGED + ROWS_AFFECTED;

    -- 2. completedatasetregistration: keep the newest registration
    DELETE FROM completedatasetregistration r
    WHERE r.attributeoptioncomboid = REMOVE_ID
      AND EXISTS (
        SELECT 1 FROM completedatasetregistration k
        WHERE k.attributeoptioncomboid = KEEP_ID
          AND k.datasetid = r.datasetid AND k.periodid = r.periodid
          AND k.sourceid = r.sourceid);
    GET DIAGNOSTICS ROWS_AFFECTED = ROW_COUNT;
    VALUES_MERGED := VALUES_MERGED + ROWS_AFFECTED;

    -- 3. minmaxdataelement: drop the duplicate where the keeper has a row
    DELETE FROM minmaxdataelement r
    WHERE r.categoryoptioncomboid = REMOVE_ID
      AND EXISTS (
        SELECT 1 FROM minmaxdataelement k
        WHERE k.categoryoptioncomboid = KEEP_ID
          AND k.dataelementid = r.dataelementid AND k.sourceid = r.sourceid);
    GET DIAGNOSTICS ROWS_AFFECTED = ROW_COUNT;
    VALUES_MERGED := VALUES_MERGED + ROWS_AFFECTED;

    -- 4. Repoint every remaining reference to the duplicate combo,
    --    discovered from the catalog so this works across DHIS2 versions
    --    (data approvals, events, audits, expressions, ...). The category
    --    metadata link tables are excluded — those rows are deleted with
    --    the combo itself.
    FOR FK IN
        SELECT DISTINCT c.conrelid::regclass AS child_table, att.attname AS child_column
        FROM pg_constraint c
        JOIN pg_attribute att ON att.attrelid = c.conrelid AND att.attnum = c.conkey[1]
        WHERE c.confrelid = 'categoryoptioncombo'::regclass
          AND c.contype = 'f'
          AND c.conrelid::regclass::text NOT IN
              ('categoryoptioncombos_categoryoptions', 'categorycombos_optioncombos')
    LOOP
        EXECUTE format('UPDATE %s SET %I = $1 WHERE %I = $2',
            FK.child_table, FK.child_column, FK.child_column)
        USING KEEP_ID, REMOVE_ID;
        GET DIAGNOSTICS ROWS_AFFECTED = ROW_COUNT;
        ROWS_REPOINTED := ROWS_REPOINTED + ROWS_AFFECTED;
    END LOOP;

    -- 5. Delete the duplicate combo and its option/combo links
    DELETE FROM categoryoptioncombos_categoryoptions WHERE categoryoptioncomboid = REMOVE_ID;
    DELETE FROM categorycombos_optioncombos WHERE categoryoptioncomboid = REMOVE_ID;
    DELETE FROM categoryoptioncombo WHERE categoryoptioncomboid = REMOVE_ID;

    RETURN format('Merged %s into %s: %s duplicate rows removed (newest value kept), %s rows repointed',
        remove_uid, keep_uid, VALUES_MERGED, ROWS_REPOINTED);
END
$$;
