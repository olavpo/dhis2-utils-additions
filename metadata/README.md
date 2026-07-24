# Metadata packages

Importable DHIS2 metadata.

## `demo_data_sqlviews.json`

SQL views for checking the state of demo/training data from the DHIS2
web UI (Data Administration > SQL View) — no database access needed.
Companions to the [`sql/data-shifting/`](../sql/data-shifting/) tools:
after shifting, these show at a glance whether every dataset/program
has recent data at the expected org unit levels.

| View | Shows |
|---|---|
| Demo data status: aggregate | Data values and newest period per dataset and org unit level |
| Demo data status: tracker (2.40 / 2.41-2.42 / 2.43+) | Events and newest event date per program and org unit level |

Import:

```bash
curl -X POST -u admin:district -H "Content-Type: application/json" \
    -d @demo_data_sqlviews.json "https://<server>/api/metadata"
```

All four views import on any version; SQL views are only parsed when
**executed**, so run the tracker variant matching your DHIS2 version
(the tracker tables were renamed in 2.41 and split in 2.43) and ignore
the others — or delete them after import.

The stable UIDs (`uDemoDat...`) make re-imports update in place.

## Version compatibility

Import and execution tested on 2.40, 2.41, 2.42 and 2.43 (Sierra Leone
demo database); the aggregate view works on all versions, each tracker
variant on its labeled versions.

Curated from Olav's "DHIS2 Tools" collection (`sqlviews_demo_data.json`).
