-- =====================================================================
-- 12_security.sql
-- PART H -- Security (OPTIONAL). Requires admin/CREATE USER privileges;
-- the rest of the project does NOT depend on this file running, so
-- skip it if your MySQL account cannot create users/grants.
-- =====================================================================
USE nvces_db;

-- ---------------------------------------------------------------------
-- ROLE RATIONALE
--
-- candidate  -- can only ever see/insert their OWN rows in a real app
--               (enforced at the application layer, since MySQL
--               privileges are table-wide, not row-wide). At the
--               database layer we give candidates SELECT-only access
--               to their own reference data and INSERT on bookings --
--               never UPDATE/DELETE on attempts, scores, or results
--               (those must be tamper-proof from the candidate side).
--
-- examiner   -- needs to INSERT/UPDATE results and read attempts/
--               scores/candidates for grading context. Should NOT be
--               able to touch bookings, exam_slots capacity, or
--               candidates' personal data (email/phone) beyond what
--               grading requires -- modelled here with SELECT/UPDATE
--               limited to the results-related tables.
--
-- auditor    -- read-only across the whole schema, for compliance and
--               reporting. No write privileges of any kind.
--
-- dba        -- full privileges; this is normally just your existing
--               root/admin account, so no separate user is created for
--               it here.
-- ---------------------------------------------------------------------

-- Candidate-facing application role (used by a web/app backend, not by
-- an actual human candidate logging into MySQL directly).
CREATE USER IF NOT EXISTS 'nvces_candidate'@'%' IDENTIFIED BY 'ChangeMe_Candidate#1';
GRANT SELECT ON nvces_db.exams            TO 'nvces_candidate'@'%';
GRANT SELECT ON nvces_db.exam_centers     TO 'nvces_candidate'@'%';
GRANT SELECT ON nvces_db.exam_slots       TO 'nvces_candidate'@'%';
GRANT SELECT, INSERT ON nvces_db.bookings TO 'nvces_candidate'@'%';
GRANT SELECT ON nvces_db.attempts         TO 'nvces_candidate'@'%';
GRANT SELECT ON nvces_db.scores           TO 'nvces_candidate'@'%';
GRANT SELECT ON nvces_db.results          TO 'nvces_candidate'@'%';

-- Examiner application role.
CREATE USER IF NOT EXISTS 'nvces_examiner'@'%' IDENTIFIED BY 'ChangeMe_Examiner#1';
GRANT SELECT ON nvces_db.attempts             TO 'nvces_examiner'@'%';
GRANT SELECT ON nvces_db.responses            TO 'nvces_examiner'@'%';
GRANT SELECT ON nvces_db.scores               TO 'nvces_examiner'@'%';
GRANT SELECT, UPDATE ON nvces_db.results      TO 'nvces_examiner'@'%';
GRANT SELECT ON nvces_db.candidates           TO 'nvces_examiner'@'%';
GRANT SELECT ON nvces_db.exams                TO 'nvces_examiner'@'%';

-- Auditor role: read-only, whole schema.
CREATE USER IF NOT EXISTS 'nvces_auditor'@'%' IDENTIFIED BY 'ChangeMe_Auditor#1';
GRANT SELECT ON nvces_db.* TO 'nvces_auditor'@'%';

FLUSH PRIVILEGES;

-- ---------------------------------------------------------------------
-- REVOKE example: an examiner account that should lose the ability to
-- update results (e.g. after certification review is closed).
-- ---------------------------------------------------------------------
REVOKE UPDATE ON nvces_db.results FROM 'nvces_examiner'@'%';

-- Verify current grants for a role:
SHOW GRANTS FOR 'nvces_examiner'@'%';
SHOW GRANTS FOR 'nvces_candidate'@'%';
SHOW GRANTS FOR 'nvces_auditor'@'%';

-- ---------------------------------------------------------------------
-- CLEANUP (uncomment to remove the demo users when you're done)
-- ---------------------------------------------------------------------
-- DROP USER IF EXISTS 'nvces_candidate'@'%';
-- DROP USER IF EXISTS 'nvces_examiner'@'%';
-- DROP USER IF EXISTS 'nvces_auditor'@'%';
