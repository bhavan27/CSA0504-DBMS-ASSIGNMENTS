-- =====================================================================
-- 01_database_schema.sql
-- National Vocational Certification and Exam Slot-Booking System
-- MySQL 8.x
--
-- Creates the database and all base tables in dependency-safe order:
-- parents before children (referenced tables before referencing FKs).
-- =====================================================================

DROP DATABASE IF EXISTS nvces_db;
CREATE DATABASE nvces_db CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE nvces_db;

-- ---------------------------------------------------------------------
-- 1. candidates  (no FK dependencies)
-- ---------------------------------------------------------------------
CREATE TABLE candidates (
    candidate_id    INT AUTO_INCREMENT PRIMARY KEY,
    full_name       VARCHAR(100) NOT NULL,
    email           VARCHAR(120) NOT NULL UNIQUE,
    phone           VARCHAR(15)  NOT NULL,
    dob             DATE         NOT NULL,
    created_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 2. exam_centers  (no FK dependencies)
-- ---------------------------------------------------------------------
CREATE TABLE exam_centers (
    center_id       INT AUTO_INCREMENT PRIMARY KEY,
    center_name     VARCHAR(120) NOT NULL,
    city            VARCHAR(60)  NOT NULL,
    address         VARCHAR(200) NOT NULL,
    total_capacity  INT NOT NULL CHECK (total_capacity > 0)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 3. exams  (no FK dependencies)
-- ---------------------------------------------------------------------
CREATE TABLE exams (
    exam_id           INT AUTO_INCREMENT PRIMARY KEY,
    exam_code         VARCHAR(20) NOT NULL UNIQUE,
    exam_name         VARCHAR(150) NOT NULL,
    duration_minutes  INT NOT NULL CHECK (duration_minutes > 0),
    max_score         INT NOT NULL DEFAULT 100 CHECK (max_score > 0)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 4. examiners  (no FK dependencies)
-- ---------------------------------------------------------------------
CREATE TABLE examiners (
    examiner_id   INT AUTO_INCREMENT PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    email         VARCHAR(120) NOT NULL UNIQUE,
    role          ENUM('EXAMINER','SENIOR_EXAMINER') NOT NULL DEFAULT 'EXAMINER'
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 5. exam_slots  (depends on exams, exam_centers)
--    Fixed-capacity slot; booked_count tracks live occupancy.
-- ---------------------------------------------------------------------
CREATE TABLE exam_slots (
    slot_id         INT AUTO_INCREMENT PRIMARY KEY,
    exam_id         INT NOT NULL,
    center_id       INT NOT NULL,
    exam_date       DATE NOT NULL,
    start_time      TIME NOT NULL,
    end_time        TIME NOT NULL,
    capacity        INT NOT NULL CHECK (capacity > 0),
    booked_count    INT NOT NULL DEFAULT 0,
    CONSTRAINT fk_slot_exam
        FOREIGN KEY (exam_id) REFERENCES exams(exam_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_slot_center
        FOREIGN KEY (center_id) REFERENCES exam_centers(center_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT chk_slot_capacity CHECK (booked_count <= capacity),
    CONSTRAINT chk_slot_time CHECK (end_time > start_time),
    -- A center cannot run two identical slots (same exam/date/start_time) twice
    CONSTRAINT uq_slot_unique UNIQUE (exam_id, center_id, exam_date, start_time)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 6. bookings  (depends on exam_slots, candidates)
--    UNIQUE(slot_id, candidate_id) is the integrity backstop that
--    prevents the SAME candidate from double-booking the SAME slot,
--    even if application logic is bypassed.
-- ---------------------------------------------------------------------
CREATE TABLE bookings (
    booking_id      INT AUTO_INCREMENT PRIMARY KEY,
    slot_id         INT NOT NULL,
    candidate_id    INT NOT NULL,
    booking_time    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status          ENUM('CONFIRMED','CANCELLED') NOT NULL DEFAULT 'CONFIRMED',
    CONSTRAINT fk_booking_slot
        FOREIGN KEY (slot_id) REFERENCES exam_slots(slot_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_booking_candidate
        FOREIGN KEY (candidate_id) REFERENCES candidates(candidate_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_booking_slot_candidate UNIQUE (slot_id, candidate_id)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 7. attempts  (depends on bookings, candidates, exams, exam_centers)
--    This is the "exam attempt archive" record.
-- ---------------------------------------------------------------------
CREATE TABLE attempts (
    attempt_id      INT AUTO_INCREMENT PRIMARY KEY,
    booking_id      INT NOT NULL UNIQUE,
    candidate_id    INT NOT NULL,
    exam_id         INT NOT NULL,
    center_id       INT NOT NULL,
    exam_date       DATE NOT NULL,
    slot_id         INT NOT NULL,
    attempt_status  ENUM('IN_PROGRESS','COMPLETED','ABSENT') NOT NULL DEFAULT 'COMPLETED',
    CONSTRAINT fk_attempt_booking
        FOREIGN KEY (booking_id) REFERENCES bookings(booking_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_attempt_candidate
        FOREIGN KEY (candidate_id) REFERENCES candidates(candidate_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_attempt_exam
        FOREIGN KEY (exam_id) REFERENCES exams(exam_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_attempt_center
        FOREIGN KEY (center_id) REFERENCES exam_centers(center_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_attempt_slot
        FOREIGN KEY (slot_id) REFERENCES exam_slots(slot_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 8. responses  (depends on attempts)
-- ---------------------------------------------------------------------
CREATE TABLE responses (
    response_id     INT AUTO_INCREMENT PRIMARY KEY,
    attempt_id      INT NOT NULL,
    question_no     INT NOT NULL,
    selected_option CHAR(1) NOT NULL,
    is_correct      TINYINT(1) NOT NULL,
    CONSTRAINT fk_response_attempt
        FOREIGN KEY (attempt_id) REFERENCES attempts(attempt_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT uq_response_attempt_question UNIQUE (attempt_id, question_no)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 9. timings  (depends on attempts) -- 1:1 with attempts
-- ---------------------------------------------------------------------
CREATE TABLE timings (
    timing_id       INT AUTO_INCREMENT PRIMARY KEY,
    attempt_id      INT NOT NULL UNIQUE,
    start_time      DATETIME NOT NULL,
    end_time        DATETIME NOT NULL,
    duration_seconds INT GENERATED ALWAYS AS (TIMESTAMPDIFF(SECOND, start_time, end_time)) STORED,
    CONSTRAINT fk_timing_attempt
        FOREIGN KEY (attempt_id) REFERENCES attempts(attempt_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT chk_timing_order CHECK (end_time > start_time)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 10. scores  (depends on attempts) -- 1:1 with attempts
-- ---------------------------------------------------------------------
CREATE TABLE scores (
    score_id        INT AUTO_INCREMENT PRIMARY KEY,
    attempt_id      INT NOT NULL UNIQUE,
    total_score     DECIMAL(6,2) NOT NULL CHECK (total_score >= 0),
    max_score       DECIMAL(6,2) NOT NULL CHECK (max_score > 0),
    percentage      DECIMAL(5,2) GENERATED ALWAYS AS (ROUND(total_score / max_score * 100, 2)) STORED,
    grade           CHAR(2) NOT NULL,
    CONSTRAINT fk_score_attempt
        FOREIGN KEY (attempt_id) REFERENCES attempts(attempt_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 11. results  (depends on attempts, examiners)
--     version column supports the lost-update demo (Part C).
-- ---------------------------------------------------------------------
CREATE TABLE results (
    result_id       INT AUTO_INCREMENT PRIMARY KEY,
    attempt_id      INT NOT NULL UNIQUE,
    examiner_id     INT NOT NULL,
    final_score     DECIMAL(6,2) NOT NULL CHECK (final_score >= 0),
    status          ENUM('PENDING','PUBLISHED') NOT NULL DEFAULT 'PENDING',
    version         INT NOT NULL DEFAULT 0,
    published_at    TIMESTAMP NULL DEFAULT NULL,
    CONSTRAINT fk_result_attempt
        FOREIGN KEY (attempt_id) REFERENCES attempts(attempt_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_result_examiner
        FOREIGN KEY (examiner_id) REFERENCES examiners(examiner_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 12. result_update_history  (depends on results, examiners)
--     Preserves the complete audit history of all examiner decisions
--     and score adjustments across concurrent or sequential evaluations.
-- ---------------------------------------------------------------------
CREATE TABLE result_update_history (
    history_id      INT AUTO_INCREMENT PRIMARY KEY,
    result_id       INT NOT NULL,
    examiner_id     INT NOT NULL,
    old_score       DECIMAL(6,2) NULL,
    new_score       DECIMAL(6,2) NOT NULL,
    version_no      INT NOT NULL,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_history_result
        FOREIGN KEY (result_id) REFERENCES results(result_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_history_examiner
        FOREIGN KEY (examiner_id) REFERENCES examiners(examiner_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 13. candidate_hash_index  (depends on candidates, attempts)
--     Deliberately NOT a MySQL index -- a plain relational table used to
--     demonstrate textbook hashing concepts (hash function, bucket
--     calculation, collisions, and separate chaining). See 04_hashing.sql.
-- ---------------------------------------------------------------------
CREATE TABLE candidate_hash_index (
    bucket_no       INT NOT NULL,
    candidate_id    INT NOT NULL,
    attempt_id      INT NOT NULL,
    chain_seq       INT NOT NULL DEFAULT 0,   -- position within the bucket's chain
    PRIMARY KEY (bucket_no, candidate_id, attempt_id),
    CONSTRAINT fk_hash_candidate
        FOREIGN KEY (candidate_id) REFERENCES candidates(candidate_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_hash_attempt
        FOREIGN KEY (attempt_id) REFERENCES attempts(attempt_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- Verification: list all tables just created
-- ---------------------------------------------------------------------
SHOW TABLES;
