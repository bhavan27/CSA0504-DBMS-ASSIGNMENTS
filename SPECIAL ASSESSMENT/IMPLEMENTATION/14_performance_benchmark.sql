-- =====================================================================
-- 14_performance_benchmark.sql
-- PART G -- Performance benchmark at a scale where index effects are
-- actually measurable. Generates several thousand extra rows so
-- EXPLAIN ANALYZE numbers become meaningful (the ~15-row sample
-- dataset is too small for the optimizer's choices to matter much).
--
-- WARNING: this adds bulk synthetic data to a COPY-WORTHY scale. Run
-- this against a scratch copy of the database, or be ready to reload
-- 01-02 afterward, if you want to keep the small sample data clean for
-- grading/demo purposes.
-- =====================================================================
USE nvces_db;

-- ---------------------------------------------------------------------
-- STEP 1: bulk-generate ~5,000 extra candidates using a recursive CTE
-- (MySQL 8.x supports WITH RECURSIVE).
-- ---------------------------------------------------------------------
INSERT INTO candidates (full_name, email, phone, dob)
SELECT
    CONCAT('Bulk Candidate ', n),
    CONCAT('bulk.candidate', n, '@example.com'),
    CONCAT('98', LPAD(n, 8, '0')),
    DATE_ADD('1995-01-01', INTERVAL (n MOD 3650) DAY)
FROM (
    WITH RECURSIVE seq(n) AS (
        SELECT 1
        UNION ALL
        SELECT n + 1 FROM seq WHERE n < 5000
    )
    SELECT n FROM seq
) numbers;

-- ---------------------------------------------------------------------
-- STEP 2: bulk-generate ~5,000 extra attempts spread across existing
-- exams/centers/slots/dates, referencing a real booking each time
-- (booking_id must stay unique -- we create one throwaway booking per
-- attempt against slot 5, which has spare declared capacity for the
-- purpose of this synthetic load only; capacity checks are bypassed
-- intentionally here because this is bulk test-data generation, not a
-- live booking flow).
-- ---------------------------------------------------------------------
INSERT INTO bookings (slot_id, candidate_id, status)
SELECT 5, candidate_id, 'CONFIRMED'
FROM candidates
WHERE full_name LIKE 'Bulk Candidate %';

INSERT INTO attempts (booking_id, candidate_id, exam_id, center_id, exam_date, slot_id, attempt_status)
SELECT
    b.booking_id,
    b.candidate_id,
    1 + (b.candidate_id MOD 4),                              -- spread across exam_id 1-4
    1 + (b.candidate_id MOD 3),                               -- spread across center_id 1-3
    DATE_ADD('2026-01-01', INTERVAL (b.candidate_id MOD 240) DAY),  -- spread across ~8 months
    5,
    'COMPLETED'
FROM bookings b
JOIN candidates c ON c.candidate_id = b.candidate_id
WHERE c.full_name LIKE 'Bulk Candidate %';

-- Sanity check on row count
SELECT COUNT(*) AS total_attempts FROM attempts;

-- ---------------------------------------------------------------------
-- STEP 3: BENCHMARK A -- query WITHOUT a useful index
-- Temporarily drop the date index to measure the "before" state at scale.
-- ---------------------------------------------------------------------
DROP INDEX idx_attempt_examdate ON attempts;

EXPLAIN ANALYZE
SELECT attempt_id FROM attempts
WHERE exam_date BETWEEN '2026-03-01' AND '2026-03-31';
-- RECORD FROM YOUR OWN OUTPUT (do not copy numbers from this comment):
--   - "actual time=" first and last values (start/total time in ms)
--   - "rows=" (estimated) vs "actual rows=" (real count examined)
--   - access type shown (e.g. "Table scan on attempts")

-- ---------------------------------------------------------------------
-- STEP 4: BENCHMARK B -- query WITH the index restored
-- ---------------------------------------------------------------------
CREATE INDEX idx_attempt_examdate ON attempts (exam_date);

EXPLAIN ANALYZE
SELECT attempt_id FROM attempts
WHERE exam_date BETWEEN '2026-03-01' AND '2026-03-31';
-- RECORD FROM YOUR OWN OUTPUT, same fields as Step 3, and compare.

-- ---------------------------------------------------------------------
-- STEP 5: BENCHMARK C -- unoptimized vs optimized RESULT query at scale
-- (mirrors Case Study 2 in 06_query_optimization.sql, now with enough
-- rows for the optimizer's choice to actually matter)
-- ---------------------------------------------------------------------
-- Give the bulk attempts matching results so the join has volume too.
INSERT INTO results (attempt_id, examiner_id, final_score, status, version)
SELECT attempt_id, 1 + (attempt_id MOD 4), 50.00, 'PENDING', 0
FROM attempts
WHERE candidate_id IN (SELECT candidate_id FROM candidates WHERE full_name LIKE 'Bulk Candidate %')
  AND attempt_id NOT IN (SELECT attempt_id FROM results);

DROP INDEX idx_result_status ON results;
EXPLAIN ANALYZE
SELECT COUNT(*) FROM results WHERE status = 'PENDING';
-- RECORD your own "before" timing here.

CREATE INDEX idx_result_status ON results (status);
EXPLAIN ANALYZE
SELECT COUNT(*) FROM results WHERE status = 'PENDING';
-- RECORD your own "after" timing here.

-- ---------------------------------------------------------------------
-- WHAT TO RECORD FOR YOUR REPORT (fields that matter from EXPLAIN /
-- EXPLAIN ANALYZE -- fill these in from YOUR terminal output, never
-- fabricate them):
--   1. Access type (ALL / range / ref / index)
--   2. key used (or NULL)
--   3. rows examined (estimated "rows" AND, for ANALYZE, "actual rows")
--   4. actual time range from EXPLAIN ANALYZE (first..last, in ms)
--   5. Whether "Using filesort" or "Using temporary" appears in Extra
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- CLEANUP: remove the bulk synthetic rows to restore the small,
-- easy-to-read sample dataset for demos/grading.
-- ---------------------------------------------------------------------
-- DELETE FROM results WHERE attempt_id IN (
--     SELECT attempt_id FROM attempts WHERE candidate_id IN (
--         SELECT candidate_id FROM candidates WHERE full_name LIKE 'Bulk Candidate %'));
-- DELETE FROM attempts WHERE candidate_id IN (
--     SELECT candidate_id FROM candidates WHERE full_name LIKE 'Bulk Candidate %');
-- DELETE FROM bookings WHERE candidate_id IN (
--     SELECT candidate_id FROM candidates WHERE full_name LIKE 'Bulk Candidate %');
-- DELETE FROM candidates WHERE full_name LIKE 'Bulk Candidate %';
-- UPDATE exam_slots SET booked_count = 0 WHERE slot_id = 5;
