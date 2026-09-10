BEGIN;

CREATE TABLE IF NOT EXISTS hotel_bookings (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id        UUID           NOT NULL,
    hotel_id      VARCHAR(100)   NOT NULL,
    city          VARCHAR(100)   NOT NULL,
    checkin_date  DATE           NOT NULL,
    checkout_date DATE           NOT NULL,
    amount        NUMERIC(12, 2) NOT NULL,
    status        VARCHAR(50)    NOT NULL,
    created_at    TIMESTAMPTZ    NOT NULL DEFAULT now(),

    CONSTRAINT hotel_bookings_stay_is_forward
        CHECK (checkout_date > checkin_date),
    CONSTRAINT hotel_bookings_amount_non_negative
        CHECK (amount >= 0),
    CONSTRAINT hotel_bookings_status_known
        CHECK (status IN ('pending', 'confirmed', 'cancelled', 'completed', 'no_show'))
);

CREATE TABLE IF NOT EXISTS booking_events (
    id         BIGSERIAL PRIMARY KEY,
    booking_id UUID         NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    payload    JSONB,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT booking_events_booking_fk
        FOREIGN KEY (booking_id) REFERENCES hotel_bookings (id) ON DELETE CASCADE
);

COMMIT;
