-- shift_aggregate_periods.sql
--
-- Shifts aggregate data values (the datavalue table) forward in time.
-- Intended for keeping demo/training databases current: data that has fallen
-- behind is moved forward so it appears recent.
--
-- Contains two functions and a catch-up query:
--
--   shift_dataset_periods(period_type, dataset_uid, num_periods)
--       Shifts all data values of one dataset's data elements.
--
--   shift_dataelement_periods(period_type, dataelement_uid, num_periods)
--       Shifts all data values of a single data element. Prefer this one
--       when data elements are shared between datasets, to avoid shifting
--       the same values once per dataset.
--
--   Catch-up query (bottom of file): brings ALL aggregate data up to the
--       present. Works per data element: each data element is shifted by
--       the lag of its least-behind dataset, and predictor-generated data
--       elements are skipped (regenerate those with the predictor instead).
--
-- Arguments:
--   period_type       'Daily', 'Weekly', 'Monthly', 'Quarterly',
--                     'SixMonthly' or 'Yearly'
--   *_uid             UID of the dataset / data element
--   num_periods       Number of periods to shift forward (positive only)
--
-- Target periods that do not yet exist in the period table are created
-- automatically (period ids are drawn from the sequence appropriate to the
-- DHIS2 version).
--
-- NOTES:
--   * Shift forward only. Values are moved one period at a time, newest
--     first, so each target period is vacated before older values arrive; a
--     backward shift can abort with a duplicate-key error (any failure rolls
--     back cleanly - no partial update).
--   * Restart DHIS2 afterwards (it caches periods) and run "Analytics
--     Tables" export for the shift to be visible in analytics.
--   * Only touches the datavalue table (aggregate data); use
--     shift_tracker_dates.sql for tracker/event data.
--   * Tested on DHIS2 2.40-2.43 (Sierra Leone demo database).


CREATE OR REPLACE FUNCTION shift_dataset_periods (period_type text, dataset_uid text, num_periods double precision) RETURNS boolean
    LANGUAGE plpgsql
AS
$$
DECLARE
    period_sequence text;
    OLD_PERIOD RECORD;
    iso_column text := '';
    iso_value text := '';
BEGIN
    -- 2.43+ has a NOT NULL iso column on period holding the ISO period
    -- name (e.g. 202607, 2026Q3, 2026W27); populate it when present.
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'period'
                 AND column_name = 'iso') THEN
        iso_column := ', iso';
        iso_value := $iso$,
            CASE WHEN t.frequency = 'Daily' THEN to_char(t.new_date, 'YYYYMMDD')
                 WHEN t.frequency = 'Weekly' THEN to_char(t.new_date, 'IYYY') || 'W' || date_part('week', t.new_date)::int
                 WHEN t.frequency = 'Monthly' THEN to_char(t.new_date, 'YYYYMM')
                 WHEN t.frequency = 'Quarterly' THEN to_char(t.new_date, 'YYYY"Q"Q')
                 WHEN t.frequency = 'SixMonthly' THEN to_char(t.new_date, 'YYYY') || 'S' || (CASE WHEN date_part('month', t.new_date) < 7 THEN 1 ELSE 2 END)
                 WHEN t.frequency = 'Yearly' THEN to_char(t.new_date, 'YYYY')
            END$iso$;
    END IF;
    -- DHIS2 <= 2.40 draws period ids from hibernate_sequence; 2.41+ has a
    -- dedicated sequence.
    SELECT CASE WHEN to_regclass('public.period_seq') IS NOT NULL
                THEN 'period_seq' ELSE 'hibernate_sequence' END
    INTO period_sequence;

    DROP TABLE IF EXISTS tbl_shift_date;
    CREATE TEMP TABLE tbl_shift_date AS
    SELECT
        dv.dataelementid,
        sourceid,
        categoryoptioncomboid,
        attributeoptioncomboid,
        dv.periodid as old_periodid,
        pt.name as frequency,
        pp.periodtypeid, pp.startdate,
        CASE WHEN pt.name = 'Daily' THEN DATE(pp.startdate + (num_periods * INTERVAL '1 DAY'))
             WHEN pt.name = 'Weekly' THEN DATE(pp.startdate + (num_periods * INTERVAL '7 DAY'))
             WHEN pt.name = 'Monthly' THEN DATE(date_trunc('month', pp.startdate + (num_periods * INTERVAL '1 MONTH')))
             WHEN pt.name = 'Quarterly' THEN DATE(date_trunc('quarter', pp.startdate + (num_periods * INTERVAL '3 MONTH')))
             WHEN pt.name = 'Yearly' THEN DATE(date_trunc('year', pp.startdate + (num_periods * INTERVAL '1 YEAR')))
             WHEN pt.name = 'SixMonthly' THEN DATE(date_trunc('month', pp.startdate + (num_periods * INTERVAL '6 MONTH')))
        END as new_date
    FROM datavalue dv
    INNER JOIN datasetelement dse ON dv.dataelementid = dse.dataelementid
    INNER JOIN dataset ds ON ds.datasetid = dse.datasetid
    LEFT JOIN period pp on dv.periodid = pp.periodid
    LEFT JOIN periodtype pt on pp.periodtypeid = pt.periodtypeid
    WHERE ds.datasetid = (SELECT datasetid FROM dataset WHERE uid = dataset_uid)
    ORDER BY pp.startdate DESC;

    -- Create any target periods that do not exist yet
    EXECUTE format($ins$
        INSERT INTO period (periodid, periodtypeid, startdate, enddate%3$s)
        SELECT nextval(%1$L), t.periodtypeid, t.new_date,
            CASE WHEN t.frequency = 'Daily' THEN t.new_date
                 WHEN t.frequency = 'Weekly' THEN t.new_date + 6
                 WHEN t.frequency = 'Monthly' THEN (t.new_date + INTERVAL '1 MONTH - 1 DAY')::date
                 WHEN t.frequency = 'Quarterly' THEN (t.new_date + INTERVAL '3 MONTH - 1 DAY')::date
                 WHEN t.frequency = 'SixMonthly' THEN (t.new_date + INTERVAL '6 MONTH - 1 DAY')::date
                 WHEN t.frequency = 'Yearly' THEN (t.new_date + INTERVAL '1 YEAR - 1 DAY')::date
            END%4$s
        FROM (SELECT DISTINCT periodtypeid, frequency, new_date
              FROM tbl_shift_date WHERE new_date IS NOT NULL AND frequency = %2$L) t
        WHERE NOT EXISTS (
            SELECT 1 FROM period p
            WHERE p.periodtypeid = t.periodtypeid AND p.startdate = t.new_date)
    $ins$, period_sequence, period_type, iso_column, iso_value);

    CREATE INDEX ON tbl_shift_date (old_periodid);

    -- Move one period at a time, newest first, so each target period has
    -- been vacated before older values arrive (avoids transient duplicate
    -- keys on the datavalue primary key).
    FOR OLD_PERIOD IN
        SELECT DISTINCT old_periodid, startdate FROM tbl_shift_date
        WHERE frequency = period_type
        ORDER BY startdate DESC
    LOOP
        UPDATE datavalue dv
        SET periodid = new_period.periodid
        FROM tbl_shift_date
        INNER JOIN period new_period on tbl_shift_date.periodtypeid = new_period.periodtypeid AND new_period.startdate = tbl_shift_date.new_date
        WHERE
            tbl_shift_date.old_periodid = OLD_PERIOD.old_periodid AND
            dv.dataelementid = tbl_shift_date.dataelementid AND
            dv.sourceid = tbl_shift_date.sourceid AND
            dv.categoryoptioncomboid = tbl_shift_date.categoryoptioncomboid AND
            dv.attributeoptioncomboid = tbl_shift_date.attributeoptioncomboid AND
            dv.periodid = tbl_shift_date.old_periodid;
    END LOOP;

    DROP TABLE tbl_shift_date;

    RETURN TRUE;
END
$$;


CREATE OR REPLACE FUNCTION shift_dataelement_periods (period_type text, dataelement_uid text, num_periods double precision) RETURNS boolean
    LANGUAGE plpgsql
AS
$$
DECLARE
    period_sequence text;
    OLD_PERIOD RECORD;
    iso_column text := '';
    iso_value text := '';
BEGIN
    -- 2.43+ has a NOT NULL iso column on period holding the ISO period
    -- name (e.g. 202607, 2026Q3, 2026W27); populate it when present.
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'period'
                 AND column_name = 'iso') THEN
        iso_column := ', iso';
        iso_value := $iso$,
            CASE WHEN t.frequency = 'Daily' THEN to_char(t.new_date, 'YYYYMMDD')
                 WHEN t.frequency = 'Weekly' THEN to_char(t.new_date, 'IYYY') || 'W' || date_part('week', t.new_date)::int
                 WHEN t.frequency = 'Monthly' THEN to_char(t.new_date, 'YYYYMM')
                 WHEN t.frequency = 'Quarterly' THEN to_char(t.new_date, 'YYYY"Q"Q')
                 WHEN t.frequency = 'SixMonthly' THEN to_char(t.new_date, 'YYYY') || 'S' || (CASE WHEN date_part('month', t.new_date) < 7 THEN 1 ELSE 2 END)
                 WHEN t.frequency = 'Yearly' THEN to_char(t.new_date, 'YYYY')
            END$iso$;
    END IF;
    -- DHIS2 <= 2.40 draws period ids from hibernate_sequence; 2.41+ has a
    -- dedicated sequence.
    SELECT CASE WHEN to_regclass('public.period_seq') IS NOT NULL
                THEN 'period_seq' ELSE 'hibernate_sequence' END
    INTO period_sequence;

    DROP TABLE IF EXISTS tbl_shift_date;
    CREATE TEMP TABLE tbl_shift_date AS
    SELECT
        dv.dataelementid,
        sourceid,
        categoryoptioncomboid,
        attributeoptioncomboid,
        dv.periodid as old_periodid,
        pt.name as frequency,
        pp.periodtypeid, pp.startdate,
        CASE WHEN pt.name = 'Daily' THEN DATE(pp.startdate + (num_periods * INTERVAL '1 DAY'))
             WHEN pt.name = 'Weekly' THEN DATE(pp.startdate + (num_periods * INTERVAL '7 DAY'))
             WHEN pt.name = 'Monthly' THEN DATE(date_trunc('month', pp.startdate + (num_periods * INTERVAL '1 MONTH')))
             WHEN pt.name = 'Quarterly' THEN DATE(date_trunc('quarter', pp.startdate + (num_periods * INTERVAL '3 MONTH')))
             WHEN pt.name = 'Yearly' THEN DATE(date_trunc('year', pp.startdate + (num_periods * INTERVAL '1 YEAR')))
             WHEN pt.name = 'SixMonthly' THEN DATE(date_trunc('month', pp.startdate + (num_periods * INTERVAL '6 MONTH')))
        END as new_date
    FROM datavalue dv
    LEFT JOIN period pp on dv.periodid = pp.periodid
    LEFT JOIN periodtype pt on pp.periodtypeid = pt.periodtypeid
    WHERE dv.dataelementid = (select dataelementid from dataelement where uid = dataelement_uid)
    ORDER BY pp.startdate DESC;

    -- Create any target periods that do not exist yet
    EXECUTE format($ins$
        INSERT INTO period (periodid, periodtypeid, startdate, enddate%3$s)
        SELECT nextval(%1$L), t.periodtypeid, t.new_date,
            CASE WHEN t.frequency = 'Daily' THEN t.new_date
                 WHEN t.frequency = 'Weekly' THEN t.new_date + 6
                 WHEN t.frequency = 'Monthly' THEN (t.new_date + INTERVAL '1 MONTH - 1 DAY')::date
                 WHEN t.frequency = 'Quarterly' THEN (t.new_date + INTERVAL '3 MONTH - 1 DAY')::date
                 WHEN t.frequency = 'SixMonthly' THEN (t.new_date + INTERVAL '6 MONTH - 1 DAY')::date
                 WHEN t.frequency = 'Yearly' THEN (t.new_date + INTERVAL '1 YEAR - 1 DAY')::date
            END%4$s
        FROM (SELECT DISTINCT periodtypeid, frequency, new_date
              FROM tbl_shift_date WHERE new_date IS NOT NULL AND frequency = %2$L) t
        WHERE NOT EXISTS (
            SELECT 1 FROM period p
            WHERE p.periodtypeid = t.periodtypeid AND p.startdate = t.new_date)
    $ins$, period_sequence, period_type, iso_column, iso_value);

    CREATE INDEX ON tbl_shift_date (old_periodid);

    -- Move one period at a time, newest first, so each target period has
    -- been vacated before older values arrive (avoids transient duplicate
    -- keys on the datavalue primary key).
    FOR OLD_PERIOD IN
        SELECT DISTINCT old_periodid, startdate FROM tbl_shift_date
        WHERE frequency = period_type
        ORDER BY startdate DESC
    LOOP
        UPDATE datavalue dv
        SET periodid = new_period.periodid
        FROM tbl_shift_date
        INNER JOIN period new_period on tbl_shift_date.periodtypeid = new_period.periodtypeid AND new_period.startdate = tbl_shift_date.new_date
        WHERE
            tbl_shift_date.old_periodid = OLD_PERIOD.old_periodid AND
            dv.dataelementid = tbl_shift_date.dataelementid AND
            dv.sourceid = tbl_shift_date.sourceid AND
            dv.categoryoptioncomboid = tbl_shift_date.categoryoptioncomboid AND
            dv.attributeoptioncomboid = tbl_shift_date.attributeoptioncomboid AND
            dv.periodid = tbl_shift_date.old_periodid;
    END LOOP;

    DROP TABLE tbl_shift_date;

    RETURN TRUE;
END
$$;


-- Catch-up: shift ALL aggregate data that is behind up to the present.
--
-- Calculates, per dataset, how many periods behind its newest data is. Each
-- data element is then shifted ONCE, by the smallest lag among the datasets
-- it belongs to (data elements shared between datasets would otherwise be
-- shifted once per dataset). Predictor-generated data elements are skipped -
-- rerun the predictors afterwards instead.
WITH ds_lag AS (
    SELECT
        ds.datasetid,
        pt.name AS period_type,
        max(pp.enddate) AS max_enddate,
        CASE
            WHEN pt.name = 'Daily' THEN abs(max(pp.enddate)::date - now()::date)
            WHEN pt.name = 'Weekly' THEN ceil(abs(max(pp.enddate)::date - now()::date)/7)-1
            WHEN pt.name = 'Monthly' THEN ceil(abs(max(pp.enddate)::date - now()::date)/(365.25/12))-1
            WHEN pt.name = 'Quarterly' THEN round(abs(max(pp.enddate)::date - now()::date)/(365.25/4))-1
            WHEN pt.name = 'Yearly' THEN ceil(abs(max(pp.enddate)::date - now()::date)/(365.25))-1
            WHEN pt.name = 'SixMonthly' THEN round(abs(max(pp.enddate)::date - now()::date)/(365.25/2))-1
        END AS lag
    FROM datavalue dv
    INNER JOIN datasetelement dse ON dv.dataelementid = dse.dataelementid
    INNER JOIN dataset ds ON ds.datasetid = dse.datasetid
    INNER JOIN period pp ON dv.periodid = pp.periodid AND pp.periodtypeid = ds.periodtypeid
    INNER JOIN periodtype pt ON pp.periodtypeid = pt.periodtypeid
    GROUP BY ds.datasetid, pt.name
    HAVING max(pp.enddate)::date < now()::date
),
de_lag AS (
    SELECT de.uid AS de_uid, de.name AS de_name, dl.period_type, min(dl.lag) AS lag
    FROM datasetelement dse
    INNER JOIN ds_lag dl ON dse.datasetid = dl.datasetid
    INNER JOIN dataelement de ON dse.dataelementid = de.dataelementid
    WHERE de.dataelementid NOT IN (
        SELECT generatoroutput FROM predictor WHERE generatoroutput IS NOT NULL)
    GROUP BY de.uid, de.name, dl.period_type
)
SELECT de_name, period_type, lag, shift_dataelement_periods(period_type, de_uid, lag)
FROM de_lag
WHERE lag >= 1
ORDER BY de_name;
