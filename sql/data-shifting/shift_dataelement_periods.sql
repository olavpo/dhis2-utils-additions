-- shift_dataelement_periods.sql
--
-- Shifts aggregate data values forward in time for a single data element.
-- The data-element-level twin of shift_dataset_periods.sql — useful when
-- different data elements within the same dataset need different shifts, or
-- when a data element belongs to several datasets and shifting per dataset
-- would double-shift shared elements.
--
-- Function: shift_dataelement_periods(period_type, dataelement_uid, num_periods)
--   period_type      Period type of the data to shift ('Daily', 'Weekly',
--                    'Monthly', 'Quarterly', 'SixMonthly', 'Yearly')
--   dataelement_uid  UID of the data element whose values should be shifted
--   num_periods      Number of periods to shift forward
--
-- The target period must already exist in the period table for a value to be
-- moved. Values calculated by predictors are typically excluded by the caller
-- (see the examples in the README) so they can be regenerated instead.
--
-- NOTE: run "Analytics Tables" export afterwards for the shift to be visible
-- in analytics.

CREATE OR REPLACE FUNCTION shift_dataelement_periods (period_type text, dataelement_uid text, num_periods double precision) RETURNS boolean
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
        LEFT JOIN period pp on dv.periodid = pp.periodid
        LEFT JOIN periodtype pt on pp.periodtypeid = pt.periodtypeid
        WHERE dv.dataelementid = (select dataelementid from dataelement where uid = dataelement_uid)
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
