-- pg_activity.sql
--
-- Query cookbook for monitoring PostgreSQL activity, slow queries and
-- locks on a DHIS2 database server. Run individual queries as needed
-- (this file is not meant to be executed top to bottom).
--
-- To enable slow-query logging, add to postgresql.conf (or conf.d/):
--
--   log_min_duration_statement = 200
--   log_statement = none
--   track_activity_query_size = 8192
--
-- The log settings apply after: SELECT pg_reload_conf();
-- (track_activity_query_size requires a server restart.)

-- Current queries

SELECT pid, datname, usename, query_start, now() - query_start AS duration, state, query
FROM pg_catalog.pg_stat_activity
WHERE state != 'idle'
AND query NOT ILIKE '%pg_stat_activity%';

-- Idle connections

SELECT pid, datname, usename, query_start, now() - query_start AS duration, state, query
FROM pg_catalog.pg_stat_activity
WHERE state ILIKE '%idle%'
AND query NOT ILIKE '%pg_stat_activity%';

-- Queries running for more than 10 seconds (change interval as needed)

SELECT pid, datname, usename, query_start, now() - query_start AS duration, state, query
FROM pg_catalog.pg_stat_activity
WHERE (now() - query_start) > interval '10 seconds'
AND state != 'idle'
AND query NOT ILIKE '%pg_stat_activity%';

-- Count of active queries by running-time bucket

WITH cte_activity AS (
  SELECT *
  FROM pg_catalog.pg_stat_activity
  WHERE state != 'idle'
  AND query NOT ILIKE '%pg_stat_activity%'
)
SELECT 'gt_100ms' AS query_time_interval, count(*) FROM cte_activity
WHERE (now() - query_start) > interval '100 milliseconds'
UNION ALL SELECT 'gt_500ms', count(*) FROM cte_activity
WHERE (now() - query_start) > interval '500 milliseconds'
UNION ALL SELECT 'gt_1s', count(*) FROM cte_activity
WHERE (now() - query_start) > interval '1 seconds'
UNION ALL SELECT 'gt_5s', count(*) FROM cte_activity
WHERE (now() - query_start) > interval '5 seconds'
UNION ALL SELECT 'gt_20s', count(*) FROM cte_activity
WHERE (now() - query_start) > interval '20 seconds'
UNION ALL SELECT 'gt_90s', count(*) FROM cte_activity
WHERE (now() - query_start) > interval '90 seconds'
UNION ALL SELECT 'gt_5m', count(*) FROM cte_activity
WHERE (now() - query_start) > interval '5 minutes';

-- Current locks

SELECT pl.pid, pl.locktype, pl.mode, pl.granted, pa.datname, pa.client_addr,
       pa.query_start, pa.state, substring(pa.query FOR 1000)
FROM pg_catalog.pg_locks pl
LEFT JOIN pg_stat_activity pa ON pl.pid = pa.pid;

-- Locks older than 5 seconds

SELECT pl.pid, pl.locktype, pl.mode, pl.granted, pa.datname, pa.client_addr,
       pa.query_start, pa.state, substring(pa.query FOR 1000)
FROM pg_catalog.pg_locks pl
LEFT JOIN pg_stat_activity pa ON pl.pid = pa.pid
WHERE (now() - pa.query_start) > interval '5 seconds';

-- Blocked and blocking activity (who is waiting on whom)

SELECT blocked_locks.pid AS blocked_pid, blocked_activity.usename AS blocked_user,
       blocking_locks.pid AS blocking_pid, blocking_activity.usename AS blocking_user,
       blocked_activity.query AS blocked_statement,
       blocking_activity.query AS current_statement_in_blocking_process
FROM pg_catalog.pg_locks blocked_locks
    JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
    JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
        AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
        AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
        AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
        AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
        AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
        AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
        AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
        AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
        AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
        AND blocking_locks.pid != blocked_locks.pid
    JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

-- Count of connections

SELECT sum(numbackends)
FROM pg_stat_database;

-- Tables with dead tuples (candidates for vacuum)

SELECT relname, n_dead_tup
FROM pg_stat_user_tables
WHERE n_dead_tup > 10
ORDER BY n_dead_tup DESC;

-- Performance-related settings

SELECT version();
SHOW max_connections;
SHOW shared_buffers;
SHOW work_mem;
SHOW maintenance_work_mem;
SHOW effective_cache_size;
SHOW checkpoint_completion_target;
SHOW synchronous_commit;
SHOW random_page_cost;
SHOW track_activity_query_size;
