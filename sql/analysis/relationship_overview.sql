-- relationship_overview.sql
--
-- Overview of tracker relationship types with their from/to constraints
-- resolved to names: which tracked entity type, program and program
-- stage each side of the relationship may connect. Useful when auditing
-- tracker configuration, since the Maintenance app shows constraints
-- one relationship type at a time.
--
--   psql -d dhis2 -f relationship_overview.sql

SELECT
  rt.uid AS type_uid,
  rt.name AS type_name,
  rt.bidirectional,
  from_rc.entity AS from_entity,
  from_tet.name AS from_trackedentitytype,
  from_pr.name AS from_program,
  from_ps.name AS from_programstage,
  to_rc.entity AS to_entity,
  to_tet.name AS to_trackedentitytype,
  to_pr.name AS to_program,
  to_ps.name AS to_programstage,
  (SELECT count(*) FROM relationship r
   WHERE r.relationshiptypeid = rt.relationshiptypeid) AS relationship_count
FROM relationshiptype rt
INNER JOIN relationshipconstraint from_rc
  ON rt.from_relationshipconstraintid = from_rc.relationshipconstraintid
LEFT JOIN trackedentitytype from_tet
  ON from_rc.trackedentitytypeid = from_tet.trackedentitytypeid
LEFT JOIN program from_pr ON from_rc.programid = from_pr.programid
LEFT JOIN programstage from_ps ON from_rc.programstageid = from_ps.programstageid
INNER JOIN relationshipconstraint to_rc
  ON rt.to_relationshipconstraintid = to_rc.relationshipconstraintid
LEFT JOIN trackedentitytype to_tet
  ON to_rc.trackedentitytypeid = to_tet.trackedentitytypeid
LEFT JOIN program to_pr ON to_rc.programid = to_pr.programid
LEFT JOIN programstage to_ps ON to_rc.programstageid = to_ps.programstageid
ORDER BY rt.name;
