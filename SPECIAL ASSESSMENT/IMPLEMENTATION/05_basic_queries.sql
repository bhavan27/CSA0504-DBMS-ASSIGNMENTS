-- =====================================================================
-- 05_basic_queries.sql
-- PART E -- Query processing catalogue.
-- Run after 01-04. Every query here executes against the sample data.
-- =====================================================================
USE nvces_db;

-- 1-2-3. SELECT + WHERE + ORDER BY: candidates from a city, alphabetic
SELECT c.candidate_id, c.full_name, c.email
FROM candidates c
ORDER BY c.full_name;

-- 4-5. JOIN / INNER JOIN: attempt with candidate + exam names
SELECT a.attempt_id, c.full_name, e.exam_name, a.exam_date
FROM attempts a
INNER JOIN candidates c ON c.candidate_id = a.candidate_id
INNER JOIN exams e      ON e.exam_id = a.exam_id
ORDER BY a.exam_date, a.attempt_id;

-- 6. LEFT JOIN: every booking, with attempt info if one exists yet
-- (useful because a booking can exist before its exam day arrives,
-- i.e. before an attempt row is created)
SELECT b.booking_id, cand.full_name, b.status, a.attempt_id, a.attempt_status
FROM bookings b
JOIN candidates cand ON cand.candidate_id = b.candidate_id
LEFT JOIN attempts a ON a.booking_id = b.booking_id
ORDER BY b.booking_id;

-- 7-8-9. GROUP BY + HAVING + aggregate functions:
-- centers that have handled more than 2 attempts
SELECT ec.center_name, COUNT(*) AS attempt_count, AVG(s.total_score) AS avg_score
FROM attempts a
JOIN exam_centers ec ON ec.center_id = a.center_id
LEFT JOIN scores s   ON s.attempt_id = a.attempt_id
GROUP BY ec.center_id, ec.center_name
HAVING COUNT(*) > 2
ORDER BY attempt_count DESC;

-- 10. SUBQUERY: candidates who scored above the overall average
SELECT c.full_name, s.total_score
FROM candidates c
JOIN attempts a ON a.candidate_id = c.candidate_id
JOIN scores s   ON s.attempt_id = a.attempt_id
WHERE s.total_score > (SELECT AVG(total_score) FROM scores)
ORDER BY s.total_score DESC;

-- 11. DATE FILTERING: all activity on a specific exam day
SELECT a.attempt_id, c.full_name, e.exam_name, a.exam_date
FROM attempts a
JOIN candidates c ON c.candidate_id = a.candidate_id
JOIN exams e      ON e.exam_id = a.exam_id
WHERE a.exam_date = '2026-09-10';

-- 12. CANDIDATE HISTORY: one candidate's full record with results
SELECT a.attempt_id, e.exam_name, a.exam_date, s.total_score, s.grade,
       r.status AS result_status
FROM attempts a
JOIN exams e         ON e.exam_id = a.exam_id
LEFT JOIN scores s   ON s.attempt_id = a.attempt_id
LEFT JOIN results r  ON r.attempt_id = a.attempt_id
WHERE a.candidate_id = 1
ORDER BY a.exam_date;

-- 13. CENTER AUDIT: attempts + pass/fail breakdown per center on a date
SELECT ec.center_name, a.exam_date,
       COUNT(*) AS total_attempts,
       SUM(CASE WHEN s.total_score >= 50 THEN 1 ELSE 0 END) AS passed,
       SUM(CASE WHEN s.total_score < 50  THEN 1 ELSE 0 END) AS failed
FROM attempts a
JOIN exam_centers ec ON ec.center_id = a.center_id
LEFT JOIN scores s   ON s.attempt_id = a.attempt_id
WHERE ec.center_id = 1 AND a.exam_date = '2026-09-10'
GROUP BY ec.center_name, a.exam_date;

-- 14. RESULT REPORT: published results with examiner names
SELECT c.full_name, e.exam_name, r.final_score, r.status,
       ex.full_name AS examiner_name, r.published_at
FROM results r
JOIN attempts a   ON a.attempt_id = r.attempt_id
JOIN candidates c ON c.candidate_id = a.candidate_id
JOIN exams e      ON e.exam_id = a.exam_id
JOIN examiners ex ON ex.examiner_id = r.examiner_id
WHERE r.status = 'PUBLISHED'
ORDER BY r.published_at;
