# External Log Aggregation Examples

This directory contains validated examples for integrating external log aggregation solutions with the IQ Server HA Helm chart.

> **Important**: These examples deploy *alongside* the Helm chart, not *inside* it. They mount the same PVC that IQ Server uses for log storage, allowing them to read and aggregate logs without modifying the chart.

## Available Examples

| Directory | Description | Output Destination |
|-----------|-------------|-------------------|
| [`fluent-bit/`](fluent-bit/) | Fluent Bit DaemonSet that tails IQ Server logs and writes parsed records back to the shared PVC | Shared PVC (local file output) |
| [`datadog/`](datadog/) | Same shape as the Fluent Bit example, but also forwards each log type to Datadog's HTTP intake | Datadog + shared PVC |

Each subdirectory has its own README with deployment steps, parser configuration, and verification instructions.

## Background

For an explanation of the log files IQ Server emits and their formats, see [Log Aggregation](../chart/README.md#log-aggregation) in the chart README.
