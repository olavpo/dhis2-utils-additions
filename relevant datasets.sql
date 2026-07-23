-- 24 periods with more than 50 data values (including only periods with > 50 values)
with 
 de_pe as (select dataelementid,periodid from datavalue group by dataelementid,periodid having count(*) > 50), 
 de_pe_count as (select dataelementid,count(*) from de_pe group by dataelementid having count(*) > 24)
SELECT ds.name as dataset, split_part(de.name, ':', 0) as program, de.name as dataelement, de.uid as dataelement_uid, extract(year from pp.enddate) as yr, extract(year from pp.enddate)::varchar || to_char(extract(month from pp.enddate), 'fm00') as isoperiod, count(dv.dataelementid) FROM dataset ds
LEFT JOIN datasetelement dse on ds.datasetid = dse.datasetid
LEFT JOIN datavalue dv on dv.dataelementid = dse.dataelementid
LEFT JOIN dataelement de on dv.dataelementid = de.dataelementid
LEFT JOIN period pp on dv.periodid = pp.periodid AND pp.periodtypeid = ds.periodtypeid
LEFT JOIN periodtype ppt on ds.periodtypeid = ppt.periodtypeid
where ppt.name in ('Weekly', 'Monthly', 'Quarterly') and 
 dv.deleted = false and
 dv.dataelementid in (select dataelementid from de_pe_count)
GROUP BY ds.name, split_part(de.name, ':', 1), de.name, de.uid, yr, isoperiod
having count(*) > 50
ORDER BY program, de.name, yr, isoperiod, count(dv.dataelementid) DESC;
