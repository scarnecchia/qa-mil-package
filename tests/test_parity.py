"""Tests for parity harness: canonicalization, comparison, strict diffs (NUM-33/NUM-37)."""

from __future__ import annotations

import pandas as pd
import pytest

from tests.parity.canonicalize import (
    canonicalize,
    canonicalize_column_name,
    canonicalize_columns,
    canonicalize_dates,
    sort_rows_stable,
)
from tests.parity.compare import (
    assert_parity,
    compare,
)

# ---------------------------------------------------------------------------
# Column name canonicalization
# ---------------------------------------------------------------------------


class TestCanonicalizeColumnName:
    @pytest.mark.parametrize(
        "input_name,expected",
        [
            ("FlagType", "flag_type"),
            ("AbortYN", "abort_yn"),
            ("MPatID", "m_pat_id"),
            ("CPatID", "c_pat_id"),
            ("flag_descr", "flag_descr"),
            ("EncounterID", "encounter_id"),
            ("BirthType", "birth_type"),
            ("FlagID", "flag_id"),
        ],
    )
    def test_canonicalize_column_name(self, input_name: str, expected: str) -> None:
        assert canonicalize_column_name(input_name) == expected

    def test_canonicalize_columns_dataframe(self) -> None:
        df = pd.DataFrame({"FlagType": ["Warn"], "AbortYN": ["N"]})
        result = canonicalize_columns(df)
        assert list(result.columns) == ["flag_type", "abort_yn"]


# ---------------------------------------------------------------------------
# Date/datetime normalization
# ---------------------------------------------------------------------------


class TestDateNormalization:
    def test_date_normalization(self) -> None:
        df = pd.DataFrame({"ADate": ["01/15/2020", "03/20/2020"]})
        result = canonicalize_dates(df, date_columns=["ADate"])
        assert result["ADate"].tolist() == ["2020-01-15", "2020-03-20"]

    def test_auto_detect_date_columns(self) -> None:
        df = pd.DataFrame({"birth_date": ["2020-01-15"], "name": ["test"]})
        result = canonicalize_dates(df)
        assert result["birth_date"].tolist() == ["2020-01-15"]


# ---------------------------------------------------------------------------
# Null/missing normalization
# ---------------------------------------------------------------------------


class TestNullNormalization:
    def test_nulls_preserved(self) -> None:
        df = pd.DataFrame({"a": [1.0, None, 3.0]})
        result = canonicalize(df)
        # After stable sort, NaN sorts last
        assert result["a"].isna().sum() == 1


# ---------------------------------------------------------------------------
# Stable row sorting
# ---------------------------------------------------------------------------


class TestStableSort:
    def test_sort_by_all_columns(self) -> None:
        df = pd.DataFrame({"a": [3, 1, 2], "b": ["c", "a", "b"]})
        result = sort_rows_stable(df)
        assert result["a"].tolist() == [1, 2, 3]
        assert result["b"].tolist() == ["a", "b", "c"]

    def test_empty_dataframe(self) -> None:
        df = pd.DataFrame({"a": [], "b": []})
        result = sort_rows_stable(df)
        assert len(result) == 0


# ---------------------------------------------------------------------------
# Comparison: strict fields
# ---------------------------------------------------------------------------


class TestStrictComparison:
    def test_matching_dataframes_pass(self) -> None:
        expected = pd.DataFrame(
            {
                "flagid": ["MIL_3_00_00-0_371"],
                "flag_descr": ["test"],
                "flag_type": ["Warn"],
                "abort_yn": ["N"],
            }
        )
        actual = expected.copy()
        diff = compare(expected, actual, key_columns=["flagid"])
        assert diff.is_match

    def test_flagid_difference_fails(self) -> None:
        expected = pd.DataFrame({"flagid": ["MIL_3_00_00-0_371"], "flag_type": ["Warn"]})
        actual = pd.DataFrame({"flagid": ["MIL_3_00_00-0_372"], "flag_type": ["Warn"]})
        diff = compare(expected, actual, key_columns=["flagid"])
        assert not diff.is_match
        assert len(diff.flagid_diffs) > 0

    def test_strict_field_diff_fails(self) -> None:
        expected = pd.DataFrame(
            {
                "flagid": ["MIL_3_00_00-0_371"],
                "flag_type": ["Warn"],
            }
        )
        actual = pd.DataFrame(
            {
                "flagid": ["MIL_3_00_00-0_371"],
                "flag_type": ["Abort"],
            }
        )
        diff = compare(expected, actual, key_columns=["flagid"])
        assert not diff.is_match
        assert len(diff.strict_diffs) > 0

    def test_missing_rows_fail(self) -> None:
        expected = pd.DataFrame(
            {
                "flagid": ["ID1", "ID2"],
                "flag_type": ["Warn", "Warn"],
            }
        )
        actual = pd.DataFrame(
            {
                "flagid": ["ID1"],
                "flag_type": ["Warn"],
            }
        )
        diff = compare(expected, actual, key_columns=["flagid"])
        assert not diff.is_match
        assert diff.missing_rows > 0

    def test_unexpected_rows_fail(self) -> None:
        expected = pd.DataFrame({"flagid": ["ID1"], "flag_type": ["Warn"]})
        actual = pd.DataFrame(
            {
                "flagid": ["ID1", "ID2"],
                "flag_type": ["Warn", "Warn"],
            }
        )
        diff = compare(expected, actual, key_columns=["flagid"])
        assert not diff.is_match
        assert diff.unexpected_rows > 0


# ---------------------------------------------------------------------------
# Comparison: message differences are informational
# ---------------------------------------------------------------------------


class TestMessageDifferences:
    def test_message_diff_does_not_fail(self) -> None:
        expected = pd.DataFrame(
            {
                "flagid": ["MIL_3_00_00-0_371"],
                "flag_type": ["Warn"],
                "message": ["Patient P001 has issue"],
            }
        )
        actual = pd.DataFrame(
            {
                "flagid": ["MIL_3_00_00-0_371"],
                "flag_type": ["Warn"],
                "message": ["Different wording for same issue"],
            }
        )
        diff = compare(expected, actual, key_columns=["flagid"])
        assert diff.is_match  # message diff is informational
        assert len(diff.message_diffs) > 0

    def test_assert_parity_passes_with_message_diff(self) -> None:
        expected = pd.DataFrame(
            {
                "flagid": ["MIL_3_00_00-0_371"],
                "flag_type": ["Warn"],
                "message": ["msg1"],
            }
        )
        actual = pd.DataFrame(
            {
                "flagid": ["MIL_3_00_00-0_371"],
                "flag_type": ["Warn"],
                "message": ["msg2"],
            }
        )
        assert_parity(expected, actual, key_columns=["flagid"])


# ---------------------------------------------------------------------------
# Null-sensitive fixture shapes
# ---------------------------------------------------------------------------


class TestNullSensitiveFixtures:
    def test_null_linkage_id_comparison(self) -> None:
        """Null CPatID values should canonicalize consistently."""
        expected = pd.DataFrame(
            {
                "flagid": ["ID1", "ID2"],
                "cpatid": [None, "C002"],
                "flag_type": ["Warn", "Warn"],
            }
        )
        actual = pd.DataFrame(
            {
                "flagid": ["ID1", "ID2"],
                "cpatid": [None, "C002"],
                "flag_type": ["Warn", "Warn"],
            }
        )
        diff = compare(expected, actual, key_columns=["flagid"])
        assert diff.is_match

    def test_null_date_field_comparison(self) -> None:
        """Null date fields should be handled gracefully."""
        expected = pd.DataFrame(
            {
                "flagid": ["ID1"],
                "adate": [None],
                "flag_type": ["Warn"],
            }
        )
        actual = pd.DataFrame(
            {
                "flagid": ["ID1"],
                "adate": [None],
                "flag_type": ["Warn"],
            }
        )
        diff = compare(expected, actual, key_columns=["flagid"])
        assert diff.is_match


# ---------------------------------------------------------------------------
# Fixture README/layout checks
# ---------------------------------------------------------------------------


class TestFixtureLayout:
    def test_readme_exists(self) -> None:
        from pathlib import Path

        readme = Path(__file__).parent / "fixtures" / "parity" / "README.md"
        assert readme.exists()

    def test_readme_mentions_sas_not_required(self) -> None:
        from pathlib import Path

        readme = Path(__file__).parent / "fixtures" / "parity" / "README.md"
        content = readme.read_text()
        assert "NOT required" in content or "not required" in content.lower()
