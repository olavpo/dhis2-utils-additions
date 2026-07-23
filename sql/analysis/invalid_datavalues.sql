-- invalid_datavalues.sql
--
-- Read-only checks for stored data values that don't match their data
-- element's value type or fall outside a reasonable time range. Such
-- values are usually legacy imports; they break analytics table
-- generation and indicator calculations, and DHIS2's built-in data
-- integrity checks cover metadata only — not stored values.
--
-- Companion cleanup tools: sql/maintenance/delete_data_out_of_range.sql.
--
--   psql -d dhis2 -f invalid_datavalues.sql

-- Numeric data elements with non-numeric stored values (sample)

SELECT de.uid AS de_uid, de.name AS de_name, de.valuetype,
       pe.startdate, ou.name AS orgunit, dv.value
FROM datavalue dv
INNER JOIN dataelement de ON dv.dataelementid = de.dataelementid
INNER JOIN period pe ON dv.periodid = pe.periodid
INNER JOIN organisationunit ou ON dv.sourceid = ou.organisationunitid
WHERE de.valuetype IN ('INTEGER', 'INTEGER_POSITIVE', 'INTEGER_NEGATIVE',
                       'INTEGER_ZERO_OR_POSITIVE', 'NUMBER', 'UNIT_INTERVAL', 'PERCENTAGE')
  AND dv.value IS NOT NULL
  AND dv.value !~ '^(-?[0-9]+)(\.[0-9]+)?$'
LIMIT 500;

-- Count of non-numeric values per numeric data element

SELECT de.uid AS de_uid, de.name AS de_name, de.valuetype, count(*) AS invalid_count
FROM datavalue dv
INNER JOIN dataelement de ON dv.dataelementid = de.dataelementid
WHERE de.valuetype IN ('INTEGER', 'INTEGER_POSITIVE', 'INTEGER_NEGATIVE',
                       'INTEGER_ZERO_OR_POSITIVE', 'NUMBER', 'UNIT_INTERVAL', 'PERCENTAGE')
  AND dv.value IS NOT NULL
  AND dv.value !~ '^(-?[0-9]+)(\.[0-9]+)?$'
GROUP BY de.uid, de.name, de.valuetype
ORDER BY invalid_count DESC;

-- Boolean data elements with invalid stored values

SELECT de.uid AS de_uid, de.name AS de_name, de.valuetype, count(*) AS invalid_count
FROM datavalue dv
INNER JOIN dataelement de ON dv.dataelementid = de.dataelementid
WHERE (de.valuetype = 'BOOLEAN' AND dv.value NOT IN ('true', 'false'))
   OR (de.valuetype = 'TRUE_ONLY' AND dv.value != 'true')
GROUP BY de.uid, de.name, de.valuetype
ORDER BY invalid_count DESC;

-- Count of data values in periods outside a reasonable range

SELECT count(*) AS out_of_range_datavalues
FROM datavalue dv
WHERE dv.periodid IN (
  SELECT pe.periodid
  FROM period pe
  WHERE pe.enddate < '1960-01-01'
     OR pe.startdate > '2100-01-01');
