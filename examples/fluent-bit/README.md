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
│            │  DaemonSet      │                       │
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
cp fluent-bit-daemonset.yaml my-fluent-bit-daemonset.yaml

# Edit both files to set the namespace and PVC claim name to match your IQ
# Server deployment. Defaults assumed by the manifests:
#   namespace:  iq-ha
#   claimName:  iq-server-pvc

# Apply
kubectl apply -f my-fluent-bit-configmap.yaml -f my-fluent-bit-daemonset.yaml

# Verify deployment
kubectl get pods -n <your-namespace> -l app.kubernetes.io/name=fluent-bit
```

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

### Known limitation: multi-line records

Stack traces and other multi-line entries in `*-clm-server.log` and
`*-stderr.log` fragment because each continuation line is tailed
independently. The first line of an exception parses cleanly; subsequent
`at com.foo.Bar(...)` and `Caused by:` lines fall through to raw
`{"log":"..."}` records. To join continuation lines back to the parent record,
add a `[MULTILINE_PARSER]` to `parsers.conf` and reference it via
`multiline.parser` in the matching `[INPUT]` — see the
[Fluent Bit multiline tail documentation](https://docs.fluentbit.io/manual/administration/configuring-fluent-bit/multiline-parsing).
This was left out of the example to keep the parser configuration legible.

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

## Cleanup

```bash
kubectl delete -f my-fluent-bit-daemonset.yaml -n <your-namespace>
kubectl delete -f my-fluent-bit-configmap.yaml -n <your-namespace>
```

## See Also

- [Chart README - Log Aggregation Section](../../chart/README.md#log-aggregation)
- [CLM-39117](https://sonatype.atlassian.net/browse/CLM-39117) - Remove Fluentd from Helm chart
