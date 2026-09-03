-- =====================================================================
-- 08_result_transaction.sql
-- PART C -- Result processing: publishing a result without a lost
-- update, when two examiners might touch the same row.
-- =====================================================================
USE nvces_db;

-- ---------------------------------------------------------------------
-- ISOLATION LEVEL used for this session (InnoDB default is
-- REPEATABLE READ; we make it explicit here for clarity/rubric credit).
-- ---------------------------------------------------------------------
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- ---------------------------------------------------------------------
-- SAFE PUBLISH PROCEDURE
-- Uses SELECT ... FOR UPDATE to take an exclusive row lock BEFORE
-- reading the current score, so a second examiner's transaction must
-- wait until the first COMMITs -- this is what prevents the classic
-- "lost update": two sessions read the same old value, both compute a
-- new value from it, and the second COMMIT silently overwrites the
-- first, discarding its change.
-- ---------------------------------------------------------------------
DELIMITER $$

DROP PROCEDURE IF EXISTS publish_result $$
CREATE PROCEDURE publish_result (
    IN p_attempt_id INT,
    IN p_examiner_id INT,
    IN p_new_score DECIMAL(6,2),
    OUT p_result VARCHAR(30)
)
BEGIN
    DECLARE v_result_id INT;
    DECLARE v_current_version INT;
    DECLARE v_old_score DECIMAL(6,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result = 'ERROR';
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Row lock acquired here; a concurrent publish_result() call on the
    -- SAME attempt_id will block at this exact line until we commit.
    SELECT result_id, version, final_score
      INTO v_result_id, v_current_version, v_old_score
      FROM results
     WHERE attempt_id = p_attempt_id
       FOR UPDATE;

    -- 1. Update the live results row (latest state + increment version)
    UPDATE results
       SET final_score  = p_new_score,
           examiner_id  = p_examiner_id,
           status       = 'PUBLISHED',
           version      = v_current_version + 1,
           published_at = CURRENT_TIMESTAMP
     WHERE attempt_id = p_attempt_id;

    -- 2. Preserve audit trail in result_update_history
    INSERT INTO result_update_history (
        result_id, examiner_id, old_score, new_score, version_no, updated_at
    ) VALUES (
        v_result_id, p_examiner_id, v_old_score, p_new_score, v_current_version + 1, CURRENT_TIMESTAMP
    );

    COMMIT;
    SET p_result = 'PUBLISHED';
END $$

DELIMITER ;

-- ---------------------------------------------------------------------
-- USAGE EXAMPLE (single session)
-- ---------------------------------------------------------------------
CALL publish_result(3, 3, 52.00, @res);
SELECT @res AS publish_result;
SELECT attempt_id, final_score, status, version, examiner_id FROM results WHERE attempt_id = 3;
SELECT * FROM result_update_history WHERE result_id = (SELECT result_id FROM results WHERE attempt_id = 3);

-- ---------------------------------------------------------------------
-- TWO-EXAMINER RACE: see 09_concurrency_session1.sql and
-- 10_concurrency_session2.sql for how to reproduce this with two real
-- MySQL client connections.
--
-- IMPORTANT CONCEPTUAL DISTINCTION:
-- When Examiner 1 updates a score from 50.00 -> 58.00 (version 1) and
-- Examiner 2 subsequently updates 58.00 -> 60.00 (version 2):
--
--   A. PREVENTING STALE READS / LOST UPDATES (results table):
--      Pessimistic locking (SELECT ... FOR UPDATE) forces Examiner 2
--      to wait. When Examiner 2 unblocks, it reads the updated state
--      (58.00, version 1) instead of the stale initial state (50.00, version 0).
--      The live table reflects final_score = 60.00 with version = 2.
--      (The score is 60.00, NOT a merge of both numbers).
--
--   B. PRESERVING COMPLETE EVALUATION HISTORY (result_update_history table):
--      Both examiner decisions (50 -> 58 and 58 -> 60) are preserved as
--      distinct audit rows in result_update_history with timestamps,
--      examiner IDs, and old/new score deltas.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- OPTIMISTIC-LOCKING ALTERNATIVE (shown for comparison; not required,
-- but useful if you want to discuss trade-offs in your report):
-- an UPDATE that only succeeds if version has not moved since you read
-- it. If ROW_COUNT() = 0, someone else updated first -- re-read and retry.
-- ---------------------------------------------------------------------
-- UPDATE results
--    SET final_score = 60.00, status = 'PUBLISHED', version = version + 1
--  WHERE attempt_id = 4 AND version = 0;   -- 0 = the version you last read
-- SELECT ROW_COUNT();  -- 1 = success, 0 = someone else updated it first
