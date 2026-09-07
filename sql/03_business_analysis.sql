-- Brisbane Airbnb Market Analysis — business-question queries.
-- Run against the schema built by 01_schema.sql / 02_transform_load.sql.
--
-- Data scope notes (see README for full detail):
--   - Pricing analysis excludes the top 1% of prices (>= 99th percentile): a handful
--     of listings carry implausible "deterrent" prices hosts set when they don't want
--     bookings, confirmed by manual inspection (one listing was $18,623/night for a
--     2-bedroom unit, ~2.7x the next highest price in the dataset).
--   - `calendar` is FORWARD-looking (next 365 days from the 2026-07-14 scrape date),
--     not historical bookings. "Unavailable" is a proxy for booked/blocked demand,
--     not confirmed bookings — a known Inside Airbnb limitation, used here as a
--     forward booking-pace indicator rather than a historical occupancy trend.


-- ============================================================================
-- Q1. Market overview: where is the estimated Airbnb revenue in Brisbane?
-- ============================================================================
SELECT
    n.neighbourhood_name,
    COUNT(*) AS total_listings,
    COUNT(l.estimated_revenue_l365d) AS priced_listings,
    ROUND(SUM(l.estimated_revenue_l365d)) AS total_estimated_revenue_aud,
    ROUND(AVG(l.estimated_revenue_l365d)) AS avg_estimated_revenue_aud
FROM listings l
JOIN neighbourhoods n ON n.neighbourhood_id = l.neighbourhood_id
GROUP BY n.neighbourhood_name
ORDER BY total_estimated_revenue_aud DESC NULLS LAST
LIMIT 15;


-- ============================================================================
-- Q2. Price landscape: median nightly price by suburb and room type
--     (99th-percentile price outliers excluded; suburbs need 5+ listings)
-- ============================================================================
WITH price_bounds AS (
    SELECT percentile_cont(0.99) WITHIN GROUP (ORDER BY price) AS p99
    FROM listings WHERE price IS NOT NULL
)
SELECT
    n.neighbourhood_name,
    l.room_type,
    COUNT(*) AS n_listings,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY l.price)::NUMERIC) AS median_price_aud,
    ROUND(AVG(l.price)::NUMERIC) AS avg_price_aud
FROM listings l
JOIN neighbourhoods n ON n.neighbourhood_id = l.neighbourhood_id
CROSS JOIN price_bounds pb
WHERE l.price IS NOT NULL
  AND l.price <= pb.p99
  AND l.room_type IN ('Entire home/apt', 'Private room')
GROUP BY n.neighbourhood_name, l.room_type
HAVING COUNT(*) >= 5
ORDER BY l.room_type, median_price_aud DESC;


-- ============================================================================
-- Q3. Revenue concentration: single-listing hosts vs. multi-listing operators
--     (listing count computed from THIS dataset, not Airbnb's global host field)
-- ============================================================================
WITH host_local_counts AS (
    SELECT
        host_id,
        COUNT(*) AS local_listing_count,
        SUM(estimated_revenue_l365d) AS host_revenue
    FROM listings
    WHERE estimated_revenue_l365d IS NOT NULL
    GROUP BY host_id
)
SELECT
    CASE WHEN local_listing_count = 1 THEN 'Single-listing host' ELSE 'Multi-listing host (2+)' END AS host_type,
    COUNT(*) AS n_hosts,
    SUM(local_listing_count) AS n_listings,
    ROUND(SUM(host_revenue)) AS total_revenue_aud,
    ROUND(100.0 * SUM(host_revenue) / SUM(SUM(host_revenue)) OVER (), 1) AS pct_of_total_revenue
FROM host_local_counts
GROUP BY host_type;


-- ============================================================================
-- Q4. The superhost effect: occupancy, revenue and rating vs. non-superhosts
-- ============================================================================
SELECT
    h.host_is_superhost,
    COUNT(*) AS n_listings,
    ROUND(AVG(l.estimated_occupancy_l365d)) AS avg_est_occupied_nights_per_yr,
    ROUND(AVG(l.estimated_revenue_l365d)) AS avg_est_revenue_aud,
    ROUND(AVG(l.review_scores_rating)::NUMERIC, 2) AS avg_rating
FROM listings l
JOIN hosts h ON h.host_id = l.host_id
WHERE l.number_of_reviews >= 5   -- exclude listings too new to have a meaningful rating/occupancy signal
GROUP BY h.host_is_superhost;


-- ============================================================================
-- Q5. Forward booking pace by month (next 12 months from scrape date)
--     NOTE: "unavailable" = booked OR host-blocked (proxy, not confirmed bookings)
-- ============================================================================
WITH monthly AS (
    SELECT
        date_trunc('month', calendar_date)::date AS month,
        COUNT(*) AS listing_nights,
        COUNT(*) FILTER (WHERE available = false) AS unavailable_nights,
        ROUND(100.0 * COUNT(*) FILTER (WHERE available = false) / COUNT(*), 2) AS booked_out_rate_pct
    FROM calendar
    GROUP BY 1
)
SELECT
    month,
    booked_out_rate_pct,
    ROUND(booked_out_rate_pct - LAG(booked_out_rate_pct) OVER (ORDER BY month), 2) AS mom_change_pp,
    ROUND(AVG(booked_out_rate_pct) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS rolling_3mo_avg_pct
FROM monthly
ORDER BY month;


-- ============================================================================
-- Q6. Commercial-scale hosts: portfolio ranking and revenue concentration
-- ============================================================================
WITH host_summary AS (
    SELECT
        h.host_id,
        h.host_name,
        h.host_is_superhost,
        COUNT(*) AS n_listings,
        SUM(l.estimated_revenue_l365d) AS total_revenue_aud
    FROM listings l
    JOIN hosts h ON h.host_id = l.host_id
    GROUP BY h.host_id, h.host_name, h.host_is_superhost
)
SELECT
    host_name,
    host_is_superhost,
    n_listings,
    total_revenue_aud,
    RANK() OVER (ORDER BY n_listings DESC) AS rank_by_portfolio_size,
    ROUND(100.0 * SUM(total_revenue_aud) OVER (ORDER BY total_revenue_aud DESC NULLS LAST ROWS UNBOUNDED PRECEDING)
          / SUM(total_revenue_aud) OVER (), 1) AS cumulative_pct_of_market_revenue
FROM host_summary
ORDER BY total_revenue_aud DESC NULLS LAST
LIMIT 20;


-- ============================================================================
-- Q7. Market growth: new listings entering the market per year (cumulative)
--     (first_review date used as a proxy for "went live", since host_since is
--      not published in this scrape)
-- ============================================================================
WITH yearly AS (
    SELECT EXTRACT(YEAR FROM first_review)::INT AS year, COUNT(*) AS new_listings
    FROM listings
    WHERE first_review IS NOT NULL
    GROUP BY 1
)
SELECT
    year,
    new_listings,
    SUM(new_listings) OVER (ORDER BY year) AS cumulative_active_listings
FROM yearly
ORDER BY year;


-- ============================================================================
-- Q8. Demand momentum by suburb: review volume, last 12 months vs. prior 12
--     (review count is a standard Airbnb-market proxy for booking volume)
-- ============================================================================
WITH bounds AS (
    SELECT MAX(review_date) AS max_date FROM reviews
),
review_periods AS (
    SELECT
        l.neighbourhood_id,
        CASE
            WHEN r.review_date >= b.max_date - INTERVAL '12 months' THEN 'last_12mo'
            WHEN r.review_date >= b.max_date - INTERVAL '24 months' THEN 'prior_12mo'
        END AS period
    FROM reviews r
    JOIN listings l ON l.listing_id = r.listing_id
    CROSS JOIN bounds b
)
SELECT
    n.neighbourhood_name,
    COUNT(*) FILTER (WHERE period = 'prior_12mo') AS reviews_prior_12mo,
    COUNT(*) FILTER (WHERE period = 'last_12mo') AS reviews_last_12mo,
    ROUND(100.0 * (COUNT(*) FILTER (WHERE period = 'last_12mo') - COUNT(*) FILTER (WHERE period = 'prior_12mo'))
          / NULLIF(COUNT(*) FILTER (WHERE period = 'prior_12mo'), 0), 1) AS pct_change
FROM review_periods rp
JOIN neighbourhoods n ON n.neighbourhood_id = rp.neighbourhood_id
WHERE period IS NOT NULL
GROUP BY n.neighbourhood_name
HAVING COUNT(*) FILTER (WHERE period = 'prior_12mo') >= 20
ORDER BY pct_change DESC;


-- ============================================================================
-- Q9. Stay-length policy mix: genuine short-stay tourism vs. mid/long-stay
--     (housing-supply angle: 30+ night minimums function like standard leases)
-- ============================================================================
SELECT
    CASE
        WHEN minimum_nights <= 3 THEN '1-3 nights (short-stay tourism)'
        WHEN minimum_nights BETWEEN 4 AND 29 THEN '4-29 nights (mid-stay)'
        ELSE '30+ nights (long-stay / lease-like)'
    END AS stay_policy,
    COUNT(*) AS n_listings,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_market
FROM listings
GROUP BY 1
ORDER BY 2 DESC;


-- ============================================================================
-- Q10. Best value-for-money: top-rated listing per suburb, priced below its
--      suburb+room-type median (CTE + join + window function ranking)
-- ============================================================================
WITH suburb_median AS (
    SELECT neighbourhood_id, room_type,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS median_price
    FROM listings
    WHERE price IS NOT NULL
    GROUP BY neighbourhood_id, room_type
),
candidates AS (
    SELECT
        n.neighbourhood_name,
        l.name,
        l.room_type,
        l.price,
        l.review_scores_rating,
        l.number_of_reviews,
        ROW_NUMBER() OVER (
            PARTITION BY n.neighbourhood_name
            ORDER BY l.review_scores_rating DESC, l.number_of_reviews DESC
        ) AS rn
    FROM listings l
    JOIN neighbourhoods n ON n.neighbourhood_id = l.neighbourhood_id
    JOIN suburb_median sm ON sm.neighbourhood_id = l.neighbourhood_id AND sm.room_type = l.room_type
    WHERE l.price < sm.median_price
      AND l.review_scores_rating >= 4.8
      AND l.number_of_reviews >= 10
)
SELECT neighbourhood_name, name, room_type, price, review_scores_rating, number_of_reviews
FROM candidates
WHERE rn = 1
ORDER BY review_scores_rating DESC, number_of_reviews DESC
LIMIT 20;
