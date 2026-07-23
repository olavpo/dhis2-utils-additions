-- delete_orgunit_tree.sql
--
-- Deletes an organisation unit and its whole subtree, INCLUDING all data
-- registered for those organisation units: data values, complete
-- registrations, approvals, tracked entities, enrollments, events, and
-- all group/user/dataset memberships. Objects that merely point at a
-- deleted organisation unit through an optional reference (e.g.
-- interpretations) keep existing with that reference set to NULL.
--
-- This is for pruning copied databases (e.g. cutting a training database
-- down to one region). The API refuses to delete organisation units with
-- data; this does it at the database level.
--
-- Requires delete_where_cascade.sql to have been run first.
--
-- Function: delete_orgunit_tree(orgunit_uid)
--   orgunit_uid   UID of the root of the subtree to delete
--   returns       Total number of rows deleted (all tables combined)
--
-- Run in a transaction and sanity-check the count before committing:
--
--   BEGIN;
--   SELECT delete_orgunit_tree('O6uvpzGd5pu');  -- Bo district
--   COMMIT;
--
-- Afterwards:
--   * restart DHIS2 (organisation units are cached)
--   * run Analytics Tables export
--   * users whose only data-capture org units were deleted must be
--     reassigned in the Users app

CREATE OR REPLACE FUNCTION delete_orgunit_tree(orgunit_uid text)
    RETURNS bigint
    LANGUAGE plpgsql
AS
$$
DECLARE
    SUBTREE_CONDITION text;
    TOTAL_DELETED bigint;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM organisationunit WHERE uid = orgunit_uid) THEN
        RAISE EXCEPTION 'No organisation unit with uid %', orgunit_uid;
    END IF;

    -- All organisation units in the subtree, root included. The "path"
    -- column (present on all supported versions) contains the UIDs of all
    -- ancestors, so descendants are the rows whose path contains the uid.
    SUBTREE_CONDITION := format(
        'organisationunitid IN (
            SELECT organisationunitid FROM organisationunit
            WHERE path LIKE %L OR uid = %L)',
        '%/' || orgunit_uid || '/%', orgunit_uid);

    TOTAL_DELETED := delete_where_cascade('organisationunit', SUBTREE_CONDITION);

    -- Relationships that pointed at deleted tracked entities/enrollments/events
    RETURN TOTAL_DELETED + delete_orphan_relationships();
END
$$;
