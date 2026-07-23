# Data shifting

SQL tools for moving DHIS2 data forward in time. Their purpose is keeping
demo and training databases *current*: a demo database with data ending two
years ago looks dead, so these tools periodically shift everything forward
so the newest data is always recent.

**Never run these against a production database.** They rewrite the periods
and dates of existing data. Take a backup first; any failure rolls back
cleanly, but the intended change itself is destructive by design.

## Tools

### `shift_aggregate_periods.sql` — aggregate data (datavalue table)

Defines two functions and ends with a catch-up query that brings all
aggregate data up to the present:

| Function | Shifts |
|---|---|
| `shift_dataset_periods(period_type, dataset_uid, num_periods)` | all data for one dataset's data elements |
| `shift_dataelement_periods(period_type, dataelement_uid, num_periods)` | all data for one data element |

- Supported period types: Daily, Weekly, Monthly, Quarterly, SixMonthly,
  Yearly. Data of other period types (e.g. FinancialOct, WeeklyWednesday)
  is left untouched.
- Missing target periods are created automatically — including the ISO
  period name in the NOT NULL `iso` column that 2.43 added to the period
  table.
- Shift **forward only** (positive `num_periods`).
- Data elements shared between datasets are shifted once per
  `shift_dataset_periods` call — when datasets overlap, prefer
  `shift_dataelement_periods`, which is also what the catch-up query uses
  (each data element is shifted once, by the smallest lag among its
  datasets).
- Predictor-generated data elements are skipped by the catch-up query;
  rerun the predictors afterwards instead.

Running the whole file executes the catch-up:

```bash
psql -h localhost -U dhis -d dhis2 -f shift_aggregate_periods.sql
```

Or load the functions and shift selectively:

```sql
-- one dataset, 3 months forward
SELECT shift_dataset_periods('Monthly', 'BfMAe6Itzgt', 3);

-- one data element, 2 quarters forward
SELECT shift_dataelement_periods('Quarterly', 's46m5MS0hxu', 2);

-- a group of datasets, excluding predictor outputs (historical pattern):
WITH des AS (
    SELECT de.uid AS de_uid, pt.name AS ds_ptype
    FROM datasetelement dse
    LEFT JOIN dataset ds USING(datasetid)
    LEFT JOIN periodtype pt USING(periodtypeid)
    LEFT JOIN dataelement de USING(dataelementid)
    WHERE ds.uid IN ('ql3YI4SokB3', 'OyutuMOPgkt')
      AND pt.name = 'Quarterly'
      AND de.dataelementid NOT IN (SELECT generatoroutput FROM predictor)
    GROUP BY de.uid, pt.name
)
SELECT shift_dataelement_periods(ds_ptype, de_uid, 4) FROM des;
```

### `shift_tracker_dates.sql` — tracker and event data

`shift_tracker_dates(number_days)` shifts all tracker/event data forward by
a number of days: enrollment dates, DATE-type tracked entity attribute
values, event dates (occurred/scheduled/completed) and DATE-type data
values inside events.

```sql
-- everything one week forward
SELECT shift_tracker_dates(7);
```

The function detects the DHIS2 schema at runtime and follows the tracker
table changes across versions: 2.40's `programinstance`/
`programstageinstance`, the 2.41 renames to `enrollment`/`event`, and the
2.43 split of `event` into `trackerevent` and `singleevent`.

## After shifting

1. Restart DHIS2 — it caches periods, and newly created period rows are
   not picked up until restart.
2. Run **Analytics Tables** export so the shifted data appears in analytics.
3. If predictors are in use, rerun them for the affected periods.

## Version compatibility

| Tool | 2.40 | 2.41 | 2.42 | 2.43 |
|---|---|---|---|---|
| `shift_aggregate_periods.sql` | ✅ | ✅ | ✅ | ✅ |
| `shift_tracker_dates.sql` | ✅ | ✅ | ✅ | ✅ |

Tested on the Sierra Leone demo database for each version: values shifted
with no change in row counts, and shifted data verified visible in
analytics after an analytics run.
