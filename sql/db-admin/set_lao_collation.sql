-- set_lao_collation.sql
--
-- PostgreSQL sorts Lao text very slowly under the default collation.
-- This sets the ICU Lao collation ("lo-x-icu") on the name/shortname
-- columns that DHIS2 sorts on most, and reindexes the affected tables.
-- Sort performance on Lao-language databases improves dramatically.
--
-- The column's existing data type is preserved (read from the catalog),
-- so the same script works across DHIS2 versions; tables that don't
-- exist are skipped. Requires PostgreSQL with ICU support (any modern
-- packaged PostgreSQL).
--
--   psql -d dhis2 -f set_lao_collation.sql
--
-- To use a different language, replace "lo-x-icu" with another ICU
-- collation from: SELECT collname FROM pg_collation;

DO
$$
DECLARE
    TARGET RECORD;
    COL_TYPE text;
BEGIN
    FOR TARGET IN
        SELECT t.table_name, c.column_name
        FROM (VALUES
            ('organisationunit', ARRAY['name', 'shortname']),
            ('dataelement', ARRAY['name', 'shortname']),
            ('dataelementcategoryoption', ARRAY['name', 'shortname']),  -- 2.40
            ('categoryoption', ARRAY['name', 'shortname']),             -- 2.41+
            ('indicator', ARRAY['name', 'shortname']),
            ('dataset', ARRAY['name', 'shortname']),
            ('program', ARRAY['name', 'shortname']),
            ('trackedentityattribute', ARRAY['name', 'shortname']),
            ('optionvalue', ARRAY['name']),
            ('visualization', ARRAY['name']),
            ('map', ARRAY['name']),
            ('eventvisualization', ARRAY['name']),
            ('dashboard', ARRAY['name'])
        ) AS t(table_name, columns),
        LATERAL unnest(t.columns) AS c(column_name)
        WHERE to_regclass('public.' || t.table_name) IS NOT NULL
    LOOP
        SELECT format_type(a.atttypid, a.atttypmod) INTO COL_TYPE
        FROM pg_attribute a
        WHERE a.attrelid = ('public.' || TARGET.table_name)::regclass
          AND a.attname = TARGET.column_name
          AND NOT a.attisdropped;

        CONTINUE WHEN COL_TYPE IS NULL;

        RAISE NOTICE 'Setting Lao collation on %.%', TARGET.table_name, TARGET.column_name;
        EXECUTE format('ALTER TABLE %I ALTER COLUMN %I SET DATA TYPE %s COLLATE "lo-x-icu"',
            TARGET.table_name, TARGET.column_name, COL_TYPE);
    END LOOP;
END
$$;

REINDEX TABLE organisationunit;
REINDEX TABLE dataelement;
