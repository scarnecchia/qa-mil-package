"""CLI entrypoint for qa-mil."""

from __future__ import annotations

import typer

from qa_mil.config import load_config
from qa_mil.manifest import (
    load_input_manifest,
    validate_etl_consistency,
    validate_table_paths,
)
from qa_mil.observability import init_observability

app = typer.Typer(
    name="qa-mil",
    help="SCDM MIL data QA review tool (Python port).",
    no_args_is_help=True,
)


@app.command()
def version() -> None:
    """Print the qa-mil package version."""
    from qa_mil import __version__

    typer.echo(__version__)


@app.command(name="validate-config")
def validate_config(
    config: str = typer.Option(..., "--config", help="Path to the config YAML file."),
) -> None:
    """Validate config and input manifest without running checks."""
    try:
        cfg = load_config(config)
    except FileNotFoundError as e:
        typer.echo(f"Error: {e}", err=True)
        raise typer.Exit(1) from e
    except Exception as e:
        typer.echo(f"Config validation error: {e}", err=True)
        raise typer.Exit(1) from e

    try:
        manifest, manifest_parent = load_input_manifest(cfg.input_manifest)
        validate_etl_consistency(cfg.etl_number, manifest.etl_number)
        validate_table_paths(manifest, manifest_parent, check_exists=True)
    except FileNotFoundError as e:
        typer.echo(f"Error: {e}", err=True)
        raise typer.Exit(1) from e
    except ValueError as e:
        typer.echo(f"Manifest validation error: {e}", err=True)
        raise typer.Exit(1) from e

    typer.echo(f"Config valid. Request ID: {cfg.request_id}")
    typer.echo(f"ETL: {cfg.etl_number}, Backend: {cfg.backend.name}")
    typer.echo("All validations passed.")


@app.command(name="list-checks")
def list_checks() -> None:
    """List all registered checks with metadata."""
    from qa_mil.checks.registry import list_checks as _list_checks

    checks = _list_checks()
    if not checks:
        typer.echo("No checks registered.")
        return

    typer.echo(f"{'ID':<8} {'Lvl':<4} {'Severity':<8} {'Scope':<10} {'Tables':<20} Description")
    typer.echo("-" * 100)
    for check in checks:
        md = check.metadata
        tables = ",".join(sorted(md.tables))
        typer.echo(
            f"{md.check_id:<8} {md.level:<4} {md.severity.value:<8} "
            f"{md.output_scope.value:<10} {tables:<20} {md.description}"
        )


@app.command()
def run(
    config: str = typer.Option(..., "--config", help="Path to the config YAML file."),
) -> None:
    """Run the full QA MIL pipeline."""
    init_observability()

    from qa_mil.runner import run as _run

    try:
        cfg = load_config(config)
    except FileNotFoundError as e:
        typer.echo(f"Error: {e}", err=True)
        raise typer.Exit(1) from e
    except Exception as e:
        typer.echo(f"Config validation error: {e}", err=True)
        raise typer.Exit(1) from e

    result = _run(cfg)
    typer.echo(f"Run complete. Request ID: {result['request_id']}")
    summary = result["output_summary"]
    typer.echo(f"dplocal flags: {summary['dplocal_flag_count']}")
    typer.echo(f"msoc flags: {summary['msoc_flag_count']}")


if __name__ == "__main__":
    app()
