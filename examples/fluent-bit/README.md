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
| Log format parser | Custom regex for IQ Server format: `YYYY-MM-DD HH:MM:SS,SSS+ZZZZ LEVEL [thread] user logger - message` |
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

## Log Format

IQ Server logs use this format:

```
YYYY-MM-DD HH:MM:SS,SSS+ZZZZ LEVEL [thread] user logger - message
```

Example:
```
2026-06-02 17:01:28,138+0000 INFO [main] *SYSTEM com.sonatype.insight.brain.service - Initializing...
```

The ConfigMap includes a regex parser that extracts:
- `time` - Timestamp
- `level` - Log level (INFO, DEBUG, ERROR, etc.)
- `thread` - Thread name
- `user` - User context
- `logger` - Logger class name
- `message` - Log message

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

Each file contains entries from all IQ Server pods combined, one record per line. Because the `nexus_iq` parser produces a structured record, the file output writes each record as JSON (with `time`, `level`, `thread`, `user`, `logger`, and `message` keys) regardless of whether `Format plain` or `Format json` is set in `[OUTPUT]`.

> **Note**: If you need the raw log line back instead of a JSON record, drop the `Parser nexus_iq` line from each `[INPUT]` section.

## Verification

```bash
# Check aggregated logs exist
kubectl exec -n <namespace> deployment/<iq-server-deployment> -- \
  ls -la /sonatype-work/clm-cluster/log/*.aggregated.log

# View sample content
kubectl exec -n <namespace> deployment/<iq-server-deployment> -- \
  head -5 /sonatype-work/clm-cluster/log/clm-server.aggregated.log
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
