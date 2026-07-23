-- delete_data_out_of_range.sql
--
-- Deletes aggregate data values and tracker/event data whose dates are
-- outside a reasonable range. Such data typically comes from data entry
-- typos (year 216 or 20155) and breaks analytics table generation.
--
-- Requires delete_where_cascade.sql to have been run first.
--
-- Functions:
--   delete_periods_out_of_range(earliest, latest)
--     Deletes periods starting before <earliest> or ending after <latest>,
--     together with everything referencing them (data values, approvals,
--     complete registrations, audits...). Favorites referencing a deleted
--     period lose that period.
--
--   delete_events_out_of_range(earliest, latest)
--     Deletes events whose occurred date (or scheduled date, for events
--     that have no occurred date) is outside the range, together with
--     everything referencing them. Handles 2.40 (programstageinstance),
--     2.41/2.42 (event) and 2.43 (trackerevent + singleevent).
--
-- Both return the total number of rows deleted. Run in a transaction and
-- inspect the count before committing:
--
--   BEGIN;
--   SELECT delete_periods_out_of_range('1960-01-01', '2100-01-01');
--   SELECT delete_events_out_of_range('1960-01-01', '2100-01-01');
--   COMMIT;

CREATE OR REPLACE FUNCTION delete_periods_out_of_range(earliest date, latest date)
    RETURNS bigint
    LANGUAGE plpgsql
AS
$$
BEGIN
    RETURN delete_where_cascade('period',
        format('enddate < %L OR startdate > %L', earliest, latest));
END
$$;

CREATE OR REPLACE FUNCTION delete_events_out_of_range(earliest date, latest date)
    RETURNS bigint
    LANGUAGE plpgsql
AS
$$
DECLARE
    EVT_TABLE text;
    DATE_CONDITION text;
    TOTAL_DELETED bigint := 0;
BEGIN
    FOREACH EVT_TABLE IN ARRAY ARRAY['programstageinstance', 'event', 'trackerevent', 'singleevent']
    LOOP
        CONTINUE WHEN to_regclass('public.' || EVT_TABLE) IS NULL;

        -- 2.40 names the occurred date "executiondate" and the scheduled
        -- date "duedate"; 2.41+ uses occurreddate/scheduleddate (and 2.43's
        -- singleevent has no scheduled date at all).
        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = EVT_TABLE
                     AND column_name = 'executiondate') THEN
            DATE_CONDITION := format(
                'executiondate < %L OR executiondate > %L
                 OR (executiondate IS NULL AND (duedate < %L OR duedate > %L))',
                earliest, latest, earliest, latest);
        ELSIF EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = EVT_TABLE
                        AND column_name = 'scheduleddate') THEN
            DATE_CONDITION := format(
                'occurreddate < %L OR occurreddate > %L
                 OR (occurreddate IS NULL AND (scheduleddate < %L OR scheduleddate > %L))',
                earliest, latest, earliest, latest);
        ELSE
            DATE_CONDITION := format(
                'occurreddate < %L OR occurreddate > %L', earliest, latest);
        END IF;

        TOTAL_DELETED := TOTAL_DELETED
            + delete_where_cascade(EVT_TABLE::regclass, DATE_CONDITION);
    END LOOP;

    -- Relationships that pointed at a deleted event
    TOTAL_DELETED := TOTAL_DELETED + delete_orphan_relationships();

    RETURN TOTAL_DELETED;
END
$$;
