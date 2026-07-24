# DHIS2 Metadata Deduplication — SQL Functions

Direct-database SQL functions for deduplicating DHIS2 category metadata.
Use these when no native merge endpoint exists for the type on your
version (see below), or when you only have database access.

## Prefer the native merge endpoints where they exist

Newer DHIS2 versions provide `POST /api/<type>/merge`, which performs the
same data-safe migration (references + data values + audit, in one
transaction, with a `LAST_UPDATED` or `DISCARD` data strategy):

```json
{"sources": ["uid", ...], "target": "uid", "deleteSources": true,
 "dataMergeStrategy": "LAST_UPDATED"}
```

Availability is version-dependent — **probe, don't assume**: an empty
`POST /api/<type>/merge {}` returns `404`/`405` if the endpoint doesn't
exist, `409`/`400` if it does.

| Type | 2.40–2.41 | 2.42 | 2.43+ |
|---|---|---|---|
| categoryOptionCombos | SQL (this toolkit) | API merge | API merge |
| dataElements, indicators, organisationUnits | SQL/manual | API merge | API merge |
| categories, categoryOptions, categoryCombos | SQL (this toolkit) | SQL (this toolkit) | API merge |

So on a current DHIS2 the API endpoint is the first choice; this toolkit
is the tested path for **older versions**, for **offline work on a
database copy**, and for the **diagnostic functions** (`*_dup_list`,
`*_dup_count`), which are useful on every version.

All functions live in `merge_functions.sql` and are loaded once via `psql`.

---

## Contents

1. [Setup](#setup)
2. [Safety and transactions](#safety-and-transactions)
3. [DHIS2 version compatibility](#dhis2-version-compatibility)
4. [Diagnostic functions](#diagnostic-functions)
   - [cat_dup_list](#cat_dup_list)
   - [cat_dup_count](#cat_dup_count)
   - [cc_dup_list](#cc_dup_list)
   - [cc_dup_count](#cc_dup_count)
   - [coc_dup_list](#coc_dup_list)
   - [coc_dup_count](#coc_dup_count)
5. [Merge functions](#merge-functions)
   - [co_dup_merge](#co_dup_merge)
   - [cat_dup_merge](#cat_dup_merge)
   - [cc_dup_merge](#cc_dup_merge)
   - [coc_dup_merge](#coc_dup_merge)
6. [Typical workflows](#typical-workflows)
7. [Helper functions](#helper-functions)

---

## Setup

Load all functions into the target database once:

```bash
psql -d <dbname> -f sql/merge_functions.sql
```

Re-run the same command after any update to the file — all functions are
`CREATE OR REPLACE`, so existing definitions are replaced in-place.

The functions are created in the `public` schema and require no special
extensions beyond a standard PostgreSQL installation.

---

## Safety and transactions

**Write functions are atomic at the function level.** Each merge function
wraps its entire write section in a nested PL/pgSQL `BEGIN … EXCEPTION WHEN
OTHERS THEN RAISE; END` block, which creates an implicit savepoint. If any
unexpected error occurs mid-write (constraint violation, missing column, etc.),
PostgreSQL rolls back every write made by that function invocation before
re-raising the error. The database is never left in a partially-written state.

**Recommended pattern — inspect before committing:**

```sql
BEGIN;

SELECT co_dup_merge(
    'UIDtarget1',
    ARRAY['UIDsource1', 'UIDsource2']
);

-- Inspect the result before deciding:
SELECT cat_dup_list();

-- If happy:
COMMIT;

-- If not:
ROLLBACK;
```

Wrapping in an explicit `BEGIN/COMMIT` lets you review the outcome and roll
back if anything looks wrong, without losing the atomic-failure guarantee
already baked into the functions.

---

## DHIS2 version compatibility

The functions detect schema differences automatically at runtime using
`information_schema`, so the same file runs against all supported versions.

| DHIS2 version | Notable differences handled |
|---|---|
| < 2.38 | Events table is `programstageinstance` (not `event`) |
| ≥ 2.43 | Events split into `trackerevent` and `singleevent` |
| < 2.38 | Category table is `dataelementcategory` (not `category`) |
| < 2.38 | Category option table is `dataelementcategoryoption` (not `categoryoption`) |
| ≥ 2.41 | `programindicator` has `categorycomboid` and `attributecomboid` columns |
| ≥ 2.42 | `program` has `enrollmentcategorycomboid` column |

Tested against DHIS2 2.40, 2.41, 2.42 and 2.43 (Sierra Leone demo database).

---

## Diagnostic functions

Use these before merging to understand what you are working with.

---

### cat_dup_list

```sql
SELECT * FROM cat_dup_list();
```

Returns all **categories** (dataElementCategories) that share the exact same
set of category options — i.e. are functionally identical regardless of name or
code.

Duplicates are defined by member identity, not by name. Two categories with
different names but the same options are returned; two categories with the same
name but different options are not.

**Columns returned:**

| Column | Description |
|---|---|
| `category_name` | Display name |
| `cat_uid` | DHIS2 UID |
| `cat_id` | Internal database ID |
| `cat_code` | Code (may be null) |
| `member_options` | Comma-separated sorted list of option IDs (groups duplicates together) |

All rows with the same `member_options` value are duplicates of each other.
Choose one as the target and pass the rest to `cat_dup_merge`.

---

### cat_dup_count

```sql
SELECT * FROM cat_dup_count(keep_id integer, remove_id integer);
```

Shows **reference counts** for two categories across all FK-dependent tables.
Pass integer internal IDs (from `cat_dup_list.cat_id`).

Useful for deciding which category to keep (prefer the one with more references,
as fewer rewrites are needed — though the merge function handles both directions).

**Columns returned:** `description`, `keep_count`, `remove_count`

---

### cc_dup_list

```sql
SELECT * FROM cc_dup_list();
```

Returns all **categoryCombos** that share the exact same set of categories —
functionally identical combos.

**Columns returned:**

| Column | Description |
|---|---|
| `combo_name` | Display name |
| `cc_uid` | DHIS2 UID |
| `cc_id` | Internal database ID |
| `cc_code` | Code (may be null) |
| `member_categories` | Comma-separated sorted list of category IDs (groups duplicates) |

---

### cc_dup_count

```sql
SELECT * FROM cc_dup_count(keep_id integer, remove_id integer);
```

Shows reference counts for two categoryCombos across all FK-dependent tables,
including `dataelement`, `dataset`, `datasetelement`, `program`,
`programindicator` (version-guarded), and `dataapprovalworkflow`.

---

### coc_dup_list

```sql
SELECT * FROM coc_dup_list();
```

Returns all **categoryOptionCombos** within each categoryCombo that share the
exact same set of categoryOptions. These are the lowest-level duplicates and
the hardest to eliminate safely, since COCs are referenced by data values.

**Columns returned:**

| Column | Description |
|---|---|
| `categorycombo` | Name of the parent categoryCombo |
| `cc_uid` | UID of the parent categoryCombo |
| `categoryoptioncombo` | Name of the duplicate COC |
| `coc_uid` | UID of the duplicate COC |
| `coc_id` | Internal database ID of the duplicate COC |

Each set of duplicate COCs within the same combo will appear as multiple rows
with the same `cc_uid`. Pick one UID as the target and pass the others to
`coc_dup_merge`.

---

### coc_dup_count

```sql
SELECT * FROM coc_dup_count('UID_keep', 'UID_remove');
```

Shows reference counts and **merge conflict counts** for two COCs. Accepts
UIDs (not integer IDs).

**Columns returned:** `description`, `first_coc` (count as text), `second_coc`

Key rows to look at:

| Row label | Meaning |
|---|---|
| `datavalue` | Data values referencing each COC |
| `[conflicts] datavalue` | Data value rows that would conflict on merge (same data element + period + org unit) |
| `[conflicts] datavalue (different values)` | Conflicts where the two values differ (LAST_UPDATED will resolve these) |
| `[conflicts] dataapproval` | Approval records that would conflict |
| `[uid] indicator (numerator/denominator)` | Indicators using the COC UID in an expression |
| `[uid] expression (predictor/validationRule)` | Expressions using the COC UID |

A large number of `[conflicts] datavalue (different values)` means data from
the source will be silently discarded in favour of the most recently updated
record; review these before merging in a production database.

---

## Merge functions

All merge functions:
- **Return `TRUE`** on success.
- **Return `FALSE`** (with a `WARNING` message) if any pre-condition fails. No
  data is written when FALSE is returned.
- **Are atomic** — a mid-write failure rolls back all changes from that call.
- Accept a `delete_sources bool DEFAULT true` parameter; pass `false` to
  remap references without deleting the source rows.

---

### co_dup_merge

```sql
SELECT co_dup_merge(
    target_uid     text,
    source_uids    text[],
    delete_sources bool DEFAULT true
);
```

Merges one or more **categoryOptions** into a target. All references to each
source option are redirected to the target. If `delete_sources` is true, the
source rows are deleted from `categoryoption`.

**Pre-conditions:**
- Target must exist.
- Target must not appear in the source list.
- Every source must exist (the entire operation is aborted if any source is missing — no partial merges).

**Tables updated:**

| Table | What changes |
|---|---|
| `categories_categoryoptions` | Source option memberships moved to target; duplicates removed |
| `categoryoptioncombos_categoryoptions` | Source option references in COCs updated to target |
| `categoryoptiongroupmembers` | Option group memberships remapped |
| `categoryoption_organisationunits` | Org-unit access restrictions remapped |
| `categorydimension_items` | Visualization filter items remapped |

**COC deduplication:** when updating a COC's option membership from source →
target would create a COC with an identical option fingerprint to an existing
COC in the same combo, `co_dup_merge` automatically calls
`coc_dup_merge` to merge the data (LAST_UPDATED conflict resolution). This
handles the common cascade where merging options produces duplicate COCs.

---

### cat_dup_merge

```sql
SELECT cat_dup_merge(
    target_uid     text,
    source_uids    text[],
    delete_sources bool DEFAULT true
);
```

Merges one or more **categories** into a target. Requires that every source
category has exactly the same set of category options as the target (if
options differ, the categories are not true duplicates and the merge is
rejected).

**Pre-conditions:**
- Target must exist.
- Target must not appear in the source list.
- Every source must exist.
- Every source must have the same sorted set of categoryOptions as the target.
- No source may share a CategoryCombo with the target (would produce a combo
  containing two copies of the target category after merge).
- No two sources may share a CategoryCombo with each other (same reason).

**Tables updated:**

| Table | What changes |
|---|---|
| `categories_categoryoptions` | Source option memberships deleted (identical to target) |
| `categorycombos_categories` | Combo memberships remapped from source to target |
| `categorydimension` | Category dimension references remapped |
| `users_catdimensionconstraints` | User data-dimension constraints remapped; if a user already has the target, duplicate source constraints are deleted |

---

### cc_dup_merge

```sql
SELECT cc_dup_merge(
    target_uid     text,
    source_uids    text[],
    delete_sources bool DEFAULT true
);
```

Merges one or more **categoryCombos** into a target. Requires that every
source combo has exactly the same set of categories as the target.

**Pre-conditions:**
- Target must exist.
- Target must not appear in the source list.
- Every source must exist.
- Every source must have the same sorted set of categories as the target.
- **Integrity check 1:** no combo (target or source) may contain duplicate COCs
  (two COCs with the same option fingerprint).
- **Integrity check 2:** all COCs in every involved combo must have the correct
  cardinality (number of options = number of categories in the combo).
- **Integrity check 3:** all options in every COC must actually belong to one
  of the combo's categories.

The integrity checks prevent the merge from producing an inconsistent state.
If any combo fails, fix its COCs first (using `coc_dup_merge` or manually)
before retrying.

**Tables updated:**

| Table | What changes |
|---|---|
| `categorycombos_categories` | Source category memberships deleted |
| `categorycombos_optioncombos` | Source COC memberships remapped; source COCs that duplicate target COCs are merged via `coc_dup_merge` |
| `dataelement` | combo FK remapped |
| `dataset` | combo FK remapped |
| `datasetelement` | override combo FK remapped |
| `program` | combo FK remapped |
| `program.enrollmentcategorycomboid` | remapped (DHIS2 ≥ 2.42, version-guarded) |
| `programindicator.categorycomboid` | remapped (version-guarded) |
| `programindicator.attributecomboid` | remapped (version-guarded) |
| `dataapprovalworkflow` | combo FK remapped |
| `caseaggregation` | remapped (version-guarded) |

---

### coc_dup_merge

```sql
SELECT coc_dup_merge(
    coc_uid_keep    text,
    coc_uids_remove text[]
);
```

Merges one or more **categoryOptionCombos** into a target. This is the most
complex merge because COCs are referenced by data values, approvals, events,
and expressions.

**Pre-conditions:**
- Target must exist.
- Target must not appear in the source list.
- Every source must exist.
- Every source must belong to the **same categoryCombo** as the target.
- Every source must have the **same set of categoryOptions** as the target
  (this is the DHIS2 definition of COC equality — same members = true duplicate).

**Data conflict resolution — LAST_UPDATED:**

When both source and target have a data value for the same
(dataElement, period, orgUnit, attributeOptionCombo) combination:

1. Soft-deleted rows are removed first.
2. Rows with identical values are deduplicated (one is deleted).
3. For rows with different values, the **most recently updated** record wins;
   the older record is deleted.

The same LAST_UPDATED strategy is applied to `completedatasetregistration`,
`dataapproval`, and `event`.

**Performance note:** Source data value rows are materialised into a temporary
table once before the multi-pass merge logic runs. This avoids repeated
full-table sequential scans on `datavalue`, which has no standalone index on
`categoryoptioncomboid`. On databases with millions of data values the merge
still completes in seconds.

**Tables updated:**

| Table | Action |
|---|---|
| `categoryoption` (via `categoryoptioncombos`) | Source option memberships removed from source COCs |
| `categorycombo` (via `categorycombos_optioncombos`) | Source COC memberships removed |
| `datavalue` | Source references remapped to target; conflicts resolved by LAST_UPDATED |
| `datavalueaudit` | Source references remapped |
| `completedatasetregistration` | Remapped; conflicts resolved by LAST_UPDATED |
| `dataapproval` | Remapped; conflicts resolved by most recently created/updated |
| `dataapprovalaudit` | Source references deleted (audit records for deleted approvals) |
| `validationresult` | Remapped; duplicate rows for same rule+period+orgunit deleted |
| `minmaxdataelement` | Remapped; duplicates for same element+orgunit deleted |
| `dataelementoperand` | Source FK set to target |
| `datadimensionitem` | Source FK set to target |
| `indicator` (numerator/denominator) | UID in expression string replaced |
| `indicator.aggregateexportcategoryoptioncombo` | UID replaced |
| `programindicator.aggregateexportcategoryoptioncombo` | UID replaced |
| `predictor.outputcombo` | FK set to target |
| `smscodes` | FK set to target |
| `expression` | UID in expression string replaced |
| `dataentryform` (html) | UID in HTML replaced |
| `event` / `programstageinstance` | `attributeOptionCombo` remapped (table name auto-detected) |
| Source `categoryoptioncombo` rows | Deleted after all references are remapped |

---

## Typical workflows

### Workflow A: merge duplicate categories

```sql
-- 1. Find duplicates
SELECT * FROM cat_dup_list();

-- 2. Check reference counts to choose which to keep
SELECT * FROM cat_dup_count(1234, 5678);

-- 3. Inspect, then merge inside a transaction
BEGIN;
SELECT cat_dup_merge(
    'UIDofTargetCategory',
    ARRAY['UIDofSource1', 'UIDofSource2']
);
-- Verify the result looks right, then commit:
COMMIT;
-- Or: ROLLBACK;
```

---

### Workflow B: merge duplicate categoryCombos

```sql
-- 1. Find duplicates
SELECT * FROM cc_dup_list();

-- 2. Check reference counts
SELECT * FROM cc_dup_count(1234, 5678);

-- 3. Merge
BEGIN;
SELECT cc_dup_merge(
    'UIDofTargetCombo',
    ARRAY['UIDofSourceCombo1']
);
COMMIT;
```

If integrity checks fail, `cc_dup_merge` returns FALSE with a warning
explaining which combo has a problem. Fix the flagged combo's COCs first:

```sql
-- Fix duplicate COCs in the problematic combo before retrying:
SELECT * FROM coc_dup_list() WHERE cc_uid = 'UIDofProblematicCombo';

BEGIN;
SELECT coc_dup_merge('UIDofTargetCOC', ARRAY['UIDofDuplicateCOC']);
COMMIT;

-- Then retry the combo merge:
BEGIN;
SELECT cc_dup_merge('UIDofTargetCombo', ARRAY['UIDofSourceCombo']);
COMMIT;
```

---

### Workflow C: full cascade (options → categories → combos → COCs)

When merging at every level, work **bottom-up** (options first, then
categories, then combos). Merging at a higher level may automatically trigger
lower-level merges (e.g. `cc_dup_merge` calls `coc_dup_merge`
internally), but starting from the bottom avoids integrity-check failures.

```sql
-- Step 1: merge duplicate category options
BEGIN;
SELECT co_dup_merge('UIDtargetOpt', ARRAY['UIDsrcOpt1','UIDsrcOpt2']);
COMMIT;

-- Step 2: merge categories that became identical after option merge
SELECT * FROM cat_dup_list();   -- re-run to see new duplicates
BEGIN;
SELECT cat_dup_merge('UIDtargetCat', ARRAY['UIDsrcCat1']);
COMMIT;

-- Step 3: merge combos that became identical after category merge
SELECT * FROM cc_dup_list();
BEGIN;
SELECT cc_dup_merge('UIDtargetCombo', ARRAY['UIDsrcCombo1']);
COMMIT;

-- Step 4: check for any remaining COC duplicates
SELECT * FROM coc_dup_list();
BEGIN;
SELECT coc_dup_merge('UIDtargetCOC', ARRAY['UIDsrcCOC1']);
COMMIT;
```

---

### Workflow D: investigate COC conflicts before merging

```sql
-- See what data values conflict between two duplicate COCs
SELECT * FROM coc_dup_count('UIDkeep', 'UIDremove');
```

Pay attention to `[conflicts] datavalue (different values)`. These are records
where both COCs have a value for the same data element + period + org unit, but
the values differ. The **most recently updated** record wins. If this is
unacceptable, do not merge.

---

## Helper functions

### d2_dependencies

```sql
SELECT * FROM d2_dependencies('categoryoptioncombo', 'categoryoptioncomboid');
```

Lists every table and column that has a foreign key pointing at the given
table/column. Used internally by `coc_dup_count` to enumerate all FK-dependent
tables dynamically. Useful for ad-hoc investigation.

---

### FIRST / LAST aggregates

The file installs `first(anyelement)` and `last(anyelement)` aggregate
functions, which return the first or last non-null value from a sorted set.
Used internally; not intended for direct use.
