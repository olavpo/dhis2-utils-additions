# Maintenance

SQL tools for repairing and pruning DHIS2 databases: removing invalid or
unwanted data, fixing corrupted sort orders, merging duplicate category
option combos and recovering locked-out admin accounts.

**These tools modify data.** Take a backup first, run inside a
transaction where the tool supports it, and never point them at a
production database without a tested rollback plan. Curated and reworked
from the upstream [dhis2/dhis2-utils](https://github.com/dhis2/dhis2-utils/tree/master/resources/sql)
`resources/sql` collection — see "Provenance" below.

## The cascade helper

Most tools here build on **`delete_where_cascade.sql`** — run it once
first (the functions persist in the database). It deletes rows *and
everything referencing them*, discovering the referencing tables from
the PostgreSQL catalog at runtime instead of hardcoding table lists per
DHIS2 version:

- NOT NULL references (a data value's period): referencing row is
  deleted, recursively
- nullable references (an interpretation's period): reference is set
  to NULL, the object survives
- `ON DELETE CASCADE`/`SET NULL` constraints: left to the database

It also defines `delete_orphan_relationships()`, which removes tracker
relationships whose ends were deleted.

```sql
-- Generic use: delete any row(s) plus everything hanging off them
BEGIN;
SELECT delete_where_cascade('organisationunit', 'uid = ''AAAAAAAAAAA''');
COMMIT;
```

## Tools

### `delete_orgunit_tree.sql`

Deletes an organisation unit subtree with ALL its data (data values,
tracked entities, enrollments, events, memberships). The API refuses to
delete org units with data; this is for pruning copied databases.

```sql
BEGIN;
SELECT delete_orgunit_tree('O6uvpzGd5pu');
COMMIT;
```

Restart DHIS2 and run Analytics Tables export afterwards. Users whose
only data-capture org units were deleted must be reassigned.

### `delete_data_out_of_range.sql`

Deletes periods and events outside a reasonable date range (data entry
typos like year 216 or 20155 that break analytics generation).

```sql
BEGIN;
SELECT delete_periods_out_of_range('1960-01-01', '2100-01-01');
SELECT delete_events_out_of_range('1960-01-01', '2100-01-01');
COMMIT;
```

Find such values first with the read-only
[`sql/analysis/invalid_datavalues.sql`](../analysis/invalid_datavalues.sql).

### `delete_all_data.sql`

Deletes ALL data (aggregate + tracker + audits) while keeping metadata,
users and configuration — for turning a production copy into a clean
training/development database. Returns a summary of rows deleted per
entity.

```sql
BEGIN;
SELECT * FROM delete_all_data();
COMMIT;
```

### `merge_category_option_combos.sql`

Merges a duplicate category option combo into the one to keep: data
values are merged (newest value wins on conflicts), every other
reference is repointed (discovered from the catalog), and the duplicate
is deleted. Typical use: repairing duplicate "default" combos flagged by
the data integrity checks.

```sql
BEGIN;
SELECT merge_category_option_combos('<keep-uid>', '<remove-uid>');
COMMIT;
```

### `fix_sort_order_gaps.sql`

Renumbers corrupted `sort_order` sequences (gaps, duplicates, NULLs)
while preserving the existing order. Generic function plus wrappers:

```sql
SELECT fix_option_sort_order();                       -- optionvalue
SELECT fix_visualization_orgunit_sort_order();        -- visualization_organisationunits
SELECT fix_visualization_datadimension_sort_order();  -- visualization_datadimensionitems
SELECT fix_sort_order_gaps('sectiondataelements', 'sectionid', 'dataelementid', 0);  -- any table
```

### `restore_admin_access.sql`

Recovers a locked-out superuser: password reset to `district`, account
enabled, 2FA off, membership in an ALL-authority role ensured. Restart
DHIS2 afterwards (credentials are cached) and change the password
immediately.

```sql
SELECT restore_admin_access('admin');
```

## Version compatibility

Tested on the Sierra Leone demo database for each version, with
before/after row-count verification:

| Tool | 2.40 | 2.41 | 2.42 | 2.43 |
|---|---|---|---|---|
| `delete_where_cascade.sql` | ✅ | ✅ | ✅ | ✅ |
| `delete_orgunit_tree.sql` | ✅ | ✅ | ✅ | ✅ |
| `delete_data_out_of_range.sql` | ✅ | ✅ | ✅ | ✅ |
| `delete_all_data.sql` | ✅ | ✅ | ✅ | ✅ |
| `merge_category_option_combos.sql` | ✅ | ✅ | ✅ | ✅ |
| `fix_sort_order_gaps.sql` | ✅ | ✅ | ✅ | ✅ |
| `restore_admin_access.sql` | ✅ | ✅ | ✅ | ✅ |

The catalog-driven design means the same files handle the 2.41 tracker
table renames (`programinstance`→`enrollment`,
`programstageinstance`→`event`) and the 2.43 split of `event` into
`trackerevent`/`singleevent` without version-specific table lists.

## Provenance

Reworked from upstream `resources/sql` scripts:
`delete_orgunittree_with_data.sql` (rewritten: the original targeted
2.3x-era tables and its chart/visualization re-sort blocks ran after the
rows were already deleted), `delete_data_out_of_range.sql` (original
missed `datavalueaudit` and favorite references and used 2.40-only
tracker tables), `clean_data.sql` (original's delete list omitted
`programinstance`, so it failed on foreign keys),
`fix_duplicate_default_category_option_combos.sql` (original was a
one-off with hardcoded ids; on tied timestamps its symmetric delete
removed *both* duplicate values), `clean_up_option_sort_order.sql` +
`clean_up_visualization_*_sort_order.sql` (merged; single-pass
renumbering could violate primary keys where sort_order is part of the
key), and `admin_user_queries.sql` (write statements turned into a
function; the original's role-grant query selected a non-existent
column).
