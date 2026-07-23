-- dataset_usage_stats.sql
--
-- Three queries for assessing how much datasets and data elements are
-- actually used — useful when deciding what can be removed or archived
-- during metadata cleanup.
--
-- 1. Dataset summary: completeness registrations + data element counts
--    ("exclusive" = data elements that belong to this dataset only)
-- 2. Data element yearly statistics: data values per year per data element
--    (adjust the hardcoded years to the range of interest)
-- 3. Dataset data value counts: total and exclusive data values per dataset
--
-- Read-only; safe to run on a production replica. The yearly query scans the
-- whole datavalue table and can be slow on large databases.


-- 1. Dataset summary statistics: completed registrations and data element
--    counts (exclusive and total) per dataset.
SELECT
    ds.name AS dataset_name,
    ds.uid AS dataset_uid,
    ds.created,
    ds.lastupdated,
    COUNT(DISTINCT cdr.sourceid) AS completed_dataset_registrations,
    COUNT(DISTINCT CASE WHEN ed.dataelementid IS NOT NULL THEN de.dataelementid END) AS exclusive_dataelements_count,
    COUNT(DISTINCT de.dataelementid) AS total_dataelements_count
FROM
    dataset AS ds
LEFT JOIN
    completedatasetregistration AS cdr ON ds.datasetid = cdr.datasetid
LEFT JOIN
    datasetelement AS de ON ds.datasetid = de.datasetid
LEFT JOIN (
    SELECT
        de.dataelementid
    FROM
        datasetelement de
    GROUP BY
        de.dataelementid
    HAVING
        COUNT(DISTINCT de.datasetid) = 1
) AS ed ON de.dataelementid = ed.dataelementid
GROUP BY
    ds.datasetid;


-- 2. Yearly data value statistics per (aggregate domain) data element.
--    Adjust the years in the CASE columns to the range of interest.
WITH PeriodYear AS (
    SELECT
        periodid,
        EXTRACT(YEAR FROM enddate) AS year
    FROM
        period
)
SELECT
    de.name AS dataelement_name,
    de.uid AS dataelement_uid,
    de.created AS dataelement_created,
    de.lastupdated AS dataelement_lastupdated,
    STRING_AGG(DISTINCT ds.name, ', ') AS dataset_names,
    MIN(p.startdate) AS min_startdate,
    MAX(p.enddate) AS max_enddate,
    COUNT(DISTINCT CASE WHEN py.year = 2021 THEN dv.* END) AS datavalues_2021,
    COUNT(DISTINCT CASE WHEN py.year = 2022 THEN dv.* END) AS datavalues_2022,
    COUNT(DISTINCT CASE WHEN py.year = 2023 THEN dv.* END) AS datavalues_2023,
    COUNT(DISTINCT CASE WHEN py.year = 2024 THEN dv.* END) AS datavalues_2024,
    COUNT(DISTINCT CASE WHEN py.year = 2025 THEN dv.* END) AS datavalues_2025,
    COUNT(DISTINCT CASE WHEN py.year = 2026 THEN dv.* END) AS datavalues_2026,
    COUNT(DISTINCT dv.*) AS total_datavalues
FROM
    dataelement AS de
JOIN
    datasetelement AS dse ON de.dataelementid = dse.dataelementid
JOIN
    dataset AS ds ON ds.datasetid = dse.datasetid
JOIN
    datavalue AS dv ON de.dataelementid = dv.dataelementid
JOIN
    PeriodYear AS py ON dv.periodid = py.periodid
JOIN
    period AS p ON dv.periodid = p.periodid
WHERE
    de.domaintype = 'AGGREGATE'
GROUP BY
    de.dataelementid;


-- 3. Dataset-level data value counts: total, and values belonging to data
--    elements exclusive to this dataset.
SELECT
    ds.name AS dataset_name,
    ds.uid AS dataset_uid,
    ds.created,
    ds.lastupdated,
    -- Count of datavalues for data elements only associated with this dataset
    COUNT(DISTINCT CASE WHEN s.exclusive_dataelementid IS NOT NULL THEN dv.* END) AS exclusive_datavalues_count,
    -- Count of all datavalues associated with this dataset
    COUNT(DISTINCT dv.*) AS total_datavalues_count
FROM
    dataset AS ds
JOIN
    datasetelement AS dse ON ds.datasetid = dse.datasetid
JOIN
    datavalue AS dv ON dse.dataelementid = dv.dataelementid
LEFT JOIN (
    SELECT
        dse.dataelementid AS exclusive_dataelementid
    FROM
        datasetelement AS dse
    GROUP BY
        dse.dataelementid
    HAVING
        COUNT(DISTINCT dse.datasetid) = 1
) AS s ON dse.dataelementid = s.exclusive_dataelementid
GROUP BY
    ds.datasetid;
