select 
	ds.name,
	de.name,
	co_ds.name,
	coc_de.name
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