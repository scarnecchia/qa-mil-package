"""OpenTelemetry observability for qa-mil.

Environment-driven configuration with safe local defaults:
- No-op exporter locally (default)
- OTLP collector configurable via OTEL_EXPORTER_OTLP_ENDPOINT
- Console exporter via OTEL_EXPORTER_TYPE=console

Privacy: never emit PHI/PII, patient identifiers, encounter IDs, or source cell values
as span attributes, metric labels, or log records.
"""

from __future__ import annotations

import os
from collections.abc import Iterator
from contextlib import contextmanager
from typing import Any

# Safe attribute keys that are always OK to emit
SAFE_ATTRIBUTE_KEYS = frozenset(
    {
        "qa_mil.request_id",
        "qa_mil.project_id",
        "qa_mil.workplan_id",
        "qa_mil.dpid",
        "qa_mil.version_id",
        "qa_mil.backend_name",
        "qa_mil.manifest_version",
        "qa_mil.scdm_version",
        "qa_mil.check_id",
        "qa_mil.check_level",
        "qa_mil.check_severity",
        "qa_mil.check_output_scope",
        "qa_mil.check_tables",
        "qa_mil.check_status",
        "qa_mil.flag_count",
        "qa_mil.outcome",
        "qa_mil.etl_number",
    }
)

# Sensitive values that must never appear in telemetry
SENSITIVE_PATTERNS = [
    "mpatid",
    "cpatid",
    "patid",
    "encounterid",
]

_tracer: Any = None
_meter: Any = None
_initialized = False


def init_observability(
    service_name: str = "qa-mil",
    service_version: str = "0.1.0",
) -> None:
    """Initialize OpenTelemetry tracer and meter.

    Uses environment variables for configuration:
    - OTEL_EXPORTER_TYPE: "none" (default), "console", "otlp"
    - OTEL_EXPORTER_OTLP_ENDPOINT: OTLP collector endpoint
    """
    global _tracer, _meter, _initialized
    if _initialized:
        return

    exporter_type = os.environ.get("OTEL_EXPORTER_TYPE", "none").lower()

    if exporter_type == "none":
        # Use no-op tracer/meter
        from opentelemetry import metrics, trace
        from opentelemetry.sdk.metrics import MeterProvider
        from opentelemetry.sdk.trace import TracerProvider

        trace.set_tracer_provider(TracerProvider())
        metrics.set_meter_provider(MeterProvider())
        _tracer = trace.get_tracer(service_name, service_version)
        _meter = metrics.get_meter(service_name, service_version)

    elif exporter_type == "console":
        from opentelemetry import metrics, trace
        from opentelemetry.sdk.metrics import MeterProvider
        from opentelemetry.sdk.metrics.export import (
            ConsoleMetricExporter,
            PeriodicExportingMetricReader,
        )
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import (
            BatchSpanProcessor,
            ConsoleSpanExporter,
        )

        provider = TracerProvider()
        provider.add_span_processor(BatchSpanProcessor(ConsoleSpanExporter()))
        trace.set_tracer_provider(provider)

        reader = PeriodicExportingMetricReader(ConsoleMetricExporter(), export_interval_millis=5000)
        metrics.set_meter_provider(MeterProvider(metric_readers=[reader]))

        _tracer = trace.get_tracer(service_name, service_version)
        _meter = metrics.get_meter(service_name, service_version)

    elif exporter_type == "otlp":
        from opentelemetry import metrics, trace
        from opentelemetry.exporter.otlp.proto.http.metric_exporter import (
            OTLPMetricExporter,
        )
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import (
            OTLPSpanExporter,
        )
        from opentelemetry.sdk.metrics import MeterProvider
        from opentelemetry.sdk.metrics.export import (
            PeriodicExportingMetricReader,
        )
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor

        provider = TracerProvider()
        provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
        trace.set_tracer_provider(provider)

        endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")
        reader = PeriodicExportingMetricReader(
            OTLPMetricExporter(endpoint=f"{endpoint}/v1/metrics"),
            export_interval_millis=5000,
        )
        metrics.set_meter_provider(MeterProvider(metric_readers=[reader]))

        _tracer = trace.get_tracer(service_name, service_version)
        _meter = metrics.get_meter(service_name, service_version)

    else:
        from opentelemetry import metrics, trace

        _tracer = trace.get_tracer(service_name, service_version)
        _meter = metrics.get_meter(service_name, service_version)

    _initialized = True


def get_tracer() -> Any:
    """Get the initialized tracer (or a no-op one if not initialized)."""
    if _tracer is None:
        init_observability()
    return _tracer


def get_meter() -> Any:
    """Get the initialized meter (or a no-op one if not initialized)."""
    if _meter is None:
        init_observability()
    return _meter


@contextmanager
def span(name: str, **attributes: Any) -> Iterator[Any]:
    """Context manager for creating a traced span.

    Only safe attributes are set on the span.
    """
    tracer = get_tracer()
    with tracer.start_as_current_span(name) as s:
        for key, value in attributes.items():
            attr_key = f"qa_mil.{key}" if not key.startswith("qa_mil.") else key
            if attr_key in SAFE_ATTRIBUTE_KEYS:
                s.set_attribute(attr_key, value)
        yield s


def record_counter(name: str, value: int = 1, **attributes: Any) -> None:
    """Record a metric counter."""
    meter = get_meter()
    counter = meter.create_counter(name)
    safe_attrs = {
        k: v
        for k, v in attributes.items()
        if f"qa_mil.{k}" in SAFE_ATTRIBUTE_KEYS or k in SAFE_ATTRIBUTE_KEYS
    }
    counter.add(value, safe_attrs)


def assert_no_sensitive_data(
    span_attributes: dict[str, Any],
    log_records: list[str],
    known_sensitive_values: list[str],
) -> None:
    """Test helper: assert no known sensitive values appear in telemetry.

    Checks span attribute values and log record messages by substring match.
    """
    for attr_value in span_attributes.values():
        val_str = str(attr_value).lower()
        for sensitive in known_sensitive_values:
            if sensitive.lower() in val_str:
                raise AssertionError(
                    f"Sensitive value '{sensitive}' found in span attribute value: {attr_value}"
                )
    for log_msg in log_records:
        for sensitive in known_sensitive_values:
            if sensitive.lower() in log_msg.lower():
                raise AssertionError(
                    f"Sensitive value '{sensitive}' found in log record: {log_msg}"
                )
