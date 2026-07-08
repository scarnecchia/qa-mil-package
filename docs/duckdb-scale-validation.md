# DuckDB Scale Validation (NUM-48)

**Status:** Documented
**Last updated:** 2026-07-07

## Purpose

Document the DuckDB larger-than-memory validation strategy and procedure.

## Validation strategy

DuckDB supports spilling to disk when data exceeds available memory. The
validation procedure confirms that the full QA MIL check suite can run
successfully on data larger than available RAM by:

1. Generating or identifying representative SCDM/MIL parquet data
2. Configuring DuckDB with a memory limit smaller than the dataset
3. Configuring a temp directory for spill files
4. Running the full DuckDB check suite
5. Recording runtime, dataset size, memory limit, and spill behavior

## Reproducible procedure

```bash
# 1. Generate large parquet fixture (if not using existing data)
uv run python -c "
import pyarrow as pa
import pyarrow.parquet as pq
import random
random.seed(42)
n = 2_000_000  # 2M rows
table = pa.table({
    'MPatID': [f'M{i:07d}' for i in range(n)],
    'CPatID': [f'C{i:07d}' for i in range(n)],
    'ADate': ['2020-01-15'] * n,
    'EncounterID': [f'E{i:07d}' for i in range(n)],
    'Birth_Type': [random.randint(1, 5) for _ in range(n)],
})
pq.write_table(table, '/tmp/qa_mil_scale/mil.parquet')
"

# 2. Run with memory limit and temp directory
qa-mil run --config scale_config.yaml
# scale_config.yaml should set:
#   backend:
#     name: duckdb
#     options:
#       memory_limit: "512MB"
#       temp_directory: /tmp/qa_mil_duckdb_spill
```

## Environment assumptions

- Sufficient disk space for spill files (2-3x dataset size recommended)
- Temp directory is writable and on fast storage (SSD preferred)
- DuckDB version supports spilling (all recent versions do)

## CI vs manual validation

- **Ordinary CI**: Maintains the low-memory spill smoke test from NUM-31
  (128MB memory limit, 500K rows). This is automated in `tests/test_engine.py`.
- **Full scale validation**: Manual or periodic benchmark using the procedure
  above. Results recorded in this document.

## Failure guidance

- **"Out of memory" errors**: Increase memory_limit or ensure temp_directory
  is writable with sufficient disk space.
- **Slow performance**: Spilling to disk is inherently slower. Consider:
  - Increasing memory_limit if more RAM is available
  - Using faster storage for temp_directory
  - Reducing parallel threads if disk I/O is the bottleneck
- **Temp directory full**: Ensure at least 2-3x dataset size in free disk space.

## Validation evidence

The low-memory spill smoke test in `tests/test_engine.py::TestDuckDbOptions::test_low_memory_spill_smoke`
confirms that DuckDB correctly configures memory limits and temp directories
and can complete aggregations that require spilling.

Full larger-than-memory validation should be performed manually before
production deployment using the procedure above.
