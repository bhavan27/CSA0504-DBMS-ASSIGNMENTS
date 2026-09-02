-- =====================================================================
-- 03_indexes.sql
-- PART A -- Exam Attempt Archive: from sequential scan to
-- indexed-sequential access using InnoDB B+ tree indexes.
-- =====================================================================
USE nvces_db;

-- ---------------------------------------------------------------------
-- THE PROBLEM: a sequential archive
--
-- attempts is InnoDB, so it is already physically stored as a
-- clustered B+ tree ordered by the PRIMARY KEY (attempt_id). Without
-- a secondary index, "find all attempts for candidate_id = 5" forces
-- MySQL to walk every leaf page of that clustered index and test each
-- row -- a full table scan, i.e. exactly the "sequential archive"
-- problem described in classical file organization theory. Cost grows
-- linearly with table size (O(n)) no matter how selective the filter is.
--
-- Run this BEFORE adding indexes to see the scan:
-- ---------------------------------------------------------------------
EXPLAIN SELECT * FROM attempts WHERE candidate_id = 5;
-- Expect: type = ALL, key = NULL, rows ~= total row count in attempts.

-- ---------------------------------------------------------------------
-- THE FIX: indexed-sequential access via B+ tree secondary indexes.
-- A secondary index is itself a small B+ tree whose leaf nodes hold
-- (indexed_column, primary_key) pairs in sorted order. MySQL can binary
-- -search that tree in O(log n) and then follow the primary key back
-- into the clustered index ("index dive + lookup"). This is the
-- relational equivalent of an indexed-sequential file: the index gives
-- ordered, jump-to access instead of linear scanning.
-- ---------------------------------------------------------------------

-- =====================================================================
-- INDEX DEFINITIONS & WORKLOAD MAPPING
--
-- 1. Candidate attempt lookup:
--    Query: SELECT * FROM attempts WHERE candidate_id = ?
--    Index: idx_attempt_candidate ON attempts (candidate_id)
--    Selectivity: High. Returns attempts for one specific candidate.
-- ---------------------------------------------------------------------
CREATE INDEX idx_attempt_candidate ON attempts (candidate_id);

-- 2. Candidate attempt history (ordered):
--    Query: SELECT * FROM attempts WHERE candidate_id = ? ORDER BY exam_date
--    Index: idx_attempt_candidate_date ON attempts (candidate_id, exam_date)
--    Leftmost prefix: candidate_id filters rows; exam_date satisfies sorting
--    directly from B+ tree without an in-memory or on-disk filesort.
-- ---------------------------------------------------------------------
CREATE INDEX idx_attempt_candidate_date ON attempts (candidate_id, exam_date);

-- 3 & 4. Center/date audit & Center/date/slot retrieval:
--    Query 3: WHERE center_id = ? AND exam_date = ?
--    Query 4: WHERE center_id = ? AND exam_date = ? AND slot_id = ?
--    Index: idx_attempt_center_date_slot ON attempts (center_id, exam_date, slot_id)
--    Leftmost prefix rule:
--      - (center_id, exam_date) serves Query 3 (2-column prefix).
--      - (center_id, exam_date, slot_id) serves Query 4 (full 3-column index).
--    Column ordering: equality filters first (center_id, exam_date, slot_id).
-- ---------------------------------------------------------------------
CREATE INDEX idx_attempt_center_date_slot ON attempts (center_id, exam_date, slot_id);

-- 5. Candidate booking history & lookup:
--    Query: SELECT * FROM bookings WHERE candidate_id = ?
--    Index: idx_booking_candidate ON bookings (candidate_id)
--    Note: (slot_id, candidate_id) is also covered by uq_booking_slot_candidate.
-- ---------------------------------------------------------------------
CREATE INDEX idx_booking_candidate ON bookings (candidate_id);

-- 6. Supporting workload indexes:
CREATE INDEX idx_result_status ON results (status);              -- examiner dashboard ("PENDING" filter)
CREATE INDEX idx_slot_exam_center_date ON exam_slots (exam_id, center_id, exam_date); -- slot availability search

-- ---------------------------------------------------------------------
-- WHY INDEX ORDER MATTERS (leftmost-prefix rule)
--
-- idx_attempt_center_date_slot (center_id, exam_date, slot_id):
--   - center_id is placed first because every one of queries 3 and 4
--     filters on it with equality, and it is the coarsest, most
--     reliably-supplied filter (an audit is always "for a center").
--   - exam_date is second because it narrows the center's attempts to
--     a single day -- still an equality filter, and highly selective
--     once center_id is fixed.
--   - slot_id is last because it is only needed for query 4's finer
--     grain (center+date+slot); MySQL can still use the first two
--     columns alone for query 3, but CANNOT use exam_date or slot_id
--     alone without center_id (a left-to-right prefix is required).
--
-- idx_attempt_candidate_date (candidate_id, exam_date):
--   - candidate_id first (always the equality filter for "this
--     candidate's history"), exam_date second so the index is already
--     sorted for an ORDER BY exam_date on that candidate, avoiding a
--     separate filesort step.
-- ---------------------------------------------------------------------

-- Re-run the same query now that an index exists:
EXPLAIN SELECT * FROM attempts WHERE candidate_id = 5;
-- Expect: type = ref, key = idx_attempt_candidate, rows ~= 1 (candidate
-- 5's actual attempt count), Extra without "Using filesort".

-- ---------------------------------------------------------------------
-- QUERY 1: all attempts for a candidate
-- ---------------------------------------------------------------------
EXPLAIN SELECT attempt_id, exam_id, exam_date, attempt_status
FROM attempts
WHERE candidate_id = 1;

SELECT attempt_id, exam_id, exam_date, attempt_status
FROM attempts
WHERE candidate_id = 1;

-- ---------------------------------------------------------------------
-- QUERY 2: candidate's complete attempt history (ordered)
-- ---------------------------------------------------------------------
EXPLAIN SELECT a.attempt_id, e.exam_name, a.exam_date, s.total_score, s.grade
FROM attempts a
JOIN exams e  ON e.exam_id = a.exam_id
LEFT JOIN scores s ON s.attempt_id = a.attempt_id
WHERE a.candidate_id = 1
ORDER BY a.exam_date;

-- ---------------------------------------------------------------------
-- QUERY 3: all attempts at a center on a date
-- ---------------------------------------------------------------------
EXPLAIN SELECT attempt_id, candidate_id, exam_id, slot_id
FROM attempts
WHERE center_id = 1 AND exam_date = '2026-09-10';

-- ---------------------------------------------------------------------
-- QUERY 4: attempts by center + date + slot
-- ---------------------------------------------------------------------
EXPLAIN SELECT attempt_id, candidate_id, exam_id
FROM attempts
WHERE center_id = 1 AND exam_date = '2026-09-10' AND slot_id = 1;

-- ---------------------------------------------------------------------
-- Verify which indexes actually exist on attempts
-- ---------------------------------------------------------------------
SHOW INDEX FROM attempts;
