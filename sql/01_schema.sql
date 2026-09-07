-- Final normalized schema for the Brisbane Airbnb market analysis.
-- Source: Inside Airbnb, Brisbane QLD snapshot 2026-07-14 (https://insideairbnb.com)
--
-- Design notes:
--   - host_since, host_response_time/rate, license and instant_bookable are excluded:
--     they came back 100% empty in this scrape (Airbnb no longer publishes them),
--     confirmed via staging.listings_raw before modeling.
--   - estimated_revenue_l365d / estimated_occupancy_l365d are Inside Airbnb's own
--     modeled demand metrics (derived from calendar + review activity) and are the
--     centerpiece of the revenue-side analysis.

DROP TABLE IF EXISTS reviews CASCADE;
DROP TABLE IF EXISTS calendar CASCADE;
DROP TABLE IF EXISTS listings CASCADE;
DROP TABLE IF EXISTS hosts CASCADE;
DROP TABLE IF EXISTS neighbourhoods CASCADE;

CREATE TABLE neighbourhoods (
    neighbourhood_id    SERIAL PRIMARY KEY,
    neighbourhood_name  TEXT NOT NULL UNIQUE
);

CREATE TABLE hosts (
    host_id                 BIGINT PRIMARY KEY,
    host_name               TEXT,
    host_is_superhost       BOOLEAN,
    host_identity_verified  BOOLEAN,
    host_listings_count     INT,
    host_total_listings_count INT,
    host_neighbourhood      TEXT
);

CREATE TABLE listings (
    listing_id                  BIGINT PRIMARY KEY,
    host_id                     BIGINT REFERENCES hosts(host_id),
    neighbourhood_id            INT REFERENCES neighbourhoods(neighbourhood_id),
    name                        TEXT,
    latitude                    NUMERIC(9,6),
    longitude                   NUMERIC(9,6),
    property_type               TEXT,
    room_type                   TEXT,
    accommodates                INT,
    bathrooms                   NUMERIC(4,1),
    bedrooms                    INT,
    beds                        INT,
    price                       NUMERIC(10,2),
    minimum_nights              INT,
    maximum_nights               INT,
    availability_30             INT,
    availability_60             INT,
    availability_90             INT,
    availability_365            INT,
    number_of_reviews           INT,
    number_of_reviews_ltm       INT,
    number_of_reviews_l30d      INT,
    first_review                DATE,
    last_review                 DATE,
    review_scores_rating        NUMERIC(3,2),
    review_scores_accuracy      NUMERIC(3,2),
    review_scores_cleanliness   NUMERIC(3,2),
    review_scores_checkin       NUMERIC(3,2),
    review_scores_communication NUMERIC(3,2),
    review_scores_location      NUMERIC(3,2),
    review_scores_value         NUMERIC(3,2),
    reviews_per_month           NUMERIC(6,2),
    estimated_occupancy_l365d   INT,
    estimated_revenue_l365d     NUMERIC(12,2)
);

CREATE TABLE calendar (
    listing_id      BIGINT REFERENCES listings(listing_id),
    calendar_date   DATE NOT NULL,
    available       BOOLEAN NOT NULL,
    minimum_nights  INT,
    maximum_nights  INT,
    PRIMARY KEY (listing_id, calendar_date)
);

CREATE TABLE reviews (
    review_id     BIGINT PRIMARY KEY,
    listing_id    BIGINT REFERENCES listings(listing_id),
    review_date   DATE,
    reviewer_id   BIGINT,
    reviewer_name TEXT
);

CREATE INDEX idx_listings_neighbourhood ON listings(neighbourhood_id);
CREATE INDEX idx_listings_host ON listings(host_id);
CREATE INDEX idx_calendar_date ON calendar(calendar_date);
CREATE INDEX idx_reviews_listing ON reviews(listing_id);
CREATE INDEX idx_reviews_date ON reviews(review_date);
