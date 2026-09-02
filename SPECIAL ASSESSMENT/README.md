# National Vocational Certification and Exam Slot-Booking System: An Integrated Study in File Organization, Indexing, Hashing, Query Optimization, and Transaction Management

**Course:** CSA05 — Database Management Systems  
**Target RDBMS:** MySQL 8.0+ (InnoDB Storage Engine)

---

## 1. Project Title & Problem Statement

### Title
**National Vocational Certification and Exam Slot-Booking System: An Integrated Study in File Organization, Indexing, Hashing, Query Optimization, and Transaction Management**

### Problem Statement
Vocational training and skill certification authorities conduct large-scale, computer-based examinations across distributed exam centers, test dates, and time slots. The database engine supporting this infrastructure faces several critical technical challenges:
1. **Archive Retrieval Overhead:** Archival tables (such as `attempts`) rapidly accumulate hundreds of thousands of historical records. Linear/sequential scans over unindexed clustered tables cause severe I/O bottlenecks and unacceptable query latencies.
2. **Race Conditions & Overbooking:** When multiple candidates simultaneously contest a single remaining seat in an examination slot, naive application reads and writes lead to race conditions, lost updates, and capacity violations (`booked_count > capacity`).
3. **Concurrent Examiner Conflicts & Lost Updates:** In multi-evaluator environments, concurrent score updates on the same candidate result row can silently overwrite grading decisions unless explicit pessimistic or optimistic concurrency controls and audit mechanisms are deployed.
4. **Suboptimal Query Execution:** Complex multi-table reporting queries can suffer from unindexed joins, full-table scans, and memory-intensive filesorts without principled indexing (informed by the leftmost-prefix rule and column selectivity) and systematic execution plan analysis.

---

## 2. Objectives

- **Relational Schema Design:** Design and deploy a 3NF normalized schema enforcing entity and referential integrity using primary keys, foreign keys, `CHECK` constraints, and `UNIQUE` constraints.
- **File Organization & B+ Tree Indexing:** Transition an exam attempt archive from naive sequential scans to indexed-sequential access using single-column and composite B+ tree secondary indexes.
- **Textbook Hashing Demonstration:** Implement a separate relational simulation of textbook hashing with modulo bucket calculation, forced collisions, and separate chaining.
- **ACID Transaction Management:** Build robust, atomic transaction routines utilizing `SELECT ... FOR UPDATE`, safe capacity validations, and explicit error handlers.
- **Granular Transaction Control:** Demonstrate `COMMIT`, `ROLLBACK`, `SAVEPOINT`, and `ROLLBACK TO SAVEPOINT` using realistic domain workflows.
- **Concurrency Control & Serializability:** Implement and evaluate paired multi-session tests verifying lock acquisition, lock waiting, stale-read prevention, and historical audit preservation.
- **Empirical Query Optimization:** Optimize reporting queries through before-and-after `EXPLAIN` and `EXPLAIN ANALYZE` execution plans on both baseline and bulk synthetic datasets.
- **Role-Based Security:** Establish least-privilege security roles (`nvces_candidate`, `nvces_examiner`, `nvces_auditor`) with appropriate `GRANT` and `REVOKE` policies.

---

## 3. System Architecture

```
                       [ Database: nvces_db ]
                                 │
                            [candidates]
                                 │ (1:N)
                                 ▼
[exams] ───────┐            [bookings] ◄──────── [exam_slots] ◄────── [exam_centers]
               │                 │                      │
               ▼                 ▼                      │
         ┌───────────────►  [attempts] ◄────────────────┘
         │                       │
         │           ┌───────────┼───────────┐
         │           ▼           ▼           ▼
         │      [responses]  [timings]   [scores]
         │                                   │
         │                                   ▼
[examiners] ──────────────────────────►  [results]
                                             │ (1:N)
                                             ▼
                                  [result_update_history]

[candidate_hash_index] (Relational textbook hashing demonstration structure)
```

### Data Flow Breakdown
1. **Candidates** register in the system.
2. **Exams** and **Exam Centers** define schedules within **Exam Slots** (fixed capacity).
3. Candidates place **Bookings** against specific slots (guaranteed unique per slot-candidate).
4. On exam day, **Attempts** are generated from confirmed bookings.
5. Candidate test execution generates detailed **Responses**, **Timings**, and aggregate **Scores**.
6. Examiners grade and publish finalized **Results**, while **Result Update History** tracks every grading decision across time and sessions.
7. **Candidate Hash Index** provides a dedicated demonstration table for textbook hash-bucket access and collision chaining.

---

## 4. Database Tables & Schema Specifications

The schema comprises 13 normalized tables:

| # | Table Name | Purpose | Primary Key | Key Foreign Keys / Constraints |
|---|---|---|---|---|
| 1 | `candidates` | Candidate profiles and contact details | `candidate_id` | `email` (UNIQUE) |
| 2 | `exam_centers` | Physical exam center details and capacities | `center_id` | `total_capacity > 0` |
| 3 | `exams` | Certification catalog and grading rules | `exam_id` | `exam_code` (UNIQUE), `duration_minutes > 0` |
| 4 | `examiners` | Authorized evaluation staff | `examiner_id` | `email` (UNIQUE), `role` ENUM |
| 5 | `exam_slots` | Timetabled exam capacity per center | `slot_id` | `FK(exam_id)`, `FK(center_id)`, `chk_slot_capacity` (`booked_count <= capacity`), `UQ(exam_id, center_id, exam_date, start_time)` |
| 6 | `bookings` | Slot reservation records | `booking_id` | `FK(slot_id)`, `FK(candidate_id)`, `UQ(slot_id, candidate_id)` |
| 7 | `attempts` | Archive of candidate exam sittings | `attempt_id` | `FK(booking_id)` (UNIQUE), `FK(candidate_id)`, `FK(exam_id)`, `FK(center_id)`, `FK(slot_id)` |
| 8 | `responses` | Question-level candidate choices | `response_id` | `FK(attempt_id)`, `UQ(attempt_id, question_no)` |
| 9 | `timings` | Start/end timestamps and durations | `timing_id` | `FK(attempt_id)` (UNIQUE), `duration_seconds` STORED GENERATED |
| 10 | `scores` | Calculated total score and grade | `score_id` | `FK(attempt_id)` (UNIQUE), `percentage` STORED GENERATED |
| 11 | `results` | Official examiner evaluation and publishing | `result_id` | `FK(attempt_id)` (UNIQUE), `FK(examiner_id)`, `version` INT |
| 12 | `result_update_history` | Audit trail of all score adjustments | `history_id` | `FK(result_id)`, `FK(examiner_id)` |
| 13 | `candidate_hash_index` | Textbook hashing demonstration table | `(bucket_no, candidate_id, attempt_id)` | `FK(candidate_id)`, `FK(attempt_id)` |

---

## 5. File Organization Approach

In MySQL InnoDB:
- Tables are physically organized as **Clustered Indexes** (index-organized tables) structured as B+ trees where the leaf pages store full row records ordered strictly by the Primary Key (`PRIMARY`).
- Without secondary indexes, searching for records by non-primary attributes (e.g., `candidate_id` or `center_id` on the `attempts` table) forces the storage engine to perform a **Full Table Scan** (sequential walk of all leaf pages in the clustered index, $O(N)$ complexity).
- Creating **Secondary B+ Tree Indexes** establishes auxiliary ordered access paths storing `(secondary_key, primary_key)`. The database engine traverses the secondary B+ tree in $O(\log N)$ time and performs an index dive into the clustered index to fetch required row data.

---

## 6. Indexing Approach

### Index Workload Matrix & Leftmost-Prefix Rationale

```
Index: idx_attempt_center_date_slot ON attempts (center_id, exam_date, slot_id)

Index Structure (B+ Tree Order):
┌────────────────────────┬────────────────────────┬────────────────────────┐
│  center_id (Level 1)   │  exam_date (Level 2)   │   slot_id (Level 3)    │
└────────────────────────┴────────────────────────┴────────────────────────┘
 ◄────────────────────── 2-column prefix (serves Query 3) ───────────────►
 ◄────────────────────── Full 3-column index (serves Query 4) ────────────►
```

1. **Candidate Attempt Lookup:**
   - Query: `WHERE candidate_id = ?`
   - Index: `idx_attempt_candidate ON attempts (candidate_id)`
   - High selectivity; replaces $O(N)$ table scan with $O(\log N)$ point seek.
2. **Candidate History (Sorted):**
   - Query: `WHERE candidate_id = ? ORDER BY exam_date`
   - Index: `idx_attempt_candidate_date ON attempts (candidate_id, exam_date)`
   - Leftmost prefix filters candidate; ordered second key eliminates `Using filesort`.
3. **Center/Date Audit:**
   - Query: `WHERE center_id = ? AND exam_date = ?`
   - Index: `idx_attempt_center_date_slot ON attempts (center_id, exam_date, slot_id)`
   - Utilizes the 2-column leftmost prefix `(center_id, exam_date)` without needing a duplicate index.
4. **Center/Date/Slot Retrieval:**
   - Query: `WHERE center_id = ? AND exam_date = ? AND slot_id = ?`
   - Utilizes the full 3-column composite index.
5. **Candidate Booking Lookup:**
   - Query: `WHERE candidate_id = ?` on `bookings`
   - Index: `idx_booking_candidate ON bookings (candidate_id)`

---

## 7. Hashing Approach

> [!NOTE]
> **Conceptual Note:**
> "This is a relational implementation used to demonstrate textbook hashing concepts; it is not a claim that the InnoDB secondary index is a user-defined hash index."

- **Hash Function:** Division/modulo hashing over candidate ID domain:
  $$\text{bucket\_no} = \text{MOD}(\text{candidate\_id}, 10)$$
- **Bucket Calculation & Forced Collision:**
  - Candidate 1: $\text{MOD}(1, 10) = 1 \implies \text{Bucket } 1$
  - Candidate 11: $\text{MOD}(11, 10) = 1 \implies \text{Bucket } 1$ (Collision)
- **Collision Resolution:** Separate Chaining modeled relationally:
  - Multiple records share `bucket_no = 1`.
  - Position within the bucket chain is tracked via `chain_seq` (0 for candidate 1, 1 for candidate 11).
- **Lookup Mechanism:**
  - Compute bucket on search key: `bucket_no = MOD(11, 10) = 1`.
  - Probe candidate row: `WHERE bucket_no = 1 AND candidate_id = 11`.
  - Expected access cost is $O(1)$ compared to scanning all buckets.

---

## 8. Query Optimization Approach

Every optimization case study follows a strict 8-part academic methodology:
1. **Original Query Formulation**
2. **Pre-Optimization EXPLAIN / EXPLAIN ANALYZE**
3. **Execution Plan Bottleneck Identification** (e.g., `type: ALL`, `key: NULL`, full table scan)
4. **Index Design & Optimization Strategy**
5. **Index Creation / Query Refinement**
6. **Optimized Query Formulation**
7. **Post-Optimization EXPLAIN / EXPLAIN ANALYZE**
8. **Comparative Analysis & Cost Interpretation** (e.g., transition to `type: range` / `type: ref`)

*(No execution times are hardcoded; actual execution figures are gathered dynamically from `EXPLAIN ANALYZE` on your local environment).*

---

## 9. Transaction Approach

### Safe Booking Transaction (`book_slot` procedure)
```sql
START TRANSACTION;
SELECT capacity, booked_count 
  FROM exam_slots 
 WHERE slot_id = ? 
   FOR UPDATE;

IF booked_count < capacity THEN
    INSERT INTO bookings (slot_id, candidate_id, status) VALUES (?, ?, 'CONFIRMED');
    UPDATE exam_slots SET booked_count = booked_count + 1 WHERE slot_id = ?;
    COMMIT; -- Returns CONFIRMED
ELSE
    ROLLBACK; -- Returns SLOT_FULL
END IF;
```

### Integrity Backstops
- Engine-level check constraint: `CONSTRAINT chk_slot_capacity CHECK (booked_count <= capacity)`
- Uniqueness constraint: `CONSTRAINT uq_booking_slot_candidate UNIQUE (slot_id, candidate_id)`

---

## 10. Concurrency Approach & Two-Session Testing

### Distinction between Concurrency Control and Audit History
When Session 1 updates score $50.00 \to 58.00$ and Session 2 updates $58.00 \to 60.00$:
1. **Preventing Stale Reads / Lost Updates (`results` table):**
   - Pessimistic locking (`SELECT ... FOR UPDATE`) forces Session 2 to wait until Session 1 completes `COMMIT`.
   - When Session 2 executes, it reads the updated state ($58.00$, version 1) rather than the stale value ($50.00$, version 0).
   - The final live state reflects `final_score = 60.00` and `version = 2`.
2. **Preserving Complete Decision History (`result_update_history` table):**
   - Both distinct grading decisions ($50 \to 58$ by Examiner 1 and $58 \to 60$ by Examiner 2) are preserved as distinct chronological rows.

---

## 11. Testing & Validation (TC01–TC15)

| Test Case | Description | Primary Verification | Expected Result |
|---|---|---|---|
| **TC01** | Candidate Primary Key Lookup | `SELECT * FROM candidates WHERE candidate_id = 1;` | Exactly 1 row (Arun Kumar) |
| **TC02** | Candidate Attempt History | `EXPLAIN SELECT ... FROM attempts WHERE candidate_id = 1 ORDER BY exam_date;` | Uses `idx_attempt_candidate_date`, no filesort |
| **TC03** | Center/Date Audit | `EXPLAIN SELECT ... WHERE center_id = 1 AND exam_date = '2026-09-10';` | Uses `idx_attempt_center_date_slot` prefix |
| **TC04** | Hash Lookup | `SELECT ... WHERE bucket_no = MOD(3, 10) AND candidate_id = 3;` | Resolves candidate 3 via bucket 3 |
| **TC05** | Hash Collision | `SELECT ... WHERE bucket_no = 1;` | Shows Candidate 1 and 11 in bucket 1 |
| **TC06** | Successful Booking | `CALL book_slot(2, 8, @res);` | `@res = 'CONFIRMED'`, `booked_count` increments |
| **TC07** | Full Slot Rejection | `CALL book_slot(3, 8, @res);` | `@res = 'SLOT_FULL'`, slot count unchanged |
| **TC08** | Concurrent Booking Race | Two-session interleaved execution (`09` & `10`) | Exactly 1 seat granted; second session gets `SLOT_FULL` |
| **TC09** | Result Publishing | `CALL publish_result(4, 3, 72.00, @res);` | `@res = 'PUBLISHED'`, `version` increments |
| **TC10** | Concurrent Result Update | Two-session interleaved execution (`09` & `10`) | `results.version = 2`, `result_update_history` has 2 rows |
| **TC11** | Transaction COMMIT | Insert confirmed booking + `COMMIT` | Row persists permanently |
| **TC12** | Transaction ROLLBACK | Insert booking + `ROLLBACK` | Zero rows inserted |
| **TC13** | SAVEPOINT Partial Rollback | `SAVEPOINT` + erroneous update + `ROLLBACK TO SAVEPOINT` | Valid update kept; bad update discarded |
| **TC14** | Query Optimization Plan | `EXPLAIN` before and after date index | Access path shifts from `ALL` to `range` |
| **TC15** | Index Structure Audit | `SHOW INDEX FROM attempts;` | Confirms all secondary indexes & column orders |

---

## 12. Execution Guide

### Prerequisites
- MySQL 8.0+ Server and MySQL Command-Line Client / MySQL Workbench.

### Sequential Script Execution

Run files **1 through 8** and **11 through 15** in order:

```bash
mysql -u root -p < 01_database_schema.sql
mysql -u root -p < 02_sample_data.sql
mysql -u root -p < 03_indexes.sql
mysql -u root -p < 04_hashing.sql
mysql -u root -p < 05_basic_queries.sql
mysql -u root -p < 06_query_optimization.sql
mysql -u root -p < 07_booking_transaction.sql
mysql -u root -p < 08_result_transaction.sql
mysql -u root -p < 11_savepoints.sql
mysql -u root -p < 12_security.sql
mysql -u root -p < 13_test_cases.sql
mysql -u root -p < 14_performance_benchmark.sql
```

---

## 13. How to Perform Two-Session Concurrency Testing

Open **two separate terminal windows** (or two query tabs in MySQL Workbench):

```bash
# Terminal A (Session 1)
mysql -u root -p nvces_db

# Terminal B (Session 2)
mysql -u root -p nvces_db
```

### Demo 1: Booking Race (Slot with 1 seat left)
1. **Terminal A (STEP 1):** Start transaction and execute `SELECT ... FOR UPDATE` on `slot_id = 2`.
2. **Terminal B (STEP 2):** Execute `SELECT ... FOR UPDATE` on `slot_id = 2` $\implies$ **Terminal B hangs/blocks**.
3. **Terminal A (STEP 3):** Execute `INSERT` booking, update `booked_count`, and `COMMIT;`.
4. **Terminal B (STEP 4):** Unblocks immediately, reads updated `booked_count = capacity`, and executes `ROLLBACK;`.

### Demo 2: Result Lost-Update Prevention
1. **Terminal A (STEP 5):** Start transaction and lock result row for `attempt_id = 6`.
2. **Terminal B (STEP 6):** Execute `SELECT ... FOR UPDATE` for `attempt_id = 6` $\implies$ **Terminal B blocks**.
3. **Terminal A (STEP 7):** Update score to $58.00$, insert history, and `COMMIT;`.
4. **Terminal B (STEP 8):** Unblocks, reads unblocked score $58.00$, updates score to $60.00$, inserts history, and `COMMIT;`.
5. **Terminal A (STEP 9):** Verify `results` has `final_score = 60.00`, `version = 2`, and `result_update_history` holds both decisions.

---

## 14. GitHub & Repository Structure

```
.
├── 01_database_schema.sql         # Base DDL: 13 tables, PKs, FKs, CHECKs, UNIQUE constraints
├── 02_sample_data.sql             # Realistic seed dataset for testing and demonstration
├── 03_indexes.sql                 # B+ tree single and composite secondary index definitions
├── 04_hashing.sql                 # Modulo hashing, forced collision, and chaining simulation
├── 05_basic_queries.sql           # Query catalogue (SELECT, JOIN, GROUP BY, aggregates, subqueries)
├── 06_query_optimization.sql      # 8-part query optimization case studies with EXPLAIN ANALYZE
├── 07_booking_transaction.sql     # Safe booking stored procedure with row-level locking
├── 08_result_transaction.sql      # Safe result publishing stored procedure with versioning & audit
├── 09_concurrency_session1.sql    # Multi-session concurrency test (Session 1 statements)
├── 10_concurrency_session2.sql    # Multi-session concurrency test (Session 2 statements)
├── 11_savepoints.sql              # Transaction controls: COMMIT, ROLLBACK, SAVEPOINT demonstrations
├── 12_security.sql                # Role-based privilege management (GRANT / REVOKE)
├── 13_test_cases.sql              # Test suite covering TC01 through TC15
├── 14_performance_benchmark.sql   # Controlled synthetic bulk data benchmark (~5,000 rows)
└── README.md                      # Comprehensive academic project documentation
```

---

## 15. Limitations & Future Work

- **Static Modulo Hashing:** The hashing demonstration uses a fixed modulus ($N=10$). In dynamic production systems, Extendible Hashing or Linear Hashing is preferred to avoid bucket chain degradation.
- **Application Layer Integration:** In production, connection pooling, client-side retry loops for optimistic locking, and message queues for asynchronous result publishing would be layered on top of this database core.
- **Data Archiving & Partitioning:** For multi-year archives scaling into tens of millions of rows, range partitioning on `exam_date` or list partitioning by `center_id` can be combined with secondary B+ tree indexes to further reduce partition scan overhead.

---

## Team Contribution

| Name | Registration No. | Contribution |
|---|---|---|
| Bhavan | 192511369 | Schema Design, Indexing, Transactions & Optimization |
| *(Teammate Name)* | *(Reg. No.)* | *(Contribution Details)* |

**Faculty Guide:** Dr. Vinod AyyapPan
