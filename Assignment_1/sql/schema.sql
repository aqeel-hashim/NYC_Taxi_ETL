BEGIN;

CREATE TABLE alembic_version (
    version_num VARCHAR(32) NOT NULL,
    CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
);

-- Running upgrade  -> 0001

CREATE SCHEMA IF NOT EXISTS warehouse;

CREATE SCHEMA IF NOT EXISTS analytics;

CREATE SCHEMA IF NOT EXISTS ops;

CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE warehouse.dim_date (
    date_key SERIAL NOT NULL,
    calendar_date DATE NOT NULL,
    year SMALLINT NOT NULL,
    quarter SMALLINT NOT NULL,
    month SMALLINT NOT NULL,
    month_name VARCHAR(10) NOT NULL,
    iso_week SMALLINT NOT NULL,
    iso_year SMALLINT NOT NULL,
    day_of_month SMALLINT NOT NULL,
    day_of_year SMALLINT NOT NULL,
    weekday_number SMALLINT NOT NULL,
    weekday_name VARCHAR(10) NOT NULL,
    is_weekend BOOLEAN NOT NULL,
    PRIMARY KEY (date_key)
);

CREATE TABLE warehouse.dim_time (
    time_key SMALLSERIAL NOT NULL,
    hour SMALLINT NOT NULL,
    minute SMALLINT NOT NULL,
    quarter_hour SMALLINT NOT NULL,
    hour_label VARCHAR(8) NOT NULL,
    daypart VARCHAR(16) NOT NULL,
    PRIMARY KEY (time_key)
);

CREATE TABLE warehouse.dim_taxi_zone (
    surrogate_key SERIAL NOT NULL,
    business_key INTEGER NOT NULL,
    label VARCHAR(128) NOT NULL,
    attributes VARCHAR(256),
    reference_snapshot_id VARCHAR(64),
    row_hash VARCHAR(64),
    observed_from TIMESTAMP WITH TIME ZONE NOT NULL,
    observed_to TIMESTAMP WITH TIME ZONE,
    is_current BOOLEAN NOT NULL,
    PRIMARY KEY (surrogate_key)
);

CREATE INDEX ix_dim_taxi_zone_business_key ON warehouse.dim_taxi_zone (business_key);

CREATE INDEX ix_dim_taxi_zone_current ON warehouse.dim_taxi_zone (is_current);

ALTER TABLE warehouse.dim_taxi_zone
            ADD CONSTRAINT dim_taxi_zone_no_overlap
            EXCLUDE USING gist (
                business_key WITH =,
                tstzrange(observed_from, observed_to, '[)'::text) WITH &&
            );

CREATE UNIQUE INDEX dim_taxi_zone_one_current ON warehouse.dim_taxi_zone (business_key) WHERE is_current IS TRUE;

CREATE TABLE warehouse.dim_payment_type (
    surrogate_key SERIAL NOT NULL,
    business_key INTEGER NOT NULL,
    label VARCHAR(128) NOT NULL,
    attributes VARCHAR(256),
    reference_snapshot_id VARCHAR(64),
    row_hash VARCHAR(64),
    observed_from TIMESTAMP WITH TIME ZONE NOT NULL,
    observed_to TIMESTAMP WITH TIME ZONE,
    is_current BOOLEAN NOT NULL,
    PRIMARY KEY (surrogate_key)
);

CREATE INDEX ix_dim_payment_type_business_key ON warehouse.dim_payment_type (business_key);

CREATE INDEX ix_dim_payment_type_current ON warehouse.dim_payment_type (is_current);

ALTER TABLE warehouse.dim_payment_type
            ADD CONSTRAINT dim_payment_type_no_overlap
            EXCLUDE USING gist (
                business_key WITH =,
                tstzrange(observed_from, observed_to, '[)'::text) WITH &&
            );

CREATE UNIQUE INDEX dim_payment_type_one_current ON warehouse.dim_payment_type (business_key) WHERE is_current IS TRUE;

CREATE TABLE warehouse.dim_vendor (
    surrogate_key SERIAL NOT NULL,
    business_key INTEGER NOT NULL,
    label VARCHAR(128) NOT NULL,
    attributes VARCHAR(256),
    reference_snapshot_id VARCHAR(64),
    row_hash VARCHAR(64),
    observed_from TIMESTAMP WITH TIME ZONE NOT NULL,
    observed_to TIMESTAMP WITH TIME ZONE,
    is_current BOOLEAN NOT NULL,
    PRIMARY KEY (surrogate_key)
);

CREATE INDEX ix_dim_vendor_business_key ON warehouse.dim_vendor (business_key);

CREATE INDEX ix_dim_vendor_current ON warehouse.dim_vendor (is_current);

ALTER TABLE warehouse.dim_vendor
            ADD CONSTRAINT dim_vendor_no_overlap
            EXCLUDE USING gist (
                business_key WITH =,
                tstzrange(observed_from, observed_to, '[)'::text) WITH &&
            );

CREATE UNIQUE INDEX dim_vendor_one_current ON warehouse.dim_vendor (business_key) WHERE is_current IS TRUE;

CREATE TABLE warehouse.dim_rate_code (
    surrogate_key SERIAL NOT NULL,
    business_key INTEGER NOT NULL,
    label VARCHAR(128) NOT NULL,
    attributes VARCHAR(256),
    reference_snapshot_id VARCHAR(64),
    row_hash VARCHAR(64),
    observed_from TIMESTAMP WITH TIME ZONE NOT NULL,
    observed_to TIMESTAMP WITH TIME ZONE,
    is_current BOOLEAN NOT NULL,
    PRIMARY KEY (surrogate_key)
);

CREATE INDEX ix_dim_rate_code_business_key ON warehouse.dim_rate_code (business_key);

CREATE INDEX ix_dim_rate_code_current ON warehouse.dim_rate_code (is_current);

ALTER TABLE warehouse.dim_rate_code
            ADD CONSTRAINT dim_rate_code_no_overlap
            EXCLUDE USING gist (
                business_key WITH =,
                tstzrange(observed_from, observed_to, '[)'::text) WITH &&
            );

CREATE UNIQUE INDEX dim_rate_code_one_current ON warehouse.dim_rate_code (business_key) WHERE is_current IS TRUE;

CREATE TABLE warehouse.fact_taxi_trips (
            trip_key BIGSERIAL,
            pickup_date_key INTEGER NOT NULL,
            dropoff_date_key INTEGER NOT NULL,
            pickup_time_key SMALLINT NOT NULL,
            dropoff_time_key SMALLINT NOT NULL,
            pickup_zone_key INTEGER NOT NULL,
            dropoff_zone_key INTEGER NOT NULL,
            payment_type_key INTEGER NOT NULL,
            vendor_key INTEGER NOT NULL,
            rate_code_key INTEGER NOT NULL,
            pickup_at_local TIMESTAMP WITHOUT TIME ZONE NOT NULL,
            dropoff_at_local TIMESTAMP WITHOUT TIME ZONE NOT NULL,
            duration_seconds BIGINT NOT NULL,
            passenger_count SMALLINT,
            distance_millimiles BIGINT NOT NULL,
            store_and_fwd_flag VARCHAR(1),
            fare_amount_cents BIGINT NOT NULL,
            extra_cents BIGINT,
            mta_tax_cents BIGINT,
            tip_amount_cents BIGINT,
            tolls_amount_cents BIGINT,
            improvement_surcharge_cents BIGINT,
            total_amount_cents BIGINT NOT NULL,
            congestion_surcharge_cents BIGINT,
            airport_fee_cents BIGINT,
            source_asset_id VARCHAR(128) NOT NULL,
            source_row_number BIGINT NOT NULL,
            source_version VARCHAR(64) NOT NULL,
            threshold_version_id VARCHAR(64),
            reference_snapshot_id VARCHAR(64),
            publish_run_id VARCHAR(64),
            has_statistical_outlier BOOLEAN NOT NULL DEFAULT FALSE,
            has_quality_issue BOOLEAN NOT NULL DEFAULT FALSE,
            PRIMARY KEY (pickup_date_key, trip_key)
        ) PARTITION BY RANGE (pickup_date_key);

CREATE TABLE analytics.trip_metrics_hourly (
            pickup_date_key INTEGER NOT NULL,
            pickup_hour SMALLINT NOT NULL,
            pickup_zone_key INTEGER NOT NULL,
            payment_type_key INTEGER NOT NULL,
            vendor_key INTEGER NOT NULL,
            rate_code_key INTEGER NOT NULL,
            has_statistical_outlier BOOLEAN NOT NULL,
            has_quality_issue BOOLEAN NOT NULL,
            trip_count BIGINT NOT NULL,
            passenger_count_sum BIGINT NOT NULL,
            passenger_sum BIGINT,
            distance_millimiles_sum BIGINT NOT NULL,
            duration_seconds_sum BIGINT NOT NULL,
            fare_amount_cents_sum BIGINT NOT NULL,
            extra_cents_sum BIGINT DEFAULT 0,
            mta_tax_cents_sum BIGINT DEFAULT 0,
            tip_amount_cents_sum BIGINT DEFAULT 0,
            tolls_amount_cents_sum BIGINT DEFAULT 0,
            improvement_surcharge_cents_sum BIGINT DEFAULT 0,
            total_amount_cents_sum BIGINT NOT NULL,
            congestion_surcharge_cents_sum BIGINT DEFAULT 0,
            airport_fee_cents_sum BIGINT DEFAULT 0,
            PRIMARY KEY (pickup_date_key, pickup_hour, pickup_zone_key, payment_type_key,
                         vendor_key, rate_code_key, has_statistical_outlier, has_quality_issue)
        ) PARTITION BY RANGE (pickup_date_key);

CREATE TABLE ops.pipeline_run (
    id BIGSERIAL NOT NULL,
    dag_id VARCHAR(128) NOT NULL,
    run_id VARCHAR(128) NOT NULL,
    task_id VARCHAR(128),
    source_month VARCHAR(7) NOT NULL,
    status VARCHAR(32) NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE,
    finished_at TIMESTAMP WITH TIME ZONE,
    duration_seconds FLOAT,
    source_rows BIGINT,
    accepted_rows BIGINT,
    rejected_rows BIGINT,
    flagged_rows BIGINT,
    source_version VARCHAR(64),
    threshold_version_id VARCHAR(64),
    reference_snapshot_id VARCHAR(64),
    error_summary TEXT,
    PRIMARY KEY (id)
);

CREATE TABLE ops.source_asset (
    id VARCHAR(128) NOT NULL,
    source_month VARCHAR(7) NOT NULL,
    source_url TEXT NOT NULL,
    byte_size BIGINT,
    sha256 VARCHAR(64) NOT NULL,
    parquet_schema_fingerprint TEXT,
    object_key VARCHAR(256) NOT NULL,
    row_count BIGINT,
    is_synthetic BOOLEAN DEFAULT 'false' NOT NULL,
    ingested_at TIMESTAMP WITH TIME ZONE NOT NULL,
    PRIMARY KEY (id)
);

CREATE TABLE ops.quality_result_summary (
    id BIGSERIAL NOT NULL,
    pipeline_run_id BIGINT,
    source_month VARCHAR(7) NOT NULL,
    issue_code VARCHAR(64) NOT NULL,
    severity VARCHAR(16) NOT NULL,
    row_count BIGINT NOT NULL,
    PRIMARY KEY (id)
);

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (0, 0, 0, 0, '00:00', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1, 0, 1, 0, '00:01', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (2, 0, 2, 0, '00:02', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (3, 0, 3, 0, '00:03', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (4, 0, 4, 0, '00:04', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (5, 0, 5, 0, '00:05', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (6, 0, 6, 0, '00:06', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (7, 0, 7, 0, '00:07', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (8, 0, 8, 0, '00:08', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (9, 0, 9, 0, '00:09', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (10, 0, 10, 0, '00:10', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (11, 0, 11, 0, '00:11', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (12, 0, 12, 0, '00:12', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (13, 0, 13, 0, '00:13', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (14, 0, 14, 0, '00:14', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (15, 0, 15, 1, '00:15', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (16, 0, 16, 1, '00:16', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (17, 0, 17, 1, '00:17', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (18, 0, 18, 1, '00:18', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (19, 0, 19, 1, '00:19', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (20, 0, 20, 1, '00:20', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (21, 0, 21, 1, '00:21', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (22, 0, 22, 1, '00:22', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (23, 0, 23, 1, '00:23', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (24, 0, 24, 1, '00:24', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (25, 0, 25, 1, '00:25', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (26, 0, 26, 1, '00:26', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (27, 0, 27, 1, '00:27', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (28, 0, 28, 1, '00:28', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (29, 0, 29, 1, '00:29', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (30, 0, 30, 2, '00:30', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (31, 0, 31, 2, '00:31', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (32, 0, 32, 2, '00:32', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (33, 0, 33, 2, '00:33', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (34, 0, 34, 2, '00:34', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (35, 0, 35, 2, '00:35', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (36, 0, 36, 2, '00:36', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (37, 0, 37, 2, '00:37', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (38, 0, 38, 2, '00:38', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (39, 0, 39, 2, '00:39', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (40, 0, 40, 2, '00:40', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (41, 0, 41, 2, '00:41', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (42, 0, 42, 2, '00:42', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (43, 0, 43, 2, '00:43', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (44, 0, 44, 2, '00:44', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (45, 0, 45, 3, '00:45', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (46, 0, 46, 3, '00:46', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (47, 0, 47, 3, '00:47', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (48, 0, 48, 3, '00:48', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (49, 0, 49, 3, '00:49', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (50, 0, 50, 3, '00:50', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (51, 0, 51, 3, '00:51', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (52, 0, 52, 3, '00:52', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (53, 0, 53, 3, '00:53', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (54, 0, 54, 3, '00:54', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (55, 0, 55, 3, '00:55', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (56, 0, 56, 3, '00:56', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (57, 0, 57, 3, '00:57', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (58, 0, 58, 3, '00:58', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (59, 0, 59, 3, '00:59', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (60, 1, 0, 0, '01:00', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (61, 1, 1, 0, '01:01', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (62, 1, 2, 0, '01:02', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (63, 1, 3, 0, '01:03', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (64, 1, 4, 0, '01:04', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (65, 1, 5, 0, '01:05', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (66, 1, 6, 0, '01:06', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (67, 1, 7, 0, '01:07', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (68, 1, 8, 0, '01:08', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (69, 1, 9, 0, '01:09', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (70, 1, 10, 0, '01:10', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (71, 1, 11, 0, '01:11', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (72, 1, 12, 0, '01:12', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (73, 1, 13, 0, '01:13', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (74, 1, 14, 0, '01:14', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (75, 1, 15, 1, '01:15', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (76, 1, 16, 1, '01:16', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (77, 1, 17, 1, '01:17', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (78, 1, 18, 1, '01:18', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (79, 1, 19, 1, '01:19', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (80, 1, 20, 1, '01:20', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (81, 1, 21, 1, '01:21', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (82, 1, 22, 1, '01:22', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (83, 1, 23, 1, '01:23', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (84, 1, 24, 1, '01:24', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (85, 1, 25, 1, '01:25', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (86, 1, 26, 1, '01:26', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (87, 1, 27, 1, '01:27', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (88, 1, 28, 1, '01:28', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (89, 1, 29, 1, '01:29', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (90, 1, 30, 2, '01:30', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (91, 1, 31, 2, '01:31', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (92, 1, 32, 2, '01:32', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (93, 1, 33, 2, '01:33', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (94, 1, 34, 2, '01:34', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (95, 1, 35, 2, '01:35', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (96, 1, 36, 2, '01:36', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (97, 1, 37, 2, '01:37', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (98, 1, 38, 2, '01:38', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (99, 1, 39, 2, '01:39', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (100, 1, 40, 2, '01:40', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (101, 1, 41, 2, '01:41', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (102, 1, 42, 2, '01:42', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (103, 1, 43, 2, '01:43', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (104, 1, 44, 2, '01:44', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (105, 1, 45, 3, '01:45', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (106, 1, 46, 3, '01:46', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (107, 1, 47, 3, '01:47', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (108, 1, 48, 3, '01:48', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (109, 1, 49, 3, '01:49', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (110, 1, 50, 3, '01:50', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (111, 1, 51, 3, '01:51', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (112, 1, 52, 3, '01:52', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (113, 1, 53, 3, '01:53', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (114, 1, 54, 3, '01:54', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (115, 1, 55, 3, '01:55', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (116, 1, 56, 3, '01:56', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (117, 1, 57, 3, '01:57', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (118, 1, 58, 3, '01:58', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (119, 1, 59, 3, '01:59', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (120, 2, 0, 0, '02:00', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (121, 2, 1, 0, '02:01', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (122, 2, 2, 0, '02:02', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (123, 2, 3, 0, '02:03', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (124, 2, 4, 0, '02:04', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (125, 2, 5, 0, '02:05', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (126, 2, 6, 0, '02:06', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (127, 2, 7, 0, '02:07', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (128, 2, 8, 0, '02:08', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (129, 2, 9, 0, '02:09', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (130, 2, 10, 0, '02:10', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (131, 2, 11, 0, '02:11', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (132, 2, 12, 0, '02:12', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (133, 2, 13, 0, '02:13', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (134, 2, 14, 0, '02:14', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (135, 2, 15, 1, '02:15', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (136, 2, 16, 1, '02:16', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (137, 2, 17, 1, '02:17', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (138, 2, 18, 1, '02:18', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (139, 2, 19, 1, '02:19', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (140, 2, 20, 1, '02:20', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (141, 2, 21, 1, '02:21', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (142, 2, 22, 1, '02:22', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (143, 2, 23, 1, '02:23', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (144, 2, 24, 1, '02:24', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (145, 2, 25, 1, '02:25', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (146, 2, 26, 1, '02:26', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (147, 2, 27, 1, '02:27', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (148, 2, 28, 1, '02:28', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (149, 2, 29, 1, '02:29', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (150, 2, 30, 2, '02:30', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (151, 2, 31, 2, '02:31', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (152, 2, 32, 2, '02:32', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (153, 2, 33, 2, '02:33', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (154, 2, 34, 2, '02:34', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (155, 2, 35, 2, '02:35', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (156, 2, 36, 2, '02:36', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (157, 2, 37, 2, '02:37', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (158, 2, 38, 2, '02:38', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (159, 2, 39, 2, '02:39', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (160, 2, 40, 2, '02:40', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (161, 2, 41, 2, '02:41', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (162, 2, 42, 2, '02:42', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (163, 2, 43, 2, '02:43', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (164, 2, 44, 2, '02:44', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (165, 2, 45, 3, '02:45', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (166, 2, 46, 3, '02:46', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (167, 2, 47, 3, '02:47', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (168, 2, 48, 3, '02:48', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (169, 2, 49, 3, '02:49', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (170, 2, 50, 3, '02:50', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (171, 2, 51, 3, '02:51', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (172, 2, 52, 3, '02:52', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (173, 2, 53, 3, '02:53', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (174, 2, 54, 3, '02:54', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (175, 2, 55, 3, '02:55', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (176, 2, 56, 3, '02:56', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (177, 2, 57, 3, '02:57', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (178, 2, 58, 3, '02:58', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (179, 2, 59, 3, '02:59', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (180, 3, 0, 0, '03:00', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (181, 3, 1, 0, '03:01', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (182, 3, 2, 0, '03:02', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (183, 3, 3, 0, '03:03', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (184, 3, 4, 0, '03:04', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (185, 3, 5, 0, '03:05', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (186, 3, 6, 0, '03:06', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (187, 3, 7, 0, '03:07', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (188, 3, 8, 0, '03:08', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (189, 3, 9, 0, '03:09', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (190, 3, 10, 0, '03:10', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (191, 3, 11, 0, '03:11', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (192, 3, 12, 0, '03:12', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (193, 3, 13, 0, '03:13', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (194, 3, 14, 0, '03:14', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (195, 3, 15, 1, '03:15', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (196, 3, 16, 1, '03:16', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (197, 3, 17, 1, '03:17', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (198, 3, 18, 1, '03:18', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (199, 3, 19, 1, '03:19', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (200, 3, 20, 1, '03:20', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (201, 3, 21, 1, '03:21', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (202, 3, 22, 1, '03:22', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (203, 3, 23, 1, '03:23', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (204, 3, 24, 1, '03:24', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (205, 3, 25, 1, '03:25', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (206, 3, 26, 1, '03:26', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (207, 3, 27, 1, '03:27', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (208, 3, 28, 1, '03:28', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (209, 3, 29, 1, '03:29', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (210, 3, 30, 2, '03:30', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (211, 3, 31, 2, '03:31', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (212, 3, 32, 2, '03:32', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (213, 3, 33, 2, '03:33', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (214, 3, 34, 2, '03:34', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (215, 3, 35, 2, '03:35', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (216, 3, 36, 2, '03:36', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (217, 3, 37, 2, '03:37', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (218, 3, 38, 2, '03:38', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (219, 3, 39, 2, '03:39', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (220, 3, 40, 2, '03:40', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (221, 3, 41, 2, '03:41', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (222, 3, 42, 2, '03:42', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (223, 3, 43, 2, '03:43', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (224, 3, 44, 2, '03:44', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (225, 3, 45, 3, '03:45', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (226, 3, 46, 3, '03:46', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (227, 3, 47, 3, '03:47', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (228, 3, 48, 3, '03:48', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (229, 3, 49, 3, '03:49', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (230, 3, 50, 3, '03:50', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (231, 3, 51, 3, '03:51', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (232, 3, 52, 3, '03:52', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (233, 3, 53, 3, '03:53', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (234, 3, 54, 3, '03:54', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (235, 3, 55, 3, '03:55', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (236, 3, 56, 3, '03:56', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (237, 3, 57, 3, '03:57', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (238, 3, 58, 3, '03:58', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (239, 3, 59, 3, '03:59', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (240, 4, 0, 0, '04:00', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (241, 4, 1, 0, '04:01', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (242, 4, 2, 0, '04:02', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (243, 4, 3, 0, '04:03', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (244, 4, 4, 0, '04:04', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (245, 4, 5, 0, '04:05', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (246, 4, 6, 0, '04:06', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (247, 4, 7, 0, '04:07', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (248, 4, 8, 0, '04:08', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (249, 4, 9, 0, '04:09', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (250, 4, 10, 0, '04:10', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (251, 4, 11, 0, '04:11', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (252, 4, 12, 0, '04:12', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (253, 4, 13, 0, '04:13', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (254, 4, 14, 0, '04:14', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (255, 4, 15, 1, '04:15', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (256, 4, 16, 1, '04:16', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (257, 4, 17, 1, '04:17', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (258, 4, 18, 1, '04:18', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (259, 4, 19, 1, '04:19', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (260, 4, 20, 1, '04:20', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (261, 4, 21, 1, '04:21', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (262, 4, 22, 1, '04:22', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (263, 4, 23, 1, '04:23', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (264, 4, 24, 1, '04:24', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (265, 4, 25, 1, '04:25', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (266, 4, 26, 1, '04:26', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (267, 4, 27, 1, '04:27', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (268, 4, 28, 1, '04:28', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (269, 4, 29, 1, '04:29', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (270, 4, 30, 2, '04:30', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (271, 4, 31, 2, '04:31', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (272, 4, 32, 2, '04:32', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (273, 4, 33, 2, '04:33', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (274, 4, 34, 2, '04:34', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (275, 4, 35, 2, '04:35', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (276, 4, 36, 2, '04:36', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (277, 4, 37, 2, '04:37', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (278, 4, 38, 2, '04:38', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (279, 4, 39, 2, '04:39', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (280, 4, 40, 2, '04:40', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (281, 4, 41, 2, '04:41', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (282, 4, 42, 2, '04:42', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (283, 4, 43, 2, '04:43', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (284, 4, 44, 2, '04:44', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (285, 4, 45, 3, '04:45', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (286, 4, 46, 3, '04:46', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (287, 4, 47, 3, '04:47', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (288, 4, 48, 3, '04:48', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (289, 4, 49, 3, '04:49', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (290, 4, 50, 3, '04:50', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (291, 4, 51, 3, '04:51', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (292, 4, 52, 3, '04:52', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (293, 4, 53, 3, '04:53', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (294, 4, 54, 3, '04:54', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (295, 4, 55, 3, '04:55', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (296, 4, 56, 3, '04:56', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (297, 4, 57, 3, '04:57', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (298, 4, 58, 3, '04:58', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (299, 4, 59, 3, '04:59', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (300, 5, 0, 0, '05:00', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (301, 5, 1, 0, '05:01', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (302, 5, 2, 0, '05:02', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (303, 5, 3, 0, '05:03', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (304, 5, 4, 0, '05:04', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (305, 5, 5, 0, '05:05', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (306, 5, 6, 0, '05:06', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (307, 5, 7, 0, '05:07', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (308, 5, 8, 0, '05:08', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (309, 5, 9, 0, '05:09', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (310, 5, 10, 0, '05:10', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (311, 5, 11, 0, '05:11', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (312, 5, 12, 0, '05:12', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (313, 5, 13, 0, '05:13', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (314, 5, 14, 0, '05:14', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (315, 5, 15, 1, '05:15', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (316, 5, 16, 1, '05:16', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (317, 5, 17, 1, '05:17', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (318, 5, 18, 1, '05:18', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (319, 5, 19, 1, '05:19', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (320, 5, 20, 1, '05:20', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (321, 5, 21, 1, '05:21', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (322, 5, 22, 1, '05:22', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (323, 5, 23, 1, '05:23', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (324, 5, 24, 1, '05:24', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (325, 5, 25, 1, '05:25', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (326, 5, 26, 1, '05:26', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (327, 5, 27, 1, '05:27', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (328, 5, 28, 1, '05:28', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (329, 5, 29, 1, '05:29', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (330, 5, 30, 2, '05:30', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (331, 5, 31, 2, '05:31', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (332, 5, 32, 2, '05:32', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (333, 5, 33, 2, '05:33', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (334, 5, 34, 2, '05:34', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (335, 5, 35, 2, '05:35', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (336, 5, 36, 2, '05:36', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (337, 5, 37, 2, '05:37', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (338, 5, 38, 2, '05:38', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (339, 5, 39, 2, '05:39', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (340, 5, 40, 2, '05:40', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (341, 5, 41, 2, '05:41', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (342, 5, 42, 2, '05:42', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (343, 5, 43, 2, '05:43', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (344, 5, 44, 2, '05:44', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (345, 5, 45, 3, '05:45', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (346, 5, 46, 3, '05:46', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (347, 5, 47, 3, '05:47', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (348, 5, 48, 3, '05:48', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (349, 5, 49, 3, '05:49', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (350, 5, 50, 3, '05:50', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (351, 5, 51, 3, '05:51', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (352, 5, 52, 3, '05:52', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (353, 5, 53, 3, '05:53', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (354, 5, 54, 3, '05:54', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (355, 5, 55, 3, '05:55', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (356, 5, 56, 3, '05:56', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (357, 5, 57, 3, '05:57', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (358, 5, 58, 3, '05:58', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (359, 5, 59, 3, '05:59', 'Late Night');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (360, 6, 0, 0, '06:00', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (361, 6, 1, 0, '06:01', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (362, 6, 2, 0, '06:02', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (363, 6, 3, 0, '06:03', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (364, 6, 4, 0, '06:04', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (365, 6, 5, 0, '06:05', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (366, 6, 6, 0, '06:06', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (367, 6, 7, 0, '06:07', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (368, 6, 8, 0, '06:08', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (369, 6, 9, 0, '06:09', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (370, 6, 10, 0, '06:10', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (371, 6, 11, 0, '06:11', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (372, 6, 12, 0, '06:12', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (373, 6, 13, 0, '06:13', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (374, 6, 14, 0, '06:14', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (375, 6, 15, 1, '06:15', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (376, 6, 16, 1, '06:16', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (377, 6, 17, 1, '06:17', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (378, 6, 18, 1, '06:18', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (379, 6, 19, 1, '06:19', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (380, 6, 20, 1, '06:20', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (381, 6, 21, 1, '06:21', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (382, 6, 22, 1, '06:22', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (383, 6, 23, 1, '06:23', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (384, 6, 24, 1, '06:24', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (385, 6, 25, 1, '06:25', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (386, 6, 26, 1, '06:26', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (387, 6, 27, 1, '06:27', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (388, 6, 28, 1, '06:28', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (389, 6, 29, 1, '06:29', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (390, 6, 30, 2, '06:30', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (391, 6, 31, 2, '06:31', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (392, 6, 32, 2, '06:32', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (393, 6, 33, 2, '06:33', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (394, 6, 34, 2, '06:34', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (395, 6, 35, 2, '06:35', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (396, 6, 36, 2, '06:36', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (397, 6, 37, 2, '06:37', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (398, 6, 38, 2, '06:38', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (399, 6, 39, 2, '06:39', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (400, 6, 40, 2, '06:40', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (401, 6, 41, 2, '06:41', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (402, 6, 42, 2, '06:42', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (403, 6, 43, 2, '06:43', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (404, 6, 44, 2, '06:44', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (405, 6, 45, 3, '06:45', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (406, 6, 46, 3, '06:46', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (407, 6, 47, 3, '06:47', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (408, 6, 48, 3, '06:48', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (409, 6, 49, 3, '06:49', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (410, 6, 50, 3, '06:50', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (411, 6, 51, 3, '06:51', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (412, 6, 52, 3, '06:52', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (413, 6, 53, 3, '06:53', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (414, 6, 54, 3, '06:54', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (415, 6, 55, 3, '06:55', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (416, 6, 56, 3, '06:56', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (417, 6, 57, 3, '06:57', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (418, 6, 58, 3, '06:58', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (419, 6, 59, 3, '06:59', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (420, 7, 0, 0, '07:00', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (421, 7, 1, 0, '07:01', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (422, 7, 2, 0, '07:02', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (423, 7, 3, 0, '07:03', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (424, 7, 4, 0, '07:04', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (425, 7, 5, 0, '07:05', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (426, 7, 6, 0, '07:06', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (427, 7, 7, 0, '07:07', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (428, 7, 8, 0, '07:08', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (429, 7, 9, 0, '07:09', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (430, 7, 10, 0, '07:10', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (431, 7, 11, 0, '07:11', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (432, 7, 12, 0, '07:12', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (433, 7, 13, 0, '07:13', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (434, 7, 14, 0, '07:14', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (435, 7, 15, 1, '07:15', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (436, 7, 16, 1, '07:16', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (437, 7, 17, 1, '07:17', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (438, 7, 18, 1, '07:18', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (439, 7, 19, 1, '07:19', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (440, 7, 20, 1, '07:20', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (441, 7, 21, 1, '07:21', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (442, 7, 22, 1, '07:22', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (443, 7, 23, 1, '07:23', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (444, 7, 24, 1, '07:24', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (445, 7, 25, 1, '07:25', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (446, 7, 26, 1, '07:26', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (447, 7, 27, 1, '07:27', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (448, 7, 28, 1, '07:28', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (449, 7, 29, 1, '07:29', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (450, 7, 30, 2, '07:30', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (451, 7, 31, 2, '07:31', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (452, 7, 32, 2, '07:32', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (453, 7, 33, 2, '07:33', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (454, 7, 34, 2, '07:34', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (455, 7, 35, 2, '07:35', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (456, 7, 36, 2, '07:36', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (457, 7, 37, 2, '07:37', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (458, 7, 38, 2, '07:38', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (459, 7, 39, 2, '07:39', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (460, 7, 40, 2, '07:40', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (461, 7, 41, 2, '07:41', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (462, 7, 42, 2, '07:42', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (463, 7, 43, 2, '07:43', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (464, 7, 44, 2, '07:44', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (465, 7, 45, 3, '07:45', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (466, 7, 46, 3, '07:46', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (467, 7, 47, 3, '07:47', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (468, 7, 48, 3, '07:48', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (469, 7, 49, 3, '07:49', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (470, 7, 50, 3, '07:50', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (471, 7, 51, 3, '07:51', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (472, 7, 52, 3, '07:52', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (473, 7, 53, 3, '07:53', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (474, 7, 54, 3, '07:54', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (475, 7, 55, 3, '07:55', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (476, 7, 56, 3, '07:56', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (477, 7, 57, 3, '07:57', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (478, 7, 58, 3, '07:58', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (479, 7, 59, 3, '07:59', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (480, 8, 0, 0, '08:00', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (481, 8, 1, 0, '08:01', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (482, 8, 2, 0, '08:02', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (483, 8, 3, 0, '08:03', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (484, 8, 4, 0, '08:04', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (485, 8, 5, 0, '08:05', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (486, 8, 6, 0, '08:06', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (487, 8, 7, 0, '08:07', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (488, 8, 8, 0, '08:08', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (489, 8, 9, 0, '08:09', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (490, 8, 10, 0, '08:10', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (491, 8, 11, 0, '08:11', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (492, 8, 12, 0, '08:12', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (493, 8, 13, 0, '08:13', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (494, 8, 14, 0, '08:14', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (495, 8, 15, 1, '08:15', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (496, 8, 16, 1, '08:16', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (497, 8, 17, 1, '08:17', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (498, 8, 18, 1, '08:18', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (499, 8, 19, 1, '08:19', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (500, 8, 20, 1, '08:20', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (501, 8, 21, 1, '08:21', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (502, 8, 22, 1, '08:22', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (503, 8, 23, 1, '08:23', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (504, 8, 24, 1, '08:24', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (505, 8, 25, 1, '08:25', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (506, 8, 26, 1, '08:26', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (507, 8, 27, 1, '08:27', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (508, 8, 28, 1, '08:28', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (509, 8, 29, 1, '08:29', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (510, 8, 30, 2, '08:30', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (511, 8, 31, 2, '08:31', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (512, 8, 32, 2, '08:32', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (513, 8, 33, 2, '08:33', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (514, 8, 34, 2, '08:34', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (515, 8, 35, 2, '08:35', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (516, 8, 36, 2, '08:36', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (517, 8, 37, 2, '08:37', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (518, 8, 38, 2, '08:38', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (519, 8, 39, 2, '08:39', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (520, 8, 40, 2, '08:40', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (521, 8, 41, 2, '08:41', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (522, 8, 42, 2, '08:42', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (523, 8, 43, 2, '08:43', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (524, 8, 44, 2, '08:44', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (525, 8, 45, 3, '08:45', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (526, 8, 46, 3, '08:46', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (527, 8, 47, 3, '08:47', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (528, 8, 48, 3, '08:48', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (529, 8, 49, 3, '08:49', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (530, 8, 50, 3, '08:50', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (531, 8, 51, 3, '08:51', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (532, 8, 52, 3, '08:52', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (533, 8, 53, 3, '08:53', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (534, 8, 54, 3, '08:54', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (535, 8, 55, 3, '08:55', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (536, 8, 56, 3, '08:56', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (537, 8, 57, 3, '08:57', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (538, 8, 58, 3, '08:58', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (539, 8, 59, 3, '08:59', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (540, 9, 0, 0, '09:00', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (541, 9, 1, 0, '09:01', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (542, 9, 2, 0, '09:02', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (543, 9, 3, 0, '09:03', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (544, 9, 4, 0, '09:04', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (545, 9, 5, 0, '09:05', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (546, 9, 6, 0, '09:06', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (547, 9, 7, 0, '09:07', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (548, 9, 8, 0, '09:08', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (549, 9, 9, 0, '09:09', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (550, 9, 10, 0, '09:10', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (551, 9, 11, 0, '09:11', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (552, 9, 12, 0, '09:12', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (553, 9, 13, 0, '09:13', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (554, 9, 14, 0, '09:14', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (555, 9, 15, 1, '09:15', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (556, 9, 16, 1, '09:16', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (557, 9, 17, 1, '09:17', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (558, 9, 18, 1, '09:18', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (559, 9, 19, 1, '09:19', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (560, 9, 20, 1, '09:20', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (561, 9, 21, 1, '09:21', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (562, 9, 22, 1, '09:22', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (563, 9, 23, 1, '09:23', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (564, 9, 24, 1, '09:24', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (565, 9, 25, 1, '09:25', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (566, 9, 26, 1, '09:26', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (567, 9, 27, 1, '09:27', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (568, 9, 28, 1, '09:28', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (569, 9, 29, 1, '09:29', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (570, 9, 30, 2, '09:30', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (571, 9, 31, 2, '09:31', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (572, 9, 32, 2, '09:32', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (573, 9, 33, 2, '09:33', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (574, 9, 34, 2, '09:34', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (575, 9, 35, 2, '09:35', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (576, 9, 36, 2, '09:36', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (577, 9, 37, 2, '09:37', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (578, 9, 38, 2, '09:38', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (579, 9, 39, 2, '09:39', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (580, 9, 40, 2, '09:40', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (581, 9, 41, 2, '09:41', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (582, 9, 42, 2, '09:42', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (583, 9, 43, 2, '09:43', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (584, 9, 44, 2, '09:44', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (585, 9, 45, 3, '09:45', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (586, 9, 46, 3, '09:46', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (587, 9, 47, 3, '09:47', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (588, 9, 48, 3, '09:48', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (589, 9, 49, 3, '09:49', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (590, 9, 50, 3, '09:50', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (591, 9, 51, 3, '09:51', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (592, 9, 52, 3, '09:52', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (593, 9, 53, 3, '09:53', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (594, 9, 54, 3, '09:54', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (595, 9, 55, 3, '09:55', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (596, 9, 56, 3, '09:56', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (597, 9, 57, 3, '09:57', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (598, 9, 58, 3, '09:58', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (599, 9, 59, 3, '09:59', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (600, 10, 0, 0, '10:00', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (601, 10, 1, 0, '10:01', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (602, 10, 2, 0, '10:02', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (603, 10, 3, 0, '10:03', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (604, 10, 4, 0, '10:04', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (605, 10, 5, 0, '10:05', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (606, 10, 6, 0, '10:06', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (607, 10, 7, 0, '10:07', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (608, 10, 8, 0, '10:08', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (609, 10, 9, 0, '10:09', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (610, 10, 10, 0, '10:10', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (611, 10, 11, 0, '10:11', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (612, 10, 12, 0, '10:12', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (613, 10, 13, 0, '10:13', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (614, 10, 14, 0, '10:14', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (615, 10, 15, 1, '10:15', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (616, 10, 16, 1, '10:16', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (617, 10, 17, 1, '10:17', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (618, 10, 18, 1, '10:18', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (619, 10, 19, 1, '10:19', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (620, 10, 20, 1, '10:20', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (621, 10, 21, 1, '10:21', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (622, 10, 22, 1, '10:22', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (623, 10, 23, 1, '10:23', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (624, 10, 24, 1, '10:24', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (625, 10, 25, 1, '10:25', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (626, 10, 26, 1, '10:26', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (627, 10, 27, 1, '10:27', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (628, 10, 28, 1, '10:28', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (629, 10, 29, 1, '10:29', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (630, 10, 30, 2, '10:30', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (631, 10, 31, 2, '10:31', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (632, 10, 32, 2, '10:32', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (633, 10, 33, 2, '10:33', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (634, 10, 34, 2, '10:34', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (635, 10, 35, 2, '10:35', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (636, 10, 36, 2, '10:36', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (637, 10, 37, 2, '10:37', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (638, 10, 38, 2, '10:38', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (639, 10, 39, 2, '10:39', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (640, 10, 40, 2, '10:40', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (641, 10, 41, 2, '10:41', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (642, 10, 42, 2, '10:42', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (643, 10, 43, 2, '10:43', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (644, 10, 44, 2, '10:44', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (645, 10, 45, 3, '10:45', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (646, 10, 46, 3, '10:46', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (647, 10, 47, 3, '10:47', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (648, 10, 48, 3, '10:48', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (649, 10, 49, 3, '10:49', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (650, 10, 50, 3, '10:50', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (651, 10, 51, 3, '10:51', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (652, 10, 52, 3, '10:52', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (653, 10, 53, 3, '10:53', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (654, 10, 54, 3, '10:54', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (655, 10, 55, 3, '10:55', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (656, 10, 56, 3, '10:56', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (657, 10, 57, 3, '10:57', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (658, 10, 58, 3, '10:58', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (659, 10, 59, 3, '10:59', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (660, 11, 0, 0, '11:00', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (661, 11, 1, 0, '11:01', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (662, 11, 2, 0, '11:02', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (663, 11, 3, 0, '11:03', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (664, 11, 4, 0, '11:04', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (665, 11, 5, 0, '11:05', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (666, 11, 6, 0, '11:06', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (667, 11, 7, 0, '11:07', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (668, 11, 8, 0, '11:08', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (669, 11, 9, 0, '11:09', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (670, 11, 10, 0, '11:10', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (671, 11, 11, 0, '11:11', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (672, 11, 12, 0, '11:12', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (673, 11, 13, 0, '11:13', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (674, 11, 14, 0, '11:14', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (675, 11, 15, 1, '11:15', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (676, 11, 16, 1, '11:16', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (677, 11, 17, 1, '11:17', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (678, 11, 18, 1, '11:18', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (679, 11, 19, 1, '11:19', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (680, 11, 20, 1, '11:20', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (681, 11, 21, 1, '11:21', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (682, 11, 22, 1, '11:22', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (683, 11, 23, 1, '11:23', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (684, 11, 24, 1, '11:24', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (685, 11, 25, 1, '11:25', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (686, 11, 26, 1, '11:26', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (687, 11, 27, 1, '11:27', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (688, 11, 28, 1, '11:28', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (689, 11, 29, 1, '11:29', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (690, 11, 30, 2, '11:30', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (691, 11, 31, 2, '11:31', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (692, 11, 32, 2, '11:32', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (693, 11, 33, 2, '11:33', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (694, 11, 34, 2, '11:34', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (695, 11, 35, 2, '11:35', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (696, 11, 36, 2, '11:36', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (697, 11, 37, 2, '11:37', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (698, 11, 38, 2, '11:38', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (699, 11, 39, 2, '11:39', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (700, 11, 40, 2, '11:40', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (701, 11, 41, 2, '11:41', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (702, 11, 42, 2, '11:42', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (703, 11, 43, 2, '11:43', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (704, 11, 44, 2, '11:44', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (705, 11, 45, 3, '11:45', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (706, 11, 46, 3, '11:46', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (707, 11, 47, 3, '11:47', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (708, 11, 48, 3, '11:48', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (709, 11, 49, 3, '11:49', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (710, 11, 50, 3, '11:50', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (711, 11, 51, 3, '11:51', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (712, 11, 52, 3, '11:52', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (713, 11, 53, 3, '11:53', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (714, 11, 54, 3, '11:54', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (715, 11, 55, 3, '11:55', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (716, 11, 56, 3, '11:56', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (717, 11, 57, 3, '11:57', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (718, 11, 58, 3, '11:58', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (719, 11, 59, 3, '11:59', 'Morning');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (720, 12, 0, 0, '12:00', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (721, 12, 1, 0, '12:01', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (722, 12, 2, 0, '12:02', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (723, 12, 3, 0, '12:03', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (724, 12, 4, 0, '12:04', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (725, 12, 5, 0, '12:05', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (726, 12, 6, 0, '12:06', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (727, 12, 7, 0, '12:07', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (728, 12, 8, 0, '12:08', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (729, 12, 9, 0, '12:09', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (730, 12, 10, 0, '12:10', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (731, 12, 11, 0, '12:11', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (732, 12, 12, 0, '12:12', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (733, 12, 13, 0, '12:13', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (734, 12, 14, 0, '12:14', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (735, 12, 15, 1, '12:15', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (736, 12, 16, 1, '12:16', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (737, 12, 17, 1, '12:17', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (738, 12, 18, 1, '12:18', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (739, 12, 19, 1, '12:19', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (740, 12, 20, 1, '12:20', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (741, 12, 21, 1, '12:21', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (742, 12, 22, 1, '12:22', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (743, 12, 23, 1, '12:23', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (744, 12, 24, 1, '12:24', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (745, 12, 25, 1, '12:25', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (746, 12, 26, 1, '12:26', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (747, 12, 27, 1, '12:27', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (748, 12, 28, 1, '12:28', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (749, 12, 29, 1, '12:29', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (750, 12, 30, 2, '12:30', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (751, 12, 31, 2, '12:31', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (752, 12, 32, 2, '12:32', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (753, 12, 33, 2, '12:33', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (754, 12, 34, 2, '12:34', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (755, 12, 35, 2, '12:35', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (756, 12, 36, 2, '12:36', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (757, 12, 37, 2, '12:37', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (758, 12, 38, 2, '12:38', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (759, 12, 39, 2, '12:39', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (760, 12, 40, 2, '12:40', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (761, 12, 41, 2, '12:41', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (762, 12, 42, 2, '12:42', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (763, 12, 43, 2, '12:43', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (764, 12, 44, 2, '12:44', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (765, 12, 45, 3, '12:45', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (766, 12, 46, 3, '12:46', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (767, 12, 47, 3, '12:47', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (768, 12, 48, 3, '12:48', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (769, 12, 49, 3, '12:49', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (770, 12, 50, 3, '12:50', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (771, 12, 51, 3, '12:51', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (772, 12, 52, 3, '12:52', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (773, 12, 53, 3, '12:53', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (774, 12, 54, 3, '12:54', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (775, 12, 55, 3, '12:55', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (776, 12, 56, 3, '12:56', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (777, 12, 57, 3, '12:57', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (778, 12, 58, 3, '12:58', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (779, 12, 59, 3, '12:59', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (780, 13, 0, 0, '13:00', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (781, 13, 1, 0, '13:01', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (782, 13, 2, 0, '13:02', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (783, 13, 3, 0, '13:03', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (784, 13, 4, 0, '13:04', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (785, 13, 5, 0, '13:05', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (786, 13, 6, 0, '13:06', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (787, 13, 7, 0, '13:07', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (788, 13, 8, 0, '13:08', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (789, 13, 9, 0, '13:09', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (790, 13, 10, 0, '13:10', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (791, 13, 11, 0, '13:11', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (792, 13, 12, 0, '13:12', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (793, 13, 13, 0, '13:13', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (794, 13, 14, 0, '13:14', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (795, 13, 15, 1, '13:15', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (796, 13, 16, 1, '13:16', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (797, 13, 17, 1, '13:17', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (798, 13, 18, 1, '13:18', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (799, 13, 19, 1, '13:19', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (800, 13, 20, 1, '13:20', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (801, 13, 21, 1, '13:21', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (802, 13, 22, 1, '13:22', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (803, 13, 23, 1, '13:23', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (804, 13, 24, 1, '13:24', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (805, 13, 25, 1, '13:25', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (806, 13, 26, 1, '13:26', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (807, 13, 27, 1, '13:27', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (808, 13, 28, 1, '13:28', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (809, 13, 29, 1, '13:29', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (810, 13, 30, 2, '13:30', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (811, 13, 31, 2, '13:31', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (812, 13, 32, 2, '13:32', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (813, 13, 33, 2, '13:33', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (814, 13, 34, 2, '13:34', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (815, 13, 35, 2, '13:35', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (816, 13, 36, 2, '13:36', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (817, 13, 37, 2, '13:37', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (818, 13, 38, 2, '13:38', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (819, 13, 39, 2, '13:39', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (820, 13, 40, 2, '13:40', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (821, 13, 41, 2, '13:41', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (822, 13, 42, 2, '13:42', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (823, 13, 43, 2, '13:43', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (824, 13, 44, 2, '13:44', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (825, 13, 45, 3, '13:45', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (826, 13, 46, 3, '13:46', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (827, 13, 47, 3, '13:47', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (828, 13, 48, 3, '13:48', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (829, 13, 49, 3, '13:49', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (830, 13, 50, 3, '13:50', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (831, 13, 51, 3, '13:51', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (832, 13, 52, 3, '13:52', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (833, 13, 53, 3, '13:53', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (834, 13, 54, 3, '13:54', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (835, 13, 55, 3, '13:55', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (836, 13, 56, 3, '13:56', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (837, 13, 57, 3, '13:57', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (838, 13, 58, 3, '13:58', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (839, 13, 59, 3, '13:59', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (840, 14, 0, 0, '14:00', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (841, 14, 1, 0, '14:01', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (842, 14, 2, 0, '14:02', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (843, 14, 3, 0, '14:03', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (844, 14, 4, 0, '14:04', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (845, 14, 5, 0, '14:05', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (846, 14, 6, 0, '14:06', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (847, 14, 7, 0, '14:07', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (848, 14, 8, 0, '14:08', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (849, 14, 9, 0, '14:09', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (850, 14, 10, 0, '14:10', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (851, 14, 11, 0, '14:11', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (852, 14, 12, 0, '14:12', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (853, 14, 13, 0, '14:13', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (854, 14, 14, 0, '14:14', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (855, 14, 15, 1, '14:15', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (856, 14, 16, 1, '14:16', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (857, 14, 17, 1, '14:17', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (858, 14, 18, 1, '14:18', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (859, 14, 19, 1, '14:19', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (860, 14, 20, 1, '14:20', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (861, 14, 21, 1, '14:21', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (862, 14, 22, 1, '14:22', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (863, 14, 23, 1, '14:23', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (864, 14, 24, 1, '14:24', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (865, 14, 25, 1, '14:25', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (866, 14, 26, 1, '14:26', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (867, 14, 27, 1, '14:27', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (868, 14, 28, 1, '14:28', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (869, 14, 29, 1, '14:29', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (870, 14, 30, 2, '14:30', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (871, 14, 31, 2, '14:31', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (872, 14, 32, 2, '14:32', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (873, 14, 33, 2, '14:33', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (874, 14, 34, 2, '14:34', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (875, 14, 35, 2, '14:35', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (876, 14, 36, 2, '14:36', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (877, 14, 37, 2, '14:37', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (878, 14, 38, 2, '14:38', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (879, 14, 39, 2, '14:39', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (880, 14, 40, 2, '14:40', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (881, 14, 41, 2, '14:41', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (882, 14, 42, 2, '14:42', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (883, 14, 43, 2, '14:43', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (884, 14, 44, 2, '14:44', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (885, 14, 45, 3, '14:45', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (886, 14, 46, 3, '14:46', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (887, 14, 47, 3, '14:47', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (888, 14, 48, 3, '14:48', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (889, 14, 49, 3, '14:49', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (890, 14, 50, 3, '14:50', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (891, 14, 51, 3, '14:51', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (892, 14, 52, 3, '14:52', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (893, 14, 53, 3, '14:53', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (894, 14, 54, 3, '14:54', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (895, 14, 55, 3, '14:55', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (896, 14, 56, 3, '14:56', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (897, 14, 57, 3, '14:57', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (898, 14, 58, 3, '14:58', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (899, 14, 59, 3, '14:59', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (900, 15, 0, 0, '15:00', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (901, 15, 1, 0, '15:01', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (902, 15, 2, 0, '15:02', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (903, 15, 3, 0, '15:03', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (904, 15, 4, 0, '15:04', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (905, 15, 5, 0, '15:05', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (906, 15, 6, 0, '15:06', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (907, 15, 7, 0, '15:07', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (908, 15, 8, 0, '15:08', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (909, 15, 9, 0, '15:09', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (910, 15, 10, 0, '15:10', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (911, 15, 11, 0, '15:11', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (912, 15, 12, 0, '15:12', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (913, 15, 13, 0, '15:13', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (914, 15, 14, 0, '15:14', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (915, 15, 15, 1, '15:15', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (916, 15, 16, 1, '15:16', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (917, 15, 17, 1, '15:17', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (918, 15, 18, 1, '15:18', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (919, 15, 19, 1, '15:19', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (920, 15, 20, 1, '15:20', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (921, 15, 21, 1, '15:21', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (922, 15, 22, 1, '15:22', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (923, 15, 23, 1, '15:23', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (924, 15, 24, 1, '15:24', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (925, 15, 25, 1, '15:25', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (926, 15, 26, 1, '15:26', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (927, 15, 27, 1, '15:27', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (928, 15, 28, 1, '15:28', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (929, 15, 29, 1, '15:29', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (930, 15, 30, 2, '15:30', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (931, 15, 31, 2, '15:31', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (932, 15, 32, 2, '15:32', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (933, 15, 33, 2, '15:33', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (934, 15, 34, 2, '15:34', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (935, 15, 35, 2, '15:35', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (936, 15, 36, 2, '15:36', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (937, 15, 37, 2, '15:37', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (938, 15, 38, 2, '15:38', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (939, 15, 39, 2, '15:39', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (940, 15, 40, 2, '15:40', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (941, 15, 41, 2, '15:41', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (942, 15, 42, 2, '15:42', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (943, 15, 43, 2, '15:43', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (944, 15, 44, 2, '15:44', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (945, 15, 45, 3, '15:45', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (946, 15, 46, 3, '15:46', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (947, 15, 47, 3, '15:47', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (948, 15, 48, 3, '15:48', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (949, 15, 49, 3, '15:49', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (950, 15, 50, 3, '15:50', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (951, 15, 51, 3, '15:51', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (952, 15, 52, 3, '15:52', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (953, 15, 53, 3, '15:53', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (954, 15, 54, 3, '15:54', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (955, 15, 55, 3, '15:55', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (956, 15, 56, 3, '15:56', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (957, 15, 57, 3, '15:57', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (958, 15, 58, 3, '15:58', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (959, 15, 59, 3, '15:59', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (960, 16, 0, 0, '16:00', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (961, 16, 1, 0, '16:01', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (962, 16, 2, 0, '16:02', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (963, 16, 3, 0, '16:03', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (964, 16, 4, 0, '16:04', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (965, 16, 5, 0, '16:05', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (966, 16, 6, 0, '16:06', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (967, 16, 7, 0, '16:07', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (968, 16, 8, 0, '16:08', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (969, 16, 9, 0, '16:09', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (970, 16, 10, 0, '16:10', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (971, 16, 11, 0, '16:11', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (972, 16, 12, 0, '16:12', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (973, 16, 13, 0, '16:13', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (974, 16, 14, 0, '16:14', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (975, 16, 15, 1, '16:15', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (976, 16, 16, 1, '16:16', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (977, 16, 17, 1, '16:17', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (978, 16, 18, 1, '16:18', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (979, 16, 19, 1, '16:19', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (980, 16, 20, 1, '16:20', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (981, 16, 21, 1, '16:21', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (982, 16, 22, 1, '16:22', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (983, 16, 23, 1, '16:23', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (984, 16, 24, 1, '16:24', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (985, 16, 25, 1, '16:25', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (986, 16, 26, 1, '16:26', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (987, 16, 27, 1, '16:27', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (988, 16, 28, 1, '16:28', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (989, 16, 29, 1, '16:29', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (990, 16, 30, 2, '16:30', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (991, 16, 31, 2, '16:31', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (992, 16, 32, 2, '16:32', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (993, 16, 33, 2, '16:33', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (994, 16, 34, 2, '16:34', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (995, 16, 35, 2, '16:35', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (996, 16, 36, 2, '16:36', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (997, 16, 37, 2, '16:37', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (998, 16, 38, 2, '16:38', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (999, 16, 39, 2, '16:39', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1000, 16, 40, 2, '16:40', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1001, 16, 41, 2, '16:41', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1002, 16, 42, 2, '16:42', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1003, 16, 43, 2, '16:43', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1004, 16, 44, 2, '16:44', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1005, 16, 45, 3, '16:45', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1006, 16, 46, 3, '16:46', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1007, 16, 47, 3, '16:47', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1008, 16, 48, 3, '16:48', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1009, 16, 49, 3, '16:49', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1010, 16, 50, 3, '16:50', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1011, 16, 51, 3, '16:51', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1012, 16, 52, 3, '16:52', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1013, 16, 53, 3, '16:53', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1014, 16, 54, 3, '16:54', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1015, 16, 55, 3, '16:55', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1016, 16, 56, 3, '16:56', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1017, 16, 57, 3, '16:57', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1018, 16, 58, 3, '16:58', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1019, 16, 59, 3, '16:59', 'Afternoon');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1020, 17, 0, 0, '17:00', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1021, 17, 1, 0, '17:01', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1022, 17, 2, 0, '17:02', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1023, 17, 3, 0, '17:03', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1024, 17, 4, 0, '17:04', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1025, 17, 5, 0, '17:05', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1026, 17, 6, 0, '17:06', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1027, 17, 7, 0, '17:07', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1028, 17, 8, 0, '17:08', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1029, 17, 9, 0, '17:09', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1030, 17, 10, 0, '17:10', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1031, 17, 11, 0, '17:11', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1032, 17, 12, 0, '17:12', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1033, 17, 13, 0, '17:13', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1034, 17, 14, 0, '17:14', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1035, 17, 15, 1, '17:15', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1036, 17, 16, 1, '17:16', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1037, 17, 17, 1, '17:17', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1038, 17, 18, 1, '17:18', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1039, 17, 19, 1, '17:19', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1040, 17, 20, 1, '17:20', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1041, 17, 21, 1, '17:21', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1042, 17, 22, 1, '17:22', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1043, 17, 23, 1, '17:23', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1044, 17, 24, 1, '17:24', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1045, 17, 25, 1, '17:25', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1046, 17, 26, 1, '17:26', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1047, 17, 27, 1, '17:27', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1048, 17, 28, 1, '17:28', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1049, 17, 29, 1, '17:29', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1050, 17, 30, 2, '17:30', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1051, 17, 31, 2, '17:31', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1052, 17, 32, 2, '17:32', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1053, 17, 33, 2, '17:33', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1054, 17, 34, 2, '17:34', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1055, 17, 35, 2, '17:35', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1056, 17, 36, 2, '17:36', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1057, 17, 37, 2, '17:37', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1058, 17, 38, 2, '17:38', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1059, 17, 39, 2, '17:39', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1060, 17, 40, 2, '17:40', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1061, 17, 41, 2, '17:41', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1062, 17, 42, 2, '17:42', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1063, 17, 43, 2, '17:43', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1064, 17, 44, 2, '17:44', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1065, 17, 45, 3, '17:45', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1066, 17, 46, 3, '17:46', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1067, 17, 47, 3, '17:47', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1068, 17, 48, 3, '17:48', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1069, 17, 49, 3, '17:49', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1070, 17, 50, 3, '17:50', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1071, 17, 51, 3, '17:51', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1072, 17, 52, 3, '17:52', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1073, 17, 53, 3, '17:53', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1074, 17, 54, 3, '17:54', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1075, 17, 55, 3, '17:55', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1076, 17, 56, 3, '17:56', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1077, 17, 57, 3, '17:57', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1078, 17, 58, 3, '17:58', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1079, 17, 59, 3, '17:59', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1080, 18, 0, 0, '18:00', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1081, 18, 1, 0, '18:01', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1082, 18, 2, 0, '18:02', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1083, 18, 3, 0, '18:03', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1084, 18, 4, 0, '18:04', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1085, 18, 5, 0, '18:05', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1086, 18, 6, 0, '18:06', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1087, 18, 7, 0, '18:07', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1088, 18, 8, 0, '18:08', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1089, 18, 9, 0, '18:09', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1090, 18, 10, 0, '18:10', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1091, 18, 11, 0, '18:11', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1092, 18, 12, 0, '18:12', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1093, 18, 13, 0, '18:13', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1094, 18, 14, 0, '18:14', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1095, 18, 15, 1, '18:15', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1096, 18, 16, 1, '18:16', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1097, 18, 17, 1, '18:17', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1098, 18, 18, 1, '18:18', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1099, 18, 19, 1, '18:19', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1100, 18, 20, 1, '18:20', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1101, 18, 21, 1, '18:21', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1102, 18, 22, 1, '18:22', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1103, 18, 23, 1, '18:23', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1104, 18, 24, 1, '18:24', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1105, 18, 25, 1, '18:25', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1106, 18, 26, 1, '18:26', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1107, 18, 27, 1, '18:27', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1108, 18, 28, 1, '18:28', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1109, 18, 29, 1, '18:29', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1110, 18, 30, 2, '18:30', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1111, 18, 31, 2, '18:31', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1112, 18, 32, 2, '18:32', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1113, 18, 33, 2, '18:33', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1114, 18, 34, 2, '18:34', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1115, 18, 35, 2, '18:35', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1116, 18, 36, 2, '18:36', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1117, 18, 37, 2, '18:37', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1118, 18, 38, 2, '18:38', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1119, 18, 39, 2, '18:39', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1120, 18, 40, 2, '18:40', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1121, 18, 41, 2, '18:41', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1122, 18, 42, 2, '18:42', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1123, 18, 43, 2, '18:43', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1124, 18, 44, 2, '18:44', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1125, 18, 45, 3, '18:45', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1126, 18, 46, 3, '18:46', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1127, 18, 47, 3, '18:47', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1128, 18, 48, 3, '18:48', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1129, 18, 49, 3, '18:49', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1130, 18, 50, 3, '18:50', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1131, 18, 51, 3, '18:51', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1132, 18, 52, 3, '18:52', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1133, 18, 53, 3, '18:53', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1134, 18, 54, 3, '18:54', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1135, 18, 55, 3, '18:55', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1136, 18, 56, 3, '18:56', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1137, 18, 57, 3, '18:57', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1138, 18, 58, 3, '18:58', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1139, 18, 59, 3, '18:59', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1140, 19, 0, 0, '19:00', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1141, 19, 1, 0, '19:01', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1142, 19, 2, 0, '19:02', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1143, 19, 3, 0, '19:03', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1144, 19, 4, 0, '19:04', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1145, 19, 5, 0, '19:05', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1146, 19, 6, 0, '19:06', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1147, 19, 7, 0, '19:07', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1148, 19, 8, 0, '19:08', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1149, 19, 9, 0, '19:09', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1150, 19, 10, 0, '19:10', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1151, 19, 11, 0, '19:11', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1152, 19, 12, 0, '19:12', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1153, 19, 13, 0, '19:13', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1154, 19, 14, 0, '19:14', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1155, 19, 15, 1, '19:15', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1156, 19, 16, 1, '19:16', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1157, 19, 17, 1, '19:17', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1158, 19, 18, 1, '19:18', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1159, 19, 19, 1, '19:19', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1160, 19, 20, 1, '19:20', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1161, 19, 21, 1, '19:21', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1162, 19, 22, 1, '19:22', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1163, 19, 23, 1, '19:23', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1164, 19, 24, 1, '19:24', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1165, 19, 25, 1, '19:25', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1166, 19, 26, 1, '19:26', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1167, 19, 27, 1, '19:27', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1168, 19, 28, 1, '19:28', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1169, 19, 29, 1, '19:29', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1170, 19, 30, 2, '19:30', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1171, 19, 31, 2, '19:31', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1172, 19, 32, 2, '19:32', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1173, 19, 33, 2, '19:33', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1174, 19, 34, 2, '19:34', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1175, 19, 35, 2, '19:35', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1176, 19, 36, 2, '19:36', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1177, 19, 37, 2, '19:37', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1178, 19, 38, 2, '19:38', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1179, 19, 39, 2, '19:39', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1180, 19, 40, 2, '19:40', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1181, 19, 41, 2, '19:41', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1182, 19, 42, 2, '19:42', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1183, 19, 43, 2, '19:43', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1184, 19, 44, 2, '19:44', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1185, 19, 45, 3, '19:45', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1186, 19, 46, 3, '19:46', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1187, 19, 47, 3, '19:47', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1188, 19, 48, 3, '19:48', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1189, 19, 49, 3, '19:49', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1190, 19, 50, 3, '19:50', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1191, 19, 51, 3, '19:51', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1192, 19, 52, 3, '19:52', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1193, 19, 53, 3, '19:53', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1194, 19, 54, 3, '19:54', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1195, 19, 55, 3, '19:55', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1196, 19, 56, 3, '19:56', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1197, 19, 57, 3, '19:57', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1198, 19, 58, 3, '19:58', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1199, 19, 59, 3, '19:59', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1200, 20, 0, 0, '20:00', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1201, 20, 1, 0, '20:01', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1202, 20, 2, 0, '20:02', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1203, 20, 3, 0, '20:03', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1204, 20, 4, 0, '20:04', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1205, 20, 5, 0, '20:05', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1206, 20, 6, 0, '20:06', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1207, 20, 7, 0, '20:07', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1208, 20, 8, 0, '20:08', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1209, 20, 9, 0, '20:09', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1210, 20, 10, 0, '20:10', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1211, 20, 11, 0, '20:11', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1212, 20, 12, 0, '20:12', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1213, 20, 13, 0, '20:13', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1214, 20, 14, 0, '20:14', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1215, 20, 15, 1, '20:15', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1216, 20, 16, 1, '20:16', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1217, 20, 17, 1, '20:17', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1218, 20, 18, 1, '20:18', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1219, 20, 19, 1, '20:19', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1220, 20, 20, 1, '20:20', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1221, 20, 21, 1, '20:21', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1222, 20, 22, 1, '20:22', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1223, 20, 23, 1, '20:23', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1224, 20, 24, 1, '20:24', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1225, 20, 25, 1, '20:25', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1226, 20, 26, 1, '20:26', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1227, 20, 27, 1, '20:27', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1228, 20, 28, 1, '20:28', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1229, 20, 29, 1, '20:29', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1230, 20, 30, 2, '20:30', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1231, 20, 31, 2, '20:31', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1232, 20, 32, 2, '20:32', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1233, 20, 33, 2, '20:33', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1234, 20, 34, 2, '20:34', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1235, 20, 35, 2, '20:35', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1236, 20, 36, 2, '20:36', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1237, 20, 37, 2, '20:37', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1238, 20, 38, 2, '20:38', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1239, 20, 39, 2, '20:39', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1240, 20, 40, 2, '20:40', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1241, 20, 41, 2, '20:41', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1242, 20, 42, 2, '20:42', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1243, 20, 43, 2, '20:43', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1244, 20, 44, 2, '20:44', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1245, 20, 45, 3, '20:45', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1246, 20, 46, 3, '20:46', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1247, 20, 47, 3, '20:47', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1248, 20, 48, 3, '20:48', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1249, 20, 49, 3, '20:49', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1250, 20, 50, 3, '20:50', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1251, 20, 51, 3, '20:51', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1252, 20, 52, 3, '20:52', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1253, 20, 53, 3, '20:53', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1254, 20, 54, 3, '20:54', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1255, 20, 55, 3, '20:55', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1256, 20, 56, 3, '20:56', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1257, 20, 57, 3, '20:57', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1258, 20, 58, 3, '20:58', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1259, 20, 59, 3, '20:59', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1260, 21, 0, 0, '21:00', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1261, 21, 1, 0, '21:01', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1262, 21, 2, 0, '21:02', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1263, 21, 3, 0, '21:03', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1264, 21, 4, 0, '21:04', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1265, 21, 5, 0, '21:05', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1266, 21, 6, 0, '21:06', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1267, 21, 7, 0, '21:07', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1268, 21, 8, 0, '21:08', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1269, 21, 9, 0, '21:09', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1270, 21, 10, 0, '21:10', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1271, 21, 11, 0, '21:11', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1272, 21, 12, 0, '21:12', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1273, 21, 13, 0, '21:13', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1274, 21, 14, 0, '21:14', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1275, 21, 15, 1, '21:15', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1276, 21, 16, 1, '21:16', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1277, 21, 17, 1, '21:17', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1278, 21, 18, 1, '21:18', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1279, 21, 19, 1, '21:19', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1280, 21, 20, 1, '21:20', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1281, 21, 21, 1, '21:21', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1282, 21, 22, 1, '21:22', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1283, 21, 23, 1, '21:23', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1284, 21, 24, 1, '21:24', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1285, 21, 25, 1, '21:25', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1286, 21, 26, 1, '21:26', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1287, 21, 27, 1, '21:27', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1288, 21, 28, 1, '21:28', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1289, 21, 29, 1, '21:29', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1290, 21, 30, 2, '21:30', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1291, 21, 31, 2, '21:31', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1292, 21, 32, 2, '21:32', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1293, 21, 33, 2, '21:33', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1294, 21, 34, 2, '21:34', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1295, 21, 35, 2, '21:35', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1296, 21, 36, 2, '21:36', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1297, 21, 37, 2, '21:37', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1298, 21, 38, 2, '21:38', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1299, 21, 39, 2, '21:39', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1300, 21, 40, 2, '21:40', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1301, 21, 41, 2, '21:41', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1302, 21, 42, 2, '21:42', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1303, 21, 43, 2, '21:43', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1304, 21, 44, 2, '21:44', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1305, 21, 45, 3, '21:45', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1306, 21, 46, 3, '21:46', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1307, 21, 47, 3, '21:47', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1308, 21, 48, 3, '21:48', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1309, 21, 49, 3, '21:49', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1310, 21, 50, 3, '21:50', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1311, 21, 51, 3, '21:51', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1312, 21, 52, 3, '21:52', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1313, 21, 53, 3, '21:53', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1314, 21, 54, 3, '21:54', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1315, 21, 55, 3, '21:55', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1316, 21, 56, 3, '21:56', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1317, 21, 57, 3, '21:57', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1318, 21, 58, 3, '21:58', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1319, 21, 59, 3, '21:59', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1320, 22, 0, 0, '22:00', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1321, 22, 1, 0, '22:01', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1322, 22, 2, 0, '22:02', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1323, 22, 3, 0, '22:03', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1324, 22, 4, 0, '22:04', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1325, 22, 5, 0, '22:05', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1326, 22, 6, 0, '22:06', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1327, 22, 7, 0, '22:07', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1328, 22, 8, 0, '22:08', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1329, 22, 9, 0, '22:09', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1330, 22, 10, 0, '22:10', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1331, 22, 11, 0, '22:11', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1332, 22, 12, 0, '22:12', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1333, 22, 13, 0, '22:13', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1334, 22, 14, 0, '22:14', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1335, 22, 15, 1, '22:15', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1336, 22, 16, 1, '22:16', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1337, 22, 17, 1, '22:17', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1338, 22, 18, 1, '22:18', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1339, 22, 19, 1, '22:19', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1340, 22, 20, 1, '22:20', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1341, 22, 21, 1, '22:21', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1342, 22, 22, 1, '22:22', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1343, 22, 23, 1, '22:23', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1344, 22, 24, 1, '22:24', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1345, 22, 25, 1, '22:25', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1346, 22, 26, 1, '22:26', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1347, 22, 27, 1, '22:27', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1348, 22, 28, 1, '22:28', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1349, 22, 29, 1, '22:29', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1350, 22, 30, 2, '22:30', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1351, 22, 31, 2, '22:31', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1352, 22, 32, 2, '22:32', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1353, 22, 33, 2, '22:33', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1354, 22, 34, 2, '22:34', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1355, 22, 35, 2, '22:35', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1356, 22, 36, 2, '22:36', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1357, 22, 37, 2, '22:37', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1358, 22, 38, 2, '22:38', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1359, 22, 39, 2, '22:39', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1360, 22, 40, 2, '22:40', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1361, 22, 41, 2, '22:41', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1362, 22, 42, 2, '22:42', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1363, 22, 43, 2, '22:43', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1364, 22, 44, 2, '22:44', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1365, 22, 45, 3, '22:45', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1366, 22, 46, 3, '22:46', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1367, 22, 47, 3, '22:47', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1368, 22, 48, 3, '22:48', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1369, 22, 49, 3, '22:49', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1370, 22, 50, 3, '22:50', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1371, 22, 51, 3, '22:51', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1372, 22, 52, 3, '22:52', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1373, 22, 53, 3, '22:53', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1374, 22, 54, 3, '22:54', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1375, 22, 55, 3, '22:55', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1376, 22, 56, 3, '22:56', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1377, 22, 57, 3, '22:57', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1378, 22, 58, 3, '22:58', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1379, 22, 59, 3, '22:59', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1380, 23, 0, 0, '23:00', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1381, 23, 1, 0, '23:01', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1382, 23, 2, 0, '23:02', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1383, 23, 3, 0, '23:03', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1384, 23, 4, 0, '23:04', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1385, 23, 5, 0, '23:05', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1386, 23, 6, 0, '23:06', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1387, 23, 7, 0, '23:07', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1388, 23, 8, 0, '23:08', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1389, 23, 9, 0, '23:09', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1390, 23, 10, 0, '23:10', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1391, 23, 11, 0, '23:11', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1392, 23, 12, 0, '23:12', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1393, 23, 13, 0, '23:13', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1394, 23, 14, 0, '23:14', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1395, 23, 15, 1, '23:15', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1396, 23, 16, 1, '23:16', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1397, 23, 17, 1, '23:17', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1398, 23, 18, 1, '23:18', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1399, 23, 19, 1, '23:19', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1400, 23, 20, 1, '23:20', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1401, 23, 21, 1, '23:21', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1402, 23, 22, 1, '23:22', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1403, 23, 23, 1, '23:23', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1404, 23, 24, 1, '23:24', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1405, 23, 25, 1, '23:25', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1406, 23, 26, 1, '23:26', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1407, 23, 27, 1, '23:27', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1408, 23, 28, 1, '23:28', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1409, 23, 29, 1, '23:29', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1410, 23, 30, 2, '23:30', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1411, 23, 31, 2, '23:31', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1412, 23, 32, 2, '23:32', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1413, 23, 33, 2, '23:33', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1414, 23, 34, 2, '23:34', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1415, 23, 35, 2, '23:35', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1416, 23, 36, 2, '23:36', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1417, 23, 37, 2, '23:37', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1418, 23, 38, 2, '23:38', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1419, 23, 39, 2, '23:39', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1420, 23, 40, 2, '23:40', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1421, 23, 41, 2, '23:41', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1422, 23, 42, 2, '23:42', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1423, 23, 43, 2, '23:43', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1424, 23, 44, 2, '23:44', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1425, 23, 45, 3, '23:45', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1426, 23, 46, 3, '23:46', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1427, 23, 47, 3, '23:47', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1428, 23, 48, 3, '23:48', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1429, 23, 49, 3, '23:49', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1430, 23, 50, 3, '23:50', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1431, 23, 51, 3, '23:51', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1432, 23, 52, 3, '23:52', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1433, 23, 53, 3, '23:53', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1434, 23, 54, 3, '23:54', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1435, 23, 55, 3, '23:55', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1436, 23, 56, 3, '23:56', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1437, 23, 57, 3, '23:57', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1438, 23, 58, 3, '23:58', 'Evening');

INSERT INTO warehouse.dim_time (time_key, hour, minute, quarter_hour, hour_label, daypart)
            VALUES (1439, 23, 59, 3, '23:59', 'Evening');

INSERT INTO warehouse.dim_taxi_zone (surrogate_key, business_key, label, observed_from, is_current)
            VALUES (0, 0, 'Unknown', '1970-01-01 00:00:00+00', TRUE);

INSERT INTO warehouse.dim_payment_type (surrogate_key, business_key, label, observed_from, is_current)
            VALUES (0, 0, 'Unknown', '1970-01-01 00:00:00+00', TRUE);

INSERT INTO warehouse.dim_vendor (surrogate_key, business_key, label, observed_from, is_current)
            VALUES (0, 0, 'Unknown', '1970-01-01 00:00:00+00', TRUE);

INSERT INTO warehouse.dim_rate_code (surrogate_key, business_key, label, observed_from, is_current)
            VALUES (0, 0, 'Unknown', '1970-01-01 00:00:00+00', TRUE);

INSERT INTO alembic_version (version_num) VALUES ('0001') RETURNING alembic_version.version_num;

COMMIT;
