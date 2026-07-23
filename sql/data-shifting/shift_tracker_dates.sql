-- shift_tracker_dates.sql
--
-- Shifts all tracker and event data forward in time by a number of days.
-- Intended for keeping demo/training databases current. Updates:
--   * enrollment dates
--   * DATE-type tracked entity attribute values
--   * event dates (occurred/scheduled/completed)
--   * DATE-type data values stored in events (the eventdatavalues JSON)
--
-- Function: shift_tracker_dates(number_days)
--   number_days   Number of days to shift forward (negative shifts backward)
--
-- Handles the DHIS2 tracker schema changes across versions by detecting
-- which tables exist at runtime:
--   * 2.40:  programinstance / programstageinstance
--   * 2.41+: enrollment / event
--   * 2.43+: enrollment / trackerevent + singleevent
--
-- NOTE: run "Analytics Tables" export afterwards for the shift to be visible
-- in analytics. Use shift_aggregate_periods.sql for aggregate data.

CREATE OR REPLACE FUNCTION shift_tracker_dates (number_days integer) RETURNS boolean
    LANGUAGE plpgsql
AS
$$
DECLARE
    TABLE_RECORD RECORD;
    EVT_TABLE text;
    shift_interval INTERVAL := (number_days::TEXT || ' DAY')::INTERVAL;
BEGIN

    IF to_regclass('public.programstageinstance') IS NOT NULL THEN
        -- DHIS2 2.40 and earlier

        -- Update enrollment dates
        UPDATE programinstance
        SET enrollmentdate = enrollmentdate::TIMESTAMP + shift_interval,
            lastupdated = NOW();

        -- Update DATE-type TEA values for enrollments
        UPDATE trackedentityattributevalue teav
        SET value = DATE(value::TIMESTAMP + shift_interval)
        FROM trackedentityattribute tea
        WHERE tea.trackedentityattributeid = teav.trackedentityattributeid AND
        tea.valuetype = 'DATE';

        -- Update event dates
        UPDATE programstageinstance
        SET executiondate = executiondate::TIMESTAMP + shift_interval,
            duedate = duedate::TIMESTAMP + shift_interval,
            completeddate = completeddate::TIMESTAMP + shift_interval,
            lastupdated = NOW();

        -- Update DATE-type data element values inside events (JSON)
        FOR TABLE_RECORD IN
            select psi.programstageinstanceid,
               ('{'||js.key||',value}')::TEXT[] as path,
               ('"'||TEXT(DATE(to_timestamp(replace(js_value.value::TEXT, '"', ''), 'YYYY-MM-DD') + shift_interval))||'"')::jsonb as value
            from programstageinstance psi, jsonb_each(eventdatavalues::jsonb) as js, jsonb_each(js.value) as js_value
            where js.key IN (SELECT uid FROM dataelement WHERE valuetype = 'DATE') AND js_value.key = 'value'
        LOOP
            UPDATE programstageinstance psi
            SET eventdatavalues = jsonb_set(eventdatavalues, TABLE_RECORD.path, TABLE_RECORD.value)
            WHERE psi.programstageinstanceid = TABLE_RECORD.programstageinstanceid;
        END LOOP;

    ELSE
        -- DHIS2 2.41 and later

        -- Update enrollment dates
        UPDATE enrollment
        SET enrollmentdate = enrollmentdate::TIMESTAMP + shift_interval,
            lastupdated = NOW();

        -- Update DATE-type TEA values for enrollments
        UPDATE trackedentityattributevalue teav
        SET value = DATE(value::TIMESTAMP + shift_interval)
        FROM trackedentityattribute tea
        WHERE tea.trackedentityattributeid = teav.trackedentityattributeid AND
        tea.valuetype = 'DATE';

        -- Update event dates and DATE-type data element values inside events.
        -- 2.41/2.42 have a single "event" table; 2.43 split it into
        -- "trackerevent" and "singleevent" (the latter has no scheduleddate).
        FOREACH EVT_TABLE IN ARRAY ARRAY['event', 'trackerevent', 'singleevent']
        LOOP
            CONTINUE WHEN to_regclass('public.' || EVT_TABLE) IS NULL;

            EXECUTE format(
                'UPDATE %I SET occurreddate = occurreddate::TIMESTAMP + $1,
                               completeddate = completeddate::TIMESTAMP + $1,
                               lastupdated = NOW()', EVT_TABLE)
            USING shift_interval;

            IF EXISTS (SELECT 1 FROM information_schema.columns
                       WHERE table_schema = 'public' AND table_name = EVT_TABLE
                         AND column_name = 'scheduleddate') THEN
                EXECUTE format(
                    'UPDATE %I SET scheduleddate = scheduleddate::TIMESTAMP + $1', EVT_TABLE)
                USING shift_interval;
            END IF;

            FOR TABLE_RECORD IN EXECUTE format($q$
                SELECT ev.eventid,
                       ('{'||js.key||',value}')::TEXT[] as path,
                       ('"'||TEXT(DATE(to_timestamp(replace(js_value.value::TEXT, '"', ''), 'YYYY-MM-DD') + $1))||'"')::jsonb as value
                FROM %I ev, jsonb_each(ev.eventdatavalues::jsonb) as js, jsonb_each(js.value) as js_value
                WHERE js.key IN (SELECT uid FROM dataelement WHERE valuetype = 'DATE') AND js_value.key = 'value'
                $q$, EVT_TABLE)
            USING shift_interval
            LOOP
                EXECUTE format(
                    'UPDATE %I SET eventdatavalues = jsonb_set(eventdatavalues, $1, $2) WHERE eventid = $3', EVT_TABLE)
                USING TABLE_RECORD.path, TABLE_RECORD.value, TABLE_RECORD.eventid;
            END LOOP;
        END LOOP;

    END IF;

    RETURN TRUE;
END
$$;

-- Example: shift all tracker/event data one week forward
-- SELECT shift_tracker_dates(7);
