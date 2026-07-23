-- shift_dataset_periods.sql
--
-- Shifts aggregate data values forward in time, dataset by dataset. Intended
-- for keeping demo/training databases current: data that has fallen behind is
-- moved forward so it appears recent.
--
-- Function: shift_dataset_periods(period_type, dataset_uid, num_periods)
--   period_type   Period type name of the dataset ('Daily', 'Weekly',
--                 'Monthly', 'Quarterly', 'SixMonthly', 'Yearly')
--   dataset_uid   UID of the dataset whose data values should be shifted
--   num_periods   Number of periods to shift forward
--
-- The target period must already exist in the period table for a value to be
-- moved (rows are matched against existing periods; missing target periods
-- mean those values are silently left in place).
--
-- The helper view/query at the bottom shifts ALL datasets that are behind
-- today's date up to the present in one go.
--
-- NOTE: run "Analytics Tables" export afterwards for the shift to be visible
-- in analytics. Only touches the datavalue table (aggregate data); use
-- shift_tracker_dates.sql for tracker/event data.

CREATE OR REPLACE FUNCTION shift_dataset_periods (period_type text, dataset_uid text, num_periods double precision) RETURNS boolean
    LANGUAGE plpgsql
AS
$$
DECLARE
BEGIN

    WITH tbl_shift_date as
    (
        SELECT
        dv.dataelementid,
        sourceid,
        categoryoptioncomboid,
        attributeoptioncomboid,
        value,
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
        ORDER BY pp.startdate DESC
    )
    UPDATE datavalue dv
    SET periodid = new_period.periodid
    FROM tbl_shift_date
    INNER JOIN period new_period on tbl_shift_date.periodtypeid = new_period.periodtypeid AND new_period.startdate = tbl_shift_date.new_date
    WHERE
        dv.dataelementid = tbl_shift_date.dataelementid AND
        dv.sourceid = tbl_shift_date.sourceid AND
        dv.categoryoptioncomboid = tbl_shift_date.categoryoptioncomboid AND
        dv.attributeoptioncomboid = tbl_shift_date.attributeoptioncomboid AND
        dv.value = tbl_shift_date.value AND -- Not part of the unique key
        dv.periodid = tbl_shift_date.old_periodid AND
        tbl_shift_date.frequency = period_type;

    RETURN TRUE;
END
$$;


-- Shift ALL datasets that are behind up to the present.
-- Reviews every dataset with data, calculates how many periods behind its
-- newest data is, and calls shift_dataset_periods() for each dataset that is
-- at least one full period behind.
WITH source as (
  SELECT ds.name as dataSet, ds.uid as datasetid, pt.name as periodType, min(pp.startDate), max(pp.endDate),
  CASE
        WHEN max(pp.endDate):: date < now() :: date THEN 'y'
        ELSE 'n'
  END as is_behind,
  CASE
    WHEN pt.name = 'Daily' THEN abs(max(pp.endDate):: date - now() :: date)
    WHEN pt.name = 'Weekly' THEN ceil(abs(max(pp.endDate):: date - now() :: date)/7)-1
    WHEN pt.name = 'Monthly' THEN ceil(abs(max(pp.endDate):: date - now() :: date)/(365.25/12))-1
    WHEN pt.name = 'Quarterly' THEN round(abs(max(pp.endDate):: date - now() :: date)/(365.25/4))-1
    WHEN pt.name = 'Yearly' THEN ceil(abs(max(pp.endDate):: date - now() :: date)/(365.25))-1
    WHEN pt.name = 'SixMonthly' THEN round(abs(max(pp.endDate):: date - now() :: date)/(365.25/2))-1
  END as number_periods_from_today
FROM datavalue dv
INNER JOIN datasetelement dse ON dv.dataelementid = dse.dataelementid
INNER JOIN dataset ds ON ds.datasetid = dse.datasetid
INNER JOIN period pp ON dv.periodid = pp.periodid AND pp.periodtypeid = ds.periodtypeid
INNER JOIN periodtype pt ON pp.periodtypeid = pt.periodtypeid
GROUP BY ds.name, ds.uid, pt.name
)
SELECT dataSet, periodType, number_periods_from_today, shift_dataset_periods(periodType, datasetid, number_periods_from_today)
FROM source
WHERE is_behind = 'y' AND number_periods_from_today >= 1;
