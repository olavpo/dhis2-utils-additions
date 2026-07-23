-- pg_stat_statements.sql
--
-- Sets up the pg_stat_statements extension for finding the slowest and
-- most time-consuming queries on a DHIS2 database server, with two
-- convenience views. Requires PostgreSQL 13+ (uses *_exec_time columns).
--
-- 1) Add to postgresql.conf (or a file in conf.d/) and RESTART PostgreSQL:
--
--      shared_preload_libraries = 'pg_stat_statements'
--      track_activity_query_size = 8192
--      pg_stat_statements.track = 'all'
--      pg_stat_statements.max = 10000
--
-- 2) Run this file against the DHIS2 database:
--
--      psql -d dhis2 -f pg_stat_statements.sql
--
-- 3) Query (use \x in psql for expanded display; times are ms):
--
--      SELECT * FROM stat.view_slow_queries;      -- by mean time
--      SELECT * FROM stat.view_frequent_queries;  -- by total time
--
-- Reset collected statistics with: SELECT pg_stat_statements_reset();

CREATE SCHEMA IF NOT EXISTS stat;

CREATE EXTENSION IF NOT EXISTS pg_stat_statements SCHEMA stat;

-- Slowest queries by mean execution time

DROP VIEW IF EXISTS stat.view_slow_queries;

CREATE VIEW stat.view_slow_queries AS
SELECT
  to_char(mean_exec_time, 'FM999G999G999G990') AS mean_time_ms,
  to_char(max_exec_time, 'FM999G999G999G990') AS max_time_ms,
  to_char(min_exec_time, 'FM999G999G999G990') AS min_time_ms,
  calls,
  query
FROM stat.pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 200;

-- Most time-consuming queries by total execution time

DROP VIEW IF EXISTS stat.view_frequent_queries;

CREATE VIEW stat.view_frequent_queries AS
SELECT
  to_char(mean_exec_time, 'FM999G999G999G990') AS mean_time_ms,
  to_char(total_exec_time, 'FM999G999G999G990') AS total_time_ms,
  calls,
  rows,
  query
FROM stat.pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 200;
