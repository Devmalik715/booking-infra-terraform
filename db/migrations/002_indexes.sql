-- 002_indexes.sql
-- Indexes are kept in their own migration so it is obvious which ones were
-- added for a specific query, and why.
--
-- Target query (Part 5 of the assignment):
--
--   SELECT org_id, status, COUNT(*), SUM(amount)
--   FROM hotel_bookings
--   WHERE city = 'delhi'
--     AND created_at >= NOW() - INTERVAL '30 days'
--   GROUP BY org_id, status;
--
-- The reasoning behind the index below is written up in docs/query-optimization.md
-- together with the EXPLAIN output from before and after.

BEGIN;

-- Equality column first, range column second: Postgres can only use a b-tree
-- range bound on the column that follows the equality predicates. The reverse
-- order (created_at, city) would force a scan across every city in the window.
--
-- org_id, status and amount are carried as INCLUDE payload. They are not part
-- of the search key, they exist so the aggregate can be answered from the index
-- alone (index-only scan) instead of visiting the heap once per matching row.
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at)
    INCLUDE (org_id, status, amount);

-- Reading a booking's history is the second hot path in this schema: fetch the
-- events for one booking, newest first.
CREATE INDEX IF NOT EXISTS idx_booking_events_booking_id_created_at
    ON booking_events (booking_id, created_at DESC);

COMMIT;
