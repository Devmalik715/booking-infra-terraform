-- The reporting query from Part 5 of the assignment: per-organisation booking
-- totals for one city over the trailing 30 days.
--
-- Run it with timing and a plan:
--   docker compose exec postgres psql -U bookings_app -d bookings -f /work/db/queries/booking_rollup.sql

\timing on

EXPLAIN (ANALYZE, BUFFERS)
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;

SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status
ORDER BY org_id, status;
