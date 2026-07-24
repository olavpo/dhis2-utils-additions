-- generate_completeness.sql
--
-- Generates complete data set registrations from existing data values:
-- a (dataset, period, orgunit) combination is marked complete when at
-- least <min_values> data values exist for the dataset's data elements.
-- Existing registrations are never touched.
--
-- Use for demo/training databases where data was imported without
-- completeness information, so that reporting-rate analytics work.
--
-- Function: generate_completeness(dataset_uid, min_values)
--   dataset_uid   Dataset to generate registrations for
--   min_values    Minimum data values for a period/orgunit to count as
--                 complete (default 1)
--   returns       Number of registrations created
--
--   BEGIN;
--   SELECT generate_completeness('BfMAe6Itzgt', 5);
--   COMMIT;
--
-- Registrations are attributed to 'auto-generated' with the newest
-- data value's timestamp as the completion date. Data elements shared
-- with other datasets count toward this dataset too — completeness by
-- data values is inherently approximate.
--
-- Run Analytics Tables export afterwards.

CREATE OR REPLACE FUNCTION generate_completeness(dataset_uid text, min_values integer DEFAULT 1)
    RETURNS bigint
    LANGUAGE plpgsql
AS
$$
DECLARE
    DATASET_ID bigint;
    DEFAULT_AOC bigint;
    ROWS_CREATED bigint;
BEGIN
    SELECT datasetid INTO DATASET_ID FROM dataset WHERE uid = dataset_uid;
    IF DATASET_ID IS NULL THEN
        RAISE EXCEPTION 'No dataset with uid %', dataset_uid;
    END IF;

    SELECT coc.categoryoptioncomboid INTO DEFAULT_AOC
    FROM categoryoptioncombo coc
    INNER JOIN categorycombos_optioncombos ccoc ON coc.categoryoptioncomboid = ccoc.categoryoptioncomboid
    INNER JOIN categorycombo cc ON ccoc.categorycomboid = cc.categorycomboid
    WHERE cc.name = 'default'
    LIMIT 1;

    CREATE TEMP TABLE tbl_new_registrations ON COMMIT DROP AS
    SELECT
        DATASET_ID AS datasetid,
        dv.periodid,
        dv.sourceid,
        max(dv.lastupdated) AS completed_date
    FROM datavalue dv
    INNER JOIN datasetelement dse ON dv.dataelementid = dse.dataelementid
    INNER JOIN period pe ON dv.periodid = pe.periodid
    INNER JOIN dataset ds ON ds.datasetid = dse.datasetid
        AND ds.periodtypeid = pe.periodtypeid
    WHERE dse.datasetid = DATASET_ID
      AND NOT EXISTS (
        SELECT 1 FROM completedatasetregistration cr
        WHERE cr.datasetid = DATASET_ID
          AND cr.periodid = dv.periodid
          AND cr.sourceid = dv.sourceid)
    GROUP BY dv.periodid, dv.sourceid
    HAVING count(*) >= min_values;

    INSERT INTO completedatasetregistration
        (datasetid, periodid, sourceid, attributeoptioncomboid,
         date, storedby, lastupdated, completed)
    SELECT datasetid, periodid, sourceid, DEFAULT_AOC,
           completed_date, 'auto-generated', now(), true
    FROM tbl_new_registrations;

    GET DIAGNOSTICS ROWS_CREATED = ROW_COUNT;
    RETURN ROWS_CREATED;
END
$$;
