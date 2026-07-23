-- delete_all_data.sql
--
-- Deletes ALL data from a DHIS2 database while keeping metadata, users
-- and configuration: aggregate data values, complete registrations,
-- approvals, tracked entities, enrollments, events, relationships and
-- the related audit/message tables. The result is a metadata-only
-- database, e.g. for turning a production copy into a clean training or
-- development instance.
--
-- THIS IS IRREVERSIBLE BY DESIGN. Take a backup first. Never run against
-- a production database.
--
-- Requires delete_where_cascade.sql to have been run first.
--
--   BEGIN;
--   SELECT delete_all_data();
--   COMMIT;
--
-- Afterwards, restart DHIS2 and run Analytics Tables export. Note that
-- file resources belonging to deleted values are left behind; DHIS2's
-- "Remove expired file resources" job cleans them up.

CREATE OR REPLACE FUNCTION delete_all_data()
    RETURNS TABLE (entity text, rows_deleted bigint)
    LANGUAGE plpgsql
AS
$$
DECLARE
    ROOT_TABLE text;
    DATA_TABLE text;
    ROWS_AFFECTED bigint;
BEGIN
    -- Relationships first (their item rows follow via ON DELETE CASCADE)
    IF to_regclass('public.relationship') IS NOT NULL THEN
        DELETE FROM relationship;
        GET DIAGNOSTICS ROWS_AFFECTED = ROW_COUNT;
        entity := 'relationship'; rows_deleted := ROWS_AFFECTED;
        RETURN NEXT;
    END IF;

    -- Tracker roots: tracked entities (2.40: trackedentityinstance,
    -- 2.41+: trackedentity), then enrollments (2.40: programinstance,
    -- 2.41+: enrollment) which also covers event programs. Everything
    -- hanging off them (attribute values, events, data value audits,
    -- notes, ownership...) is resolved through the foreign keys.
    FOREACH ROOT_TABLE IN ARRAY ARRAY[
        'trackedentityinstance', 'trackedentity',
        'programinstance', 'enrollment']
    LOOP
        CONTINUE WHEN to_regclass('public.' || ROOT_TABLE) IS NULL;
        entity := ROOT_TABLE;
        rows_deleted := delete_where_cascade(ROOT_TABLE::regclass, 'true');
        RETURN NEXT;
    END LOOP;

    -- Aggregate data and remaining data-only tables. Names vary across
    -- versions; missing tables are skipped.
    FOREACH DATA_TABLE IN ARRAY ARRAY[
        'datavalueaudit',
        'datavalue',
        'completedatasetregistration',
        'dataapprovalaudit',
        'dataapproval',
        'validationresult',
        'trackedentityinstanceaudit',
        'trackedentityaudit',
        'trackedentityattributevalueaudit',
        'trackedentitydatavalueaudit',
        'eventchangelog',
        'trackedentitychangelog',
        'programmessage',
        'programnotificationinstance',
        'potentialduplicate',
        'reservedvalue',
        'sequentialnumbercounter',
        'datastatisticsevent',
        'completenessyearlyseries']
    LOOP
        CONTINUE WHEN to_regclass('public.' || DATA_TABLE) IS NULL;
        ROWS_AFFECTED := delete_where_cascade(DATA_TABLE::regclass, 'true');
        IF ROWS_AFFECTED > 0 THEN
            entity := DATA_TABLE; rows_deleted := ROWS_AFFECTED;
            RETURN NEXT;
        END IF;
    END LOOP;

    RETURN;
END
$$;
