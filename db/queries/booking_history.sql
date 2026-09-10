EXPLAIN (ANALYZE, BUFFERS)
SELECT event_type, payload, created_at
FROM booking_events
WHERE booking_id = (SELECT booking_id FROM booking_events LIMIT 1)
ORDER BY created_at DESC;
