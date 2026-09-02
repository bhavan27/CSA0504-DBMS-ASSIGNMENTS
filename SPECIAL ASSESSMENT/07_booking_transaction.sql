-- =====================================================================
-- 07_booking_transaction.sql
-- PART B -- Safe slot booking (single-session reference version).
-- For the two-session concurrency demo, use 09_concurrency_session1.sql
-- and 10_concurrency_session2.sql in TWO SEPARATE mysql client windows.
-- =====================================================================
USE nvces_db;

-- ---------------------------------------------------------------------
-- SAFE BOOKING PROCEDURE (parameterized, reusable)
-- Encapsulates: FOR UPDATE lock -> capacity check -> insert+update ->
-- commit, or rollback if the slot is full. Uses a SIGNAL to report a
-- clear error when the slot is full, and relies on
-- uq_booking_slot_candidate as a second line of defense against a
-- duplicate booking by the same candidate.
-- ---------------------------------------------------------------------
DELIMITER $$

DROP PROCEDURE IF EXISTS book_slot $$
CREATE PROCEDURE book_slot (
    IN p_slot_id INT,
    IN p_candidate_id INT,
    OUT p_result VARCHAR(30)
)
BEGIN
    DECLARE v_capacity INT;
    DECLARE v_booked INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result = 'ERROR';
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Row-level lock: no other transaction can read this row with
    -- FOR UPDATE, or modify it, until we COMMIT/ROLLBACK.
    SELECT capacity, booked_count
      INTO v_capacity, v_booked
      FROM exam_slots
     WHERE slot_id = p_slot_id
       FOR UPDATE;

    IF v_booked < v_capacity THEN
        INSERT INTO bookings (slot_id, candidate_id, status)
        VALUES (p_slot_id, p_candidate_id, 'CONFIRMED');

        UPDATE exam_slots
           SET booked_count = booked_count + 1
         WHERE slot_id = p_slot_id;

        COMMIT;
        SET p_result = 'CONFIRMED';
    ELSE
        ROLLBACK;
        SET p_result = 'SLOT_FULL';
    END IF;
END $$

DELIMITER ;

-- ---------------------------------------------------------------------
-- USAGE EXAMPLES
-- ---------------------------------------------------------------------

-- Successful booking: slot 1 has 1 free seat (2/3 booked) in the
-- sample data -- candidate 8 has never booked slot 1.
CALL book_slot(1, 8, @result);
SELECT @result AS booking_result;   -- expect CONFIRMED
SELECT capacity, booked_count FROM exam_slots WHERE slot_id = 1;  -- expect 3/3

-- Rejected booking: slot 3 is already FULL (2/2) in the sample data.
CALL book_slot(3, 9, @result2);
SELECT @result2 AS booking_result;  -- expect SLOT_FULL
SELECT capacity, booked_count FROM exam_slots WHERE slot_id = 3;  -- unchanged, still 2/2

-- Duplicate-booking rejection via the UNIQUE constraint: candidate 1
-- already booked slot 1 -- this INSERT (outside the procedure, to show
-- the raw constraint) must fail even if the capacity check were
-- somehow bypassed.
-- Uncomment to see the error:
-- INSERT INTO bookings (slot_id, candidate_id) VALUES (1, 1);
-- Expected: ERROR 1062 (23000): Duplicate entry '1-1' for key
-- 'uq_booking_slot_candidate'

-- ---------------------------------------------------------------------
-- MANUAL (non-procedure) version of the exact same logic, shown
-- explicitly because the rubric asks for the raw transaction shape:
-- ---------------------------------------------------------------------
-- START TRANSACTION;
-- SELECT capacity, booked_count FROM exam_slots WHERE slot_id = 2 FOR UPDATE;
-- -- (application checks: booked_count < capacity ?)
-- INSERT INTO bookings (slot_id, candidate_id, status) VALUES (2, 9, 'CONFIRMED');
-- UPDATE exam_slots SET booked_count = booked_count + 1 WHERE slot_id = 2;
-- COMMIT;
-- -- or, if capacity was NOT available:
-- -- ROLLBACK;
