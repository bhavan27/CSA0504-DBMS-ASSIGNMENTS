-- =====================================================================
-- 02_sample_data.sql
-- Realistic, internally-consistent sample data.
-- Run AFTER 01_database_schema.sql.
-- =====================================================================
USE nvces_db;

-- ---------------------------------------------------------------------
-- candidates (10 candidates). IDs will be 1..10 on a fresh load.
-- ---------------------------------------------------------------------
INSERT INTO candidates (full_name, email, phone, dob) VALUES
('Arun Kumar',        'arun.kumar@example.com',     '9840011111', '2001-04-12'),
('Bhavani Shankar',   'bhavani.s@example.com',      '9840011112', '2000-11-02'),
('Chitra Devi',       'chitra.devi@example.com',    '9840011113', '2002-01-19'),
('Deepak Raj',        'deepak.raj@example.com',     '9840011114', '1999-07-25'),
('Elango Perumal',    'elango.p@example.com',       '9840011115', '2001-09-08'),
('Farida Begum',      'farida.b@example.com',       '9840011116', '2000-03-30'),
('Gokul Nathan',      'gokul.n@example.com',        '9840011117', '2002-05-14'),
('Harini Suresh',     'harini.s@example.com',       '9840011118', '2001-12-01'),
('Ibrahim Sait',      'ibrahim.sait@example.com',   '9840011119', '1998-06-17'),
('Janani Vel',        'janani.vel@example.com',     '9840011120', '2000-08-22');

-- ---------------------------------------------------------------------
-- exam_centers (3 centers)
-- ---------------------------------------------------------------------
INSERT INTO exam_centers (center_name, city, address, total_capacity) VALUES
('Chennai Central Skill Center',   'Chennai',   '12 Anna Salai, Chennai',        200),
('Coimbatore Vocational Hub',      'Coimbatore','45 Race Course Rd, Coimbatore', 150),
('Madurai Certification Center',   'Madurai',   '7 Alagar Kovil Rd, Madurai',    120);

-- ---------------------------------------------------------------------
-- exams (4 exams)
-- ---------------------------------------------------------------------
INSERT INTO exams (exam_code, exam_name, duration_minutes, max_score) VALUES
('ELE-101', 'Certified Electrician - Level 1',      120, 100),
('WLD-201', 'Certified Welder - Level 2',            150, 100),
('PLM-101', 'Certified Plumber - Level 1',            90, 100),
('CNC-301', 'CNC Machine Operator - Advanced',       180, 100);

-- ---------------------------------------------------------------------
-- examiners (4 examiners)
-- ---------------------------------------------------------------------
INSERT INTO examiners (full_name, email, role) VALUES
('Dr. Vinod AyyapPan',  'vinod.a@nvces.example.com',  'SENIOR_EXAMINER'),
('Priya Ramesh',        'priya.r@nvces.example.com',  'EXAMINER'),
('Suresh Babu',         'suresh.b@nvces.example.com', 'EXAMINER'),
('Meena Iyer',          'meena.i@nvces.example.com',  'EXAMINER');

-- ---------------------------------------------------------------------
-- exam_slots
-- Capacities kept SMALL on purpose (2-3) so booking-capacity tests
-- (Part K, TC06/TC07/TC08) are easy to exercise by hand.
-- ---------------------------------------------------------------------
INSERT INTO exam_slots (exam_id, center_id, exam_date, start_time, end_time, capacity, booked_count) VALUES
(1, 1, '2026-09-10', '09:00:00', '11:00:00', 3, 0),  -- slot_id 1: ELE-101 @ Chennai
(1, 1, '2026-09-10', '13:00:00', '15:00:00', 3, 0),  -- slot_id 2: ELE-101 @ Chennai, afternoon
(2, 1, '2026-09-11', '09:00:00', '11:30:00', 2, 0),  -- slot_id 3: WLD-201 @ Chennai
(3, 2, '2026-09-10', '09:00:00', '10:30:00', 2, 0),  -- slot_id 4: PLM-101 @ Coimbatore
(4, 3, '2026-09-12', '09:00:00', '12:00:00', 2, 0);  -- slot_id 5: CNC-301 @ Madurai

-- ---------------------------------------------------------------------
-- bookings (7 bookings across slots; slot 1 left with 1 free seat,
-- slot 3 and slot 4 deliberately filled to capacity for TC07 tests)
-- ---------------------------------------------------------------------
INSERT INTO bookings (slot_id, candidate_id, status) VALUES
(1, 1, 'CONFIRMED'),   -- booking_id 1
(1, 2, 'CONFIRMED'),   -- booking_id 2  (slot 1 now 2/3)
(2, 3, 'CONFIRMED'),   -- booking_id 3
(3, 4, 'CONFIRMED'),   -- booking_id 4
(3, 5, 'CONFIRMED'),   -- booking_id 5  (slot 3 now FULL 2/2)
(4, 6, 'CONFIRMED'),   -- booking_id 6
(4, 7, 'CONFIRMED');   -- booking_id 7  (slot 4 now FULL 2/2)

-- Keep booked_count in sync with the bookings above.
UPDATE exam_slots SET booked_count = 2 WHERE slot_id = 1;
UPDATE exam_slots SET booked_count = 1 WHERE slot_id = 2;
UPDATE exam_slots SET booked_count = 2 WHERE slot_id = 3;
UPDATE exam_slots SET booked_count = 2 WHERE slot_id = 4;
UPDATE exam_slots SET booked_count = 0 WHERE slot_id = 5;

-- ---------------------------------------------------------------------
-- attempts (one attempt per confirmed booking so far)
-- ---------------------------------------------------------------------
INSERT INTO attempts (booking_id, candidate_id, exam_id, center_id, exam_date, slot_id, attempt_status) VALUES
(1, 1, 1, 1, '2026-09-10', 1, 'COMPLETED'),  -- attempt_id 1
(2, 2, 1, 1, '2026-09-10', 1, 'COMPLETED'),  -- attempt_id 2
(3, 3, 1, 1, '2026-09-10', 2, 'COMPLETED'),  -- attempt_id 3
(4, 4, 2, 1, '2026-09-11', 3, 'COMPLETED'),  -- attempt_id 4
(5, 5, 2, 1, '2026-09-11', 3, 'ABSENT'),     -- attempt_id 5
(6, 6, 3, 2, '2026-09-10', 4, 'COMPLETED'),  -- attempt_id 6
(7, 7, 3, 2, '2026-09-10', 4, 'COMPLETED');  -- attempt_id 7

-- ---------------------------------------------------------------------
-- responses (a few questions per completed attempt)
-- ---------------------------------------------------------------------
INSERT INTO responses (attempt_id, question_no, selected_option, is_correct) VALUES
(1, 1, 'A', 1), (1, 2, 'C', 0), (1, 3, 'B', 1),
(2, 1, 'A', 1), (2, 2, 'B', 1), (2, 3, 'B', 1),
(3, 1, 'D', 0), (3, 2, 'C', 1),
(4, 1, 'A', 1), (4, 2, 'A', 1), (4, 3, 'C', 0),
(6, 1, 'B', 1), (6, 2, 'B', 0),
(7, 1, 'A', 1), (7, 2, 'A', 1);

-- ---------------------------------------------------------------------
-- timings (only for completed attempts; attempt 5 was ABSENT, skip)
-- ---------------------------------------------------------------------
INSERT INTO timings (attempt_id, start_time, end_time) VALUES
(1, '2026-09-10 09:00:00', '2026-09-10 10:55:00'),
(2, '2026-09-10 09:02:00', '2026-09-10 11:00:00'),
(3, '2026-09-10 13:00:00', '2026-09-10 14:40:00'),
(4, '2026-09-11 09:00:00', '2026-09-11 11:15:00'),
(6, '2026-09-10 09:00:00', '2026-09-10 10:20:00'),
(7, '2026-09-10 09:05:00', '2026-09-10 10:30:00');

-- ---------------------------------------------------------------------
-- scores (only for completed attempts)
-- ---------------------------------------------------------------------
INSERT INTO scores (attempt_id, total_score, max_score, grade) VALUES
(1, 66.00, 100.00, 'B'),
(2, 90.00, 100.00, 'A'),
(3, 50.00, 100.00, 'C'),
(4, 70.00, 100.00, 'B'),
(6, 55.00, 100.00, 'C'),
(7, 88.00, 100.00, 'A');

-- ---------------------------------------------------------------------
-- results (one PENDING row per completed attempt, assigned to an examiner)
-- ---------------------------------------------------------------------
INSERT INTO results (attempt_id, examiner_id, final_score, status, version) VALUES
(1, 2, 66.00, 'PENDING',   0),
(2, 2, 90.00, 'PUBLISHED', 1),
(3, 3, 50.00, 'PENDING',   0),
(4, 3, 70.00, 'PENDING',   0),
(6, 4, 55.00, 'PENDING',   0),
(7, 4, 88.00, 'PENDING',   0);

UPDATE results SET published_at = '2026-09-10 12:00:00' WHERE attempt_id = 2;

-- ---------------------------------------------------------------------
-- result_update_history (seed initial audit entry for published result)
-- ---------------------------------------------------------------------
INSERT INTO result_update_history (result_id, examiner_id, old_score, new_score, version_no, updated_at)
SELECT result_id, examiner_id, NULL, final_score, version, '2026-09-10 12:00:00'
FROM results
WHERE status = 'PUBLISHED';

-- ---------------------------------------------------------------------
-- candidate_hash_index -- populated properly in 04_hashing.sql, but we
-- seed it here too so PART A hash queries work immediately if you skip
-- straight to querying. bucket_no = MOD(candidate_id, 10).
-- Candidates 1..10 -> buckets 1,2,3,4,5,6,7,8,9,0 (10 mod 10 = 0)
-- Note: with only 10 candidates and 10 buckets there is no collision
-- yet -- 04_hashing.sql inserts an 11th candidate (id 11) to force one
-- (11 mod 10 = 1, colliding with candidate_id 1).
-- ---------------------------------------------------------------------
INSERT INTO candidate_hash_index (bucket_no, candidate_id, attempt_id, chain_seq)
SELECT MOD(c.candidate_id, 10), c.candidate_id, a.attempt_id, 0
FROM candidates c
JOIN attempts a ON a.candidate_id = c.candidate_id;

-- ---------------------------------------------------------------------
-- Sanity check
-- ---------------------------------------------------------------------
SELECT 'candidates' AS tbl, COUNT(*) AS rows_ FROM candidates
UNION ALL SELECT 'exam_centers', COUNT(*) FROM exam_centers
UNION ALL SELECT 'exams', COUNT(*) FROM exams
UNION ALL SELECT 'examiners', COUNT(*) FROM examiners
UNION ALL SELECT 'exam_slots', COUNT(*) FROM exam_slots
UNION ALL SELECT 'bookings', COUNT(*) FROM bookings
UNION ALL SELECT 'attempts', COUNT(*) FROM attempts
UNION ALL SELECT 'responses', COUNT(*) FROM responses
UNION ALL SELECT 'timings', COUNT(*) FROM timings
UNION ALL SELECT 'scores', COUNT(*) FROM scores
UNION ALL SELECT 'results', COUNT(*) FROM results
UNION ALL SELECT 'result_update_history', COUNT(*) FROM result_update_history
UNION ALL SELECT 'candidate_hash_index', COUNT(*) FROM candidate_hash_index;
