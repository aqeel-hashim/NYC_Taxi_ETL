-- Average fare per mile (dollars per mile)
-- Excludes statistical outliers by default.
-- Uses ratio-of-sums, not average of per-trip ratios.
SELECT
    pickup_date_key,
    ROUND(
        10.0 * SUM(fare_amount_cents)::numeric
        / NULLIF(SUM(distance_millimiles), 0),
        2
    ) AS avg_fare_per_mile_dollars
FROM warehouse.fact_taxi_trips
WHERE NOT has_statistical_outlier
GROUP BY pickup_date_key
ORDER BY pickup_date_key;
