-- Query Name: DatasetSummaryStatisticsQuery
-- Purpose: Retrieve dataset-level summary statistics, including counts of completed registrations and data elements,
--           both exclusive and total, associated with each dataset.
WITH ExclusiveDataElements AS (
    SELECT 
        de.dataelementid
    FROM 
        datasetelement de
    GROUP BY 
        de.dataelementid
    HAVING 
        COUNT(DISTINCT de.datasetid) = 1
)

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
LEFT JOIN 
    ExclusiveDataElements AS ed ON de.dataelementid = ed.dataelementid
GROUP BY 
    ds.datasetid;



-- Query Name: DataElementAggregateYearlyStatisticsQuery
-- Purpose: Retrieve yearly statistics for data elements with domaintype 'AGGREGATE' pre-mapped with periods.
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
    COUNT(DISTINCT CASE WHEN py.year = 2020 THEN dv.* END) AS datavalues_2020,
    COUNT(DISTINCT CASE WHEN py.year = 2021 THEN dv.* END) AS datavalues_2021,
    COUNT(DISTINCT CASE WHEN py.year = 2022 THEN dv.* END) AS datavalues_2022,
    COUNT(DISTINCT CASE WHEN py.year = 2023 THEN dv.* END) AS datavalues_2023,
    COUNT(DISTINCT CASE WHEN py.year = 2024 THEN dv.* END) AS datavalues_2024,
    COUNT(DISTINCT CASE WHEN py.year = 2025 THEN dv.* END) ASavalues_2025,
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



-- Optimized Query Name: DatasetDataValueStatisticsOptimizedQuery
-- Purpose: Retrieve optimized dataset-level statistics with streamlined datavalue counts.
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
