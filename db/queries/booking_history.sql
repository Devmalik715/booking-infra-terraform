-- Second access pattern the schema is indexed for: the event history of one
-- booking, newest first. Served by idx_booking_events_booking_id_created_at.

EXPLAIN (ANALYZE, BUFFERS)
SELECT event_type, payload, created_at
FROM booking_events
WHERE booking_id = (SELECT booking_id FROM booking_events LIMIT 1)
ORDER BY created_at DESC;
