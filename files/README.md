# File tools

Small helpers for manipulating DHIS2 export files (JSON) before re-import.
They work on files only — no DHIS2 connection involved, so they are
independent of the DHIS2 version (verified against exports from 2.40–2.43).

## Tools

### `shift_json_years.sh`

Shifts all years one year forward in the `"period"`, `"created"` and
`"lastUpdated"` fields of a DHIS2 JSON export — for refreshing exported
demo data so it appears one year more recent. Only the year component
changes; months/weeks/days are untouched. The file is modified in place.

```bash
./shift_json_years.sh export.json            # default year range 2013-2025
./shift_json_years.sh export.json 2015 2024  # explicit range
```

### `replace_uid.sh`

Replaces every occurrence of one string (typically a UID) with another in a
file, in place — e.g. re-pointing a data export at a different category
option combo before import.

```bash
./replace_uid.sh datavalues.json VYHuIGXpfow wnsR66pfYZ1
```

### `prune_orgunit_metadata.py`

Strips an org unit metadata export (organisationUnits, -Groups, -GroupSets,
-Levels) down to the fields needed to recreate the hierarchy elsewhere:
names, IDs, relationships, geometry, opening dates. Sharing, access,
attribute values and audit fields are dropped.

```bash
python prune_orgunit_metadata.py metadata.json -o metadata_pruned.json
```
