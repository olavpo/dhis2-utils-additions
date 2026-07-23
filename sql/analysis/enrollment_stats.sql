-- enrollment_stats.sql
--
-- Monthly statistics on tracker enrollments for one program:
--   1. Total enrollments created per month
--   2. Number of distinct districts (org unit level 3) enrolling per month
--   3. Number of distinct users enrolling per month
--
-- Useful for assessing uptake of a tracker program over time.
--
-- Usage (pass the program UID as a psql variable):
--   psql -d dhis2 -v program_uid=IpHINAT79UW -f enrollment_stats.sql
--
-- Requirements:
--   * The _orgunitstructure resource table must exist (generate resource
--     tables in DHIS2 first) for the district query.
--   * Works on DHIS2 2.40 (programinstance) and 2.41+ (enrollment): a temp
--     view bridges the table rename on older versions.
--
-- Read-only apart from a session-local temp view.

-- Compatibility: on DHIS2 <= 2.40 the enrollment table is called
-- programinstance; expose it as "enrollment" for this session.
DO $$
BEGIN
    IF to_regclass('public.enrollment') IS NULL THEN
        EXECUTE 'CREATE TEMP VIEW enrollment AS SELECT * FROM programinstance';
    END IF;
END $$;

-- 1. Total enrollments created by month
select to_char (en.created, 'YYYYMM') as month, count(*)
from enrollment en
left join program pr using(programid)
where pr.uid = :'program_uid'
group by month order by month;

-- 2. Districts (org unit level 3) enrolling cases by month
with enrollment_stats_ou as (
    select to_char (en.created, 'YYYYMM') as month, ous.namelevel3 as district
    from enrollment en
    left join _orgunitstructure ous using (organisationunitid)
    left join program pr using(programid)
    where pr.uid = :'program_uid'
    group by month, district
)
select month, count(district) from enrollment_stats_ou group by month order by month;

-- 3. Users enrolling cases by month
with enrollment_stats_usr as (
    select to_char (en.created, 'YYYYMM') as month, en.storedby as usr
    from enrollment en
    left join program pr using(programid)
    where pr.uid = :'program_uid'
    group by month, usr
)
select month, count(usr) from enrollment_stats_usr group by month order by month;
