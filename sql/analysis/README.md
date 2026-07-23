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

Requires the `_orgunitstructure` resource table (generate resource tables
in DHIS2 first).

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
| `table_dependencies.sql` | ✅ | ✅ | ✅ | ✅ |

Two queries bridge cross-version table renames automatically with a
session-local temp view: `dataset_disaggregations.sql` (2.40's
`dataelementcategoryoption` → `categoryoption`) and `enrollment_stats.sql`
(2.40's `programinstance` → `enrollment`).
