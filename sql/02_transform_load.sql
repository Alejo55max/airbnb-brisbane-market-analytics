-- Transforms staging.* (raw text, 1:1 with source CSVs) into the normalized
-- schema in 01_schema.sql: type casts, blank-string -> NULL, price cleanup,
-- and de-duplication into dimension tables (neighbourhoods, hosts).

-- 1. Neighbourhoods (dimension)
INSERT INTO neighbourhoods (neighbourhood_name)
SELECT DISTINCT neighbourhood_cleansed
FROM staging.listings_raw
WHERE neighbourhood_cleansed <> ''
ORDER BY 1;

-- 2. Hosts (dimension) — one row per distinct host_id
INSERT INTO hosts (host_id, host_name, host_is_superhost, host_identity_verified,
                    host_listings_count, host_total_listings_count, host_neighbourhood)
SELECT DISTINCT ON (host_id)
    host_id::BIGINT,
    host_name,
    host_is_superhost = 't',
    host_identity_verified = 't',
    NULLIF(host_listings_count, '')::INT,
    NULLIF(host_total_listings_count, '')::INT,
    NULLIF(host_neighbourhood, '')
FROM staging.listings_raw
WHERE host_id <> '';

-- 3. Listings (fact)
INSERT INTO listings (
    listing_id, host_id, neighbourhood_id, name, latitude, longitude,
    property_type, room_type, accommodates, bathrooms, bedrooms, beds,
    price, minimum_nights, maximum_nights,
    availability_30, availability_60, availability_90, availability_365,
    number_of_reviews, number_of_reviews_ltm, number_of_reviews_l30d,
    first_review, last_review,
    review_scores_rating, review_scores_accuracy, review_scores_cleanliness,
    review_scores_checkin, review_scores_communication, review_scores_location,
    review_scores_value, reviews_per_month,
    estimated_occupancy_l365d, estimated_revenue_l365d
)
SELECT
    l.id::BIGINT,
    NULLIF(l.host_id, '')::BIGINT,
    n.neighbourhood_id,
    l.name,
    NULLIF(l.latitude, '')::NUMERIC,
    NULLIF(l.longitude, '')::NUMERIC,
    NULLIF(l.property_type, ''),
    NULLIF(l.room_type, ''),
    NULLIF(l.accommodates, '')::INT,
    NULLIF(l.bathrooms, '')::NUMERIC,
    NULLIF(l.bedrooms, '')::INT,
    NULLIF(l.beds, '')::INT,
    NULLIF(regexp_replace(l.price, '[^0-9.]', '', 'g'), '')::NUMERIC,
    NULLIF(l.minimum_nights, '')::INT,
    NULLIF(l.maximum_nights, '')::INT,
    NULLIF(l.availability_30, '')::INT,
    NULLIF(l.availability_60, '')::INT,
    NULLIF(l.availability_90, '')::INT,
    NULLIF(l.availability_365, '')::INT,
    NULLIF(l.number_of_reviews, '')::INT,
    NULLIF(l.number_of_reviews_ltm, '')::INT,
    NULLIF(l.number_of_reviews_l30d, '')::INT,
    NULLIF(l.first_review, '')::DATE,
    NULLIF(l.last_review, '')::DATE,
    NULLIF(l.review_scores_rating, '')::NUMERIC,
    NULLIF(l.review_scores_accuracy, '')::NUMERIC,
    NULLIF(l.review_scores_cleanliness, '')::NUMERIC,
    NULLIF(l.review_scores_checkin, '')::NUMERIC,
    NULLIF(l.review_scores_communication, '')::NUMERIC,
    NULLIF(l.review_scores_location, '')::NUMERIC,
    NULLIF(l.review_scores_value, '')::NUMERIC,
    NULLIF(l.reviews_per_month, '')::NUMERIC,
    NULLIF(l.estimated_occupancy_l365d, '')::INT,
    NULLIF(l.estimated_revenue_l365d, '')::NUMERIC
FROM staging.listings_raw l
LEFT JOIN neighbourhoods n ON n.neighbourhood_name = l.neighbourhood_cleansed;

-- 4. Calendar (fact, ~2.3M rows)
INSERT INTO calendar (listing_id, calendar_date, available, minimum_nights, maximum_nights)
SELECT
    listing_id::BIGINT,
    date::DATE,
    available = 't',
    NULLIF(minimum_nights, '')::INT,
    NULLIF(maximum_nights, '')::INT
FROM staging.calendar_raw;

-- 5. Reviews (fact)
INSERT INTO reviews (review_id, listing_id, review_date, reviewer_id, reviewer_name)
SELECT
    id::BIGINT,
    listing_id::BIGINT,
    NULLIF(date, '')::DATE,
    NULLIF(reviewer_id, '')::BIGINT,
    reviewer_name
FROM staging.reviews_raw;
