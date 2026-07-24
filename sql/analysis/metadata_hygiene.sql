-- metadata_hygiene.sql
--
-- Metadata and usage hygiene assessment: how much of the configuration
-- is actually used? Surfaces abandoned datasets, data elements without
-- data or analysis use, unused indicators, empty/unviewed dashboards
-- and visualizations, and inactive users — the raw material for a
-- metadata cleanup exercise.
--
-- Two parts: a SUMMARY (one row per check: count, share, description)
-- and LISTINGS (name + uid per offending object) for the most
-- actionable checks. Read-only.
--
--   psql -d dhis2 -f metadata_hygiene.sql
--
-- Complements DHIS2's built-in data integrity checks, which cover
-- structural integrity but not whether metadata is used.

-- ============================== SUMMARY ==============================

-- Data sets

WITH ds_period AS (
    SELECT ds.datasetid, dse.dataelementid, pe.periodid
    FROM dataset ds
    LEFT JOIN period pe USING (periodtypeid)
    LEFT JOIN datasetelement dse USING (datasetid)
    WHERE date_part('day', now() - pe.enddate::timestamp)::int
          <= 3 * date_part('day', pe.enddate::timestamp - pe.startdate::timestamp)::int
)
SELECT 'dataset_count' AS check_name, count(*)::text AS value, '100%' AS share,
       'Total number of data sets' AS description
FROM dataset

UNION ALL
SELECT 'dataset_abandoned', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM dataset), 0)) || '%',
       'Data sets not changed in the last 100 days and assigned to 1 or fewer org units'
FROM dataset
WHERE date_part('day', now() - lastupdated::date) > 100
  AND (datasetid NOT IN (SELECT datasetid FROM datasetsource)
       OR datasetid IN (SELECT datasetid FROM datasetsource
                        GROUP BY datasetid HAVING count(*) = 1))

UNION ALL
SELECT 'dataset_nonewdata', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM dataset), 0)) || '%',
       'Data sets with no data values in the last 3 periods (by data set period type)'
FROM dataset
WHERE datasetid NOT IN (
    SELECT DISTINCT datasetid FROM ds_period
    WHERE (dataelementid, periodid) IN (SELECT dataelementid, periodid FROM datavalue));

-- Data elements (aggregate)

WITH ds_period AS (
    SELECT ds.datasetid, dse.dataelementid, pe.periodid
    FROM dataset ds
    LEFT JOIN period pe USING (periodtypeid)
    LEFT JOIN datasetelement dse USING (datasetid)
    WHERE date_part('day', now() - pe.enddate::timestamp)::int
          <= 3 * date_part('day', pe.enddate::timestamp - pe.startdate::timestamp)::int
),
agg_de AS (SELECT * FROM dataelement WHERE domaintype = 'AGGREGATE')
SELECT 'dataelement_count' AS check_name, count(*)::text AS value, '100%' AS share,
       'Total number of aggregate data elements' AS description
FROM agg_de

UNION ALL
SELECT 'dataelement_nongrouped', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM agg_de), 0)) || '%',
       'Aggregate data elements not in any data element group'
FROM agg_de
WHERE dataelementid NOT IN (SELECT dataelementid FROM dataelementgroupmembers)

UNION ALL
SELECT 'dataelement_nodata', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM agg_de), 0)) || '%',
       'Aggregate data elements with no data values at all'
FROM agg_de
WHERE dataelementid NOT IN (SELECT dataelementid FROM datavalue GROUP BY dataelementid)

UNION ALL
SELECT 'dataelement_nonewdata', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM agg_de), 0)) || '%',
       'Aggregate data elements with no data values in the last 3 periods'
FROM agg_de
WHERE dataelementid NOT IN (
    SELECT DISTINCT dataelementid FROM ds_period
    WHERE (dataelementid, periodid) IN (SELECT dataelementid, periodid FROM datavalue))

UNION ALL
SELECT 'dataelement_noanalysis', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM agg_de), 0)) || '%',
       'Aggregate data elements not used in favorites, directly or via indicators'
FROM agg_de
WHERE dataelementid NOT IN (
        SELECT de.dataelementid FROM dataelement de
        LEFT JOIN indicator ind
            ON (ind.numerator LIKE '%' || de.uid || '%'
                OR ind.denominator LIKE '%' || de.uid || '%')
        WHERE ind.indicatorid IN
            (SELECT indicatorid FROM datadimensionitem WHERE indicatorid > 0))
  AND dataelementid NOT IN
        (SELECT dataelementoperand_dataelementid FROM datadimensionitem
         WHERE dataelementoperand_dataelementid > 0)
  AND dataelementid NOT IN
        (SELECT dataelementid FROM datadimensionitem WHERE dataelementid > 0);

-- Indicators

SELECT 'indicator_count' AS check_name, count(*)::text AS value, '100%' AS share,
       'Total number of indicators' AS description
FROM indicator

UNION ALL
SELECT 'indicator_nongrouped', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM indicator), 0)) || '%',
       'Indicators not in any indicator group'
FROM indicator
WHERE indicatorid NOT IN (SELECT indicatorid FROM indicatorgroupmembers)

UNION ALL
SELECT 'indicator_nouse', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM indicator), 0)) || '%',
       'Indicators not used in favorites or data sets'
FROM indicator
WHERE indicatorid NOT IN (SELECT indicatorid FROM datadimensionitem WHERE indicatorid > 0)
  AND indicatorid NOT IN (SELECT indicatorid FROM datasetindicators);

-- Users

SELECT 'user_count' AS check_name, count(*)::text AS value, '100%' AS share,
       'Total number of users' AS description
FROM userinfo

UNION ALL
SELECT 'user_active30d', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM userinfo), 0)) || '%',
       'Users logged in during the last 30 days'
FROM userinfo WHERE date_part('day', now() - lastlogin::date) <= 30

UNION ALL
SELECT 'user_inactive1y_enabled', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM userinfo), 0)) || '%',
       'Users not logged in for a year (or never) but not disabled'
FROM userinfo
WHERE (lastlogin IS NULL OR date_part('day', now() - lastlogin::date) > 365)
  AND disabled = false;

-- Organisation units

WITH compulsory AS (
    SELECT ogm.organisationunitid,
           count(DISTINCT ogs.orgunitgroupsetid) AS actual,
           (SELECT count(*) FROM orgunitgroupset WHERE compulsory = true) AS expected
    FROM orgunitgroupsetmembers ogsm
    LEFT JOIN orgunitgroupset ogs USING (orgunitgroupsetid)
    LEFT JOIN orgunitgroupmembers ogm USING (orgunitgroupid)
    WHERE ogs.compulsory = true
    GROUP BY ogm.organisationunitid
)
SELECT 'orgunit_count' AS check_name, count(*)::text AS value, '100%' AS share,
       'Total number of org units' AS description
FROM organisationunit

UNION ALL
SELECT 'orgunit_leaf_nodataset', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM organisationunit), 0)) || '%',
       'Leaf org units with no data sets assigned'
FROM organisationunit ou
WHERE NOT EXISTS (SELECT 1 FROM organisationunit c WHERE c.parentid = ou.organisationunitid)
  AND ou.organisationunitid NOT IN (SELECT sourceid FROM datasetsource)

UNION ALL
SELECT 'orgunit_notincompulsory', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM organisationunit), 0)) || '%',
       'Org units not in all compulsory org unit group sets'
FROM compulsory WHERE actual != expected

UNION ALL
SELECT 'orgunit_assignednotreporting', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM datasetsource), 0)) || '%',
       'Org unit + data set assignments with no completed data sets'
FROM datasetsource
WHERE (datasetid, sourceid) NOT IN
      (SELECT datasetid, sourceid FROM completedatasetregistration
       GROUP BY datasetid, sourceid);

-- Dashboards and favorites (sharing is the JSONB column on 2.36+)

SELECT 'dashboard_count' AS check_name, count(*)::text AS value, '100%' AS share,
       'Total number of dashboards' AS description
FROM dashboard

UNION ALL
SELECT 'dashboard_empty', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM dashboard), 0)) || '%',
       'Dashboards with no content'
FROM dashboard
WHERE dashboardid NOT IN (SELECT dashboardid FROM dashboard_items)

UNION ALL
SELECT 'dashboard_private', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM dashboard), 0)) || '%',
       'Dashboards not shared with anyone (public access none, no user/group access)'
FROM dashboard
WHERE sharing ->> 'public' = '--------'
  AND coalesce(sharing -> 'users', '{}'::jsonb) = '{}'::jsonb
  AND coalesce(sharing -> 'userGroups', '{}'::jsonb) = '{}'::jsonb

UNION ALL
SELECT 'dashboard_notviewed1y', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM dashboard), 0)) || '%',
       'Dashboards not opened in the last 12 months'
FROM dashboard
WHERE uid NOT IN (
    SELECT favoriteuid FROM datastatisticsevent
    WHERE eventtype = 'DASHBOARD_VIEW' AND favoriteuid IS NOT NULL
      AND timestamp > now() - INTERVAL '12 months'
    GROUP BY favoriteuid);

SELECT 'visualization_count' AS check_name, count(*)::text AS value, '100%' AS share,
       'Total number of visualizations' AS description
FROM visualization

UNION ALL
SELECT 'visualization_notviewed1y', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM visualization), 0)) || '%',
       'Visualizations not opened in the last 12 months (directly; dashboard views not counted)'
FROM visualization
WHERE uid NOT IN (
    SELECT favoriteuid FROM datastatisticsevent
    WHERE eventtype = 'VISUALIZATION_VIEW' AND favoriteuid IS NOT NULL
      AND timestamp > now() - INTERVAL '12 months'
    GROUP BY favoriteuid)

UNION ALL
SELECT 'map_count', count(*)::text, '100%', 'Total number of maps' FROM map

UNION ALL
SELECT 'map_notviewed1y', count(*)::text,
       (100 * count(*) / NULLIF((SELECT count(*) FROM map), 0)) || '%',
       'Maps not opened in the last 12 months (directly)'
FROM map
WHERE uid NOT IN (
    SELECT favoriteuid FROM datastatisticsevent
    WHERE eventtype = 'MAP_VIEW' AND favoriteuid IS NOT NULL
      AND timestamp > now() - INTERVAL '12 months'
    GROUP BY favoriteuid);

-- ============================== LISTINGS =============================

SELECT 'ABANDONED DATA SETS (see summary: dataset_abandoned)' AS listing;
SELECT name, uid FROM dataset
WHERE date_part('day', now() - lastupdated::date) > 100
  AND (datasetid NOT IN (SELECT datasetid FROM datasetsource)
       OR datasetid IN (SELECT datasetid FROM datasetsource
                        GROUP BY datasetid HAVING count(*) = 1))
ORDER BY name;

SELECT 'AGGREGATE DATA ELEMENTS WITH NO DATA' AS listing;
SELECT name, uid FROM dataelement
WHERE domaintype = 'AGGREGATE'
  AND dataelementid NOT IN (SELECT dataelementid FROM datavalue GROUP BY dataelementid)
ORDER BY name;

SELECT 'INDICATORS NOT USED IN FAVORITES OR DATA SETS' AS listing;
SELECT name, uid FROM indicator
WHERE indicatorid NOT IN (SELECT indicatorid FROM datadimensionitem WHERE indicatorid > 0)
  AND indicatorid NOT IN (SELECT indicatorid FROM datasetindicators)
ORDER BY name;

SELECT 'EMPTY DASHBOARDS' AS listing;
SELECT name, uid FROM dashboard
WHERE dashboardid NOT IN (SELECT dashboardid FROM dashboard_items)
ORDER BY name;

SELECT 'ENABLED USERS INACTIVE FOR A YEAR' AS listing;
SELECT username, uid FROM userinfo
WHERE (lastlogin IS NULL OR date_part('day', now() - lastlogin::date) > 365)
  AND disabled = false
ORDER BY username;
