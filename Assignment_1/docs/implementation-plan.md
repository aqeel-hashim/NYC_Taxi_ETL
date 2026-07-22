# Assignment 1 Implementation Plan

Status: Phases 0-4 pass. Phases 5-14 active.

This plan is executable guidance, not evidence that commands or files already exist. Implement phases in order. Do not claim a command works until its phase creates and verifies it. Stop on failed gates; fix the failing layer before continuing.

## 1. Mission And Done State

Build a reproducible batch platform for NYC Yellow Taxi data that:

- Downloads January and February 2023 Parquet records from the official TLC CloudFront source using `curl`.
- Runs Apache Airflow with KubernetesExecutor on a local kind cluster.
- Transforms data with Polars, loads a PostgreSQL star schema, and publishes an aggregate analytics mart.
- Calculates average fare per mile, peak pickup hours, and gross revenue by payment type.
- Serves an executive Streamlit/Plotly dashboard plus a bounded-memory trip explorer.
- Captures structured logs, run/row metadata, data-quality results, metrics, traces of alerts, email alerts, and webhook alerts.
- Proves rerun idempotency, controlled failure alerting, and PostgreSQL backup/restore.
- Supplies deployable, guarded AWS Terraform for the EKS production path.

Definition of done:

- `./setup.sh` takes a supported clean Linux or WSL2 host from validated prerequisites to loaded data and usable UIs.
- Host with Docker memory below 8 GiB automatically uses staged mode; 8 GiB or more and at least 4 CPUs uses concurrent mode.
- Small PC full two-month run targets 45 minutes without OOM on its known 4 CPU/3.8 GiB host. Phase 11 must measure complete stack before converting this target into a release gate; if impossible, use documented stage-by-stage proof instead of claiming success. Big PC gets separate benchmark evidence.
- Rerunning either month changes no business result and creates no duplicate fact rows.
- Fact-row counts satisfy `source_rows = accepted_rows + rejected_rows`, `flagged_rows <= accepted_rows`, and `staged_fact_rows = loaded_fact_rows = published_fact_rows = accepted_rows` for each source version. Dimension/mart counts use separate names.
- Cached dashboard requests target under 1 second; uncached aggregate and trip-page requests target two-second end-to-end p95. Record Small PC and Big PC separately. Phase 10 must record test conditions before making these release gates.
- Required SQL files execute against published data and match dashboard values.
- Controlled failure reaches Airflow state/logs, local webhook receiver, Mailpit, Prometheus/Alertmanager, and Grafana/Loki evidence.
- Local backup restore recreates fixture data and passes row-count/checksum checks.
- Static checks, all automated non-kind tests, and 85% aggregate branch coverage pass before every commit.
- Release branches additionally pass kind, OIDC, Playwright, failure-drill, and backup/restore smoke checks.
- Terraform passes formatting, validation, tests, lint, security, cost, and speculative-plan gates.
- Assignment requirements and all agreed assumptions are documented.

## 2. Fixed Decisions

Do not replace these choices without user approval and an ADR update.

### Data And Analytics

- Default source months: `2023-01`, `2023-02`.
- Direct URL template: `https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_YYYY-MM.parquet`.
- Transform engine: Polars, using bounded-memory/streaming execution.
- Raw/reference/checkpoint/quarantine object store: local MinIO; AWS S3 in production.
- Warehouse: PostgreSQL through CloudNativePG locally; Aurora PostgreSQL in AWS.
- Batch grain: one Airflow DAG run per calendar month.
- Schedule: 06:00 UTC on day 5 monthly, processing the calendar month ending two months earlier.
- Source sensor: hourly reschedule, maximum seven days, then fail and alert.
- Hard rejects go to partitioned Parquet quarantine in MinIO; PostgreSQL stores manifests and summaries.
- Statistical outliers stay in the fact with `has_statistical_outlier = true`; `has_quality_issue` covers any flag. Sparse issue rows retain reasons.
- Outlier algorithm: Apache DataSketches KLL, `k=4096`, lower/upper 0.1% tails.
- Initial threshold version: combined January-February 2023 calibration.
- Production recalibration: quarterly candidate from trailing 12 complete months; activation requires review.
- Financial/unit metrics exclude statistical outliers by default; unknown references and other non-statistical flags remain included. UI provides include-outliers toggle.
- Demand volume includes all hard-valid trips; quality views always expose flagged/rejected counts.
- Monetary values use integer cents. Distance uses integer thousandths of a mile. Duration uses integer seconds.
- Trip timestamps preserve source wall time and are documented as `America/New_York`; do not fabricate UTC offsets.

### Star Schema

- Six dimensions: date, time, taxi zone, payment type, vendor, rate code.
- Pickup/dropoff reuse date, time, and taxi-zone dimensions as role-playing dimensions.
- Date key: `YYYYMMDD`. Time key: minute-of-day `0..1439`.
- Other dimensions use integer surrogate keys; key `0` means Unknown.
- Zone/payment/vendor/rate dimensions use ingestion-time SCD2.
- SCD2 columns use `observed_from`/`observed_to`, never misleading `effective_*` names.
- Every monthly partition pins its reference snapshot; reruns reuse that snapshot unless explicit re-enrichment is requested.
- Fact identity: surrogate `trip_key` plus unique source object version and source row number.
- Fact table uses monthly PostgreSQL range partitions by pickup date.
- Dashboard reads an incrementally rebuilt monthly aggregate mart, not repeated full fact scans.

### Platform

- Python: repo-managed CPython 3.12 through repo-local `uv`; host Python 3.14 is not used for project execution.
- Dependency source: `pyproject.toml` and committed `uv.lock`.
- Airflow runtime: official pinned image, KubernetesExecutor, official Helm chart, DAGs baked into immutable image.
- Local cluster: kind with Calico; five namespaces: `ingress`, `identity`, `monitoring`, `data-platform`, `taxi-app`.
- Release packaging: separate Airflow/ETL, Streamlit, and webhook receiver images; `amd64` and `arm64` release manifests.
- Release orchestration: pinned Helmfile and pinned Helm chart/image digests.
- PostgreSQL: one local CloudNativePG instance with separate Airflow metadata and warehouse databases.
- Connection control: CloudNativePG PgBouncer pools; migrations and partition publication use direct writer service.
- Object storage: host-persisted MinIO data mapped into kind; versioned buckets and checksum-addressed write-once keys.
- Ingress: Traefik at host ports `8080`/`8443`.
- Local hostnames: `*.taxi.localhost`; CoreDNS resolves the same names internally for OIDC issuer consistency.
- TLS: repo-local `mkcert`; setup asks before installing its CA into host trust.
- Identity: Dex plus oauth2-proxy; generated admin and viewer users.
- Email: Mailpit locally, optional external SMTP relay.
- Webhook: small local FastAPI receiver, persisted alert metadata, JSON logs.
- Monitoring: full kube-prometheus-stack, Grafana, Alertmanager, exporters, Pushgateway.
- Metrics retention: 14 days; local storage receives an explicit 5 GiB PVC quota; 30-second scrape; high-cardinality labels dropped.
- Logs: JSON standard logging with `python-json-logger`; Airflow remote task logs in a 14-day MinIO bucket; Loki single-binary with Grafana Alloy, 14-day retention and a 5 GiB MinIO bucket quota.
- Local Grafana dashboards: `Platform Health` and `Batch Pipeline`.

### Workflow And Delivery

- Work from `develop` on `feature/assignment-1`; use normal GitFlow thereafter.
- Complete local platform before AWS work.
- Never push; user reviews and pushes.
- Pre-commit runs all automated non-kind tests plus all static checks.
- Commits on `release/*` additionally run kind and Playwright release smoke.
- This intentionally makes commits slower. Non-kind integration hooks may start isolated Compose/Testcontainers services. Branch-aware release hook invokes explicit `release-check.sh`; CI independently enforces the same release gate.
- GitHub Actions repeats all gates; cloud apply uses a protected environment with one human approval.
- Releases use SemVer `vMAJOR.MINOR.PATCH` and attach checksums, SBOMs, and rendered diagrams.
- Renovate opens weekly grouped updates; every dependency, tool, chart, action, provider, module, and image is pinned and verified.

## 3. Planned Repository Shape

Create only when the owning phase begins.

```text
Assignment_1/
├── README.md
├── setup.sh
├── teardown.sh
├── pyproject.toml
├── uv.lock
├── .python-version
├── .env.example
├── alembic.ini
├── alembic/
│   ├── env.py
│   └── versions/
├── sql/
│   ├── schema.sql                 # Generated from Alembic offline SQL
│   └── queries/
│       ├── average_fare_per_mile.sql
│       ├── peak_ride_hours.sql
│       └── revenue_by_payment_type.sql
├── src/nyc_taxi_etl/
│   ├── config.py
│   ├── logging_config.py
│   ├── contracts/
│   ├── quality/
│   ├── storage/
│   ├── transform/
│   ├── load/
│   ├── metrics/
│   └── alerts/
├── airflow/dags/
│   ├── taxi_quality_calibration.py
│   ├── taxi_monthly_etl.py
│   └── taxi_failure_drill.py
├── dashboard/
│   ├── app.py
│   ├── queries.py
│   ├── state.py
│   └── tabs/
├── alert_receiver/
│   └── app.py
├── references/
│   ├── vendor.csv
│   ├── payment_type.csv
│   ├── rate_code.csv
│   ├── zone_sources.yaml           # Official lookup/geometry URLs and expected contract
│   └── SOURCES.md
├── docker/
│   ├── airflow.Dockerfile
│   ├── dashboard.Dockerfile
│   └── alert-receiver.Dockerfile
├── infra/
│   ├── local/
│   │   ├── kind.yaml
│   │   ├── helmfile.yaml
│   │   ├── values/
│   │   ├── charts/taxi-app/
│   │   ├── dashboards/
│   │   ├── alerts/
│   │   └── compose.postgres.yaml
│   └── aws/
│       ├── bootstrap/
│       ├── modules/
│       ├── environments/dev/
│       ├── environments/prod/
│       └── tests/
├── scripts/
│   ├── lib/
│   ├── bootstrap-tools.sh
│   ├── configure-cloud.sh
│   ├── build-images.sh
│   ├── run-pipeline.sh
│   ├── verify.sh
│   ├── release-check.sh
│   ├── backup.sh
│   └── restore-drill.sh
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── dags/
│   ├── dashboard/
│   ├── e2e/
│   └── fixtures/
└── docs/
    ├── implementation-plan.md
    ├── architecture.md
    ├── data-model.md
    ├── operations.md
    ├── dashboard.md
    ├── testing.md
    ├── production-aws.md
    ├── demo-runbook.md
    ├── adr/
    └── diagrams/
        ├── src/*.mmd
        └── rendered/*.svg
```

Root-only files created later:

- `.github/workflows/assignment-1-ci.yml`
- `.github/workflows/assignment-1-release.yml`
- `.github/workflows/assignment-1-terraform.yml`
- `.github/renovate.json` or root `renovate.json`

## 4. Data Contracts And Physical Model

### 4.1 Source Contract

Required source columns:

- `VendorID`
- `tpep_pickup_datetime`
- `tpep_dropoff_datetime`
- `passenger_count`
- `trip_distance`
- `RatecodeID`
- `store_and_fwd_flag`
- `PULocationID`
- `DOLocationID`
- `payment_type`
- `fare_amount`
- `extra`
- `mta_tax`
- `tip_amount`
- `tolls_amount`
- `improvement_surcharge`
- `total_amount`
- `congestion_surcharge`
- `airport_fee`

Contract behavior:

- Validate Parquet readability, row count, required names, and coercible types before transformation.
- Permit additive unknown columns but log and store them in schema fingerprint metadata.
- Fail missing or incompatible required columns; deterministic contract failures are not retried.
- Record source URL, HTTP headers, byte size, SHA-256, Parquet schema fingerprint, object key, source month, row count, and synthetic/real marker.
- Download to a temporary object, validate, then atomically promote to a checksum-addressed key.
- Existing matching object is reused. Replacement requires explicit force and creates a new source version.
- Commit reviewed vendor/payment/rate CSVs derived from official TLC documentation, including source URL/version/hash in `references/SOURCES.md`.
- Download official taxi-zone lookup and geometry from TLC, then pin URL, retrieval metadata, checksum, schema, and license/attribution in the reference snapshot. Verify current official URLs before committing them.
- Synthetic fallback requires `--allow-synthetic-fallback` and proven source unavailability after normal retry/cache checks. Contract, quality, transform, infrastructure, or credential failures never permit fallback. Every UI and run record must display synthetic mode.

### 4.2 Hard Validation

Columns must exist at file-contract level. Row-level required values are pickup timestamp, dropoff timestamp, trip distance, fare amount, and total amount. Reject rows with reason codes when any condition holds:

- Missing/non-finite/uncoercible row-level required value.
- Pickup timestamp outside declared source month.
- Dropoff timestamp not later than pickup timestamp.
- Dropoff timestamp on or after the second calendar day of the following month. This deterministic boundary permits a month-end pickup to finish during the following day.
- Trip distance less than or equal to zero.
- Fare amount or total amount below zero.
- Converted cents, millimiles, duration, key, or source row number exceeds warehouse type bounds.

Accepted but flagged:

- Unknown/missing vendor, payment, rate, pickup zone, or dropoff zone; map foreign key to Unknown.
- Missing/invalid passenger count; retain null and issue code.
- Missing/non-finite optional money components; retain null and issue code. Aggregate views must state whether they ignore null or expose incomplete-component counts; never silently coerce to zero.
- Statistically extreme duration, distance, speed, or fare-per-mile outside active KLL bounds.
- Future DST ambiguous/nonexistent local wall timestamps.

Never winsorize or overwrite observed values. Quarantine preserves raw fields and all rejection reasons.

### 4.3 KLL Calibration

Calibration DAG contract:

1. Resolve explicit baseline months.
2. Reuse/download and validate each raw source.
3. Apply hard-validity filters only.
4. Build one `k=4096` KLL sketch per source partition for duration, distance, speed, and fare-per-mile.
5. Serialize partition sketches and metadata to MinIO.
6. Merge partition sketches in a fixed documented partition order. KLL compaction can be randomized and merge-order-sensitive; reproducibility comes from persisting the activated artifact, not requiring byte-identical rebuilds.
7. Calculate 0.001 and 0.999 quantile bounds, one-sided normalized rank error from the pinned DataSketches version, and an expected false-flag rank band. Values equal to a bound are not outliers.
8. Compare estimated ranks against exact fixture quantiles and fail when rank deviation exceeds the library-reported bound. Do not require identical estimated values across rebuilds.
9. Persist candidate version; activate initial `2023-baseline-v1` only after checks pass.
10. Never mutate an active version. Recalibration creates another version.

### 4.4 Warehouse Schemas

Use PostgreSQL schemas `warehouse`, `analytics`, `ops`, and temporary/load-specific `staging` objects.

`warehouse.dim_date`:

- `date_key` integer primary key (`YYYYMMDD`).
- Calendar date, year, quarter, month, month name, ISO week/year, day of month/year, weekday number/name, weekend flag.
- Generate every date in each loaded calendar month plus one boundary day; reruns upsert idempotently.

`warehouse.dim_time`:

- `time_key` small integer primary key (`0..1439`).
- Hour, minute, quarter-hour bucket, hour label, and documented daypart.
- Seed exactly 1,440 rows.

Ingestion-time SCD2 dimensions:

- `warehouse.dim_taxi_zone`: source `LocationID`, borough, zone name, service zone.
- `warehouse.dim_payment_type`: source payment code and label.
- `warehouse.dim_vendor`: source vendor code and label.
- `warehouse.dim_rate_code`: source rate code and label.
- Common columns: surrogate key, business key, attributes, reference snapshot ID, row hash, `observed_from`, nullable `observed_to`, `is_current`.
- Enable `btree_gist`; enforce no overlap with an exclusion constraint on business key plus `[observed_from, observed_to)` `tstzrange`, and enforce one current row with a partial unique index.
- Require `observed_from NOT NULL`, `observed_to IS NULL OR observed_to > observed_from`, and `is_current = (observed_to IS NULL)` checks.
- Seed Unknown key `0`; sequences start at `1`.

`warehouse.fact_taxi_trips`:

- Grain: one hard-valid source row.
- Monthly range partition on `pickup_date_key`.
- Composite primary key includes partition key and `trip_key`.
- Unique source identity includes pickup partition, source asset ID/version, and source row number.
- Role-playing foreign keys: pickup/dropoff date, time, and zone.
- Other foreign keys: payment type, vendor, rate code.
- Exact pickup/dropoff local timestamps and duration seconds.
- Passenger count, distance millimiles, and `store_and_fwd` flag.
- Integer-cent columns for fare, extra, MTA tax, tip, tolls, improvement surcharge, total, congestion surcharge, airport fee.
- Source lineage, threshold version, reference snapshot, publish run, `has_statistical_outlier`, and `has_quality_issue`.
- Do not store fare-per-mile or speed ratios; derive from additive numerator/denominator values.

`analytics.trip_metrics_hourly`:

- Monthly partitioned serving table.
- Grain: pickup date, pickup hour, pickup zone, payment, vendor, rate, statistical-outlier flag, any-quality-issue flag.
- Additive measures: trip count, known passenger count/sum, distance, duration, and every money component.
- Incrementally rebuild only target month during publish.
- Required ratios use ratio-of-sums, never average-of-ratios.

Required analytics interfaces:

- Average fare per mile: `10.0 * SUM(fare_amount_cents)::numeric / NULLIF(SUM(distance_millimiles), 0)` dollars/mile, with `NOT has_statistical_outlier` applied to both numerator and denominator by default.
- Peak ride hours: trip count grouped by pickup local hour; headline selects highest count under filters.
- Revenue by payment type: `SUM(total_amount_cents)::numeric / 100.0` for hard-valid, non-refund data, with `NOT has_statistical_outlier` by default.
- Recorded card tip rate: `100.0 * SUM(tip_amount_cents)::numeric / NULLIF(SUM(fare_amount_cents), 0)` percent, restricted to credit-card trips and `NOT has_statistical_outlier` by default.
- Weighted network speed: `3.6 * SUM(distance_millimiles)::numeric / NULLIF(SUM(duration_seconds), 0)` mph, with `NOT has_statistical_outlier` by default.
- Demand trip counts include every hard-valid row regardless of statistical flag. Every financial/unit view must apply its outlier predicate consistently to all numerator/denominator aggregates.
- Trip explorer view: display-friendly dimension labels and decimal measures, preserving indexed base predicates.

`ops` tables:

- `pipeline_run`: DAG/run/task identity, source month, status, timestamps, duration, counts, versions, error summary.
- `source_asset`: immutable source metadata and schema fingerprint.
- `reference_snapshot`: artifact hashes and observed timestamp.
- `threshold_version` and `quality_threshold`: KLL settings, bounds, error, status, baseline months.
- `partition_publish`: active source/reference/threshold/run version per month.
- `quality_result_summary`: count by month/run/issue/severity.
- `trip_quality_issue`: sparse accepted-row lineage, metric, observed value, bounds, issue code.
- `quarantine_manifest`: MinIO object, row count, checksum, reason distribution.
- `alert_event`: sanitized local webhook payload metadata and receipt status.

### 4.5 Atomic Monthly Publish

1. Transform accepted, issue, and quarantine Parquet checkpoints in MinIO.
2. Sync reference SCD2 rows in a separate idempotent transaction. Atomic publication covers fact/mart/month-quality metadata; an unused reference version from a failed load is allowed and remains auditable.
3. Create load-specific standalone fact, mart, and monthly quality-issue partition tables with the parent column definitions.
4. Bulk load through psycopg 3 COPY; never row-by-row insert.
5. Build equivalent indexes/constraints, run `ANALYZE`, add exact validated month-bound `CHECK` constraints, and validate direct-table queries.
6. Validate `source = accepted + rejected`, `flagged <= accepted`, source identity uniqueness, foreign keys, sums, and bounds.
7. Acquire source-month advisory lock and a bounded PostgreSQL `lock_timeout`.
8. In one non-concurrent transaction, detach old month partitions, attach new fact/mart/quality partitions, increment warehouse version, and mark partition published. Do not use `DETACH ... CONCURRENTLY`.
9. Run parent-table pruning/required-query smoke after commit. If it fails, execute one tested compensating transaction: detach failed new fact/mart/quality partitions, attach retained old partitions into freed bounds, restore publication metadata, and increment warehouse version again. Retain failed tables for diagnosis.
10. Drop old detached tables only after post-publish smoke succeeds. On any pre-commit failure, leave current publication untouched and remove failed staging safely.

`ops.trip_quality_issue` is partitioned by pickup month and co-published. It uses immutable source asset/row lineage, not a foreign key to detachable fact partitions.

## 5. Airflow Workflows

Keep DAG files thin. Put transforms, storage, quality, loading, metrics, and alert logic in tested package modules. XCom carries object URIs/manifests/counts only, never row data.

### 5.1 `taxi_quality_calibration`

Task order:

1. Validate parameters and register run.
2. Map baseline months.
3. Reschedule source-availability sensors.
4. Download with `curl`, validate, and publish raw objects.
5. Validate source contracts and fingerprints.
6. Compute partition KLL sketches in bounded batches.
7. Merge sketches and calculate bounds/error.
8. Persist candidate threshold version and calibration report.
9. Activate only requested/approved version.
10. Emit metrics and final run event.

### 5.2 `taxi_monthly_etl`

Task order:

1. Derive/validate source month and register run.
2. Sensor waits for official source if immutable raw object is absent.
3. `BashOperator` runs shared `curl` downloader.
4. Validate source contract and pin source asset.
5. Download/hash reference files; create/reuse reference snapshot.
6. Sync SCD2 dimensions using observed-time semantics.
7. Resolve explicit active threshold version.
8. Transform in bounded batches and publish accepted/issues/quarantine checkpoints.
9. Run quality gates: zero rows, contract, reconciliation, duplicate identity, FK, reject rate.
10. Warn above 1% rejected; fail above 5%.
11. Build/load/validate replacement fact and aggregate partitions.
12. Atomically publish target month.
13. Run required SQL checks and query-budget checks.
14. Push low-cardinality metrics and final structured event.
15. Remove successful checkpoints after seven days through lifecycle policy; retain raw and quarantine per policy.

Retry rules:

- Retry bounded transient HTTP, MinIO, Kubernetes, and PostgreSQL connection errors with exponential backoff.
- Never retry deterministic contract, conversion, reconciliation, migration, or quality-gate failures.
- Every task has an execution timeout.
- Local Airflow pool permits one heavy task pod; production values permit controlled parallelism.
- Local DAG max-active-runs is one; production can increase after DB/object-store capacity validation.

### 5.3 `taxi_failure_drill`

- Uses tiny fixture data and isolated run IDs.
- Parameter selects deterministic failure point.
- Never touches published partitions.
- Must prove JSON error log, Airflow failed state, webhook receipt, Mailpit message, Alertmanager state, Prometheus series, and Loki query.
- Test cleans its temporary objects after evidence capture.

### 5.4 Logging And Alerts

JSON event fields:

- `event`, `level`, `timestamp`, `dag_id`, `run_id`, `task_id`, `try_number`, `source_month`.
- Start/end timestamps and duration.
- Input, accepted, rejected, staged, loaded, and published row counts, plus flagged subset count.
- Count names always mean fact rows for the source version. Dimension and mart counts use explicit prefixes such as `dimension_rows_*` and `mart_rows_*`.
- Source/reference/threshold/schema versions.
- Sanitized exception class/message and correlation ID; no credentials or row payloads.

Failure routes:

- Airflow callback writes structured log and `ops.pipeline_run`/event state.
- Callback posts to local webhook receiver.
- Callback sends SMTP through Mailpit or configured relay.
- Prometheus rules detect failures/staleness/duration/reject rates/service health; Alertmanager routes webhook and SMTP.
- Alert grouping/inhibition prevents duplicate floods while retaining both immediate Airflow and platform evidence.

## 6. Dashboard Contract

One Streamlit application, one page, shared sidebar filters, five tabs. Plotly charts. NYC taxi editorial theme: taxi yellow, charcoal, off-white, restrained colorblind-safe status colors, compact typography.

Shared filters:

- Pickup date range; default latest complete month, February 2023.
- Prior comparison defaults to January 2023.
- Pickup borough/zone, payment type, vendor, rate code.
- Include-outliers toggle, off by default for financial/unit metrics.

### Overview

- KPI cards: trips, gross revenue, revenue/trip, fare/mile, average duration, recorded card tip rate.
- Every card shows prior-month delta or explicit `N/A` when comparison data is absent.
- Daily trip and revenue trends.
- Current publication/freshness/quality state.

### Demand

- Daily trip trend.
- Weekday-by-pickup-hour heatmap.
- Pickup taxi-zone choropleth and ranked zones.
- Map selector: trip volume, gross revenue, revenue/trip, fare/mile; default volume.
- Quantile color scale prevents Manhattan from flattening other zones.
- Weighted network speed by hour.
- Top month-over-month pickup-zone movers.

### Revenue

- Daily gross revenue and fare-per-mile trends.
- Revenue/payment mix.
- Revenue-component waterfall.
- Vendor and rate-code comparisons.
- Recorded credit-card tip rate.
- Top month-over-month payment/vendor/rate movers.

### Data Quality

- Pipeline status and freshness.
- Reconciliation shows `raw = accepted + rejected`, then flagged as accepted subset, then `loaded = published = accepted`; never draw flagged as a separate loss stage.
- Reject and flag rates/reasons.
- KLL version, bounds, `k`, rank-error metadata, baseline months.
- Source/reference/schema fingerprints.
- Recent webhook/Alertmanager events and links to Airflow/Grafana/Loki.

### Explore Trips

- PostgreSQL server-side keyset pagination, 100 rows per page.
- Sort only by pickup timestamp plus trip key; keep cursor stack for previous page.
- Indexed filters: pickup date/time, pickup/dropoff zone, payment, vendor, rate, quality, distance, duration, total amount.
- No browser-side full dataset, no unbounded offset, no arbitrary SQL/sort.
- Database statement timeout: 1.5 seconds, leaving application/render budget inside two-second end-to-end target.
- Download current page CSV and aggregate summaries only.

Dashboard performance/security:

- SQL is parameterized; sort/filter identifiers use allowlists.
- Read-only dashboard role can access approved analytics interfaces only. Create sanitized analytics views for publication state, quality summaries, thresholds, fingerprints, and alert metadata; grant no direct `ops` access.
- Cache by filters plus published warehouse version, five-minute TTL.
- New publish changes version and immediately invalidates logical cache keys.
- Geometry is official TLC zone geometry transformed to EPSG:4326 and simplified for browser payload.
- Explorer requires a bounded pickup-date range, uses canonical `(pickup_at_local, trip_key)` partition indexes, and implements reverse keyset queries for previous-page navigation. Representative filter combinations require saved `EXPLAIN (ANALYZE, BUFFERS)` evidence.
- Measure uncached p95 over at least 20 requests with application cache cold, PostgreSQL buffers warm, one client, and documented dataset/hardware. Record DB and end-to-end latency separately.
- Empty, unavailable, timeout, synthetic, stale, and partial-comparison states show actionable messages without stack traces.
- Test desktop and 390px mobile layouts, keyboard navigation, labels, contrast, and non-color status cues.

## 7. Local Platform Contract

### 7.1 Host Prerequisites

Automate Linux `amd64`/`arm64`; support WSL2 with extra browser trust instructions. Other operating systems fail early with exact install guidance.

Known OpenCode profiles:

- `/smallpc`: native Void Linux `x86_64`, 4 CPUs, 3.8 GiB RAM, no swap; expected staged/stage-by-stage mode.
- `/bigpc`: Windows host with Void Linux WSL2, 16 CPU cores, 16 GiB host RAM, GPU; expected concurrent candidate only after Docker-visible preflight.
- Profile command sets session context, not runtime configuration. Setup always measures actual resources.
- On Big PC, clone/run under WSL Linux filesystem, verify Docker integration, keep Windows/WSL CA trust separate, and ignore GPU unless later validated requirement needs it.
- Full profile rules and benchmark metadata: `docs/agents/machine-profiles.md`.

Only globally required:

- Working Docker engine.
- `curl`.
- POSIX/Bash environment.
- Enough disk; preflight calculates image/cache/raw/DB/backup/Prometheus/Loki needs plus 20% safety margin. Start with a 40 GiB minimum until measured artifacts justify lower.

Repo-local pinned tools:

- `uv` and managed CPython 3.12.
- kind, kubectl, Helm, Helmfile.
- Gum, mkcert, and required checksum/archive helpers.
- Core mode installs local-runtime and core-verification tools. Path-aware pre-commit hooks may fetch a missing pinned validator after explicit notice when changed files require it; this is on-demand validation, not full cloud tooling installation.
- `--tools all` also installs Terraform, TFLint, Checkov, Infracost, AWS CLI, Cloudflare/Terraform helpers, Trivy, Syft, Cosign, Mermaid renderer, and release tools.
- `verify-core` validates local/runtime scope. `verify-all` auto-bootstraps missing pinned AWS/security/release validators after explicit notice. Pre-commit dispatches by changed path and fails rather than skipping a required unavailable validator.

Every binary download must:

1. Detect supported OS/architecture.
2. Use pinned version and official URL.
3. Verify published checksum/signature before installation.
4. Install only under `Assignment_1/.tools`.
5. Print exact manual install link/instructions when unsupported.

### 7.2 Setup Stages

`setup.sh` remains Bash and uses Gum in an interactive terminal; plain deterministic output under CI/noninteractive mode.

Planned stages:

1. `preflight`: OS/architecture, Docker daemon, CPU/RAM/disk, ports, network, clock, required permissions.
2. `tools`: bootstrap selected pinned tool profile and Python 3.12.
3. `python`: create `.venv`, sync exact lock, install pre-commit.
4. `secrets`: preserve existing generated secrets or create new least-privilege values.
5. `tls`: create local CA/certificates; ask before trust-store mutation; WSL2 prints Windows trust steps.
6. `cache`: fetch/verify OCI chart artifacts, images, wheels, source metadata, and schemas; support `--offline` completeness check.
7. `cluster`: create kind with default CNI disabled, ports, and host mounts; install/wait Calico.
8. `storage`: install/wait local-path provisioner, CloudNativePG CRDs/operator, MinIO/static PV, databases, roles, and pools.
9. `images`: build/load pinned local application images before any consuming workload.
10. `platform`: install/wait Prometheus CRDs/operator and Traefik; then configure exact-host CoreDNS rewrites to `traefik.ingress.svc.cluster.local`; install identity, logging/monitoring, Mailpit, webhook receiver, and Airflow dependencies.
11. `applications`: deploy Airflow with bundled PostgreSQL disabled, direct-writer migration job, KubernetesExecutor pod template/RBAC, and custom image; deploy app workloads.
12. `schema`: run Alembic job and verify generated `schema.sql` checksum.
13. `calibration`: trigger baseline calibration and activate approved version.
14. `etl`: trigger/wait January and February monthly runs.
15. `presentation`: start/verify Streamlit, Grafana, Mailpit, Airflow, MinIO console routes.
16. `acceptance`: required SQL, count reconciliation, idempotency sample, query budgets, health endpoints.
17. `summary`: print profile, synthetic status, URLs, credentials location, run IDs, exact recovery/demo commands.

Flags:

- `--profile auto|staged|concurrent`; auto selects concurrent only with at least 8 GiB Docker memory and 4 CPUs.
- `--tools core|all`; default core.
- `--from STAGE`, `--only STAGE`.
- `--offline`.
- `--allow-synthetic-fallback`.
- `--non-interactive`.
- Explicit force flags for source replacement, secret rotation, or cluster recreation.

Stage state comes from real tool/cluster/API checks, not marker files. Failure prints shortest decisive error and exact resume command.

### 7.3 Resource Profiles

Concurrent profile:

- Runs full stack together.
- Used only after preflight threshold or explicit override warning.

Staged profile:

- Keeps CNPG/PgBouncer, MinIO, Airflow control plane, Prometheus/exporters, Alertmanager, Mailpit, webhook receiver, Dex/oauth2-proxy, Traefik, Calico, Loki, and Grafana Alloy active during ETL.
- Permits one heavy ETL task pod.
- Scales Grafana and Streamlit down during heavy transforms.
- Starts presentation services after ETL task pods exit.
- Must still capture metrics, logs, email, webhook, and alerts during ETL.
- Phase 7 measures minimal ETL baseline. Phase 11 must publish complete-stack per-pod requests/limits and peak totals with at least 20% Docker-memory headroom for each machine used. If Small PC cannot satisfy this, setup must block unsupported concurrency and follow documented stage-by-stage replay/evidence path. Big PC still uses live Docker measurements, not nominal host capacity.

### 7.4 Security Boundaries

- Default-deny Calico policies per namespace; explicit DNS, Kubernetes API for Airflow scheduler/executor, ingress, DB/PgBouncer/direct writer, MinIO, SMTP, metrics, Loki, OIDC, and TLC source-download flows.
- Per-service Kubernetes accounts; no default service-account tokens where unused.
- Generated Kubernetes Secrets from gitignored environment; no secret literals in values/manifests/logs.
- Separate DB owner/migrator, loader, Airflow metadata, dashboard read-only, webhook writer, and monitoring roles.
- Containers run non-root where upstream permits, drop capabilities, use seccomp, read-only root filesystem, explicit writable volumes, resource limits.
- Admin and viewer Dex groups map to least privileges. Mail/alert administration is admin-only.
- Local ingress binds Docker ports to loopback.
- Expose every backend only through ClusterIP and Traefik; strip spoofable identity headers before trusted-header applications.

OIDC/TLS details:

- External `*.taxi.localhost` resolves to loopback port `8443`; internal CoreDNS rewrites each exact hostname to Traefik's ClusterIP, whose Service also exposes port `8443` to the websecure target.
- Certificate SANs include every service hostname. Mount the generated CA bundle into Dex clients, oauth2-proxy, Airflow, Grafana, MinIO, application/test pods, and configure each runtime trust path.
- After pinning a compatible Airflow release, install `apache-airflow-providers-fab`, configure `FabAuthManager`/`AUTH_OAUTH` with a Dex custom `remote_app`, and implement/test security-manager mapping from Dex group claims to Airflow roles. Grafana and MinIO use native OIDC; oauth2-proxy/Traefik ForwardAuth protects Streamlit, Mailpit, Prometheus, and webhook UI routes.
- Test discovery, authorization, token, JWKS, callback, logout, group mapping, and certificate trust from both host and pods.
- Refusing host CA installation is a documented degraded setup with browser trust steps. Full browser acceptance requires trusted CA.

### 7.5 Storage And Retention

- Host-persist MinIO through a static hostPath PV at a gitignored path; kind deletion does not delete source objects.
- Version raw/reference/calibration buckets; checksum-addressed keys are write-once.
- Successful checkpoints expire after seven days.
- Local quarantine expires after 90 days unless overridden.
- Prometheus uses dynamic RWO local-path PVC, 14-day retention, and 5 GiB PVC quota.
- Loki stores chunks/index in a dedicated MinIO bucket with 14-day compactor retention and a 5 GiB MinIO bucket quota; alert before quota exhaustion. Persist TSDB WAL, active index, compactor markers, and compactor working directory on documented RWO PVCs; test restart/recovery before enabling deletion.
- Airflow KubernetesExecutor uses MinIO remote task logging with a 14-day bucket lifecycle; do not require RWX log PVC.
- CNPG and Loki cache use dynamic RWO local-path PVCs. Mailpit is ephemeral. Document storage class, access mode, size, reclaim policy, host path, ownership, backup status, and cluster-deletion behavior for every volume.
- Lifecycle rules are bucket/prefix specific, include noncurrent-version/delete-marker behavior, and never delete active Loki metadata or CNPG WAL/base-backup chains.
- PostgreSQL is rebuildable after kind deletion.

### 7.6 Teardown And Recovery

- Default `teardown.sh` stops helper processes and deletes kind cluster only.
- Keep `.tools`, `.venv`, caches, generated configuration, and MinIO host data.
- `--purge-cache` and `--purge-all` show exact paths/impact and require explicit confirmation.
- Never delete cloud resources from local teardown.
- `backup.sh` uses the pinned current CloudNativePG Barman Cloud plugin, WAL archiving, path-style MinIO endpoint/TLS configuration, retention, base-backup completion, and WAL verification.
- `restore-drill.sh` restores into a temporary CNPG `Cluster` in a separate namespace with distinct PVCs, using existing MinIO. Copy least-privilege namespace-scoped ObjectStore/plugin resources, MinIO credential/CA Secrets, and explicit egress policy; check schema/rows/checksums, record timing, then delete only temporary cluster/PVCs/resources.

### 7.7 PostgreSQL Compose Fallback

- Supply minimal pinned PostgreSQL Compose profile for integration tests and focused SQL demonstration.
- It is not a second Airflow/platform deployment.
- Use separate host port and volume names to avoid kind conflicts.
- Same Alembic migrations, fixture loader, SQL queries, and DB tests must pass against Compose and CloudNativePG.

## 8. Observability Contract

Prometheus sources:

- Airflow StatsD exporter.
- CloudNativePG/PostgreSQL exporter.
- MinIO metrics.
- kube-state-metrics, node exporter, Kubernetes control-plane/kubelet targets available in kind.
- Pushgateway for bounded batch outcome metrics.
- Streamlit/webhook receiver health and request metrics.

Metric rules:

- No trip ID, run ID, source row, object checksum, exception text, URL, or user as metric label.
- Approved labels: environment, DAG, task, status, source month, quality issue class, service.
- Recording rules power repeated Grafana queries.
- Pushgateway groups are replaced/cleaned to avoid stale unbounded series.

Alerts:

- DAG/task failure and missed monthly freshness.
- ETL duration above 45 minutes.
- Reject-rate warning above 1%; critical above 5%.
- Row reconciliation failure.
- PostgreSQL, PgBouncer, MinIO, Airflow, ingress, Dex, webhook receiver unavailable.
- Pod crash loop/OOM/restarts.
- PVC/MinIO capacity threshold.
- Prometheus target absent and backup/restore drill failure.

Grafana `Platform Health`:

- Kubernetes CPU/memory/pod health by project namespace.
- CNPG/PgBouncer connections, locks, transactions, storage, replica/backup status.
- MinIO availability/capacity/errors.
- Airflow scheduler/task/executor health.
- Traefik/Dex/oauth2-proxy/Mailpit/webhook status.
- Links to filtered Loki logs.

Grafana `Batch Pipeline`:

- DAG status/freshness/duration.
- Rows per second and stage durations.
- Reconciliation invariants plus flagged accepted subset.
- Reject/flag rates and issue groups.
- Published months, source/reference/threshold versions.
- Active/recent alerts and failure-drill evidence.

## 9. Verification Contract

Commands below are target commands to implement and document; none are currently verified.

Required order:

1. Formatting and static checks.
2. Type checks.
3. Unit/DAG/dashboard tests.
4. PostgreSQL/MinIO integration tests.
5. Container/Helm/Kubernetes checks.
6. Kind release smoke when required.
7. Terraform checks/plans when AWS files change.

Validation tiers:

- Pre-commit: all non-kind static/unit/DAG/dashboard/integration checks; path-aware hooks install/fail on required validators rather than skip.
- CI: repeats pre-commit checks in clean runners with service-backed integration tests.
- Release: explicit `release-check.sh` adds kind, OIDC, failure, restore, and Playwright smoke; branch-aware hook invokes it on `release/*`, and CI enforces it independently.

Target developer commands:

```bash
./scripts/bootstrap-tools.sh --profile core
uv sync --frozen --all-groups
uv run pre-commit run --all-files
uv run ruff format --check .
uv run ruff check .
uv run mypy src airflow dashboard alert_receiver tests
uv run pytest tests/unit tests/dags tests/dashboard --cov --cov-branch
uv run pytest tests/integration --cov-append --cov-branch
uv run pytest tests/unit/transform/test_trips.py::test_rejects_non_positive_distance
./scripts/verify.sh
./scripts/verify.sh --profile all
./scripts/release-check.sh
./setup.sh --profile auto --tools core
./teardown.sh
```

Static checks included by `verify.sh`:

- Ruff format/lint.
- mypy.
- pytest/coverage erases prior data, runs explicit source coverage across unit/DAG/dashboard/integration suites with append, then executes one aggregate `coverage report --fail-under=85` branch gate.
- ShellCheck and shfmt.
- SQLFluff PostgreSQL dialect.
- Alembic single-head/history checks.
- Regenerate Alembic offline `sql/schema.sql`; fail on diff.
- Apply the initial revision to empty PostgreSQL. For later revisions, test upgrade from adjacent revision; require an explicit irreversible marker/reason when downgrade is unsafe. Compare normalized expected catalog for both migration path and generated schema snapshot.
- `docker compose config` and image build checks.
- Helm dependency lock, lint, render. Cache OCI charts or archives with SHA-256 verification; a version string alone is insufficient.
- kubeconform against pinned Kubernetes/CRD schemas. Unknown kinds fail unless an exact reviewed schema exception is committed.
- Network-policy and resource-limit assertions.
- Trivy filesystem/config/image scans.
- Secret scan.
- Mermaid syntax validation and deterministic SVG rendering.
- Reference CSV source/hash validation.
- `verify-core` uses only core tool manifest; `verify-all` owns Terraform/security/release/Mermaid checks.

Automated tests:

- Pure transform tests for coercion, integer conversion, timestamp/month boundaries, Unknown mapping, and derived duration.
- Contract tests for additive/missing/incompatible schema drift.
- Property tests for row-count reconciliation, cents/millimiles, ratios, and idempotency invariants.
- KLL merge/serialization/error tests against exact fixture quantiles.
- SCD2 observed-window tests and pinned-snapshot reruns.
- COPY/load/partition swap rollback and concurrent-lock tests.
- Required SQL golden-result tests.
- DAG import, task dependency, schedule, retry classification, pool, timeout, and parameter tests.
- Alert payload sanitization/routing tests.
- Streamlit AppTest for filters, tabs, metrics, empty/error/synthetic/stale states, pagination, cache-version invalidation.
- Compose and CloudNativePG migration/query parity.
- Offline cache test blocks outbound network and verifies every required architecture-specific binary, wheel, OCI chart, container image, schema, source/reference artifact, and checksum is available.

Release kind smoke:

- Build/load native images.
- Provision staged stack with deterministic tiny fixture.
- Complete calibration and monthly ETL.
- Assert exact fixture counts/metrics/rejects/flags.
- Rerun and prove idempotency.
- Execute controlled failure drill.
- Execute CloudNativePG backup/restore drill.
- Playwright logs in through Dex as viewer/admin, checks five dashboard tabs, Grafana, Airflow, Mailpit, keyset pagination, downloads, accessibility.
- Capture diagnostics on failure; always teardown only created resources.

Full-data acceptance, run manually before release:

- Real January-February files, no synthetic fallback.
- If Phase 11 proves Small PC supported, enforce under-45-minute and no-OOM/restart Small PC gates.
- If Phase 11 proves Small PC cannot fit active service envelope with 20% headroom, execute/document approved stage-by-stage full-data proof and report measured runtime/resource limits; never mark unsupported concurrent/staged targets as passed.
- Run Big PC acceptance separately inside WSL2, recording Docker allocation and concurrent-profile results; never substitute Big PC success for Small PC evidence.
- Required SQL/dashboard agreement.
- Query latency budgets.
- Source-to-publish reconciliation and no duplicate source identity.

## 10. AWS Terraform Contract

AWS work starts only after local done state passes.

### 10.1 Topology

- Primary region: `us-east-1`.
- DR region: `us-west-2`.
- Airflow production target: EKS with KubernetesExecutor.
- Compare Amazon MWAA in documentation; do not deploy duplicate MWAA stack.
- Dev: Aurora Serverless v2 single writer, in-cluster Prometheus/Grafana.
- Prod primary: provisioned Aurora PostgreSQL writer/readers, RDS Proxy, active EKS applications, Amazon Managed Prometheus/Grafana, CloudWatch Logs. Use separate databases/users for Airflow metadata and taxi warehouse on the global cluster initially; disable Airflow chart PostgreSQL, back up both, and route each through dedicated proxy endpoints/secrets.
- Prod DR: warm minimal EKS/system capacity and regional RDS Proxy in `us-west-2`, Aurora Global Database secondary, replicated ECR/secrets/configuration, standby application releases, DNS failover, and regional monitoring. Keep Airflow scheduler/API/triggerer replicas at zero while Aurora secondary is read-only; after promotion, switch regional proxy/secrets, run metadata checks, then start Airflow control plane and unpause schedules. Do not count Terraform-only recreation as one-hour RTO capacity.
- Raw/checkpoint/quarantine/log source: encrypted/versioned S3 with lifecycle and cross-region replication. Critical raw/reference/threshold/manifest objects must be synchronously copied to both regions before a month is marked published; ordinary logs/checkpoints may use S3 replication objectives.
- Internal Streamlit remains analyst UI. Document future stateless query API, ElastiCache, CloudFront, and separate web frontend for 100,000 clients; do not implement that app now.
- Optional disabled Redshift Serverless module and migration runbook. Enable only after volume/SLA threshold.
- Polars remains default; shard row groups first; move transforms to Glue/EMR Spark above roughly 20 GiB/month or missed 45-minute SLA.
- Karpenter: On-Demand system nodes, Spot task nodes with safe retry/disruption controls.
- Cognito OIDC for application users; IAM Identity Center for AWS/managed Grafana administration.
- Cloudflare DNS provider: dev DNS-only; prod proxied with Full (strict), WebSockets, WAF/rate limits. ACM validation records remain DNS-only.

### 10.2 Terraform Layout

Modules should cover:

- Remote state bootstrap: encrypted/versioned S3 backend and locking, cross-region state copy, documented break-glass backend promotion, lock recovery, and tested state restore when primary region is unavailable.
- VPC: three AZ production private subnets, endpoints, controlled egress; lower-cost dev layout.
- EKS: cluster, managed system nodes, Karpenter, workload identity, encryption, audit logs.
- ECR: immutable tags, scanning, lifecycle, cross-region replication.
- Data: Aurora, RDS Proxy, Secrets Manager, KMS, parameter/subnet groups.
- Object storage: source/checkpoint/quarantine/log buckets, lifecycle, replication, access logs.
- Identity: regional Cognito pools federated to the same external enterprise identity source for DR, GitHub Actions OIDC, least-privilege deploy roles, IAM Identity Center integration notes. Document that standalone Cognito passwords do not replicate.
- Platform add-ons: controllers, Airflow chart, app releases, policies, backup configuration.
- Observability: AMP, AMG, CloudWatch, SNS/SES alert routes, dashboards/rules.
- DNS/TLS: ACM and Cloudflare records/provider inputs.
- DR: warm secondary VPC/EKS capacity, regional RDS Proxy/secrets/Cognito/app releases/monitoring, Aurora global secondary, replicated S3/ECR, DNS health/failover, write fencing, promotion, failback, backup/state recovery automation.
- Optional Redshift Serverless and data-publication path, disabled by default.
- Budgets/tags: mandatory owner/environment/expiry/cost-center tags and 50/80/100% alerts.

Keep modules under Assignment 1 initially. Promote proven generic modules to root only when Assignment 2 consumes them; keep assignment states separate.

### 10.3 Environments And Safety

- Deployable low-cost `dev` environment.
- Guarded `prod` example with explicit HA/DR confirmation variables.
- Separate state and IAM role per environment.
- Infracost baseline guard: block dev estimate above `$300/month` or unapproved increase above 10%.
- Mandatory `expires_at` for dev; scheduled reminders; destroy remains human-approved.
- CI runs fmt, validate, native Terraform tests, TFLint, Checkov, Trivy, Infracost, and speculative plan.
- Protected apply uses one human approval and applies exact reviewed plan artifact.
- Protected destroy uses separate approval/workflow.
- GitHub OIDC only; no static AWS keys.
- Cloudflare token is least-privileged and only in protected GitHub secret/local environment.

### 10.4 Production Targets

- Availability objective: 99.9% monthly; topology checks alone do not prove it.
- Critical published warehouse/object state RPO objective: 5 minutes. Select an Aurora engine/version supporting managed global RPO, configure and test `rds.global_db_rpo=300`, alarm before the limit, and document commit-stall behavior; block production acceptance if unsupported. Synchronous dual-region publication protects critical S3 artifacts. Noncritical logs/checkpoints use a separate documented replication objective and are excluded from the five-minute claim.
- RTO objective: 1 hour through warm secondary capacity, tested promotion, regional proxies/secrets/identity, write fencing, and DNS failover.
- Raw and curated data: seven years, lifecycle to archival tiers.
- Quarantine: 90 days.
- Airflow logs: 90 days.
- Audit metadata: seven years.
- Monthly backup restore validation, quarterly Aurora failover, annual regional disaster exercise.
- Store measured RPO/RTO evidence after every exercise.
- Claims remain objectives until deployed failover/restore drills measure them. Terraform tests assert topology/policy only.

### 10.5 Cloud Configuration Wizard

Implement `scripts/configure-cloud.sh` with pinned repo-local Gum:

- Interactive and noninteractive modes.
- Validate AWS account/region/identity, GitHub repository/environment, Cloudflare zone/token scope, DNS names, SMTP relay, budget, and Terraform backend.
- Open exact provider/setup documentation where human action is required.
- Mask secrets, never print them after entry, never pass them on process command lines where avoidable.
- Write only gitignored environment files with restrictive permissions.
- Show exact `gh secret set` operations and execute only after confirmation.
- Confirm cost and protected-environment requirements before plan/apply.
- Supply plain CLI flags/environment variables for CI and accessibility.

## 11. CI, Release, And Supply Chain

- CI path filters isolate Assignment 1 while still checking root workflow/config changes.
- Cache by lock/tool/chart digest, never by mutable branch-only key.
- Multi-platform Buildx publishes `linux/amd64` and `linux/arm64` images.
- Generate CycloneDX and SPDX SBOMs.
- Scan source, IaC, dependencies, and images with pinned Trivy/security tools.
- Keyless-sign release images with Cosign and GitHub OIDC.
- EKS deployment verifies signatures/digests.
- GitHub Release includes image digests, tool/chart lock summaries, checksums, SBOMs, rendered SVGs, migration notes, and demo evidence.
- Renovate groups compatible Python/Docker/Helm/Terraform/Action updates; release smoke is mandatory before merge.

## 12. Documentation Deliverables

`Assignment_1/README.md` must remain quickstart-oriented:

- Purpose and requirement mapping.
- Prerequisites and supported hosts.
- Exact setup, focused test, full verification, run/backfill, dashboard, failure drill, backup/restore, teardown commands.
- URLs and credential retrieval without secret values.
- Resource profiles, offline mode, synthetic fallback warning.
- Short architecture summary and links.

Focused docs:

- `architecture.md`: local components, boundaries, data flow, resource profiles.
- `data-model.md`: grain, columns, SCD2 observed semantics, partitions, mart, metric definitions, data-quality matrix.
- `operations.md`: setup stages, reruns, backfills, alerts, logs/metrics, backups, restore, troubleshooting.
- `dashboard.md`: audiences, filters, formulas, tabs, caveats, trip explorer behavior.
- `testing.md`: command order, suites, fixtures, budgets, release gates.
- `production-aws.md`: EKS/MWAA comparison, modules, scaling, 100k-client boundary, Polars/Spark threshold, Aurora/Redshift path, HA/DR, cost/security.
- `demo-runbook.md`: happy path, SQL, UI tour, idempotent rerun, controlled failure, monitoring, recovery proof, common evaluator questions.
- ADRs for KubernetesExecutor, MinIO layering, KLL, observed-time SCD2, aggregate mart, resource profiles, OIDC, monitoring, and AWS target.

Diagrams:

- Local system architecture.
- Airflow calibration and monthly DAGs.
- Star-schema ERD.
- Security/namespace flow.
- AWS production and DR architecture.
- Keep Mermaid source and rendered SVG; validate/render in CI.

Every documented assumption must identify requirement ambiguity and chosen answer. Code-tour notes must make randomly selected code explainable without hidden framework magic.

## 13. Execution Phases And Commit Boundaries

Each phase starts only after previous exit checks pass. Commit only when explicitly requested.

### Phase 0: Record Architecture Decisions

Files:

- Assignment README link/index.
- ADRs for all fixed decisions.
- Initial architecture/data-model docs and Mermaid sources.

Steps:

1. Convert this plan's fixed decisions into concise ADRs.
2. Add agreed assumptions/metric predicates and ADR links to Assignment README before execution; update whenever a decision changes.
3. Add requirement traceability and known non-goals.
4. Write Mermaid source. Defer validation/rendering until Phase 1 installs the pinned renderer.

Exit:

- No unresolved architectural contradiction.
- Requirements map to an owner phase.
- Assignment README records agreed assumptions before implementation starts.

Planned commit: `docs(a1): record architecture decisions`

### Phase 1: Bootstrap Reproducible Toolchain

Files:

- `pyproject.toml`, `uv.lock`, `.python-version`, tool manifest/checksums.
- Bootstrap/verification shell libraries.
- Ruff, mypy, pytest, coverage, pre-commit, SQLFluff, ShellCheck/shfmt configuration.
- Assignment README command section and `AGENTS.md` verified-command update.

Steps:

1. Pin versions only after checking official compatibility and release sources.
2. Implement the single reusable architecture-aware/checksum-verified downloader, including the `curl` path later invoked by Airflow.
3. Bootstrap repo-local uv/Python and core/all tool profiles.
4. Add trivial package/test proving commands.
5. Document exact setup, focused test, lint, typecheck, test, run, and teardown commands that exist at this phase; update them after every later phase rather than waiting for final documentation.
6. Validate Phase 0 Mermaid sources and render SVG with the pinned renderer.

Exit:

- Clean host bootstrap is idempotent.
- Lock sync and all initial static/test commands pass.
- No global package installation or sudo, except opt-in mkcert CA trust later.

Planned commit: `chore(a1): bootstrap pinned toolchain`

### Phase 2: Define Data Contract, Fixtures, And Pure Transform

Files:

- Typed contract, reference CSVs/sources, quality rules, money/distance conversion, transforms.
- Tiny deterministic Parquet fixtures and unit/property tests.

Steps:

1. Use Phase 1's verified downloader to fetch/inspect official January/February schemas into a temporary/cache path before freezing contract. Do not wait for MinIO integration.
2. Build fixture covering valid, unknown-reference, rejected, statistical, overflow, month-boundary, additive-schema cases.
3. Implement pure bounded transform outputs: accepted, issues, rejects, counts/manifests.
4. Ensure source row numbering is deterministic per immutable source version.

Exit:

- Unit/property tests prove every rule and reconciliation.
- No DB/Airflow dependency in core transforms.

Planned commit: `feat(a1): add typed trip transformation`

### Phase 3: Implement KLL Calibration

Files:

- DataSketches wrapper, serialization, merge, threshold models/repository interface.
- Exact-versus-sketch tests and calibration fixture reports.

Steps:

1. Stream numeric batches into KLL `k=4096` sketches.
2. Persist/merge partition sketches through a filesystem repository test adapter; Phase 5 adds the MinIO adapter without changing calibration semantics.
3. Calculate tails/error and immutable version metadata.
4. Test architecture compatibility, especially `arm64` wheel/build path.

Exit:

- Memory stays bounded.
- Merge and serialization tests pass.
- Fixture error remains within documented rank guarantee.

Planned commit: `feat(a1): add versioned KLL quality bounds`

### Phase 4: Build PostgreSQL Schema And SQL Contract

Files:

- Alembic setup/revisions, generated `schema.sql`, required SQL, Compose fallback.
- Integration tests for schema, SCD2, partitions, roles, views.

Steps:

1. Build schemas/tables/constraints/roles/indexes.
2. Seed date/time/Unknown dimensions.
3. Implement observed-time SCD2 merge.
4. Implement monthly fact/mart partition DDL and atomic swap helpers.
5. Generate `schema.sql` from Alembic offline SQL; add drift gate.
6. Prove required metric SQL with fixture golden values.

Exit:

- Empty upgrade, upgrade path, catalog checks, downgrade policy pass.
- Required SQL returns expected values.
- Compose fallback is reproducible.

Planned commit: `feat(a1): add dimensional warehouse schema`

### Phase 5: Implement Object Storage, Load, And Atomic Publish

Files:

- MinIO/source/reference/checkpoint clients.
- MinIO adapter/promotion around Phase 1's shared `curl` downloader, psycopg COPY loader, publish service, integration tests.

Steps:

1. Integrate the shared downloader with immutable MinIO temporary-object validation/promotion, manifests, and fingerprints; do not create a second downloader.
2. Implement reference snapshots and SCD2 pinning.
3. Persist accepted/issues/quarantine checkpoints.
4. COPY into replacement partitions, validate, swap atomically.
5. Rebuild month mart and warehouse version.
6. Test failure rollback and rerun idempotency.

Exit:

- Fixture source reaches published fact/mart.
- Forced failure leaves prior published month unchanged.
- Rerun duplicates zero rows and preserves outputs.

Planned commit: `feat(a1): publish monthly warehouse partitions`

### Phase 6: Add Thin Airflow DAGs And Runtime Images

Files:

- Three DAGs, callbacks, logging/metrics adapters, Airflow image, DAG tests.

Steps:

1. Implement calibration task graph.
2. Implement monthly task graph/schedule/sensor/retries/pool/timeouts.
3. Implement failure drill.
4. Bake DAG/package into pinned Airflow image.
5. Validate imports without live Airflow services and in container.

Exit:

- DAG topology tests pass.
- Task callables run against fixture/test services without a live Airflow control plane; Phase 7 owns the first real KubernetesExecutor run.
- Logs contain required timings/counts/context.

Planned commit: `feat(a1): orchestrate monthly ETL with Airflow`

### Phase 7: Provision Minimal Local Kubernetes Vertical Slice

Files:

- kind/Calico, Helmfile, CNPG/PgBouncer, MinIO, Airflow values, ETL chart, build/load scripts.

Steps:

1. Create kind with default CNI disabled, loopback-only ports, and required host mounts.
2. Install Calico CRDs/operator; wait for node/network readiness before creating dependent workloads.
3. Install pinned local-path provisioner and define static MinIO hostPath PV plus dynamic RWO storage classes/reclaim behavior.
4. Install CloudNativePG CRDs/operator; create database cluster, roles, direct writer service, and PgBouncer pools.
5. Deploy MinIO and verify buckets/lifecycle/versioning/quota.
6. Build/load Airflow/ETL image before applying Airflow release; later phases build their own images.
7. Disable Airflow bundled PostgreSQL; configure metadata pool, direct-writer migration job, KubernetesExecutor pod template, resource limits, custom image, service account, and scheduler Kubernetes API RBAC.
8. Run migrations, calibration, and one fixture month through real KubernetesExecutor.
9. Measure minimal ETL pod requests/limits/peak. Defer complete profile certification until all services exist in Phase 11.

Exit:

- Minimal stack passes fixture ETL on active measured host; retain separate Small PC/Big PC evidence.
- No OOM, pending PVC, uncontrolled privilege, unpinned artifact, unknown CRD validation, or missing limit.

Planned commit: `feat(a1): run ETL on local Kubernetes`

### Phase 8: Add Ingress, TLS, OIDC, And Alerts

Files:

- Traefik, CoreDNS mapping, mkcert handling, Dex/oauth2-proxy, Mailpit, webhook receiver, policies/tests.

Steps:

1. Establish exact-host CoreDNS rewrites and Traefik Service port `8443`, preserving identical OIDC issuer inside/outside cluster.
2. Generate SAN certificates and establish reusable CA mount/trust mechanism; apply it to OIDC clients present in this phase. Add explicit host CA trust prompt and WSL2 instructions.
3. Build/deploy webhook receiver image. Generate admin/viewer users; configure/test Airflow and MinIO native OIDC plus Mailpit/webhook ForwardAuth. Later phases own Grafana/Prometheus/Streamlit integration.
4. Strip identity headers at ingress, prevent direct backend ingress, and test spoof attempts.
5. Add SMTP relay override and webhook persistence.
6. Enforce/test Calico default-deny, including Kubernetes API and external source flows.

Exit:

- Browser/CLI OIDC succeeds with both roles.
- Unauthorized paths fail.
- Email/webhook delivery succeeds without leaking secrets.

Planned commit: `feat(a1): secure local platform access`

### Phase 9: Add Monitoring, Logging, Failure, And Recovery Proof

Files:

- kube-prometheus-stack/Loki/Grafana Alloy values, exporters, rules, dashboards, backup/restore scripts/tests.

Steps:

1. Add low-cardinality metrics/recording rules.
2. Provision two Grafana dashboards and Loki links.
3. Route Alertmanager to Mailpit/webhook.
4. Verify controlled failure evidence.
5. Configure pinned current CNPG Barman Cloud plugin, WAL archiving/base backups to host-persisted MinIO, completion checks, and restore drill.
6. Validate retention/cap behavior.

Exit:

- Full alert set tests pass.
- Backup/restore fixture drill passes.
- Grafana/Prometheus OIDC, metrics, logs, alerts, and recovery components pass independently. Phase 11 owns complete staged-profile proof.

Planned commit: `feat(a1): add platform observability and recovery`

### Phase 10: Build Executive Dashboard

Files:

- Dashboard image/app/query/state/tab modules, geometry pipeline, AppTest/SQL/performance tests.

Steps:

1. Implement shared filters/versioned cache.
2. Implement five agreed tabs and exact formulas.
3. Add map geometry preprocessing and quantile colors.
4. Add safe keyset explorer.
5. Add error/synthetic/stale/empty/mobile/accessibility states.
6. Build/deploy dashboard image; integrate/test Streamlit Dex ForwardAuth and read-only PostgreSQL role.

Exit:

- Dashboard values match required SQL.
- Performance budgets and AppTest pass.
- Viewer cannot mutate/access prohibited data.

Planned commit: `feat(a1): add executive taxi dashboard`

### Phase 11: Complete Setup, Offline, And Demo Automation

Files:

- `setup.sh`, `teardown.sh`, stage libraries, run/verify/demo scripts, cache manifest, docs.

Steps:

1. Implement stage detection/resume/only behavior.
2. Implement auto resource profile and staged service scaling.
3. Implement core/all tools, offline completeness, and explicit synthetic fallback restricted to verified source unavailability.
4. Trigger full calibration and two monthly runs.
5. Add safe teardown/purge confirmations.
6. Run real full-data acceptance on selected measured host; label Small PC versus Big PC evidence.
7. Measure complete concurrent/staged pod envelope and prove staged mode captures metrics/logs/email/webhook/alerts while presentation UIs are scaled down.

Exit:

- Clean, rerun, resume-after-failure, offline-rerun, and teardown scenarios pass.
- Full-data/query targets pass on a Phase 11-supported profile; otherwise approved stage-by-stage evidence and explicit unmet hardware target are recorded.

Planned commit: `feat(a1): automate reproducible local demo`

### Phase 12: Add CI, Release Gates, And Supply Chain

Files:

- GitHub workflows, pre-commit, Renovate, release scripts, SBOM/signing config.

Steps:

1. Enforce all automated non-kind tests pre-commit with deterministic aggregate coverage.
2. Detect `release/*` in the local hook and run kind/Playwright/failure/restore smoke; CI independently enforces the same gate for release branches so branch detection cannot bypass it.
3. Add CI matrices for Python and image architectures where useful.
4. Add scans, SBOMs, Cosign, release assets.
5. Ensure workflows use pinned action SHAs and least privileges.

Exit:

- Normal and release gates pass from clean checkout.
- Failed smoke captures diagnostics and tears down safely.

Planned commit: `ci(a1): enforce release and supply-chain gates`

### Phase 13: Implement Guarded AWS Terraform

Files:

- Backend bootstrap, modules, dev/prod environments, tests, cloud wizard, protected workflows, production docs.

Steps:

1. Implement state/network/EKS/ECR/data/object/identity/DNS/observability/budget modules.
2. Add dev and guarded prod compositions.
3. Add optional disabled Redshift module.
4. Add Cloudflare/ACM/Cognito/GitHub OIDC integration.
5. Add primary/DR region resources and runbooks.
6. Add checks, cost guard, reviewed-plan apply/destroy workflows.
7. Deploy/destroy dev through protected workflow when credentials/budget approval exist.

Exit:

- Static/tests/speculative plans pass.
- Static completion requires topology/policy assertions for warm DR, publication replication, state recovery, and all explicit manual prerequisites.
- Credentialed acceptance, when approved credentials/budget exist, requires dev app/ETL/dashboard smoke and clean destroy; absence of credentials does not falsify static completion and must be reported.
- Availability/RPO/RTO remain objectives until deployed drills produce evidence; never claim a speculative plan proves them.

Planned commit: `feat(a1): add guarded AWS deployment`

### Phase 14: Final Documentation And Review

Steps:

1. Replace all planned commands with verified exact commands.
2. Complete diagrams/SVGs, demo runbook, troubleshooting, assumptions, code tour, AWS comparison/DR.
3. Reconcile root README and `AGENTS.md` with only non-obvious verified commands/order/prerequisites already updated incrementally by owning phases.
4. Review against every requirement and this done state.
5. Run all local/full/release/cloud checks applicable to available credentials.

Exit:

- No stale placeholder, unverified command, secret, unpinned artifact, unexplained assumption, or unmet requirement.
- User can demonstrate setup, ETL, SQL, dashboard, monitoring, failure, rerun, recovery, and AWS plan.

Planned commit: `docs(a1): finalize demo and operations guide`

## 14. Requirement Traceability

- Linux/Bash: `setup.sh`, teardown, Gum CLI, Linux/WSL2 support.
- Python 3.10+: pinned managed Python 3.12.
- Virtual environment/dependencies: uv-managed `.venv`, exact lock.
- PostgreSQL in Docker: CloudNativePG inside Docker-backed kind; literal Compose PostgreSQL fallback.
- Two months via command-line download: Airflow `BashOperator` invokes shared `curl` downloader for January/February 2023.
- Star schema: partitioned `fact_taxi_trips` plus six dimensions.
- Modern orchestrator: Airflow KubernetesExecutor.
- Structured start/end/count/error logs: JSON logging, Airflow callbacks, ops tables, Loki.
- Failure status/alerts: Airflow UI/log, webhook, SMTP/Mailpit, Prometheus/Alertmanager, Grafana.
- Required SQL: three committed SQL files and golden tests.
- Single-page dashboard: one Streamlit app with five tabs.
- Explainability: ADRs, code tour, diagrams, typed thin modules, demo runbook.
- Resource limitation: auto staged profile while retaining observable stage-by-stage proof.
- Synthetic fallback: explicit only after verified source unavailability, marked everywhere.

## 15. Explicit Non-Goals

- Do not implement Assignment 2 Kafka streaming inside Assignment 1.
- Do not claim Airflow handles 50,000 streaming events/second.
- Do not implement public 100,000-client API/web frontend now; document architecture.
- Do not deploy both EKS Airflow and MWAA; compare MWAA only.
- Do not enable Redshift by default.
- Do not add Spark locally; document threshold and AWS migration.
- Do not create a second full Docker Compose platform.
- Do not store full rejected rows in PostgreSQL.
- Do not silently repair, winsorize, drop, or synthesize data.
- Do not silently install a local CA, use sudo, overwrite source, rotate secrets, purge data, apply cloud infrastructure, or destroy cloud resources.

## 16. Implementation Review Checklist

Before marking any phase complete:

- Read current requirement, ADR, and owning tests.
- Confirm no concurrent user changes conflict.
- Add failing tests first for behavioral changes where practical.
- Make smallest complete change for phase.
- Run focused test, then phase verification in required order.
- Inspect logs/output for warnings, skips, secrets, retries, resource errors.
- Update commands/docs only after actual verification.
- Review diff for generated files, lockfiles, images/charts/providers, permissions, and unrelated changes.
- Record benchmark/evidence paths.
- Do not commit or push unless user explicitly requests it.
