# dhis2-utils

A collection of utility scripts and SQL queries for working with DHIS2:
database analysis, demo-data refreshing, bulk API operations and
export-file manipulation.

All tools have been tested against DHIS2 2.40, 2.41, 2.42 and 2.43
(Sierra Leone demo database) — see the README in each folder for details
and per-version notes.

## Contents

| Folder | Tool | Purpose |
|---|---|---|
| [`sql/data-shifting/`](sql/data-shifting/) | `shift_aggregate_periods.sql` | Move aggregate data values forward in time (demo/training DB refresh) |
| | `shift_tracker_dates.sql` | Move tracker/event dates forward in time |
| [`sql/analysis/`](sql/analysis/) | `dataset_usage_stats.sql` | Dataset/data element usage statistics for metadata cleanup |
| | `dataset_disaggregations.sql` | List datasets, data elements and their disaggregations |
| | `high_volume_dataelements.sql` | Find data elements with sustained, substantial data |
| | `enrollment_stats.sql` | Monthly enrollment statistics for a tracker program |
| | `table_dependencies.sql` | List foreign-key dependencies on a table/column |
| [`api/`](api/) | `clear_orgunit_contacts.py` | Remove contact info from org units (demo DB preparation) |
| | `disable_category_dimensions.sh` | Bulk-disable/enable the data dimension flag on categories |
| [`files/`](files/) | `shift_json_years.sh` | Shift years forward in exported JSON (period/created/lastUpdated) |
| | `replace_uid.sh` | Replace a UID (or any string) in a file |
| | `prune_orgunit_metadata.py` | Strip an org unit metadata export to essential fields |

## Conventions

- **SQL** tools run directly against the DHIS2 PostgreSQL database
  (`psql -h <host> -U <user> -d <db> -f <file.sql>`). The analysis queries
  are read-only; the data-shifting tools modify data — never point them at
  a production database.
- **API** tools talk to a running DHIS2 over the Web API and take the base
  URL and credentials as arguments; nothing is hardcoded.
- After shifting data or changing category dimensions, run **Analytics
  Tables** export (and restart DHIS2 after period changes) for the changes
  to become visible in analytics.
