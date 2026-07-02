<!--

    Sonatype Nexus (TM) Open Source Version
    Copyright (c) 2008-present Sonatype, Inc.
    All rights reserved. Includes the third-party code listed at http://links.sonatype.com/products/nexus/oss/attributions.

    This program and the accompanying materials are made available under the terms of the Eclipse Public License Version 1.0,
    which accompanies this distribution and is available at http://www.eclipse.org/legal/epl-v10.html.

    Sonatype Nexus (TM) Professional Version is available from Sonatype, Inc. "Sonatype" and "Sonatype Nexus" are trademarks
    of Sonatype, Inc. Apache Maven is a trademark of the Apache Software Foundation. M2eclipse is a trademark of the
    Eclipse Foundation. All other trademarks are the property of their respective owners.

-->
# External Log Aggregation Examples

This directory contains validated examples for integrating external log aggregation solutions with the IQ Server HA Helm chart.

> **Important**: These examples deploy *alongside* the Helm chart, not *inside* it. They mount the same PVC that IQ Server uses for log storage, allowing them to read and aggregate logs without modifying the chart.

## Available Examples

| Directory | Description | Output Destination |
|-----------|-------------|-------------------|
| [`fluent-bit/`](fluent-bit/) | Single-replica Fluent Bit Deployment that tails IQ Server logs and writes parsed records back to the shared PVC | Shared PVC (local file output) |
| [`datadog/`](datadog/) | Same shape as the Fluent Bit example, but also forwards each log type to Datadog's HTTP intake | Datadog + shared PVC |

Each subdirectory has its own README with deployment steps, parser configuration, and verification instructions.

## Background

For an explanation of the log files IQ Server emits and their formats, see [Log Aggregation](../chart/README.md#log-aggregation) in the chart README.
