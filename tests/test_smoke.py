"""Smoke tests for CLI, help output, and package import."""

from __future__ import annotations

import subprocess
import sys

import pytest
from typer.testing import CliRunner

from qa_mil import __version__
from qa_mil.cli import app

runner = CliRunner()


def test_package_importable() -> None:
    """The qa_mil package should be importable."""
    import qa_mil

    assert qa_mil is not None


def test_version_is_string() -> None:
    """__version__ should be a non-empty string."""
    assert isinstance(__version__, str)
    assert len(__version__) > 0


def test_cli_help() -> None:
    """qa-mil --help should succeed and mention qa-mil."""
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "qa" in result.stdout.lower()


def test_cli_version_command() -> None:
    """qa-mil version should print the version."""
    result = runner.invoke(app, ["version"])
    assert result.exit_code == 0
    assert __version__ in result.stdout


def test_cli_no_args_shows_help() -> None:
    """Running with no args should show help (exit code 0 or 2)."""
    result = runner.invoke(app, [])
    assert result.exit_code in (0, 2)


@pytest.mark.parametrize("args", [["--help"], ["version"]])
def test_cli_entrypoint_subprocess(args: list[str]) -> None:
    """The installed qa-mil entrypoint should work via subprocess."""
    result = subprocess.run(
        [sys.executable, "-m", "qa_mil.cli", *args],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
