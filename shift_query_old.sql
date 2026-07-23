--Quarterly TB data - 4 months
with des as (
select de.uid de_uid, pt.name ds_ptype 
from 
	datasetelement dse 
	left join dataset ds using(datasetid)
	left join periodtype pt using(periodtypeid) 
	left join dataelement de using(dataelementid)
where 
	ds.uid in ('ql3YI4SokB3', 'OyutuMOPgkt', 'ybLvxFAQyCn', 'lYNYevNTO7B') and
	pt.name = 'Quarterly' and 
	de.dataelementid not in (select generatoroutput from predictor)
group by de.uid, pt.name
order by de.uid, pt.name
	)
select move_data_fwd_by_de(ds_ptype, de_uid, 4) from des;

--Quarterly TB data (some) - 2 more months
with des as (
select de.uid de_uid, pt.name ds_ptype 
from 
	datasetelement dse 
	left join dataset ds using(datasetid)
	left join periodtype pt using(periodtypeid) 
	left join dataelement de using(dataelementid)
where 
	de.uid in ('tr0lVojK425', 'EGlb6CP7czB', 'KhCB35MHs9A', 'l4TyT04yP8f', 'lgKh8oeoKVj', 'mG3LJzaZxb8', 'NJaeD9Xia7x', 'Nv1RGi4eI7F', 'NYxehRdsQx3', 'Orjo9ewlU9Z', 'Q5KSbP9ZzHQ', 'qlkxnlC6dzU', 'QNFhsj0fOxK', 'tl9LwbDa3ny') and
	pt.name = 'Quarterly' and 
	de.dataelementid not in (select generatoroutput from predictor)
group by de.uid, pt.name
order by de.uid, pt.name
	)
select move_data_fwd_by_de(ds_ptype, de_uid, 2) from des;


--Monthly malaria, HIV, EPI, RMNCAH  data - 10 months
with des as (
select de.uid de_uid, pt.name ds_ptype 
from 
	datasetelement dse 
	left join dataset ds using(datasetid)
	left join periodtype pt using(periodtypeid) 
	left join dataelement de using(dataelementid)
where 
	ds.uid in ('O34y2Kyxx6P', 'e8BAh6eGcNE', 'VEM58nY22sO', 'F7OVox4TtLP', 'PRiItBuYx0e', 'XvcWsuHBsGA', 'jqSaKxtj8IA', 'tQc4Gv2Jwco') and
	pt.name = 'Monthly' and 
	de.dataelementid not in (select generatoroutput from predictor)
group by de.uid, pt.name
order by de.uid, pt.name
	)
select move_data_fwd_by_de(ds_ptype, de_uid, 10) from des;

--SF monthly data - 9 months
with des as (
select de.uid de_uid, pt.name ds_ptype 
from 
	datasetelement dse 
	left join dataset ds using(datasetid)
	left join periodtype pt using(periodtypeid) 
	left join dataelement de using(dataelementid)
where 
	ds.uid in ('uRrzcLSWeVh', 'LTvYVEodb2t') and
	pt.name = 'Monthly' and 
	de.dataelementid not in (select generatoroutput from predictor)
group by de.uid, pt.name
order by de.uid, pt.name
	)
select move_data_fwd_by_de(ds_ptype, de_uid, 10) from des;


--REHAB monthly data - 10 months
with des as (
select de.uid de_uid, pt.name ds_ptype 
from 
	datasetelement dse 
	left join dataset ds using(datasetid)
	left join periodtype pt using(periodtypeid) 
	left join dataelement de using(dataelementid)
where 
	ds.uid in ('WjN1YoDtlOd', 'zInFVXb98JD', 'tP8et8TNWgF') and
	pt.name = 'Monthly' and 
	de.dataelementid not in (select generatoroutput from predictor)
group by de.uid, pt.name
order by de.uid, pt.name
	)
select move_data_fwd_by_de(ds_ptype, de_uid, 10) from des;


--CH monthly data - 10 months
with des as (
select de.uid de_uid, pt.name ds_ptype 
from 
	datasetelement dse 
	left join dataset ds using(datasetid)
	left join periodtype pt using(periodtypeid) 
	left join dataelement de using(dataelementid)
where 
	ds.name like 'CH - %' and
	pt.name = 'Monthly' and 
	de.dataelementid not in (select generatoroutput from predictor) and
	dse.datasetid not in (select datasetid from dataset where name not like 'CH - %')
group by de.uid, pt.name
order by de.uid, pt.name
	)
select move_data_fwd_by_de(ds_ptype, de_uid, 10) from des;


--Nutrition monthly data - 10 months
with des as (
select de.uid de_uid, pt.name ds_ptype 
from 
	datasetelement dse 
	left join dataset ds using(datasetid)
	left join periodtype pt using(periodtypeid) 
	left join dataelement de using(dataelementid)
where 
	ds.uid in ('EgkMoa9cJ5d', 'kG0k8955sCd') and
	pt.name = 'Monthly' and 
	de.dataelementid not in (select generatoroutput from predictor) and
	dse.datasetid not in (select datasetid from dataset where uid not in ('EgkMoa9cJ5d', 'kG0k8955sCd'))
group by de.uid, pt.name
order by de.uid, pt.name
	)
select move_data_fwd_by_de(ds_ptype, de_uid, 10) from des;


--IDS weekly data - 10 months
with des as (
select de.uid de_uid, pt.name ds_ptype 
from 
	datasetelement dse 
	left join dataset ds using(datasetid)
	left join periodtype pt using(periodtypeid) 
	left join dataelement de using(dataelementid)
where 
	ds.uid in ('OTvkNTijYQY', 'ZyZmZTUwctj', 'm9yPuQEqxmS') and
	pt.name = 'Weekly' and 
	de.dataelementid not in (select generatoroutput from predictor) and
	dse.datasetid not in (select datasetid from dataset where uid not in ('OTvkNTijYQY', 'ZyZmZTUwctj', 'm9yPuQEqxmS'))
group by de.uid, pt.name
order by de.uid, pt.name
	)
select move_data_fwd_by_de(ds_ptype, de_uid, 43) from des;

-- Delete 2023 annual CH data
delete from datavalue where dataelementid in (
select de.dataelementid 
from 
	datasetelement dse 
	left join dataset ds using(datasetid)
	left join periodtype pt using(periodtypeid) 
	left join dataelement de using(dataelementid)
where 
	ds.name like 'CH -%' and
	de.name like 'CH%' and
	pt.name = 'Yearly' and 
	de.dataelementid not in (select generatoroutput from predictor)
) and
periodid in (select periodid from period where extract(year from startdate) >= 2023);


-- Annual - move all data 1 year except GEN, NUT, LSB (already in 2023)
with des as (
select de.uid de_uid, pt.name ds_ptype 
from 
	datasetelement dse 
	left join dataset ds using(datasetid)
	left join periodtype pt using(periodtypeid) 
	left join dataelement de using(dataelementid)
where 
	ds.name not like 'Estimated Population from LSB 2019%' and
	ds.name not like 'NUT - Nutrition population (annual)%' and
	ds.name not like 'Population estimates' and
	de.name not like 'GEN%' and
	de.name not like 'LSB%' and
	de.name not like 'NUT%' and
	pt.name = 'Yearly' and 
	de.dataelementid not in (select generatoroutput from predictor)
group by de.uid, pt.name
order by de.uid, pt.name
	)
select move_data_fwd_by_de(ds_ptype, de_uid, 1) from des;


--Nut six-monthly data - 2 six-months
with des as (
select de.uid de_uid, pt.name ds_ptype 
from 
	datasetelement dse 
	left join dataset ds using(datasetid)
	left join periodtype pt using(periodtypeid) 
	left join dataelement de using(dataelementid)
where 
	ds.uid like 'bkjBCohvXEO' and
	pt.name = 'SixMonthly' and 
	de.dataelementid not in (select generatoroutput from predictor) and
	dse.datasetid not in (select datasetid from dataset where uid not like 'bkjBCohvXEO')
group by de.uid, pt.name
order by de.uid, pt.name
	)
select move_data_fwd_by_de(ds_ptype, de_uid, 2) from des;
