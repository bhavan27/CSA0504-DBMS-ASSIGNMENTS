-- =====================================================================
-- 04_hashing.sql
-- Manual hashing demonstration (deliberately separate from InnoDB
-- B+ tree indexing -- see the comparison notes at the bottom).
--
-- IMPORTANT CONCEPTUAL NOTE:
-- "This is a relational implementation used to demonstrate textbook
-- hashing concepts; it is not a claim that the InnoDB secondary index
-- is a user-defined hash index."
--
-- Components demonstrated:
--   1. Hash Function: bucket_no = MOD(candidate_id, 10)
--   2. Bucket Calculation: e.g., MOD(1, 10) = 1, MOD(11, 10) = 1
--   3. Collision: Candidate 1 and Candidate 11 both hash to Bucket 1
--   4. Collision Resolution: Separate Chaining (chain_seq tracking)
--   5. Hash Lookup: Direct bucket probing + key matching in O(1) expected
-- =====================================================================
USE nvces_db;

-- ---------------------------------------------------------------------
-- HASH FUNCTION
--     bucket_no = MOD(candidate_id, 10)
-- 10 buckets (0-9). Simple modulo hashing over the primary key domain.
-- ---------------------------------------------------------------------

-- (Re)build the hash table from scratch for a clean demo.
TRUNCATE TABLE candidate_hash_index;

-- ---------------------------------------------------------------------
-- HASH INSERTION for candidates 1-10 (one row per attempt they own).
-- chain_seq records position within a bucket's collision chain; it is
-- illustrative bookkeeping only -- correctness of lookups never
-- depends on it, because every lookup filters on
-- (bucket_no AND candidate_id) together, not on chain_seq.
-- ---------------------------------------------------------------------
INSERT INTO candidate_hash_index (bucket_no, candidate_id, attempt_id, chain_seq)
SELECT MOD(c.candidate_id, 10), c.candidate_id, a.attempt_id, 0
FROM candidates c
JOIN attempts a ON a.candidate_id = c.candidate_id;

-- ---------------------------------------------------------------------
-- FORCE A COLLISION
-- Insert an 11th candidate. MOD(11,10) = 1, which collides with
-- candidate_id = 1 (MOD(1,10) = 1) in bucket 1.
-- ---------------------------------------------------------------------
INSERT INTO candidates (full_name, email, phone, dob) VALUES
('Kavya Narayan', 'kavya.narayan@example.com', '9840011121', '2001-02-10');
-- This candidate will get candidate_id = 11 on a fresh-loaded database.

-- Give candidate 11 a booking + attempt so there is real data to hash.
INSERT INTO bookings (slot_id, candidate_id, status) VALUES (2, 11, 'CONFIRMED');
SET @new_booking_id := LAST_INSERT_ID();

INSERT INTO attempts (booking_id, candidate_id, exam_id, center_id, exam_date, slot_id, attempt_status)
VALUES (@new_booking_id, 11, 1, 1, '2026-09-10', 2, 'COMPLETED');
SET @new_attempt_id := LAST_INSERT_ID();

UPDATE exam_slots SET booked_count = booked_count + 1 WHERE slot_id = 2;

-- Insert candidate 11 into the hash table -> bucket 1 (COLLISION with
-- candidate 1, which is already in bucket 1).
INSERT INTO candidate_hash_index (bucket_no, candidate_id, attempt_id, chain_seq)
VALUES (MOD(11, 10), 11, @new_attempt_id, 1);  -- chain_seq = 1 = second link in bucket 1's chain

-- ---------------------------------------------------------------------
-- SHOW THE COLLISION: bucket 1 now holds TWO different candidates.
-- This is exactly what a hash table with chaining looks like: the
-- bucket is a "chain" (linked list, here represented as a set of rows
-- sharing bucket_no) rather than a single slot.
-- ---------------------------------------------------------------------
SELECT bucket_no, candidate_id, attempt_id, chain_seq
FROM candidate_hash_index
WHERE bucket_no = 1
ORDER BY chain_seq;
-- Expect two rows: candidate_id = 1 (chain_seq 0) and candidate_id = 11
-- (chain_seq 1). Both hash to bucket 1 because MOD(1,10) = MOD(11,10) = 1.

-- ---------------------------------------------------------------------
-- COLLISION RESOLUTION STRATEGY: separate chaining.
-- Instead of overwriting the first row (open addressing, harder to
-- model relationally) we simply allow multiple rows per bucket_no and
-- always resolve a lookup by filtering on (bucket_no AND candidate_id)
-- together -- the chain is walked implicitly by the WHERE clause /
-- table scan restricted to that bucket.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- HASH LOOKUP for candidate_id = 11:
-- Step 1 (application/client side): compute bucket_no = MOD(11,10) = 1
-- Step 2: probe only that bucket, then match candidate_id within the
--         chain -- O(1) expected cost instead of scanning all buckets.
-- ---------------------------------------------------------------------
SELECT h.candidate_id, h.attempt_id, c.full_name
FROM candidate_hash_index h
JOIN candidates c ON c.candidate_id = h.candidate_id
WHERE h.bucket_no = MOD(11, 10)      -- probe bucket 1 only
  AND h.candidate_id = 11;           -- resolve the chain

-- Lookup for candidate_id = 1 (the other occupant of the same bucket) --
-- notice the WHERE clause is identical in shape, only the id changes:
SELECT h.candidate_id, h.attempt_id, c.full_name
FROM candidate_hash_index h
JOIN candidates c ON c.candidate_id = h.candidate_id
WHERE h.bucket_no = MOD(1, 10)
  AND h.candidate_id = 1;

-- ---------------------------------------------------------------------
-- B+ TREE INDEXING vs HASHING vs CLUSTERED ACCESS vs SECONDARY
-- INDEXING -- summary (for the README / report too):
--
-- 1. B+ TREE INDEX (e.g. idx_attempt_candidate on attempts):
--    - Ordered structure; supports equality AND range queries
--      (BETWEEN, <, >, ORDER BY, prefix LIKE).
--    - Cost O(log n) to locate, then sequential leaf traversal for
--      ranges.
--    - This is what InnoDB actually builds for every CREATE INDEX in
--      this project -- MySQL/InnoDB does NOT offer user-selectable
--      hash indexes on disk-based tables (only the internal, automatic
--      "adaptive hash index" inside the buffer pool, which the DBA
--      cannot create or drop by name).
--
-- 2. HASHING (candidate_hash_index, this file):
--    - Unordered; a hash function maps a key directly to a bucket.
--    - Expected O(1) lookup for exact-match equality only -- CANNOT
--      answer range queries or ORDER BY efficiently, because
--      neighbouring keys are scattered across unrelated buckets.
--    - Performance degrades toward O(n) within a bucket as collisions
--      accumulate (seen above: bucket 1 now has a 2-row chain).
--
-- 3. CLUSTERED ACCESS (attempts' own PRIMARY KEY):
--    - InnoDB stores every table's ROWS physically ordered by the
--      PRIMARY KEY -- the table itself IS the leaf level of the primary
--      key's B+ tree. There is no separate lookup step to reach the
--      full row once you have the primary key value.
--
-- 4. SECONDARY INDEXING (idx_attempt_candidate, idx_attempt_center_date_slot):
--    - A second, smaller B+ tree keyed on a non-primary column.
--    - Its leaf nodes store the indexed column value + the PRIMARY KEY
--      (not the whole row), so satisfying a query normally means one
--      lookup in the secondary index tree, THEN one lookup in the
--      clustered (primary) index tree to fetch remaining columns --
--      unless the secondary index alone covers every selected column
--      ("covering index"), in which case the second lookup is skipped.
-- ---------------------------------------------------------------------

-- Verify final hash table contents
SELECT * FROM candidate_hash_index ORDER BY bucket_no, chain_seq;
