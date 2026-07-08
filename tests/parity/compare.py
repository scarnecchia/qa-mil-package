"""Comparison helpers for parity testing (NUM-33).

Reports missing rows, unexpected rows, strict field differences, flagid
differences, and informational message differences.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import pandas as pd

from tests.parity.canonicalize import canonicalize

# Fields that must match exactly (strict)
STRICT_FIELDS = frozenset(
    {
        "flagid",
        "flag_descr",
        "flag_type",
        "abort_yn",
    }
)

# Fields that are informational (non-failing)
INFORMATIONAL_FIELDS = frozenset(
    {
        "message",
    }
)


@dataclass
class ParityDiff:
    """Result of comparing two datasets for parity."""

    is_match: bool
    missing_rows: int = 0
    unexpected_rows: int = 0
    strict_diffs: list[str] = field(default_factory=list)
    flagid_diffs: list[str] = field(default_factory=list)
    message_diffs: list[str] = field(default_factory=list)

    def summary(self) -> str:
        parts = [f"Match: {self.is_match}"]
        if self.missing_rows:
            parts.append(f"Missing rows: {self.missing_rows}")
        if self.unexpected_rows:
            parts.append(f"Unexpected rows: {self.unexpected_rows}")
        if self.strict_diffs:
            parts.append(f"Strict field diffs: {len(self.strict_diffs)}")
            parts.extend(f"  - {d}" for d in self.strict_diffs[:5])
        if self.flagid_diffs:
            parts.append(f"FlagID diffs: {len(self.flagid_diffs)}")
            parts.extend(f"  - {d}" for d in self.flagid_diffs[:5])
        if self.message_diffs:
            parts.append(f"Message diffs (informational): {len(self.message_diffs)}")
        return "\n".join(parts)


def compare(
    expected: pd.DataFrame,
    actual: pd.DataFrame,
    *,
    key_columns: list[str] | None = None,
    date_columns: list[str] | None = None,
) -> ParityDiff:
    """Compare expected and actual DataFrames for parity.

    Args:
        expected: Expected output (synthetic golden or captured SAS).
        actual: Actual Python output.
        key_columns: Columns used as row identity for row-matching comparison.
            If None, uses all columns.
        date_columns: Date columns to canonicalize.

    Returns ParityDiff with detailed findings.
    """
    exp = canonicalize(expected, date_columns)
    act = canonicalize(actual, date_columns)

    diff = ParityDiff(is_match=True)

    # Align schemas: only compare common columns
    common_cols = sorted(set(exp.columns) & set(act.columns))

    keys = [c for c in key_columns if c in common_cols] if key_columns else common_cols

    # Row-level comparison using key columns
    exp_keys = exp[keys].astype(str).agg("|".join, axis=1) if keys else pd.Series(range(len(exp)))
    act_keys = act[keys].astype(str).agg("|".join, axis=1) if keys else pd.Series(range(len(act)))

    exp_set = set(exp_keys)
    act_set = set(act_keys)

    missing = exp_set - act_set
    unexpected = act_set - exp_set

    diff.missing_rows = len(missing)
    diff.unexpected_rows = len(unexpected)

    # FlagID differences
    if "flagid" in common_cols:
        exp_flagids = set(exp["flagid"].dropna())
        act_flagids = set(act["flagid"].dropna())
        only_in_expected = exp_flagids - act_flagids
        only_in_actual = act_flagids - exp_flagids
        if only_in_expected:
            diff.flagid_diffs.append(f"FlagIDs only in expected: {sorted(only_in_expected)}")
        if only_in_actual:
            diff.flagid_diffs.append(f"FlagIDs only in actual: {sorted(only_in_actual)}")

    # Strict field differences for matching rows
    matching_keys = exp_set & act_set
    exp_indexed = exp.set_index(list(keys) if keys else exp.columns.tolist())
    act_indexed = act.set_index(list(keys) if keys else act.columns.tolist())

    for key_val in matching_keys:
        exp_row = exp_indexed.loc[key_val] if len(keys) > 0 else None
        act_row = act_indexed.loc[key_val] if len(keys) > 0 else None
        if exp_row is not None and act_row is not None:
            for col in common_cols:
                if col in INFORMATIONAL_FIELDS:
                    continue
                if col in STRICT_FIELDS or col in keys:
                    exp_val = str(exp_row.get(col, ""))
                    act_val = str(act_row.get(col, ""))
                    if exp_val != act_val:
                        diff.strict_diffs.append(
                            f"Key {key_val}: {col} expected={exp_val!r} actual={act_val!r}"
                        )

    # Message differences (informational, non-failing)
    for key_val in matching_keys:
        if "message" in common_cols:
            exp_msg = str(exp_indexed.loc[key_val].get("message", ""))
            act_msg = str(act_indexed.loc[key_val].get("message", ""))
            if exp_msg != act_msg:
                diff.message_diffs.append(f"Key {key_val}: message differs (informational)")

    # Determine if match
    if diff.missing_rows > 0 or diff.unexpected_rows > 0:
        diff.is_match = False
    if diff.strict_diffs:
        diff.is_match = False
    if diff.flagid_diffs:
        diff.is_match = False
    # Message diffs do NOT affect is_match

    return diff


def assert_parity(
    expected: pd.DataFrame,
    actual: pd.DataFrame,
    *,
    key_columns: list[str] | None = None,
    date_columns: list[str] | None = None,
) -> None:
    """Assert that expected and actual match for parity purposes.

    Raises AssertionError with detailed diff if they don't match.
    Message differences are informational and do not cause failure.
    """
    diff = compare(expected, actual, key_columns=key_columns, date_columns=date_columns)
    if not diff.is_match:
        raise AssertionError(f"Parity mismatch:\n{diff.summary()}")
