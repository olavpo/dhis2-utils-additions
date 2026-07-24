# dhis2-utils

A collection of utility scripts and SQL queries for working with DHIS2:
database analysis, maintenance and repair, demo-data refreshing, bulk
API operations and export-file manipulation. Some tools are curated and
reworked from the upstream
[dhis2/dhis2-utils](https://github.com/dhis2/dhis2-utils) `resources/`
collection — provenance is noted in the folder READMEs.

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
| | `metadata_hygiene.sql` | Metadata/usage assessment: what is abandoned or unused |
| | `relationship_overview.sql` | Tracker relationship types with resolved constraints |
| | `invalid_datavalues.sql` | Find stored values that don't match their value type |
| | `table_dependencies.sql` | List foreign-key dependencies on a table/column |
| [`sql/maintenance/`](sql/maintenance/) | `delete_where_cascade.sql` | Cascade-delete helper (used by the tools below) |
| | `delete_orgunit_tree.sql` | Delete an org unit subtree with all its data |
| | `delete_data_out_of_range.sql` | Delete periods/events outside a reasonable date range |
| | `delete_all_data.sql` | Strip all data, keep metadata and users |
| | `fix_sort_order_gaps.sql` | Repair corrupted sort_order sequences |
| | `generate_completeness.sql` | Generate completeness registrations from data values |
| | `restore_admin_access.sql` | Recover a locked-out superuser account |
| [`sql/merge-categories/`](sql/merge-categories/) | `merge_functions.sql` | Find and merge duplicate category options/categories/combos/COCs |
| [`sql/db-admin/`](sql/db-admin/) | `pg_activity.sql` | PostgreSQL activity/locks monitoring cookbook |
| | `pg_stat_statements.sql` | Slow-query statistics setup + views |
| | `cancel_slow_queries.sql` | Auto-cancel runaway DHIS2 queries |
| | `utility_functions.sql` | `uid()` and `approx_count()` helpers |
| | `set_lao_collation.sql` | Fix slow Lao-text sorting with ICU collation |
| [`api/`](api/) | `clear_orgunit_contacts.py` | Remove contact info from org units (demo DB preparation) |
| | `disable_category_dimensions.sh` | Bulk-disable/enable the data dimension flag on categories |
| | `tracker_to_aggregate.sh` | Transfer program indicator values into aggregate data elements |
| [`files/`](files/) | `shift_json_years.sh` | Shift years forward in exported JSON (period/created/lastUpdated) |
| | `replace_uid.sh` | Replace a UID (or any string) in a file |
| | `prune_orgunit_metadata.py` | Strip an org unit metadata export to essential fields |
| | `clean_custom_form_html.sh` | Strip MS Word formatting from custom form HTML |
| | `flip_geojson_coordinates.js` | Swap lat/lon order throughout a GeoJSON file |
| [`metadata/`](metadata/) | `demo_data_sqlviews.json` | Importable SQL views for checking demo data status |
| [`gsheets/`](gsheets/) | `ggl-d2-metadata-review/`, `ggl-d2-metadata-translation/` | Google Sheets metadata review and translation tools (Apps Script) |

## Conventions

- **SQL** tools run directly against the DHIS2 PostgreSQL database
  (`psql -h <host> -U <user> -d <db> -f <file.sql>`). The analysis queries
  are read-only; the data-shifting and maintenance tools modify data —
  take a backup, run inside a transaction where supported, and never
  point them at a production database casually.
- **API** tools talk to a running DHIS2 over the Web API and take the base
  URL and credentials as arguments; nothing is hardcoded.
- After shifting data or changing category dimensions, run **Analytics
  Tables** export (and restart DHIS2 after period changes) for the changes
  to become visible in analytics.

## License

BSD 3-Clause, © University of Oslo — see [LICENSE](LICENSE).
