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
-- Works across the DHIS2 2.40 -> 2.41 tracker table renames
-- (programinstance -> enrollment, programstageinstance -> event) by detecting
-- which schema is present at runtime.
--
-- NOTE: run "Analytics Tables" export afterwards for the shift to be visible
-- in analytics. Use shift_dataset_periods.sql for aggregate data.

CREATE OR REPLACE FUNCTION shift_tracker_dates (number_days integer) RETURNS boolean
    LANGUAGE plpgsql
AS
$$
DECLARE
    TABLE_RECORD RECORD;
BEGIN

    IF to_regclass('public.programstageinstance') IS NOT NULL THEN
        -- DHIS2 2.40 and earlier

        -- Update enrollment dates
        UPDATE programinstance
        SET enrollmentdate = enrollmentdate::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL,
            lastupdated = NOW();

        -- Update DATE-type TEA values for enrollments
        UPDATE trackedentityattributevalue teav
        SET value = DATE(value::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL)
        FROM trackedentityattribute tea
        WHERE tea.trackedentityattributeid = teav.trackedentityattributeid AND
        tea.valuetype = 'DATE';

        -- Update event dates
        UPDATE programstageinstance
        SET executiondate = executiondate::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL,
            duedate = duedate::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL,
            completeddate = completeddate::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL,
            lastupdated = NOW();

        -- Update DATE-type data element values inside events (JSON)
        FOR TABLE_RECORD IN
            select psi.programstageinstanceid,
               ('{'||js.key||',value}')::TEXT[] as path,
               ('"'||TEXT(DATE(to_timestamp(replace(js_value.value::TEXT, '"', ''), 'YYYY-MM-DD') + (number_days::TEXT || ' DAY')::INTERVAL))||'"')::jsonb as value
            from programstageinstance psi, jsonb_each(eventdatavalues::jsonb) as js, jsonb_each(js.value) as js_value
            where js.key IN (SELECT uid FROM dataelement WHERE valuetype = 'DATE') AND js_value.key = 'value'
        LOOP
            UPDATE programstageinstance psi
            SET eventdatavalues = jsonb_set(eventdatavalues, TABLE_RECORD.path, TABLE_RECORD.value)
            WHERE psi.programstageinstanceid = TABLE_RECORD.programstageinstanceid;
        END LOOP;

    ELSE
        -- DHIS2 2.41 and later (tracker tables renamed)

        -- Update enrollment dates
        UPDATE enrollment
        SET enrollmentdate = enrollmentdate::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL,
            lastupdated = NOW();

        -- Update DATE-type TEA values for enrollments
        UPDATE trackedentityattributevalue teav
        SET value = DATE(value::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL)
        FROM trackedentityattribute tea
        WHERE tea.trackedentityattributeid = teav.trackedentityattributeid AND
        tea.valuetype = 'DATE';

        -- Update event dates
        UPDATE event
        SET occurreddate = occurreddate::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL,
            scheduleddate = scheduleddate::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL,
            completeddate = completeddate::TIMESTAMP + (number_days::TEXT || ' DAY')::INTERVAL,
            lastupdated = NOW();

        -- Update DATE-type data element values inside events (JSON)
        FOR TABLE_RECORD IN
            select ev.eventid,
               ('{'||js.key||',value}')::TEXT[] as path,
               ('"'||TEXT(DATE(to_timestamp(replace(js_value.value::TEXT, '"', ''), 'YYYY-MM-DD') + (number_days::TEXT || ' DAY')::INTERVAL))||'"')::jsonb as value
            from event ev, jsonb_each(eventdatavalues::jsonb) as js, jsonb_each(js.value) as js_value
            where js.key IN (SELECT uid FROM dataelement WHERE valuetype = 'DATE') AND js_value.key = 'value'
        LOOP
            UPDATE event ev
            SET eventdatavalues = jsonb_set(eventdatavalues, TABLE_RECORD.path, TABLE_RECORD.value)
            WHERE ev.eventid = TABLE_RECORD.eventid;
        END LOOP;

    END IF;

    RETURN TRUE;
END
$$;

-- Example: shift all tracker/event data one week forward
-- SELECT shift_tracker_dates(7);
