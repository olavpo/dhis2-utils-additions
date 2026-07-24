# Analysis queries

Read-only SQL queries for analysing a DHIS2 database — data usage, metadata
structure and schema dependencies. Safe to run on a production replica
(two of them create a session-local temp view or function, nothing more).

Run with psql:

```bash
psql -h localhost -U dhis -d dhis2 -f <query>.sql
```

## Queries

### `dataset_usage_stats.sql`

Three queries for assessing how much datasets and data elements are used —
the raw material for deciding what can be removed during metadata cleanup:

1. Per dataset: completed registrations, exclusive/total data element counts
2. Per data element: data values per year (adjust the hardcoded years),
   with the datasets it belongs to and first/last period with data
3. Per dataset: total data values, and values belonging to data elements
   exclusive to that dataset

Scans the full datavalue table — takes a minute or two on a few million
rows, plan accordingly on large databases.

### `dataset_disaggregations.sql`

Lists every dataset with its data elements, the dataset's attribute
category options and each data element's disaggregation category option
combos. Useful when reviewing/harmonising category combos. One row per
combination — filter on dataset to keep output manageable.

### `high_volume_dataelements.sql`

Finds data elements in active, sustained use: more than 24 periods with
more than 50 data values each (thresholds adjustable in the CTEs), and
lists per-period value counts for them. The `program` column assumes the
"PREFIX: name" naming convention and shows the part before the colon.

### `enrollment_stats.sql`

Monthly uptake statistics for one tracker program: enrollments per month,
districts (org unit level 3) enrolling per month, and users enrolling per
month. Pass the program UID as a psql variable:

```bash
psql -h localhost -U dhis -d dhis2 -v program_uid=IpHINAT79UW -f enrollment_stats.sql
```

Requires the org unit structure resource table (generate resource tables in
DHIS2 first) — `analytics_rs_orgunitstructure` on 2.41+, `_orgunitstructure`
on 2.40.

### `metadata_hygiene.sql`

Metadata and usage assessment: abandoned datasets, aggregate data
elements without data or analysis use, unused indicators, empty or
never-viewed dashboards/visualizations/maps, inactive-but-enabled
users, org units missing compulsory group sets or not reporting. A
summary section (count + share per check) plus listings (name + uid)
for the actionable checks. Complements the built-in data integrity
checks, which cover structure but not usage. Modernized from Olav's
"DHIS2 Tools" metadata assessment queries (the originals used pre-2.36
tables — `users`, `chart`, `reporttable`, `publicaccess`).

### `relationship_overview.sql`

Tracker relationship types with their from/to constraints resolved to
names (tracked entity type, program, program stage per side) and the
count of actual relationships per type. The Maintenance app only shows
constraints one relationship type at a time. From the upstream
[dhis2/dhis2-utils](https://github.com/dhis2/dhis2-utils/tree/master/resources/sql)
`admin_tracker_queries.sql`.

### `invalid_datavalues.sql`

Finds stored data values that don't match their data element's value
type (non-numeric values on numeric elements, invalid booleans) or that
sit in periods outside a reasonable range. These break analytics and are
not covered by DHIS2's built-in (metadata-only) data integrity checks.
Cleanup companion: [`sql/maintenance/delete_data_out_of_range.sql`](../maintenance/delete_data_out_of_range.sql).
Adapted from the upstream `integrity_checks.sql`.

### `table_dependencies.sql`

Creates a helper function listing every table with a foreign key to a given
table/column — i.e. "what will block my DELETE":

```sql
SELECT * FROM d2_dependencies('dataelement', 'dataelementid');
```

## Version compatibility

| Query | 2.40 | 2.41 | 2.42 | 2.43 |
|---|---|---|---|---|
| `dataset_usage_stats.sql` | ✅ | ✅ | ✅ | ✅ |
| `dataset_disaggregations.sql` | ✅ | ✅ | ✅ | ✅ |
| `high_volume_dataelements.sql` | ✅ | ✅ | ✅ | ✅ |
| `enrollment_stats.sql` | ✅ | ✅ | ✅ | ✅ |
| `metadata_hygiene.sql` | ✅ | ✅ | ✅ | ✅ |
| `relationship_overview.sql` | ✅ | ✅ | ✅ | ✅ |
| `invalid_datavalues.sql` | ✅ | ✅ | ✅ | ✅ |
| `table_dependencies.sql` | ✅ | ✅ | ✅ | ✅ |

Two queries bridge cross-version table renames automatically with
session-local temp views: `dataset_disaggregations.sql` (2.40's
`dataelementcategoryoption` → `categoryoption`) and `enrollment_stats.sql`
(2.40's `programinstance` → `enrollment` and `_orgunitstructure` →
`analytics_rs_orgunitstructure`).
