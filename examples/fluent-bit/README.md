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
# Fluent Bit Log Aggregation for IQ Server HA

> **Jira**: CLM-39987  
> **Purpose**: Demonstrate how to integrate Fluent Bit as an external log aggregator with the IQ Server HA Helm chart without modifying or forking the chart.

## Overview

As of Helm chart version 202.0.0, the bundled Fluentd has been removed. This example shows how to deploy Fluent Bit alongside the IQ Server HA deployment to aggregate logs from all pods.

## Architecture

```
┌────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                  │
│                                                        │
│  ┌────────────────┐     ┌────────────────┐           │
│  │ IQ Server Pod 1│     │ IQ Server Pod 2│           │
│  │ writes logs to │     │ writes logs to │           │
│  │ shared PVC     │     │ shared PVC     │           │
│  └───────┬────────┘     └───────┬────────┘           │
│          │                      │                     │
│          └──────────┬───────────┘                     │
│                     │                                 │
│            ┌────────▼────────┐                       │
│            │  Shared PVC      │                       │
│            │  (ReadWriteMany)│                       │
│            └────────┬────────┘                       │
│                     │                                 │
│            ┌────────▼────────┐                       │
│            │  Fluent Bit     │                       │
│            │  Deployment     │                       │
│            │  (1 replica)    │                       │
│            └────────┬────────┘                       │
│                     │                                 │
│            ┌────────▼────────┐                       │
│            │ Aggregated Logs │                       │
│            │ (same PVC)      │                       │
│            └─────────────────┘                       │
└────────────────────────────────────────────────────────┘
```

## About These YAML Files

These manifests are **specifically designed for IQ Server HA** - they are not generic Kubernetes examples.

### IQ Server-Specific Configuration

| Component | IQ Server-Specific Details |
|-----------|---------------------------|
| Log file paths | Tails `*-clm-server.log`, `*-request.log`, `*-audit.log`, etc. from `/sonatype-work/clm-cluster/log/` |
| Log format parsers | Four format-specific parsers (one per log type, plus raw passthrough for stderr) — see [Log Formats and Parsers](#log-formats-and-parsers) below |
| PVC mount | Mounts `iq-server-pvc` (the Helm chart's default PVC) |
| Namespace | Uses `iq-ha` (matches Helm chart default) |

### What Customers Need to Customize

| Setting | Default | When to Change |
|---------|---------|----------------|
| `namespace` | `iq-ha` | If using a different namespace in Helm |
| `claimName` | `iq-server-pvc` | If customized via `iq_server.persistence.persistentVolumeClaimName` |
| Output destination | File output | To forward logs to external systems |

## Prerequisites

1. IQ Server HA deployed using the Helm chart
2. PVC `iq-server-pvc` exists (default name from chart)
3. Same Kubernetes namespace as IQ Server deployment

## Quick Start

Copy the manifests, edit them to match your environment, then apply:

```bash
# Copy files for editing
cp fluent-bit-configmap.yaml my-fluent-bit-configmap.yaml
cp fluent-bit-deployment.yaml my-fluent-bit-deployment.yaml

# Edit both files to set the namespace and PVC claim name to match your IQ
# Server deployment. Defaults assumed by the manifests:
#   namespace:  iq-ha
#   claimName:  iq-server-pvc

# Apply
kubectl apply -f my-fluent-bit-configmap.yaml -f my-fluent-bit-deployment.yaml

# Verify deployment
kubectl get pods -n <your-namespace> -l app.kubernetes.io/name=fluent-bit
```

> **Why a single-replica `Deployment` and not a `DaemonSet`?** IQ Server logs
> live on a shared RWX PVC, not on per-node storage. A DaemonSet would put one
> pod on every node, and all of them would tail the same files concurrently —
> producing duplicate downstream records, racing on the SQLite tail-offset DB,
> and interleaving writes to the `*.aggregated.log` files. One reader is what
> this aggregation pattern needs. Scaling beyond `replicas: 1` reintroduces the
> duplication, so leave the replica count at 1.

## Log Files

Fluent Bit tails these log files from the shared PVC:

| Log Type | Pattern | Description |
|----------|---------|-------------|
| Server | `*-clm-server.log` | Main application logs |
| Request | `*-request.log` | HTTP request logs |
| Audit | `*-audit.log` | Audit trail logs |
| Policy Violation | `*-policy-violation.log` | Policy evaluation logs |
| Stderr | `*-stderr.log` | Standard error output |

## Log Formats and Parsers

IQ Server emits five distinct log files, each with a different format. Using
one parser for all of them produces poor output — JSON records get
double-wrapped, and access-log fields (status code, URL, latency) are lost in a
flat string. The ConfigMap defines a separate parser per log type so the
aggregated output is structured for every record:

| Source pattern | Parser | Format | Fields extracted |
|----------------|--------|--------|------------------|
| `*-clm-server.log` | `nexus_iq_server` | regex | `time`, `level`, `thread`, `user`, `logger`, `message` |
| `*-request.log` | `nexus_iq_request` | regex | `client_host`, `ident`, `user`, `time`, `request_url`, `status_code`, `bytes_sent`, `elapsed_ms`, `user_agent` |
| `*-audit.log` | `nexus_iq_audit` | JSON | All top-level keys (e.g. `timestamp`, `username`, `domain`, `type`, `data`) |
| `*-policy-violation.log` | `nexus_iq_policy_violation` | JSON | All top-level keys (e.g. `eventTimestamp`, `policyName`, `policyThreatLevel`, `componentIdentifier`) |
| `*-stderr.log` | _(none)_ | raw | Lines forwarded as-is in `{"log": "..."}` records |

### Format assumptions

The two regex parsers assume the chart's default `logFormat` strings:

- **Server log** uses `%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - %msg%n`. The `%X{username}` MDC value is empty for many internal threads (scheduler, cluster manager), which produces two consecutive spaces between `[thread]` and the logger — the regex makes the user field optional to handle both cases. If you customize `logFormat` (e.g. add a padded level `%-5level`), update the regex to match, otherwise lines fall through to a raw `{"log":"..."}` record.
- **Request log** uses `%clientHost %l %user [%date] "%requestURL" %statusCode %bytesSent %elapsedTime "%header{User-Agent}"`. Same caveat — customize the request `logFormat` and you'll need to update the regex.

The two JSON parsers are robust to schema additions (extra keys are passed through). They use `Time_Key` to identify the timestamp field — `timestamp` for audit, `eventTimestamp` for policy-violation, matching IQ Server's published log schemas.

### Buffer sizing for large records

Audit and policy-violation records can exceed Fluent Bit's default 32KB
per-line buffer (e.g. an audit `data` payload containing many components, or a
policy-violation event referencing a large dependency tree). The two JSON
inputs set `Buffer_Max_Size` to 1MB so realistic IQ records aren't dropped by
`Skip_Long_Lines`.

### Multi-line records

Stack traces in `*-clm-server.log` are joined back to their parent log
entry by the custom `iq_java_logback` multiline parser, configured on the
server-log `[INPUT]` (`multiline.parser  iq_java_logback`) and defined in
the `[MULTILINE_PARSER]` block at the end of the configmap. The built-in
`java` parser doesn't match IQ Server's timestamp format
(`HH:mm:ss,SSS` with comma-millis, where the built-in expects
`HH:mm:ss.SSS` with period-millis), so a custom parser is needed.
A typical entry like:

```
2026-06-08 14:22:40,001+0000 ERROR [http-1] *SYSTEM com.example.Foo - Failed
java.lang.RuntimeException: boom
    at com.example.Foo.bar(Foo.java:42)
    at com.example.Foo.baz(Foo.java:30)
Caused by: java.io.IOException: file not found
    at java.base/java.io.FileInputStream...
```

arrives as a single record where `message` contains the entire trace.

`*-stderr.log` entries are still tailed line-by-line. Multi-line stderr
content (rare in normal operation — JVM crash output is the typical case)
fragments. To handle it, add a `multiline.parser` line to the stderr
`[INPUT]` and pick a parser that matches your stderr format — see the
[Fluent Bit multiline tail documentation](https://docs.fluentbit.io/manual/administration/configuring-fluent-bit/multiline-parsing).

## Aggregated Output

Fluent Bit writes aggregated logs back to the shared PVC:

```
/sonatype-work/clm-cluster/log/
├── clm-server.aggregated.log
├── request.aggregated.log
├── audit.aggregated.log
├── policy-violation.aggregated.log
└── stderr.aggregated.log
```

Each file contains entries from all IQ Server pods combined, one JSON record
per line. The fields in each record match the parser used for that source —
see the [Log Formats and Parsers](#log-formats-and-parsers) table above. The
file output writes each record as JSON regardless of whether `Format plain` or
`Format json` is set in `[OUTPUT]`, because the source records are already
structured.

> **Note**: If you need raw log lines back instead of structured JSON for a
> given source, drop the `Parser` line from that `[INPUT]` section. The output
> for that source then becomes `{"log": "..."}` records containing the
> verbatim line.

## Verification

```bash
# Check aggregated logs exist
kubectl exec -n <namespace> deployment/<iq-server-deployment> -- \
  ls -la /sonatype-work/clm-cluster/log/*.aggregated.log

# View sample content
kubectl exec -n <namespace> deployment/<iq-server-deployment> -- \
  head -5 /sonatype-work/clm-cluster/log/clm-server.aggregated.log
```

### Triggering policy-violation entries

Unlike the server, request, and audit logs (which write continuously as IQ
Server runs), `*-policy-violation.log` is event-driven — a record is only
written when a policy evaluation finds a violation. On a freshly deployed
cluster the file may not exist yet, and `policy-violation.aggregated.log`
will be empty until evaluations begin. This is expected behavior, not a
configuration problem.

To force entries for verification, evaluate a binary that you know will
produce violations against an application with policies attached:

1. Pick or create an application that inherits the default reference
   policies (the chart's `createSampleData: true` default seeds a Sandbox
   Application that already has them).
2. In the IQ Server UI, open that application and choose **Actions →
   Evaluate a file**.
3. Upload a deliberately vulnerable artifact (e.g., a [WebGoat
   release](https://github.com/WebGoat/WebGoat/releases) JAR — its bundled
   dependencies trigger many violations against default policies).
4. After the evaluation completes, confirm the source log was written:

   ```bash
   kubectl exec -n <namespace> <iq-server-pod> -- \
     wc -l /sonatype-work/clm-cluster/log/*-policy-violation.log
   ```

5. Confirm Fluent Bit aggregated the entries (it picks up newly created
   files on each `Refresh_Interval`, default 10s):

   ```bash
   kubectl exec -n <namespace> <iq-server-pod> -- \
     wc -l /sonatype-work/clm-cluster/log/policy-violation.aggregated.log
   ```

The aggregated line count should match (or exceed, if other evaluations
have run) the source line count. Each line is a JSON record with the shape
documented at
[help.sonatype.com/en/policy-violation-log.html](https://help.sonatype.com/en/policy-violation-log.html):

```json
{"eventType":"create","eventTimestamp":"2026-06-08T14:22:40.022Z","policyName":"Security-Critical","policyThreatLevel":10,"policyConditionTriggers":[{"reason":"Found security vulnerability CVE-2023-20873 with severity >= 9 (severity = 9.8)"}],"applicationPublicId":"sandbox-application","componentIdentifier":{"format":"maven","coordinates":{"artifactId":"spring-boot-actuator-autoconfigure","groupId":"org.springframework.boot","version":"2.4.3"}}}
```

## Customization

### Changing the Output Destination

The example uses file output for simplicity. To forward logs to external systems, modify the `[OUTPUT]` sections in the ConfigMap.

> **Tip**: Consult the [Fluent Bit documentation](https://docs.fluentbit.io/) for output plugin configuration options.

## Troubleshooting

### Fluent Bit Not Finding Logs

```bash
# Check Fluent Bit logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=fluent-bit

# Verify PVC mount
kubectl describe pod -n <namespace> -l app.kubernetes.io/name=fluent-bit | grep -A 5 "Mounts:"
```

### No Aggregated Logs

1. Ensure PVC has `ReadWriteMany` access mode
2. Verify Fluent Bit pod is running: `kubectl get pods -n <namespace>`
3. Check Fluent Bit logs for errors

### `invalid time format` warnings on audit/policy-violation parsers

You may occasionally see warnings like:

```
[error] [parser] cannot parse '2026-06-09T16:43:04Z'
[ warn] [parser:nexus_iq_audit] invalid time format %Y-%m-%dT%H:%M:%S.%LZ for '2026-06-09T16:43:04Z'
```

IQ Server's audit and policy-violation logs use ISO-8601 timestamps with millisecond precision, but its JSON serializer (Jackson) trims trailing zeros — so a timestamp landing on an integer second is emitted without a fractional component (`...04Z` instead of `...04.000Z`), which doesn't match the parser's `%Y-%m-%dT%H:%M:%S.%LZ` `Time_Format`. The record is **not dropped**: Fluent Bit falls back to ingestion time for `@timestamp`, and every other field including the original `timestamp`/`eventTimestamp` value is preserved in the record body. The warning is benign log noise; expect a small number of them in audit logs.

## Cleanup

```bash
kubectl delete -f my-fluent-bit-deployment.yaml -n <your-namespace>
kubectl delete -f my-fluent-bit-configmap.yaml -n <your-namespace>
```

## Aggregator state and the cleanup CronJob

The `.fluent-bit-*.db` tail-offset files and the `*.aggregated.log` files
both live in `/sonatype-work/clm-cluster/log/`, which is the directory the
chart's `aggregateLogFileRetention` CronJob deletes from
(`find /log/ -type f -mtime +N -delete`).

Under normal operation this is fine — both file kinds are continuously
updated while the aggregator runs, so their mtime stays recent and
`-mtime +N` never matches. The risk window opens only if the aggregator is
**stopped for longer than the retention window**: the offset DBs age out and
get deleted, and on next start Fluent Bit re-reads each still-present log
file from head, producing duplicate records downstream until it catches up.
If you plan extended downtime, either pause the cleanup CronJob or expect
that one-time re-read on restart.

## See Also

- [Chart README - Log Aggregation Section](../../chart/README.md#log-aggregation)
- [CLM-39117](https://sonatype.atlassian.net/browse/CLM-39117) - Remove Fluentd from Helm chart
