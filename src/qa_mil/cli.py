"""CLI entrypoint for qa-mil."""

from __future__ import annotations

import typer

from qa_mil.config import load_config
from qa_mil.manifest import (
    load_input_manifest,
    validate_etl_consistency,
    validate_table_paths,
)

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
        resolved = validate_table_paths(manifest, manifest_parent, check_exists=True)
    except FileNotFoundError as e:
        typer.echo(f"Error: {e}", err=True)
        raise typer.Exit(1) from e
    except ValueError as e:
        typer.echo(f"Manifest validation error: {e}", err=True)
        raise typer.Exit(1) from e

    typer.echo(f"Config valid. Request ID: {cfg.request_id}")
    typer.echo(f"ETL: {cfg.etl_number}, Backend: {cfg.backend.name}")
    typer.echo(f"Tables found: {len(resolved)}")
    typer.echo(f"Semantic profile: {manifest.semantic_profile.name}")
    typer.echo("All validations passed.")


if __name__ == "__main__":
    app()
