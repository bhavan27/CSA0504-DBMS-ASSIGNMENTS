-- =====================================================================
-- 09_concurrency_session1.sql
-- SESSION 1 -- run this in ONE mysql client window/terminal.
-- Pair it with 10_concurrency_session2.sql running in a SECOND window
-- at the same time, against the SAME database (nvces_db).
--
-- HOW TO RUN (two terminals):
--   Terminal A: mysql -u root -p nvces_db   <-- run this file's blocks
--   Terminal B: mysql -u root -p nvces_db   <-- run session2 file's blocks
-- Execute the numbered STEPs below in the ORDER shown by the step
-- number, alternating between the two terminals as instructed.
-- =====================================================================
USE nvces_db;

-- =====================================================================
-- DEMO 1: BOOKING RACE on a slot with exactly ONE seat left
-- =====================================================================
-- Reset slot 2 to have exactly 1 free seat for a clean demo (capacity 3,
-- booked_count 2 already from sample data + earlier tests -- adjust the
-- number below to match your actual current state if you already ran
-- 07_booking_transaction.sql):
-- SELECT capacity, booked_count FROM exam_slots WHERE slot_id = 2;

-- --- STEP 1 (Session 1): start transaction and lock the slot row -----
START TRANSACTION;

SELECT slot_id, capacity, booked_count
FROM exam_slots
WHERE slot_id = 2
FOR UPDATE;
-- Lock acquired. Do NOT commit yet -- switch to Session 2 now and run
-- its STEP 2. Session 2 will BLOCK on its own FOR UPDATE until you
-- commit or roll back here.

-- --- STEP 3 (Session 1): after confirming Session 2 is blocked, ------
-- --- finish this transaction ------------------------------------------
INSERT INTO bookings (slot_id, candidate_id, status) VALUES (2, 4, 'CONFIRMED');
UPDATE exam_slots SET booked_count = booked_count + 1 WHERE slot_id = 2;
COMMIT;
-- Committing releases the lock. Session 2's blocked SELECT ... FOR
-- UPDATE will now return immediately with the UPDATED booked_count,
-- so its own capacity check correctly sees the seat is gone.

-- =====================================================================
-- DEMO 2: RESULT LOST-UPDATE PREVENTION on the same attempt
-- =====================================================================
-- Scenario: Attempt 6 initial score is 55.00 (version 0).
-- Examiner 1 (Session 1) evaluates and updates the score to 58.00.
-- Simultaneously, Examiner 2 (Session 2) tries to update the score to 60.00.

-- --- STEP 5 (Session 1): lock the result row for attempt 6 -----------
START TRANSACTION;

SELECT result_id, attempt_id, final_score, version
INTO @res_id, @att_id, @old_score, @cur_ver
FROM results
WHERE attempt_id = 6
FOR UPDATE;

SELECT @res_id AS result_id, @att_id AS attempt_id, @old_score AS old_score, @cur_ver AS current_version;
-- Lock held. Switch to Session 2 and run its STEP 6 -- it will block on its FOR UPDATE.

-- --- STEP 7 (Session 1): commit this examiner's change ---------------
UPDATE results
   SET final_score = 58.00,
       status = 'PUBLISHED',
       version = @cur_ver + 1,
       published_at = CURRENT_TIMESTAMP
 WHERE attempt_id = 6;

INSERT INTO result_update_history (result_id, examiner_id, old_score, new_score, version_no, updated_at)
VALUES (@res_id, 3, @old_score, 58.00, @cur_ver + 1, CURRENT_TIMESTAMP);

COMMIT;
-- Session 2 unblocks after this COMMIT and proceeds with its own update
-- on top of version = 1 (reading 58.00, not stale 55.00), preventing a lost update.

-- --- STEP 9 (Session 1, after Session 2 finishes): verify -------------
-- 1. Live results table shows the LAST committed score (60.00) and version = 2:
SELECT attempt_id, final_score, status, version FROM results WHERE attempt_id = 6;

-- 2. Audit history table preserves BOTH examiner decisions (55->58 and 58->60):
SELECT history_id, result_id, examiner_id, old_score, new_score, version_no, updated_at
FROM result_update_history
WHERE result_id = @res_id
ORDER BY version_no;
