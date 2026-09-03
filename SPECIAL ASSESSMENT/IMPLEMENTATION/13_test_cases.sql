-- =====================================================================
-- 13_test_cases.sql
-- PART K -- Test cases TC01-TC15.
-- Run after 01-08 and 11 have been loaded (needs schema, data, indexes,
-- hashing, and the stored procedures). For TC08/TC10 (simultaneous
-- operations) you must additionally run the paired statements from
-- 09_concurrency_session1.sql / 10_concurrency_session2.sql in two
-- separate sessions -- they cannot be reproduced in a single script.
-- =====================================================================
USE nvces_db;

-- ---------------------------------------------------------------------
-- TC01: Candidate lookup
-- Purpose: verify a single candidate can be retrieved by primary key.
SELECT * FROM candidates WHERE candidate_id = 1;
-- Expected: exactly 1 row, candidate_id = 1 (Arun Kumar).
-- Observe: single-row result matching the sample data.

-- ---------------------------------------------------------------------
-- TC02: Candidate attempt history
-- Purpose: verify idx_attempt_candidate_date returns full, ordered
-- history for one candidate.
EXPLAIN SELECT attempt_id, exam_id, exam_date FROM attempts
WHERE candidate_id = 1 ORDER BY exam_date;
SELECT attempt_id, exam_id, exam_date FROM attempts
WHERE candidate_id = 1 ORDER BY exam_date;
-- Expected: EXPLAIN key = idx_attempt_candidate_date (or
-- idx_attempt_candidate); result rows sorted by exam_date ascending,
-- no filesort needed if the composite index is used.
-- Observe: attempt_id 1 (only attempt for candidate 1) returned.

-- ---------------------------------------------------------------------
-- TC03: Center/date audit
-- Purpose: verify composite index serves the center+date filter.
EXPLAIN SELECT * FROM attempts WHERE center_id = 1 AND exam_date = '2026-09-10';
SELECT * FROM attempts WHERE center_id = 1 AND exam_date = '2026-09-10';
-- Expected: EXPLAIN key = idx_attempt_center_date_slot.
-- Observe: 3 attempts returned (attempt_id 1, 2, 3).

-- ---------------------------------------------------------------------
-- TC04: Hash lookup
-- Purpose: verify a hash bucket lookup resolves to the correct
-- candidate via the chain.
SELECT h.candidate_id, c.full_name
FROM candidate_hash_index h
JOIN candidates c ON c.candidate_id = h.candidate_id
WHERE h.bucket_no = MOD(3, 10) AND h.candidate_id = 3;
-- Expected: 1 row, Chitra Devi (candidate_id 3).
-- Observe: bucket_no computed matches stored bucket_no; no ambiguity.

-- ---------------------------------------------------------------------
-- TC05: Hash collision
-- Purpose: confirm bucket 1 holds two distinct candidates (1 and 11)
-- and both are individually resolvable.
SELECT bucket_no, candidate_id FROM candidate_hash_index WHERE bucket_no = 1 ORDER BY chain_seq;
-- Expected: 2 rows -- candidate_id 1 and candidate_id 11.
-- Observe: MOD(1,10) = MOD(11,10) = 1 confirms the collision is real,
-- not a data error; chain_seq distinguishes their insertion order.

-- ---------------------------------------------------------------------
-- TC06: Successful booking
-- Purpose: booking into a slot with free capacity succeeds and
-- booked_count increments.
SELECT booked_count, capacity FROM exam_slots WHERE slot_id = 2;  -- note "before" value
CALL book_slot(2, 8, @tc06_result);
SELECT @tc06_result;                                              -- expect CONFIRMED
SELECT booked_count, capacity FROM exam_slots WHERE slot_id = 2;  -- incremented by 1

-- ---------------------------------------------------------------------
-- TC07: Full slot rejection
-- Purpose: booking into a FULL slot (slot 3, 2/2) is rejected and
-- state is unchanged.
SELECT booked_count, capacity FROM exam_slots WHERE slot_id = 3;  -- expect equal (full)
CALL book_slot(3, 8, @tc07_result);
SELECT @tc07_result;                                              -- expect SLOT_FULL
SELECT booked_count, capacity FROM exam_slots WHERE slot_id = 3;  -- unchanged
SELECT * FROM bookings WHERE slot_id = 3 AND candidate_id = 8;    -- expect 0 rows

-- ---------------------------------------------------------------------
-- TC08: Simultaneous booking (requires TWO sessions)
-- Purpose: two concurrent booking attempts on a slot with exactly one
-- free seat -- only ONE must succeed; the other must correctly observe
-- SLOT_FULL (never both CONFIRMED, never negative/over capacity).
-- Run: 09_concurrency_session1.sql DEMO 1 in Session A,
--      10_concurrency_session2.sql DEMO 1 in Session B, interleaved as
-- instructed by the STEP comments in those files.
-- Expected: exactly one booking row is inserted; booked_count never
-- exceeds capacity (enforced further by chk_slot_capacity CHECK).
-- Observe: the second session's FOR UPDATE visibly blocks/waits until
-- the first session commits -- record how long it waited.

-- ---------------------------------------------------------------------
-- TC09: Result update
-- Purpose: publish_result() correctly updates score/status/version.
CALL publish_result(4, 3, 72.00, @tc09_result);
SELECT @tc09_result;  -- expect PUBLISHED
SELECT attempt_id, final_score, status, version FROM results WHERE attempt_id = 4;
-- Expected: final_score = 72.00, status = PUBLISHED, version incremented by 1.

-- ---------------------------------------------------------------------
-- TC10: Concurrent result update (requires TWO sessions)
-- Purpose: two examiners updating the SAME result must not produce a
-- lost update. Concurrency control ensures serial execution; live table
-- reflects latest score and version = 2, while result_update_history
-- preserves both examiner decisions.
-- Run: 09_concurrency_session1.sql DEMO 2 in Session A,
--      10_concurrency_session2.sql DEMO 2 in Session B, interleaved as
-- instructed.
-- Verification Query 1 (Live Table):
SELECT attempt_id, final_score, status, version FROM results WHERE attempt_id = 6;
-- Expected: final_score = 60.00 (the last committed update), status = PUBLISHED,
-- version = 2 (incremented by 2 total). Stale-read anomaly was prevented.

-- Verification Query 2 (Audit History Table):
SELECT h.history_id, h.result_id, h.examiner_id, h.old_score, h.new_score, h.version_no, h.updated_at
FROM result_update_history h
JOIN results r ON r.result_id = h.result_id
WHERE r.attempt_id = 6
ORDER BY h.version_no;
-- Expected: Exactly 2 audit rows (Entry 1: 55.00 -> 58.00, Entry 2: 58.00 -> 60.00).
-- Observe: Both examiner decisions are preserved in history without data loss.

-- ---------------------------------------------------------------------
-- TC11: COMMIT
-- Purpose: a committed transaction's changes persist after COMMIT.
-- (See 11_savepoints.sql section 1 for the full transaction; here we
-- just verify persistence.)
SELECT * FROM bookings WHERE slot_id = 5 AND candidate_id = 9;
-- Expected: 1 row -- the COMMIT in 11_savepoints.sql section 1 persisted it.

-- ---------------------------------------------------------------------
-- TC12: ROLLBACK
-- Purpose: a rolled-back transaction leaves no trace.
SELECT * FROM bookings WHERE slot_id = 5 AND candidate_id = 10;
-- Expected: 0 rows -- the ROLLBACK in 11_savepoints.sql section 2
-- discarded this insert entirely.

-- ---------------------------------------------------------------------
-- TC13: SAVEPOINT / ROLLBACK TO SAVEPOINT
-- Purpose: a partial rollback undoes only the change made after the
-- savepoint, keeping the change made before it.
SELECT attempt_id, final_score, status FROM results WHERE attempt_id IN (1, 7);
-- Expected: attempt_id 7 shows the PUBLISHED update (kept); attempt_id
-- 1 shows its ORIGINAL pending values (the erroneous edit was undone).

-- ---------------------------------------------------------------------
-- TC14: Query optimization
-- Purpose: confirm the Case Study 1 query in 06_query_optimization.sql
-- switches from a full scan to a range scan after the index is added.
EXPLAIN SELECT attempt_id FROM attempts WHERE exam_date BETWEEN '2026-09-10' AND '2026-09-11';
-- Expected (after 06_query_optimization.sql has run): key =
-- idx_attempt_examdate, type = range.
-- Observe: compare this EXPLAIN's "key" column against the "before"
-- EXPLAIN captured earlier in 06_query_optimization.sql (key = NULL).

-- ---------------------------------------------------------------------
-- TC15: Index verification
-- Purpose: confirm every index required by Part A actually exists.
SHOW INDEX FROM attempts;
-- Expected indexes present: PRIMARY, idx_attempt_candidate,
-- idx_attempt_candidate_date, idx_attempt_center_date_slot,
-- idx_attempt_examdate.
-- Observe: Column_name / Seq_in_index values match the composite
-- column order documented in 03_indexes.sql.
