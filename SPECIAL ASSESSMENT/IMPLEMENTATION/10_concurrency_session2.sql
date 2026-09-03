-- =====================================================================
-- 10_concurrency_session2.sql
-- SESSION 2 -- run this in a SECOND mysql client window, alongside
-- 09_concurrency_session1.sql running in the first. Follow the STEP
-- numbers, alternating between the two files/terminals.
-- =====================================================================
USE nvces_db;

-- =====================================================================
-- DEMO 1: BOOKING RACE (continued from Session 1's STEP 1)
-- =====================================================================
-- --- STEP 2 (Session 2): try to lock the SAME slot row ----------------
-- Run this only AFTER Session 1 has executed its STEP 1 and is still
-- holding the transaction open (has not committed).
START TRANSACTION;

SELECT slot_id, capacity, booked_count
FROM exam_slots
WHERE slot_id = 2
FOR UPDATE;
-- WHAT SESSION 2 EXPERIENCES: this statement HANGS / BLOCKS. It does
-- not return a result and does not raise an error immediately. MySQL
-- is making Session 2 wait for Session 1's row-level exclusive lock to
-- be released. If Session 1 never commits/rolls back, Session 2 will
-- eventually fail with:
--   ERROR 1205 (HY000): Lock wait timeout exceeded; try restarting
--   transaction
-- (default innodb_lock_wait_timeout is 50 seconds).
--
-- Go back to Session 1 now and run its STEP 3 (INSERT/UPDATE/COMMIT).
-- As soon as Session 1 commits, this blocked SELECT in Session 2
-- returns immediately.

-- --- STEP 4 (Session 2): now that the SELECT returned, check capacity
-- --- correctly using the value Session 1 just committed ---------------
-- (booked_count now reflects Session 1's booking, so Session 2 correctly
-- sees fewer free seats than it would have if it had read stale data.)
-- If a seat is still free, proceed; otherwise ROLLBACK.
-- Example -- if slot 2's capacity is 3 and booked_count is now 3 (full):
ROLLBACK;   -- SLOT_FULL case: no seat left, so we roll back cleanly.

-- If instead a seat is still free, the pattern would be:
-- INSERT INTO bookings (slot_id, candidate_id, status) VALUES (2, 5, 'CONFIRMED');
-- UPDATE exam_slots SET booked_count = booked_count + 1 WHERE slot_id = 2;
-- COMMIT;

-- =====================================================================
-- DEMO 2: RESULT LOST-UPDATE PREVENTION (continued from Session 1's STEP 5)
-- =====================================================================
-- --- STEP 6 (Session 2): try to lock the same result row --------------
-- Run only AFTER Session 1 has executed STEP 5 and is holding its
-- transaction open.
START TRANSACTION;

SELECT result_id, attempt_id, final_score, version
INTO @s2_res_id, @s2_att_id, @s2_old_score, @s2_cur_ver
FROM results
WHERE attempt_id = 6
FOR UPDATE;
-- BLOCKS here, same as Demo 1 -- Session 2 must wait for Session 1's
-- COMMIT (its STEP 7) before this SELECT returns.

-- --- STEP 8 (Session 2): once unblocked, this session sees the ROW
-- --- Session 1 already updated (version = 1, final_score = 58.00,
-- --- not the stale version = 0 / 55.00 it would have seen without FOR UPDATE).
-- --- Its own update is correctly layered on top rather than overwriting Session 1's work.
SELECT @s2_res_id AS result_id, @s2_att_id AS attempt_id, @s2_old_score AS unblocked_score, @s2_cur_ver AS unblocked_version;

UPDATE results
   SET final_score = 60.00,
       status = 'PUBLISHED',
       version = @s2_cur_ver + 1,
       published_at = CURRENT_TIMESTAMP
 WHERE attempt_id = 6;

INSERT INTO result_update_history (result_id, examiner_id, old_score, new_score, version_no, updated_at)
VALUES (@s2_res_id, 4, @s2_old_score, 60.00, @s2_cur_ver + 1, CURRENT_TIMESTAMP);

COMMIT;

-- Now go back to Session 1 and run its STEP 9 to verify:
-- 1. results table shows final_score = 60.00 and version = 2.
-- 2. result_update_history preserves both examiner actions (55->58 and 58->60).
