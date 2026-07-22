-- Peak hours for taxi rides (trip count by pickup hour)
-- Includes all hard-valid rows regardless of outlier flag.
-- Hour is local NYC wall-clock hour derived from dim_time.
SELECT
    t.hour AS pickup_hour,
    t.daypart,
    LPAD(t.hour::text, 2, '0') || ':00' AS hour_label,
    COUNT(*) AS trip_count
FROM warehouse.fact_taxi_trips AS f
INNER JOIN warehouse.dim_time AS t ON f.pickup_time_key = t.time_key
GROUP BY t.hour, t.daypart
ORDER BY trip_count DESC;
