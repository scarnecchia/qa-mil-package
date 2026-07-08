# Parity Fixtures

This directory contains synthetic/golden fixtures for parity testing.

## Layout

```
fixtures/
  parity/
    README.md           ← this file
    synthetic_371_375/  ← synthetic fixture for checks 371–375
      config.yaml
      input_manifest.yaml
      input/
      expected_python/
```

## SAS execution is NOT required for current CI

Captured SAS outputs are deferred until NUM-49. The harness supports
synthetic/golden comparison now and is ready for captured SAS outputs when they
become available.

## Fixture naming convention

- `synthetic_<check_range>/` — manually crafted fixtures with known expected
  outputs.
- `captured_sas_<check_range>/` — future fixtures with captured SAS output
  (added in NUM-49).
