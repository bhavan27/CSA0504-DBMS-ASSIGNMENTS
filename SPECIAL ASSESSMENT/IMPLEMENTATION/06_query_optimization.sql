-- =====================================================================
-- 06_query_optimization.sql
-- PART F -- Query optimization case studies.
--
-- IMPORTANT: this file prints EXPLAIN output for you to read yourself.
-- No execution-time numbers are hard-coded anywhere in this project --
-- MySQL's actual timings depend on your machine, so you must run the
-- commands below and record what YOUR server reports. Anywhere a
-- number would normally appear in a lab report, write "see attached
-- EXPLAIN ANALYZE output" and paste your own console output/screenshot.
-- =====================================================================
USE nvces_db;

-- =====================================================================
-- CASE STUDY 1: date-range reporting query
-- =====================================================================

-- --- A. ORIGINAL / UNOPTIMIZED QUERY --------------------------------
-- "All attempts between two dates, across all centers" -- a common
-- report query. At this point in the script NO index starts with
-- exam_date alone (idx_attempt_candidate_date and
-- idx_attempt_center_date_slot both have exam_date in the SECOND
-- position, so neither can be used for a query that filters on
-- exam_date without also filtering on candidate_id or center_id).
EXPLAIN ANALYZE
SELECT attempt_id, candidate_id, center_id, exam_date
FROM attempts
WHERE exam_date BETWEEN '2026-09-10' AND '2026-09-11';

-- --- B. EXPLAIN OUTPUT INTERPRETATION --------------------------------
-- Run the EXPLAIN ANALYZE above yourself and look for:
--   * type: expect ALL (full table scan) because no usable index
--     has exam_date as its leading column.
--   * key: expect NULL.
--   * rows / "actual rows": MySQL scans every row in attempts.
--   * "Using where": confirms it filtered after the full scan rather
--     than during an index seek.

-- --- C. PROBLEM IDENTIFIED -------------------------------------------
-- No index leads with exam_date, so MySQL cannot binary-search a B+
-- tree for the date range and must inspect every row: an O(n) scan
-- that will not scale as the attempts table grows (see Part G for a
-- larger dataset to make this visible).

-- --- D. INDEX / QUERY REWRITE ----------------------------------------
CREATE INDEX idx_attempt_examdate ON attempts (exam_date);
-- Justification: exam_date is now a leading column in its own index,
-- so a range predicate on it alone becomes a B+ tree range scan
-- instead of a full scan. We keep the earlier composite indexes too --
-- they serve different query shapes (candidate-first, center-first).

-- --- E. OPTIMIZED QUERY -----------------------------------------------
-- Same query, now able to use idx_attempt_examdate:
EXPLAIN ANALYZE
SELECT attempt_id, candidate_id, center_id, exam_date
FROM attempts
WHERE exam_date BETWEEN '2026-09-10' AND '2026-09-11';

-- --- F. EXPLAIN / EXPLAIN ANALYZE INTERPRETATION (after) -------------
-- Re-run and check:
--   * type: expect range.
--   * key: expect idx_attempt_examdate.
--   * rows / "actual rows": should now be close to the TRUE number of
--     rows in that date range, not the whole table.
--   * The "actual time" figures in EXPLAIN ANALYZE are what you should
--     paste into your report -- do not copy the numbers from this file
--     because there are none; generate your own.

-- --- G. WHY THE OPTIMIZED QUERY IS BETTER -----------------------------
-- The access path moved from a full clustered-index scan (cost grows
-- with total table size) to a B+ tree range seek on
-- idx_attempt_examdate (cost grows with the SIZE OF THE RESULT, i.e.
-- how many rows actually fall in the date range) -- this is the core
-- benefit of indexed-sequential access over a raw sequential archive.

-- =====================================================================
-- CASE STUDY 2: pending-results workload for examiners
-- =====================================================================

-- --- A. ORIGINAL / UNOPTIMIZED QUERY ----------------------------------
-- Drop the status index temporarily to show the "before" state.
DROP INDEX idx_result_status ON results;

EXPLAIN ANALYZE
SELECT r.result_id, c.full_name, e.exam_name, r.final_score
FROM results r
JOIN attempts a   ON a.attempt_id = r.attempt_id
JOIN candidates c ON c.candidate_id = a.candidate_id
JOIN exams e      ON e.exam_id = a.exam_id
WHERE r.status = 'PENDING'
ORDER BY r.result_id;

-- --- B. INTERPRETATION -------------------------------------------------
-- Expect type = ALL on results (key = NULL) because status has no
-- index; MySQL must read every results row to test the equality filter
-- before it can even start the joins.

-- --- C. PROBLEM IDENTIFIED ----------------------------------------------
-- status is a low-cardinality column (only 'PENDING'/'PUBLISHED') being
-- filtered on a table that will be scanned by every examiner's
-- dashboard repeatedly -- a full scan here is wasted, repeated work.

-- --- D. INDEX / QUERY REWRITE --------------------------------------------
CREATE INDEX idx_result_status ON results (status);
-- Re-created exactly as it was defined in 03_indexes.sql.

-- --- E. OPTIMIZED QUERY ---------------------------------------------------
EXPLAIN ANALYZE
SELECT r.result_id, c.full_name, e.exam_name, r.final_score
FROM results r
JOIN attempts a   ON a.attempt_id = r.attempt_id
JOIN candidates c ON c.candidate_id = a.candidate_id
JOIN exams e      ON e.exam_id = a.exam_id
WHERE r.status = 'PENDING'
ORDER BY r.result_id;

-- --- F. INTERPRETATION (after) --------------------------------------------
-- Expect type = ref, key = idx_result_status on the results access,
-- with rows narrowed to only PENDING rows before the joins run.
-- NOTE: on a very small sample table (a handful of rows, as here), the
-- optimizer MAY still choose a full scan because it estimates a scan
-- is cheaper than an index lookup at this tiny scale -- that is a
-- correct, expected optimizer decision, not a bug. This is exactly why
-- Part G asks you to regenerate this comparison against a
-- several-thousand-row table, where the benefit becomes measurable.

-- --- G. WHY THE OPTIMIZED QUERY IS BETTER ----------------------------------
-- With low selectivity but a large table, an index on status lets
-- MySQL skip PUBLISHED rows entirely rather than reading and discarding
-- them one by one -- benefit scales with table size, not with this
-- small sample.
