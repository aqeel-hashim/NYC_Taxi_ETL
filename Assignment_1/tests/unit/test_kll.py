"""Tests for KLL sketch calibration, merge, serialization, and threshold versioning."""

import tempfile

from nyc_taxi_etl.quality.kll import (
    ThresholdBounds,
    ThresholdVersion,
    build_sketch,
    compute_bounds,
    deserialize_sketch,
    load_threshold_version,
    merge_sketches,
    save_threshold_version,
    serialize_sketch,
)


class TestBuildSketch:
    def test_build_from_list(self) -> None:
        data = [1.0, 2.0, 3.0, 4.0, 5.0]
        sketch = build_sketch(data)
        assert sketch.n == 5

    def test_empty_sketch(self) -> None:
        sketch = build_sketch([])
        assert sketch.is_empty()

    def test_median(self) -> None:
        data = [float(i) for i in range(100)]
        sketch = build_sketch(data)
        median = sketch.get_quantile(0.5)
        assert 45 <= median <= 55

    def test_extreme_quantiles(self) -> None:
        data = [float(i) for i in range(1000)]
        sketch = build_sketch(data)
        low = sketch.get_quantile(0.001)
        high = sketch.get_quantile(0.999)
        assert 0 <= low <= 10
        assert 990 <= high <= 1000


class TestMergeSketches:
    def test_merge_two_sketches(self) -> None:
        s1 = build_sketch([1.0, 2.0, 3.0])
        s2 = build_sketch([4.0, 5.0, 6.0])
        merged = merge_sketches(s1, s2)
        assert merged.n == 6
        assert 3.0 <= merged.get_quantile(0.5) <= 4.0

    def test_merge_maintains_k(self) -> None:
        s1 = build_sketch([float(i) for i in range(1000)], k=4096)
        s2 = build_sketch([float(i) for i in range(1000, 2000)], k=4096)
        merged = merge_sketches(s1, s2, k=4096)
        assert merged.k == 4096


class TestSerialization:
    def test_round_trip(self) -> None:
        sketch = build_sketch([float(i) for i in range(500)])
        data = serialize_sketch(sketch)
        restored = deserialize_sketch(data)
        assert restored.n == 500
        assert abs(restored.get_quantile(0.5) - sketch.get_quantile(0.5)) < 1.0


class TestThresholdBounds:
    def test_is_outlier(self) -> None:
        bounds = ThresholdBounds(
            metric="test",
            k_value=4096,
            low_quantile=0.001,
            high_quantile=0.999,
            low_bound=10.0,
            high_bound=100.0,
        )
        assert bounds.is_outlier(5.0)
        assert bounds.is_outlier(150.0)
        assert not bounds.is_outlier(50.0)
        assert not bounds.is_outlier(10.0)  # equal to bound is not outlier
        assert not bounds.is_outlier(100.0)


class TestThresholdVersion:
    def test_save_and_load(self) -> None:
        bounds = {m: compute_bounds(build_sketch([float(i) for i in range(500)]), m) for m in ["test_metric"]}
        version = ThresholdVersion(
            version_id="test-v1",
            baseline_months=["2023-01", "2023-02"],
            k_value=4096,
            bounds=bounds,
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            save_threshold_version(version, tmpdir)
            loaded = load_threshold_version("test-v1", tmpdir)

        assert loaded.version_id == "test-v1"
        assert loaded.baseline_months == ["2023-01", "2023-02"]
        assert "test_metric" in loaded.bounds
        assert not loaded.is_active

    def test_activate_version(self) -> None:
        version = ThresholdVersion(
            version_id="active-v1",
            baseline_months=["2023-01"],
            k_value=4096,
        )
        version.is_active = True
        with tempfile.TemporaryDirectory() as tmpdir:
            save_threshold_version(version, tmpdir)
            loaded = load_threshold_version("active-v1", tmpdir)
        assert loaded.is_active

    def test_get_bounds_missing(self) -> None:
        version = ThresholdVersion(version_id="v1", baseline_months=["2023-01"], k_value=4096)
        try:
            version.get_bounds("nonexistent")
            raise AssertionError("expected KeyError")
        except KeyError:
            pass
