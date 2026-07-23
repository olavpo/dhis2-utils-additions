-- cancel_slow_queries.sql
--
-- Defines a function that cancels long-running SELECT queries generated
-- by DHIS2 — a safety valve for servers where runaway analytics or SQL
-- view queries pile up and starve the database. Excludes psql and
-- pg_dump sessions, PostgreSQL maintenance, and catalog queries, so
-- backups and manual work are never cancelled.
--
-- Function: dhis_cancel_slow_queries(max_duration, db_user)
--   max_duration  Cancel queries running longer than this (default 1 minute)
--   db_user       Only cancel queries from this database user (default 'dhis')
--   returns       Number of queries cancelled
--
--   SELECT dhis_cancel_slow_queries();                     -- defaults
--   SELECT dhis_cancel_slow_queries('5 minutes', 'dhis');
--
-- Typically run from cron every minute during working hours:
--   * 8-23 * * *  psql -d dhis2 -c "SELECT dhis_cancel_slow_queries();"
--
-- Uses pg_cancel_backend (cancels the query, keeps the connection).
-- NOTE: DHIS2 analytics table generation also runs long SELECTs; the
-- query filter excludes analytics table INSERT/CREATE statements, but if
-- analytics runs are being cancelled on your server, raise max_duration
-- or restrict the cron schedule to hours when analytics does not run.

CREATE OR REPLACE FUNCTION dhis_cancel_slow_queries(
    max_duration interval DEFAULT '1 minute',
    db_user text DEFAULT 'dhis')
    RETURNS integer
    LANGUAGE plpgsql
AS
$$
DECLARE
    Q RECORD;
    CANCELLED integer := 0;
BEGIN
    FOR Q IN
        SELECT pid, query
        FROM pg_catalog.pg_stat_activity
        WHERE (now() - query_start) > max_duration
          AND usename = db_user
          AND state = 'active'
          AND application_name NOT IN ('psql', 'pg_dump')
          AND query ILIKE 'select%'
          AND query !~* 'pg_catalog|information_schema|pg_temp|pg_toast'
    LOOP
        RAISE NOTICE 'Cancelling query with pid %: %', Q.pid, left(Q.query, 100);
        PERFORM pg_cancel_backend(Q.pid);
        CANCELLED := CANCELLED + 1;
    END LOOP;

    RETURN CANCELLED;
END
$$;
