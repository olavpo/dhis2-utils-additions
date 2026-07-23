-- Total enrollments created by month
select to_char (psi.created, 'YYYYMM') as month, count(*) from programinstance psi left join program pr using(programid) where pr.uid = 'Lt6P15ps7f6' group by month order by month;

-- Total districts enrolling cases by month
with enrollment_stats_ou as (select to_char (psi.created, 'YYYYMM') as month, ous.namelevel3 as district from programinstance psi left join _orgunitstructure ous using (organisationunitid) left join program pr using(programid) where pr.uid = 'Lt6P15ps7f6' group by month, district) select month,count(district) from enrollment_stats_ou group by month order by month;

-- Total users enrolling cases by month
with enrollment_stats_usr as (select to_char (psi.created, 'YYYYMM') as month, psi.storedby as usr from programinstance psi left join program pr using(programid) where pr.uid = 'Lt6P15ps7f6' group by month, usr) select month,count(usr) from enrollment_stats_usr group by month order by month;

