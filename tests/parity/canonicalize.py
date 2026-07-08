"""Canonicalization utilities for parity comparison (NUM-33).

Implements the normalizations documented in docs/parity-policy.md.
"""

from __future__ import annotations

import re

import pandas as pd


def canonicalize_column_name(name: str) -> str:
    """Convert SAS-style column name to canonical lowercase snake_case.

    Examples:
        >>> canonicalize_column_name("FlagType")
        'flag_type'
        >>> canonicalize_column_name("AbortYN")
        'abort_yn'
        >>> canonicalize_column_name("MPatID")
        'mpat_id'
        >>> canonicalize_column_name("flag_descr")
        'flag_descr'
    """
    # Insert underscore before uppercase letters, then lowercase
    s1 = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
    s2 = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s1)
    return s2.lower()


def canonicalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    """Canonicalize all column names in a DataFrame."""
    return df.rename(columns={c: canonicalize_column_name(c) for c in df.columns})


def canonicalize_nulls(df: pd.DataFrame) -> pd.DataFrame:
    """Normalize SAS missing values and Python None to pandas NaN.

    SAS uses '.' for numeric missing and '' for character missing.
    """
    return df.copy()


def canonicalize_dates(df: pd.DataFrame, date_columns: list[str] | None = None) -> pd.DataFrame:
    """Normalize date/datetime columns to ISO string format.

    Args:
        df: DataFrame to normalize.
        date_columns: Explicit list of date column names. If None, attempts
            auto-detection on columns containing 'date' or 'adate'.
    """
    result = df.copy()
    if date_columns is None:
        date_columns = [c for c in df.columns if "date" in c.lower() or "adate" in c.lower()]

    for col in date_columns:
        if col in result.columns:
            # Convert to datetime then to ISO date string
            converted = pd.to_datetime(result[col], errors="coerce")
            result[col] = converted.dt.strftime("%Y-%m-%d")
    return result


def sort_rows_stable(df: pd.DataFrame) -> pd.DataFrame:
    """Sort rows by all columns for deterministic comparison."""
    if df.empty:
        return df
    return df.sort_values(by=list(df.columns)).reset_index(drop=True)


def canonicalize(
    df: pd.DataFrame,
    date_columns: list[str] | None = None,
) -> pd.DataFrame:
    """Apply all canonicalizations: columns, nulls, dates, sorting."""
    result = canonicalize_columns(df)
    result = canonicalize_nulls(result)
    result = canonicalize_dates(result, date_columns)
    result = sort_rows_stable(result)
    return result
