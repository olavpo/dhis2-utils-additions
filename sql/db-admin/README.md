# Database administration

PostgreSQL-level tools for DHIS2 database servers: monitoring activity,
finding and cancelling slow queries, and small helper functions. Curated
from the upstream [dhis2/dhis2-utils](https://github.com/dhis2/dhis2-utils/tree/master/resources/sql)
`resources/sql` collection.

## Tools

### `pg_activity.sql`

Query cookbook for live monitoring: current/slow queries, locks,
blocked-vs-blocking sessions, dead tuples, connection counts and
performance settings. Run individual queries as needed.

### `pg_stat_statements.sql`

Sets up the `pg_stat_statements` extension (in a `stat` schema) with two
views: `stat.view_slow_queries` (by mean time) and
`stat.view_frequent_queries` (by total time). Requires
`shared_preload_libraries = 'pg_stat_statements'` in postgresql.conf and
a server restart first — instructions in the file. PostgreSQL 13+.

### `cancel_slow_queries.sql`

`dhis_cancel_slow_queries(max_duration, db_user)` cancels long-running
DHIS2 SELECT queries (default: over 1 minute, user `dhis`), sparing
psql/pg_dump sessions and maintenance. A safety valve for servers where
runaway analytics or SQL view queries pile up; typically cron-scheduled.

```sql
SELECT dhis_cancel_slow_queries();                  -- defaults
SELECT dhis_cancel_slow_queries('5 minutes', 'dhis');
```

### `utility_functions.sql`

- `uid()` — random valid DHIS2 UID, for creating metadata in SQL
  (original by Bob Jolliffe)
- `approx_count('table')` — instant approximate row count from table
  statistics; use instead of `count(*)` on datavalue-sized tables

### `set_lao_collation.sql`

Applies the ICU Lao collation (`lo-x-icu`) to the name/shortname columns
DHIS2 sorts on, and reindexes. PostgreSQL sorts Lao text very slowly
under the default collation; this fixes sort performance on
Lao-language databases. Column types are read from the catalog, so the
script works unchanged across DHIS2 versions (the upstream original
targeted 2.3x-era tables like `reporttable` and `chart`). Adaptable to
other languages by swapping the collation name.

## Version compatibility

| Tool | 2.40 | 2.41 | 2.42 | 2.43 |
|---|---|---|---|---|
| `pg_activity.sql` | ✅ | ✅ | ✅ | ✅ |
| `pg_stat_statements.sql` | ✅ | ✅ | ✅ | ✅ |
| `cancel_slow_queries.sql` | ✅ | ✅ | ✅ | ✅ |
| `utility_functions.sql` | ✅ | ✅ | ✅ | ✅ |
| `set_lao_collation.sql` | ✅ | ✅ | ✅ | ✅ |

`pg_activity.sql`, `pg_stat_statements.sql` and `cancel_slow_queries.sql`
depend on PostgreSQL, not the DHIS2 schema (verified on PostgreSQL 16;
`pg_stat_statements.sql` needs 13+ for the `*_exec_time` column names).
