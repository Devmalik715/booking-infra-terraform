-- 50,000 bookings so the Part 5 index has enough rows to matter. Values are
-- derived from md5(row number) rather than random(), which keeps every rebuild
-- identical and avoids random() being hoisted out of the LATERAL.

INSERT INTO hotel_bookings (
    id, org_id, hotel_id, city, checkin_date, checkout_date, amount, status, created_at
)
SELECT
    md5(g::text || ':booking')::uuid,
    cfg.org_ids[1 + h.org % array_length(cfg.org_ids, 1)],
    'HTL-' || upper(substr(pick.city, 1, 3)) || '-' || lpad((1 + h.hotel % 40)::text, 3, '0'),
    pick.city,
    pick.checkin_date,
    pick.checkin_date + (1 + h.nights % 7),
    round((1500 + (h.amount % 8350000) / 100.0)::numeric, 2),
    cfg.status_pool[1 + h.status % array_length(cfg.status_pool, 1)],
    pick.created_at
FROM (
    SELECT
        50000 AS booking_count,
        ARRAY[
            '3f6c1a52-9d4e-4c8b-8f01-6a0b2d7e5c11',
            '7b2e4d19-0c53-4a76-9e88-1d4f3b6a2c47',
            'a1c9f072-64b8-4d31-b5e2-9f7c0a83d612',
            'c4d7e830-2f16-49a5-8c73-5b19e6d0f284',
            'e8a30b6d-7c41-4f92-a1d5-3e6b8c204f95',
            'f2b58c14-3a97-4e60-9d28-7c05a1f3b8de'
        ]::uuid[] AS org_ids,
        ARRAY[
            'delhi', 'delhi', 'delhi', 'delhi',
            'mumbai', 'mumbai', 'mumbai',
            'bengaluru', 'bengaluru',
            'goa', 'goa',
            'jaipur', 'hyderabad', 'pune', 'kolkata', 'chennai'
        ]::text[] AS city_pool,
        ARRAY[
            'confirmed', 'confirmed', 'confirmed', 'confirmed',
            'completed', 'completed', 'completed',
            'pending', 'pending',
            'cancelled',
            'no_show'
        ]::text[] AS status_pool
) cfg
CROSS JOIN generate_series(1, cfg.booking_count) AS g
CROSS JOIN LATERAL (
    SELECT
        ('x' || substr(md5(g::text || ':org'), 1, 7))::bit(28)::int    AS org,
        ('x' || substr(md5(g::text || ':city'), 1, 7))::bit(28)::int   AS city,
        ('x' || substr(md5(g::text || ':status'), 1, 7))::bit(28)::int AS status,
        ('x' || substr(md5(g::text || ':hotel'), 1, 7))::bit(28)::int  AS hotel,
        ('x' || substr(md5(g::text || ':amount'), 1, 7))::bit(28)::int AS amount,
        ('x' || substr(md5(g::text || ':age'), 1, 7))::bit(28)::int    AS age,
        ('x' || substr(md5(g::text || ':lead'), 1, 7))::bit(28)::int   AS lead,
        ('x' || substr(md5(g::text || ':nights'), 1, 7))::bit(28)::int AS nights
) h
CROSS JOIN LATERAL (
    SELECT
        cfg.city_pool[1 + h.city % array_length(cfg.city_pool, 1)] AS city,
        now()
            - make_interval(days => h.age % 120)
            - make_interval(hours => h.lead % 24) AS created_at
) pick_base
CROSS JOIN LATERAL (
    SELECT
        pick_base.city,
        pick_base.created_at,
        (pick_base.created_at + make_interval(days => 1 + h.lead % 60))::date AS checkin_date
) pick;

CREATE TEMP TABLE seed_sample AS
SELECT
    id,
    city,
    amount,
    status,
    created_at,
    ('x' || substr(md5(id::text), 1, 7))::bit(28)::int AS h
FROM hotel_bookings
WHERE ('x' || substr(md5(id::text || ':sample'), 1, 7))::bit(28)::int % 100 < 65;

INSERT INTO booking_events (booking_id, event_type, payload, created_at)
SELECT
    s.id,
    'booking_created',
    jsonb_build_object(
        'channel', (ARRAY['web', 'ios', 'android', 'partner_api'])[1 + s.h % 4],
        'city', s.city,
        'amount', s.amount
    ),
    s.created_at
FROM seed_sample s;

INSERT INTO booking_events (booking_id, event_type, payload, created_at)
SELECT
    s.id,
    CASE s.status
        WHEN 'cancelled' THEN 'booking_cancelled'
        WHEN 'no_show'   THEN 'stay_no_show'
        ELSE 'payment_captured'
    END,
    CASE s.status
        WHEN 'cancelled' THEN jsonb_build_object('reason', 'guest_request', 'refund_amount', round(s.amount * 0.8, 2))
        WHEN 'no_show'   THEN jsonb_build_object('reported_by', 'hotel')
        ELSE jsonb_build_object('gateway', 'razorpay', 'captured_amount', s.amount, 'currency', 'INR')
    END,
    s.created_at + make_interval(mins => 2 + s.h % 90)
FROM seed_sample s
WHERE s.status IN ('confirmed', 'completed', 'cancelled', 'no_show');

DROP TABLE seed_sample;

VACUUM ANALYZE hotel_bookings;
VACUUM ANALYZE booking_events;

\echo ''
\echo 'Seed complete:'
SELECT
    (SELECT count(*) FROM hotel_bookings)               AS bookings,
    (SELECT count(*) FROM booking_events)               AS events,
    (SELECT count(DISTINCT city) FROM hotel_bookings)   AS cities,
    (SELECT count(DISTINCT org_id) FROM hotel_bookings) AS orgs,
    (SELECT count(DISTINCT status) FROM hotel_bookings) AS statuses;
