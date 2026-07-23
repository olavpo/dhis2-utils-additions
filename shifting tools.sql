-- function for moving data elements
CREATE OR REPLACE FUNCTION move_data_fwd_by_de (period_type text, dataelement_uid text, num_periods_behind double precision) RETURNS boolean
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
        CASE WHEN pt.name = 'Daily' THEN DATE(pp.startdate + (num_periods_behind * INTERVAL '1 DAY'))
             WHEN pt.name = 'Weekly' THEN DATE(pp.startdate + (num_periods_behind * INTERVAL '7 DAY'))
             WHEN pt.name = 'Monthly' THEN DATE(date_trunc('month', pp.startdate + (num_periods_behind * INTERVAL '1 MONTH')))
             WHEN pt.name = 'Quarterly' THEN DATE(date_trunc('quarter', pp.startdate + (num_periods_behind * INTERVAL '3 MONTH')))
             WHEN pt.name = 'Yearly' THEN DATE(date_trunc('year', pp.startdate + (num_periods_behind * INTERVAL '1 YEAR')))
             WHEN pt.name = 'SixMonthly' THEN DATE(date_trunc('month', pp.startdate + (num_periods_behind * INTERVAL '6 MONTH')))
        END as new_date
        FROM datavalue dv
        INNER JOIN datasetelement dse ON dv.dataelementid = dse.dataelementid
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


-- overview of data
SELECT *
FROM CROSSTAB($$
	SELECT ds.name,
	ds.uid,
	'_' || extract(year from pp.enddate)::varchar || to_char(extract(month from pp.enddate), 'fm00') as isoperiod,
	count(dv.dataelementid) FROM dataset ds
LEFT JOIN datasetelement dse on ds.datasetid = dse.datasetid
LEFT JOIN datavalue dv on dv.dataelementid = dse.dataelementid
LEFT JOIN period pp on dv.periodid = pp.periodid AND pp.periodtypeid = ds.periodtypeid
LEFT JOIN periodtype ppt on ds.periodtypeid = ppt.periodtypeid
where ppt.name in ('Monthly') and dv.deleted = false-- and ds.name like 'CH - %'
GROUP BY ds.name, ds.uid, isoperiod
ORDER BY ds.name, isoperiod, count(dv.dataelementid) DESC
	$$, $$
	select unnest(array['_202207', '_202208', '_202209', '_202210', '_202211', '_202212', '_202301', '_202302', '_202303', '_202304', '_202305', '_202306', '_202307', '_202308', '_202309', '_202310', '_202311', '_202312'])
	$$) AS FINAL (NAME TEXT, uid text, _202207 NUMERIC, _202208 NUMERIC, _202209 NUMERIC, _202210 NUMERIC, _202211 NUMERIC, _202212 NUMERIC, _202301 NUMERIC, _202302 NUMERIC, _202303 NUMERIC, _202304 NUMERIC, _202305 NUMERIC, _202306 NUMERIC, _202307 NUMERIC, _202308 NUMERIC, _202309 NUMERIC, _202310 NUMERIC, _202311 NUMERIC, _202312 NUMERIC);

-- check for reuse of data elements
with dupes as (
select 
	dse.dataelementid, 
	de.name,
	count(*) 
from 
	datasetelement dse
left join dataelement de using(dataelementid)
where 
	dse.dataelementid in (
		select dataelementid from datasetelement dse2 where dse2.datasetid in (
			select datasetid from dataset where uid in ('ujLQPjUBfVR', 'JGZd3naC9Qx')
	))
group by dse.dataelementid, de.name having count(*) > 1 order by dse.dataelementid
)
select ds.name, de.name from datasetelement dse left join dataelement de using(dataelementid) left join dataset ds using(datasetid) where dse.dataelementid in (select dataelementid from dupes);

--move data
with des as (
select de.uid de_uid, pt.name ds_ptype 
from 
	datasetelement dse 
	left join dataset ds using(datasetid)
	left join periodtype pt using(periodtypeid) 
	left join dataelement de using(dataelementid)
where 
	ds.uid in ('ujLQPjUBfVR', 'JGZd3naC9Qx') and
	pt.name = 'Monthly' and 
	de.dataelementid not in (select generatoroutput from predictor)
group by de.uid, pt.name
order by de.uid, pt.name
	)
select move_data_fwd_by_de(ds_ptype, de_uid, 3) from des;
