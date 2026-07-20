-- Total revenue by payment type (dollars)
-- Excludes statistical outliers by default.
-- Revenue = SUM(total_amount_cents) / 100 for hard-valid, non-refund rows.
SELECT
    p.payment_type_key,
    p.label AS payment_type_label,
    ROUND(
        SUM(f.total_amount_cents)::numeric / 100.0,
        2
    ) AS total_revenue_dollars,
    COUNT(*) AS trip_count,
    ROUND(
        AVG(f.total_amount_cents)::numeric / 100.0,
        2
    ) AS avg_revenue_per_trip_dollars
FROM warehouse.fact_taxi_trips AS f
INNER JOIN warehouse.dim_payment_type AS p
    ON f.payment_type_key = p.surrogate_key
WHERE NOT f.has_statistical_outlier
GROUP BY p.payment_type_key, p.label
ORDER BY total_revenue_dollars DESC;
