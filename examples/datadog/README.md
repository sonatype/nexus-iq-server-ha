# Datadog Log Aggregation for IQ Server HA

> **Jira**: CLM-39987
> **Purpose**: Demonstrate how to forward IQ Server HA logs to Datadog using Fluent Bit, without modifying or forking the Helm chart.

## Overview

Fluent Bit runs as a single-replica Deployment alongside the IQ Server HA deployment, tails the five log files IQ Server writes to its shared PVC, applies per-format parsers, and ships each record to two destinations:

1. **PVC** — `*.aggregated.log` files (same as the [Fluent Bit example](../fluent-bit/README.md))
2. **Datadog HTTP intake** — over HTTPS, one source tag per log type

Keeping the file output gives you a working local copy on day one even if the Datadog API key is wrong, and lets you compare what Fluent Bit captured against what landed in Datadog when debugging.

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                          │
│                                                                │
│  ┌────────────┐    ┌────────────┐                             │
│  │ IQ Pod 1   │    │ IQ Pod 2   │   (writes 5 log types)      │
│  └─────┬──────┘    └─────┬──────┘                             │
│        └─────────┬───────┘                                     │
│             Shared PVC (RWX)                                   │
│                  │                                             │
│         ┌────────▼──────────┐                                  │
│         │ Fluent Bit        │                                  │
│         │ (1-replica Deploy)│                                  │
│         └────┬─────────┬────┘                                  │
│              │         │                                       │
│              ▼         └─── HTTPS ──┐                          │
│      *.aggregated.log               │                          │
│      (back to PVC)                  ▼                          │
└─────────────────────────────────────┼──────────────────────────┘
                                      ▼
                       Datadog HTTP intake (per region)
```

## Prerequisites

1. IQ Server HA deployed using the Helm chart
2. PVC `iq-server-pvc` exists (default name from chart)
3. Same Kubernetes namespace as IQ Server (`iq-ha` by default)
4. A Datadog account and API key — get one from **Organization Settings → API Keys** in the Datadog UI

> **Caution: don't run this Deployment alongside the Fluent Bit example's Deployment.** Both write to the same `*.aggregated.log` files on the shared PVC, so concurrent writes interleave or duplicate entries. Pick one example per cluster. To switch from the Fluent Bit example to this one, delete the other deployment first: `kubectl delete -f ../fluent-bit/fluent-bit-deployment.yaml`.

> **Why a single replica?** IQ Server logs live on a shared RWX PVC, not on per-node storage. A DaemonSet would put one pod on every node, and all of them would tail the same files concurrently — duplicating Datadog ingestion N-fold, racing on the SQLite tail-offset DB, and interleaving writes to the `*.aggregated.log` files. The Deployment uses `strategy: Recreate` so the old pod fully releases the offset DB before the new pod starts. Scaling beyond `replicas: 1` reintroduces the duplication.

## Quick Start

### 1. Create the Datadog API key secret

The Deployment expects a secret named `datadog-api-key` in the IQ namespace, with the API key under the `api-key` field.

**Recommended (imperative):**
```bash
kubectl create secret generic datadog-api-key \
  --from-literal=api-key=<YOUR_DATADOG_API_KEY> \
  -n iq-ha
```

**Alternative (declarative):**
Edit `datadog-secret-template.yaml`, replace `REPLACE_ME` with your key, then `kubectl apply -f` a copy that's not under version control.

### 2. Set your Datadog site

By default the configmap targets the **US5** region (`http-intake.logs.us5.datadoghq.com`). If your Datadog account lives elsewhere, edit all five `[OUTPUT] Name datadog` blocks in `fluent-bit-configmap.yaml` to use the correct host:

| Datadog site | `Host` value |
|---|---|
| US1 (datadoghq.com) | `http-intake.logs.datadoghq.com` |
| US3 (us3.datadoghq.com) | `http-intake.logs.us3.datadoghq.com` |
| US5 (us5.datadoghq.com) | `http-intake.logs.us5.datadoghq.com` |
| EU1 (datadoghq.eu) | `http-intake.logs.datadoghq.eu` |
| EU2 (eu2.datadoghq.com) | `http-intake.logs.eu2.datadoghq.com` |
| AP1 (ap1.datadoghq.com) | `http-intake.logs.ap1.datadoghq.com` |

You can confirm your site by checking the URL of the Datadog UI you log in to.

### 3. Apply the manifests

> **PVC name mismatch?** The manifests assume the Helm chart's default PVC name `iq-server-pvc`. If you customized the name via `iq_server.persistence.persistentVolumeClaimName`, edit `fluent-bit-deployment.yaml` and replace `claimName: iq-server-pvc` with your actual PVC name before applying.

```bash
kubectl apply -f fluent-bit-configmap.yaml
kubectl apply -f fluent-bit-deployment.yaml
kubectl rollout status -n iq-ha deployment/fluent-bit-datadog
```

### 4. Verify

See the [Verification](#verification) section below.

## Log Files

| Log Type | Pattern | `dd_source` |
|---|---|---|
| Server | `*-clm-server.log` | `nexus_iq_server` |
| Request | `*-request.log` | `nexus_iq_request` |
| Audit | `*-audit.log` | `nexus_iq_audit` |
| Policy Violation | `*-policy-violation.log` | `nexus_iq_policy_violation` |
| Stderr | `*-stderr.log` | `nexus_iq_stderr` |

All five types share `dd_service: iq-server` and `dd_tags: env:production`. Edit the configmap to change either.

## Verification

### Datadog UI — Live Tail

Open **Logs → Live Tail** in Datadog and filter by `service:iq-server`. Within ~10 seconds of the Deployment rolling out, you should see entries from all five sources streaming in.

> **Historical logs in Datadog:** Audit and policy-violation records carry their own `timestamp` / `eventTimestamp` fields, which Datadog uses as the official log timestamp (not ingest time). If you're testing with older logs or pre-populated PVCs, expand the Logs Explorer time range to match when the events actually occurred.

If nothing appears:
- Check the Fluent Bit pod logs: `kubectl logs -n iq-ha -l app.kubernetes.io/name=fluent-bit-datadog --tail=50`
- Look for HTTP errors (401 = bad API key, 403 = wrong region — see [Troubleshooting](#troubleshooting))

### Datadog UI — Logs Explorer (facet extraction)

Open **Logs → Explorer** and filter by `source:nexus_iq_policy_violation`. Click into one of the records — Datadog should have extracted facets from the JSON body (`policyName`, `policyThreatLevel`, `componentIdentifier.coordinates.*`, etc.).

If facets are missing, the JSON parser in the Fluent Bit configmap may not have applied — check `kubectl logs` for parser errors.

### PVC file output (still working)

The example also writes the same `*.aggregated.log` files as the Fluent Bit example. Confirm they're growing:

```bash
kubectl exec -n iq-ha $(kubectl get pod -n iq-ha -l app.kubernetes.io/name=iq-server -o jsonpath='{.items[0].metadata.name}') -- \
  ls -la /sonatype-work/clm-cluster/log/*.aggregated.log
```

### Triggering policy-violation entries

`*-policy-violation.log` is event-driven — entries appear only when an evaluation finds a violation. To force entries for verification, follow the same procedure as the Fluent Bit example: upload a deliberately vulnerable artifact (e.g., a [WebGoat release](https://github.com/WebGoat/WebGoat/releases) JAR) via **Application → Actions → Evaluate a file** in the IQ UI, against an application that inherits default policies (the Sandbox Application included with `createSampleData: true` works).

After the eval completes, check Datadog Logs Explorer with `source:nexus_iq_policy_violation` — new entries should appear within seconds.

## Customization

### Tags

Edit `dd_tags` on each `[OUTPUT] Name datadog` block. Use comma-separated `key:value` pairs:
```ini
dd_tags  env:staging,team:appsec,region:us-east-1
```

### Service name

Edit `dd_service` to use a name other than `iq-server`. The same value should be on all five outputs so all log types group together in Datadog's Service Catalog.

### Dropping log types

If you don't want a particular log type forwarded to Datadog (e.g., stderr is too noisy for your account), comment out the corresponding `[OUTPUT] Name datadog` block. The `[OUTPUT] Name file` block for that type keeps the local PVC aggregation working.

## Multi-line records

Stack traces in `*-clm-server.log` are joined back to their parent log entry by the custom `iq_java_logback` multiline parser, configured on the server-log `[INPUT]` (`multiline.parser  iq_java_logback`) and defined in the `[MULTILINE_PARSER]` block at the end of the configmap. The built-in `java` parser doesn't match IQ Server's timestamp format (`HH:mm:ss,SSS` with comma-millis, where the built-in expects `HH:mm:ss.SSS` with period-millis), so a custom parser is needed. Stack traces arrive in Datadog as single records.

`*-stderr.log` lines are tailed individually. Multi-line stderr (rare in normal operation) fragments. To handle it, add a `multiline.parser` line to the stderr `[INPUT]`.

## Troubleshooting

### 401 Unauthorized in Fluent Bit logs

Datadog rejected the API key. Check the secret:
```bash
kubectl get secret datadog-api-key -n iq-ha -o jsonpath='{.data.api-key}' | base64 -d
```
The output should be your API key, not `REPLACE_ME` or empty. Recreate the secret with the correct key and the FB pods will pick it up on next restart.

### 403 Forbidden in Fluent Bit logs

The `Host` line in the configmap doesn't match your Datadog account's region. Pick the right host from the [site table](#2-set-your-datadog-site) above and `kubectl apply` the updated configmap, then `kubectl rollout restart -n iq-ha deployment/fluent-bit-datadog`.

### Logs visible in `*.aggregated.log` but not in Datadog

Fluent Bit is parsing logs correctly but the Datadog output is failing silently. Check `kubectl logs` for HTTP errors. If pod logs are clean and Datadog still shows nothing, increase `Log_Level` to `debug` in the `[SERVICE]` block of the configmap and re-apply.

### Pod stuck in `CreateContainerConfigError`

The `datadog-api-key` secret doesn't exist in the namespace. Create it (see [Quick Start step 1](#1-create-the-datadog-api-key-secret)) and the pod will start.

### `invalid time format` warnings on audit/policy-violation parsers

You may occasionally see warnings like:

```
[error] [parser] cannot parse '2026-06-09T16:43:04Z'
[ warn] [parser:nexus_iq_audit] invalid time format %Y-%m-%dT%H:%M:%S.%LZ for '2026-06-09T16:43:04Z'
```

IQ Server's audit and policy-violation logs use ISO-8601 timestamps with millisecond precision, but its JSON serializer (Jackson) trims trailing zeros — so a timestamp landing on an integer second is emitted without a fractional component (`...04Z` instead of `...04.000Z`), which doesn't match the parser's `%Y-%m-%dT%H:%M:%S.%LZ` `Time_Format`. The record is **not dropped**: Fluent Bit falls back to ingestion time for `@timestamp`, and every other field including the original `timestamp`/`eventTimestamp` value is preserved in the record body and forwarded to Datadog. The warning is benign log noise; expect a small number of them in audit logs.

## Cleanup

```bash
kubectl delete -f fluent-bit-deployment.yaml
kubectl delete -f fluent-bit-configmap.yaml
kubectl delete secret datadog-api-key -n iq-ha
```

## Aggregator state and the cleanup CronJob

The `.fluent-bit-datadog-*.db` tail-offset files and the `*.aggregated.log` files both live in `/sonatype-work/clm-cluster/log/`, which is the directory the chart's `aggregateLogFileRetention` CronJob deletes from (`find /log/ -type f -mtime +N -delete`).

Under normal operation this is fine — both file kinds are continuously updated while the aggregator runs, so their mtime stays recent and `-mtime +N` never matches. The risk window opens only if the aggregator is **stopped for longer than the retention window**: the offset DBs age out and get deleted, and on next start Fluent Bit re-reads each still-present log file from head, producing duplicate records (sent to both Datadog and the aggregated PVC files) until it catches up. If you plan extended downtime, either pause the cleanup CronJob or expect that one-time re-read on restart.

## See Also

- [Fluent Bit example](../fluent-bit/README.md) — same shape but writes only to PVC, no external destination
- [Chart README — Log Aggregation Section](../../chart/README.md#log-aggregation)
- [CLM-39117](https://sonatype.atlassian.net/browse/CLM-39117) — Remove Fluentd from Helm chart
- [Fluent Bit Datadog output plugin docs](https://docs.fluentbit.io/manual/pipeline/outputs/datadog)
