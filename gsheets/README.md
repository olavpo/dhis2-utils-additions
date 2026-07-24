# Google Sheets tools

Google Apps Script projects that pull DHIS2 metadata into Google Sheets
for collaborative review/editing and push changes back through the API.
Useful when working with people who should review or translate metadata
but should not (or cannot) work in the Maintenance app.

| Project | Purpose |
|---|---|
| `ggl-d2-metadata-review/` | Fetch metadata (names, short names, descriptions, group memberships...) into sheets, track edits on a review sheet, push accepted changes back. Includes group-set membership editing. |
| `ggl-d2-metadata-translation/` | Fetch metadata translations into sheets for translators, push completed translations back. |

## Deployment

These run inside a Google Sheet (Extensions > Apps Script) and are
managed with [clasp](https://github.com/google/clasp):

```bash
cd ggl-d2-metadata-review
clasp login
clasp create --type sheets   # or set scriptId in .clasp.json to use an existing sheet
clasp push
```

Reload the sheet; a DHIS2 menu appears. On first use it asks for the
server URL, username and password.

## Security notes

- The server URL and username are stored in the spreadsheet's document
  properties (visible to anyone with edit access to the sheet); the
  **password is held in memory only** and asked for per session — it is
  never persisted.
- Requests go directly from Google's servers to the DHIS2 instance, so
  the instance must be reachable from the internet.
- Use a dedicated DHIS2 account with only the needed metadata
  authorities, not a superuser.

## Review notes

- Writes use the legacy property-PATCH endpoint
  (`PATCH /api/<resource>/<id>/<property>` with a `{property: value}`
  body). Newer DHIS2 versions prefer JSON Patch
  (`application/json-patch+json` on `PATCH /api/<resource>/<id>`);
  verify a single update works against your target version before a
  bulk session, and expect this to be the first thing needing an update.
- Resource fetches use `paging=false`; on very large metadata sets
  (tens of thousands of objects) Apps Script response-size limits may
  require adding paging.

## Status

Copied as-is from the working originals in Olav's "DHIS2 Tools"
collection. Not testable against the disposable test instances used for
the rest of this repo (they require a Google account and an
internet-reachable DHIS2), so unlike the SQL/API tools these carry no
2.40-2.43 version matrix. The API calls used (`/api/schemas`,
`/api/<resource>.json`, metadata PATCH/POST) are stable across those
versions.
