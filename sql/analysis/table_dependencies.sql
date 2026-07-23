-- table_dependencies.sql
--
-- Creates a helper function that lists all tables with a foreign key
-- reference to a given table and column. Handy for working out what will
-- block a DELETE in the DHIS2 database (e.g. "what references
-- dataelement.dataelementid?").
--
-- Usage:
--   SELECT * FROM d2_dependencies('dataelement', 'dataelementid');
--   SELECT * FROM d2_dependencies('categoryoptioncombo', 'categoryoptioncomboid');
--
-- Pure PostgreSQL catalog query — works on any DHIS2 version (and any
-- Postgres database, for that matter).

CREATE OR REPLACE FUNCTION d2_dependencies (dep_table text, dep_column text)
	RETURNS TABLE (
		dep_tbl text,
		dep_col text)
	LANGUAGE plpgsql
	AS $$
BEGIN
	RETURN query
	SELECT
		(
			SELECT
				r.relname
			FROM
				pg_class r
			WHERE
				r.oid = c.conrelid)::text AS table,
		(
			SELECT
				(array_agg(attname))
			FROM
				pg_attribute
			WHERE
				attrelid = c.conrelid
				AND ARRAY[attnum] <@ c.conkey)[1]::text AS col
	FROM
		pg_constraint c
	WHERE
		c.confrelid = (
			SELECT
				oid
			FROM
				pg_class
			WHERE
				relname = dep_table)
		AND c.confkey @> (
			SELECT
				array_agg(attnum)
			FROM
				pg_attribute
			WHERE
				attname = dep_column
				AND attrelid = c.confrelid);
END
$$;
