CREATE OR REPLACE FUNCTION UpdateDataAGGDateByUid (period_type text, dataset_uid text, num_periods_behind double precision) RETURNS boolean
    LANGUAGE plpgsql
AS
$$
DECLARE
BEGIN

    WITH tbl_shift_date as
    (
        SELECT
        --ds.uid, ds.periodtypeid,
        dv.dataelementid,
        sourceid,
        categoryoptioncomboid,
        attributeoptioncomboid,
        value,
        dv.periodid as old_periodid,
        pt.name as frequency,
        pp.periodtypeid, pp.startdate,
        CASE WHEN pt.name = 'Daily' THEN DATE(pp.startdate + (num_periods_behind * INTERVAL '1 DAY'))
             WHEN pt.name = 'Weekly' THEN DATE(pp.startdate + (num_periods_behind * INTERVAL '7 DAY'))
             WHEN pt.name = 'Monthly' THEN DATE(date_trunc('month', pp.startdate + (num_periods_behind * INTERVAL '1 MONTH')))
             WHEN pt.name = 'Quarterly' THEN DATE(date_trunc('quarter', pp.startdate + (num_periods_behind * INTERVAL '3 MONTH')))
             WHEN pt.name = 'Yearly' THEN DATE(date_trunc('year', pp.startdate + (num_periods_behind * INTERVAL '1 YEAR')))
             WHEN pt.name = 'SixMonthly' THEN DATE(date_trunc('month', pp.startdate + (num_periods_behind * INTERVAL '6 MONTH')))
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

CREATE OR REPLACE FUNCTION UpdateDataTRKandEVTDate (number_days integer) RETURNS boolean
    LANGUAGE plpgsql
AS
$$
DECLARE
    TABLE_RECORD RECORD;
BEGIN

     -- Only required for Tracker: Update enrollment date
     UPDATE programinstance
     SET enrollmentdate = enrollmentdate::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL,
         lastupdated = NOW();

     -- Only required for Tracker: Update TEA values for enrollments
     UPDATE trackedentityattributevalue teav
     SET value = DATE(value::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL)
     FROM trackedentityattribute tea
     WHERE tea.trackedentityattributeid = teav.trackedentityattributeid AND
     tea.valuetype = 'DATE';

     -- Update event dates
     UPDATE programstageinstance
     SET executiondate = executiondate::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL,
         duedate = duedate::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL,
         completeddate = completeddate::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL,
         lastupdated = NOW();

    -- Update DE values for events
    FOR TABLE_RECORD IN
        select psi.programstageinstanceid,
           ('{'||js.key||',value}')::TEXT[] as path,
           ('"'||TEXT(DATE(to_timestamp(replace(js_value.value::TEXT, '"', ''), 'YYYY-MM-DD') + (number_days::TEXT || ' DAY')::INTERVAL))||'"')::jsonb as value
        from programstageinstance psi, jsonb_each(eventdatavalues::jsonb) as js, jsonb_each(js.value) as js_value
        where js.key IN (SELECT uid FROM dataelement WHERE valuetype = 'DATE') AND js_value.key = 'value'
    LOOP
        UPDATE programstageinstance psi
        SET eventdatavalues = jsonb_set(eventdatavalues, TABLE_RECORD.path, TABLE_RECORD.value)
        WHERE psi.programstageinstanceid = TABLE_RECORD.programstageinstanceid;
    END LOOP;

    RETURN TRUE;
END
$$;

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
INNER JOIN _periodstructure p on pp.periodid = p.periodid
GROUP BY ds.name, ds.uid, pt.name
)
SELECT UpdateDataAGGDateByUid(periodType, datasetid, number_periods_from_today) FROM source
WHERE is_behind = 'y' AND number_periods_from_today >= 1;

SELECT UpdateDataTRKandEVTDate(7);
