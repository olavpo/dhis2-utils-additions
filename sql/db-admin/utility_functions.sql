-- utility_functions.sql
--
-- Small PostgreSQL helper functions for working with DHIS2 databases.
--
--   uid()                  Generate a random valid DHIS2 UID (11 chars,
--                          first char a letter). Useful when creating
--                          metadata rows directly in SQL.
--                          (Original by Bob Jolliffe, 2015.)
--
--   approx_count(table)    Fast approximate row count from table
--                          statistics — instant even on datavalue tables
--                          with hundreds of millions of rows, where
--                          count(*) takes minutes. Accuracy depends on
--                          when the table was last analyzed/vacuumed.
--
-- Usage:
--   SELECT uid();
--   SELECT approx_count('datavalue');

CREATE OR REPLACE FUNCTION uid()
    RETURNS text
    LANGUAGE sql
AS
$$
    SELECT substring('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
        FROM (random()*51)::int + 1 FOR 1) ||
        array_to_string(ARRAY(
            SELECT substring('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
                FROM (random()*61)::int + 1 FOR 1)
            FROM generate_series(1, 10)), '')
$$;

CREATE OR REPLACE FUNCTION approx_count(table_name regclass)
    RETURNS bigint
    LANGUAGE sql
AS
$$
    SELECT reltuples::bigint
    FROM pg_class
    WHERE oid = table_name
$$;
