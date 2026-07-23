-- delete_where_cascade.sql
--
-- Defines delete_where_cascade(target, condition): deletes the rows in
-- <target> matching <condition>, after first resolving every foreign key
-- that points at those rows:
--
--   * referencing columns that are NULLable are set to NULL
--     (the referencing row is an independent object, e.g. an
--     interpretation pointing at a period)
--   * referencing columns that are NOT NULL cause the referencing rows
--     to be deleted recursively (the row cannot exist without the
--     target, e.g. a data value pointing at a period)
--
-- This makes "delete X and everything hanging off it" version-independent:
-- the referencing tables are discovered from the database catalog at
-- runtime instead of being hardcoded per DHIS2 version.
--
-- Required by delete_data_out_of_range.sql and delete_orgunit_tree.sql:
-- run this file first (functions persist in the database).
--
-- Function: delete_where_cascade(target, condition)
--   target      Table whose rows to delete, e.g. 'period'
--   condition   SQL boolean expression selecting the rows to delete,
--               e.g. 'startdate > ''2100-01-01'''
--   returns     Total number of rows deleted (all tables combined)
--
-- Notes:
--   * Self-referencing foreign keys (e.g. organisationunit.parentid) are
--     skipped: the caller's condition must already include all descendant
--     rows. DHIS2 foreign keys are NO ACTION, checked at end of statement,
--     so deleting a whole subtree in one call is valid.
--   * Multi-column foreign keys are not handled (DHIS2 does not use them);
--     if one exists the final DELETE fails and the transaction rolls back.
--   * Run inside a transaction and check the returned count before
--     committing.

CREATE OR REPLACE FUNCTION delete_where_cascade(target regclass, condition text)
    RETURNS bigint
    LANGUAGE plpgsql
AS
$$
DECLARE
    FK RECORD;
    CHILD_CONDITION text;
    TOTAL_DELETED bigint := 0;
    ROWS_AFFECTED bigint;
BEGIN
    FOR FK IN
        SELECT DISTINCT
            c.conrelid::regclass AS child_table,
            att.attname AS child_column,
            ratt.attname AS parent_column,
            NOT att.attnotnull AS is_nullable
        FROM pg_constraint c
        JOIN pg_attribute att ON att.attrelid = c.conrelid AND att.attnum = c.conkey[1]
        JOIN pg_attribute ratt ON ratt.attrelid = c.confrelid AND ratt.attnum = c.confkey[1]
        WHERE c.confrelid = target
          AND c.contype = 'f'
          AND array_length(c.conkey, 1) = 1
          AND c.conrelid <> target
          -- ON DELETE CASCADE / SET NULL are handled by the database itself
          AND c.confdeltype NOT IN ('c', 'n')
    LOOP
        CHILD_CONDITION := format('%I IN (SELECT %I FROM %s WHERE %s)',
            FK.child_column, FK.parent_column, target, condition);

        IF FK.is_nullable THEN
            EXECUTE format('UPDATE %s SET %I = NULL WHERE %s',
                FK.child_table, FK.child_column, CHILD_CONDITION);
        ELSE
            TOTAL_DELETED := TOTAL_DELETED
                + delete_where_cascade(FK.child_table, CHILD_CONDITION);
        END IF;
    END LOOP;

    EXECUTE format('DELETE FROM %s WHERE %s', target, condition);
    GET DIAGNOSTICS ROWS_AFFECTED = ROW_COUNT;

    RETURN TOTAL_DELETED + ROWS_AFFECTED;
END
$$;

-- Companion function: delete_orphan_relationships()
--
-- A tracker relationship points at its ends through relationshipitem rows
-- whose target references (tracked entity, enrollment, event) are NULLable.
-- When a cascade delete removes a relationship's target, the item is left
-- pointing at nothing. This deletes relationships where either end has no
-- remaining target (the item rows follow via ON DELETE CASCADE). The
-- target columns are discovered from the catalog, so the same function
-- works across DHIS2 versions.

CREATE OR REPLACE FUNCTION delete_orphan_relationships()
    RETURNS bigint
    LANGUAGE plpgsql
AS
$$
DECLARE
    NULL_CONDITION text;
    ROWS_AFFECTED bigint := 0;
BEGIN
    IF to_regclass('public.relationshipitem') IS NULL THEN
        RETURN 0;
    END IF;

    SELECT string_agg(format('%I IS NULL', att.attname), ' AND ')
    INTO NULL_CONDITION
    FROM (
        SELECT DISTINCT att.attname
        FROM pg_constraint c
        JOIN pg_attribute att ON att.attrelid = c.conrelid AND att.attnum = c.conkey[1]
        WHERE c.conrelid = 'relationshipitem'::regclass
          AND c.contype = 'f'
          AND c.confrelid <> 'relationship'::regclass
          AND c.confrelid <> 'userinfo'::regclass
    ) att;

    IF NULL_CONDITION IS NULL THEN
        RETURN 0;
    END IF;

    EXECUTE format(
        'DELETE FROM relationship r
         WHERE EXISTS (
             SELECT 1 FROM relationshipitem ri
             WHERE ri.relationshipid = r.relationshipid AND %s)',
        NULL_CONDITION);
    GET DIAGNOSTICS ROWS_AFFECTED = ROW_COUNT;
    RETURN ROWS_AFFECTED;
END
$$;

-- Example: delete one organisation unit that has data values
-- BEGIN;
-- SELECT delete_where_cascade('organisationunit', 'uid = ''AAAAAAAAAAA''');
-- SELECT delete_orphan_relationships();
-- COMMIT;
