-- dataset_disaggregations.sql
--
-- Lists every dataset with its data elements and their disaggregations:
--   * the category options of the DATASET's category combo (attribute
--     dimension, e.g. funding partner)
--   * the category option combos of each DATA ELEMENT's category combo
--     (the disaggregation cells that appear in data entry)
--
-- Useful for reviewing how datasets/data elements are disaggregated, e.g.
-- when harmonising category combos or preparing metadata cleanup.
--
-- Read-only (apart from a session-local temp view). Produces one row per
-- combination, so output can be large; filter on ds.name / ds.uid to narrow
-- it down.
--
-- Works on DHIS2 2.40 (dataelementcategoryoption) and 2.41+ (categoryoption):
-- a temp view bridges the table rename on older versions.

DO $$
BEGIN
    IF to_regclass('public.categoryoption') IS NULL THEN
        EXECUTE 'CREATE TEMP VIEW categoryoption AS SELECT * FROM dataelementcategoryoption';
    END IF;
END $$;

select
	ds.name as dataset,
	de.name as dataelement,
	co_ds.name as dataset_categoryoption,
	coc_de.name as dataelement_categoryoptioncombo
from
	dataset ds
left join datasetelement dse
		using(datasetid)
left join dataelement de
		using(dataelementid)
left join categorycombos_categories cc_c_ds
		on
	ds.categorycomboid = cc_c_ds.categorycomboid
left join categories_categoryoptions c_co_ds
		on
	c_co_ds.categoryid = cc_c_ds.categoryid
left join categoryoption co_ds
		on
	co_ds.categoryoptionid = c_co_ds.categoryoptionid
left join categorycombo cc_de
		on
	cc_de.categorycomboid = de.categorycomboid
left join categorycombos_optioncombos cc_coc_de
		on
	cc_coc_de.categorycomboid = cc_de.categorycomboid
left join categoryoptioncombo coc_de
		on
	coc_de.categoryoptioncomboid = cc_coc_de.categoryoptioncomboid
order by de.name, co_ds.name, coc_de.name;
