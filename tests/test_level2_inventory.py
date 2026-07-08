"""Validation test for Level 2 inventory document (NUM-39)."""

from __future__ import annotations

import re
from pathlib import Path


def _extract_check_ids_from_inventory() -> list[str]:
    """Extract all check IDs from the Level 2 inventory markdown table."""
    inventory_path = Path(__file__).parent.parent / "docs" / "level2-inventory.md"
    content = inventory_path.read_text()
    # Find all check IDs in table rows (format: | 200 | or | 217 |)
    ids: list[str] = []
    for match in re.finditer(r"\|\s*(\d{3})\s*\|", content):
        ids.append(match.group(1))
    return ids


class TestLevel2Inventory:
    def test_inventory_exists(self) -> None:
        path = Path(__file__).parent.parent / "docs" / "level2-inventory.md"
        assert path.exists()

    def test_inventory_has_check_ids(self) -> None:
        ids = _extract_check_ids_from_inventory()
        assert len(ids) > 0

    def test_no_duplicate_check_ids(self) -> None:
        ids = _extract_check_ids_from_inventory()
        assert len(ids) == len(set(ids)), f"Duplicate check IDs: {ids}"

    def test_inventory_includes_key_checks(self) -> None:
        ids = set(_extract_check_ids_from_inventory())
        # Key checks that must be documented
        expected = {"200", "201", "202", "203", "211", "217", "218", "219", "221"}
        missing = expected - ids
        assert not missing, f"Missing check IDs in inventory: {missing}"

    def test_inventory_has_family_grouping(self) -> None:
        path = Path(__file__).parent.parent / "docs" / "level2-inventory.md"
        content = path.read_text()
        assert "Duplicate/key" in content
        assert "Date/range" in content or "Date/range/value-domain" in content
        assert "Cross-table consistency" in content
        assert "Enrollment/eligibility" in content or "Enrollment" in content

    def test_inventory_has_abort_behavior(self) -> None:
        path = Path(__file__).parent.parent / "docs" / "level2-inventory.md"
        content = path.read_text()
        assert "Abort" in content

    def test_inventory_has_source_citations(self) -> None:
        path = Path(__file__).parent.parent / "docs" / "level2-inventory.md"
        content = path.read_text()
        assert "std_macros" in content or "standard_macros" in content.lower()
