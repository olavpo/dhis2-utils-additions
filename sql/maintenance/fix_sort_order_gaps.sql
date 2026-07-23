-- fix_sort_order_gaps.sql
--
-- Repairs gaps and duplicates in sort_order columns, which cause
-- "sort_order should be unique" / constraint errors when saving options
-- or favorites through the API. A corrupted sequence like [2,5,7] is
-- rewritten to a clean sequence with the existing order preserved.
--
-- Defines one generic function and convenience wrappers for the tables
-- where this problem commonly occurs:
--
--   fix_sort_order_gaps(table, group_column, id_column, first_value)
--       generic repair for any (group, sort_order) table
--   fix_option_sort_order()                         -- optionvalue (starts at 1)
--   fix_visualization_orgunit_sort_order()          -- visualization_organisationunits (starts at 0)
--   fix_visualization_datadimension_sort_order()    -- visualization_datadimensionitems (starts at 0)
--
-- Usage:
--   psql -d dhis2 -f fix_sort_order_gaps.sql   -- defines the functions
--   SELECT fix_option_sort_order();
--
-- Restart DHIS2 afterwards so cached objects pick up the changes.

CREATE OR REPLACE FUNCTION fix_sort_order_gaps(
    target regclass, group_column text, id_column text, first_value integer)
    RETURNS text
    LANGUAGE plpgsql
AS
$$
DECLARE
    ROWS_AFFECTED bigint;
BEGIN
    -- Two-phase update: sort_order is part of the primary key on some of
    -- these tables (e.g. visualization_organisationunits), so assigning
    -- final values directly can collide with a not-yet-updated row.
    -- Rows that need to change are first parked on unique negative
    -- values, then flipped to their final value.
    EXECUTE format($q$
        UPDATE %1$s t
        SET sort_order = -(ranked.new_sort_order) - 1
        FROM (
            SELECT %2$I AS group_id, %3$I AS row_id,
                   ROW_NUMBER() OVER (PARTITION BY %2$I ORDER BY sort_order)
                       - 1 + %4$s AS new_sort_order
            FROM %1$s
        ) ranked
        WHERE t.%2$I = ranked.group_id
          AND t.%3$I = ranked.row_id
          AND (t.sort_order <> ranked.new_sort_order OR t.sort_order IS NULL)
        $q$, target, group_column, id_column, first_value);

    GET DIAGNOSTICS ROWS_AFFECTED = ROW_COUNT;

    EXECUTE format('UPDATE %s SET sort_order = -(sort_order) - 1 WHERE sort_order < 0', target);

    RETURN format('Updated %s rows in %s', ROWS_AFFECTED, target);
END
$$;

CREATE OR REPLACE FUNCTION fix_option_sort_order()
    RETURNS text LANGUAGE sql AS
$$ SELECT fix_sort_order_gaps('optionvalue', 'optionsetid', 'optionvalueid', 1) $$;

CREATE OR REPLACE FUNCTION fix_visualization_orgunit_sort_order()
    RETURNS text LANGUAGE sql AS
$$ SELECT fix_sort_order_gaps('visualization_organisationunits', 'visualizationid', 'organisationunitid', 0) $$;

CREATE OR REPLACE FUNCTION fix_visualization_datadimension_sort_order()
    RETURNS text LANGUAGE sql AS
$$ SELECT fix_sort_order_gaps('visualization_datadimensionitems', 'visualizationid', 'datadimensionitemid', 0) $$;
