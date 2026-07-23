-- restore_admin_access.sql
--
-- Restores access for a locked-out superuser account, directly in the
-- database. Sets the password to "district", enables the account,
-- disables two-factor authentication, and ensures membership in a user
-- role with the ALL authority (creating no new roles: the first existing
-- ALL role is used).
--
-- DHIS2 caches user credentials, so RESTART DHIS2 (or Tomcat) after
-- running this — a previous failed login otherwise sticks until restart.
-- Change the password immediately after logging in.
--
-- Function: restore_admin_access(username)
--
--   SELECT restore_admin_access('admin');
--
-- Reference queries at the end of the file list superusers and roles.

CREATE OR REPLACE FUNCTION restore_admin_access(target_username text)
    RETURNS text
    LANGUAGE plpgsql
AS
$$
DECLARE
    -- bcrypt hash of "district"
    DISTRICT_HASH constant text := '$2a$10$wjLPViry3bkYEcjwGRqnYO1bT2Kl.ZY0kO.fwFDfMX53hitfx5.3C';
    USER_ID bigint;
    ALL_ROLE_ID bigint;
    NOTES text := '';
BEGIN
    SELECT userinfoid INTO USER_ID FROM userinfo WHERE username = target_username;
    IF USER_ID IS NULL THEN
        RAISE EXCEPTION 'No user with username %', target_username;
    END IF;

    UPDATE userinfo
    SET password = DISTRICT_HASH,
        disabled = FALSE,
        accountexpiry = NULL
    WHERE userinfoid = USER_ID;

    -- Disable 2FA; the column layout differs between versions
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'userinfo'
                 AND column_name = 'secret') THEN
        UPDATE userinfo SET secret = NULL WHERE userinfoid = USER_ID;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'userinfo'
                 AND column_name = 'twofactortype') THEN
        -- 2.42+: NOT NULL enum column; NOT_ENABLED means 2FA off
        EXECUTE 'UPDATE userinfo SET twofactortype = ''NOT_ENABLED'' WHERE userinfoid = $1' USING USER_ID;
    END IF;

    -- Ensure membership in a role with the ALL authority
    SELECT ur.userroleid INTO ALL_ROLE_ID
    FROM userrole ur
    JOIN userroleauthorities ura ON ur.userroleid = ura.userroleid
    WHERE ura.authority = 'ALL'
    ORDER BY ur.userroleid
    LIMIT 1;

    IF ALL_ROLE_ID IS NULL THEN
        NOTES := ' WARNING: no user role with ALL authority exists; role membership unchanged.';
    ELSIF NOT EXISTS (SELECT 1 FROM userrolemembers
                      WHERE userid = USER_ID AND userroleid = ALL_ROLE_ID) THEN
        INSERT INTO userrolemembers (userid, userroleid) VALUES (USER_ID, ALL_ROLE_ID);
        NOTES := ' Added to superuser role.';
    END IF;

    RETURN format('Password for %s set to "district", account enabled, 2FA off.%s Restart DHIS2 before logging in.',
        target_username, NOTES);
END
$$;

-- Reference: users with the ALL authority
--
-- SELECT u.userinfoid, u.username, u.firstname, u.surname, u.disabled
-- FROM userinfo u
-- WHERE u.userinfoid IN (
--   SELECT urm.userid FROM userrolemembers urm
--   JOIN userroleauthorities ura ON urm.userroleid = ura.userroleid
--   WHERE ura.authority = 'ALL');
--
-- Reference: user roles of a user
--
-- SELECT ur.userroleid, ur.uid, ur.name
-- FROM userrole ur
-- JOIN userrolemembers urm ON ur.userroleid = urm.userroleid
-- JOIN userinfo u ON urm.userid = u.userinfoid
-- WHERE u.username = 'admin';
