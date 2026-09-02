-- =====================================================================
-- 11_savepoints.sql
-- PART D -- COMMIT / ROLLBACK / SAVEPOINT / ROLLBACK TO SAVEPOINT,
-- demonstrated with real booking/result operations (not toy examples).
-- =====================================================================
USE nvces_db;

-- ---------------------------------------------------------------------
-- 1. COMMIT -- a booking that should permanently succeed.
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO bookings (slot_id, candidate_id, status) VALUES (5, 9, 'CONFIRMED');
UPDATE exam_slots SET booked_count = booked_count + 1 WHERE slot_id = 5;
COMMIT;
-- Verify it persisted:
SELECT * FROM bookings WHERE slot_id = 5 AND candidate_id = 9;

-- ---------------------------------------------------------------------
-- 2. ROLLBACK -- an accidental double-booking attempt that we abandon
--    entirely before it ever reaches another session.
-- ---------------------------------------------------------------------
START TRANSACTION;
INSERT INTO bookings (slot_id, candidate_id, status) VALUES (5, 10, 'CONFIRMED');
UPDATE exam_slots SET booked_count = booked_count + 1 WHERE slot_id = 5;
-- On review, this booking was made in error (wrong candidate) --
-- discard the whole transaction:
ROLLBACK;
-- Verify it did NOT persist:
SELECT * FROM bookings WHERE slot_id = 5 AND candidate_id = 10;  -- expect 0 rows
SELECT booked_count FROM exam_slots WHERE slot_id = 5;            -- unchanged

-- ---------------------------------------------------------------------
-- 3 & 4. SAVEPOINT + ROLLBACK TO SAVEPOINT -- publish one result,
--    checkpoint, then attempt a second result update that turns out to
--    be wrong; undo ONLY the second change and keep the first.
-- ---------------------------------------------------------------------
START TRANSACTION;

-- First, legitimate change: publish attempt 7's result.
UPDATE results
   SET final_score = 88.00, status = 'PUBLISHED', version = version + 1,
       published_at = CURRENT_TIMESTAMP
 WHERE attempt_id = 7;

SAVEPOINT after_attempt7;

-- Second change: examiner mistakenly edits the WRONG attempt (1
-- instead of the intended one).
UPDATE results
   SET final_score = 0.00, status = 'PUBLISHED', version = version + 1
 WHERE attempt_id = 1;

-- Mistake noticed -- undo ONLY the second UPDATE, keeping the first:
ROLLBACK TO SAVEPOINT after_attempt7;

-- Finish the transaction now that the bad change is undone:
COMMIT;

-- Verify: attempt 7 is published with the correct score; attempt 1 is
-- untouched (still its original PENDING state from sample data).
SELECT attempt_id, final_score, status, version FROM results WHERE attempt_id IN (1, 7);
