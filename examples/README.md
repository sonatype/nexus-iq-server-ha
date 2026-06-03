# External Log Aggregation Examples

This directory contains validated examples for integrating external log aggregation solutions with the IQ Server HA Helm chart.

> **Important**: These examples deploy *alongside* the Helm chart, not *inside* it. They mount the same PVC that IQ Server uses for log storage, allowing them to read and aggregate logs without modifying the chart.

## Available Examples

| Directory | Description | Output Destination |
|-----------|-------------|-------------------|
| `fluent-bit/` | Fluent Bit writing to files (local aggregation) | Shared PVC |

## Common Pattern

All examples follow the same architecture:

```
┌────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                  │
│                                                        │
│  ┌────────────────┐     ┌────────────────┐           │
│  │ IQ Server Pod 1│     │ IQ Server Pod 2│           │
│  │ writes to:     │     │ writes to:     │           │
│  │ /sonatype-work │     │ /sonatype-work │           │
│  │ /clm-cluster/  │     │ /clm-cluster/  │           │
│  │ log/*.log      │     │ log/*.log      │           │
│  └───────┬────────┘     └───────┬────────┘           │
│          │                      │                     │
│          └──────────┬───────────┘                     │
│                     │                                 │
│            ┌────────▼────────┐                       │
│            │  Shared PVC      │                       │
│            │  (ReadWriteMany) │                       │
│            └────────┬────────┘                       │
│                     │                                 │
│            ┌────────▼────────┐                       │
│            │ Fluent Bit      │                       │
│            │ DaemonSet       │                       │
│            └────────┬────────┘                       │
│                     │                                 │
│            ┌────────▼────────┐                       │
│            │ Destination     │                       │
│            │ (File / etc.)   │                       │
│            └─────────────────┘                       │
└────────────────────────────────────────────────────────┘
```

## Log File Locations

IQ Server writes logs to the shared volume at:

| Log Type | File Pattern | Description |
|----------|-------------|-------------|
| Server | `*-clm-server.log` | Main application logs |
| Request | `*-request.log` | HTTP request logs |
| Audit | `*-audit.log` | Audit trail logs |
| Policy Violation | `*-policy-violation.log` | Policy evaluation logs |
| Stderr | `*-stderr.log` | Standard error output |

Each file is prefixed with the pod hostname, e.g.:
```
iq-cluster-iq-server-deployment-777c4869f5-dgd52-clm-server.log
iq-cluster-iq-server-deployment-777c4869f5-xf8jh-clm-server.log
```

## Prerequisites for All Examples

1. **Deployed IQ Server HA** with the Helm chart
2. **PVC name**: `iq-server-pvc` (default)
3. **Namespace**: Same as IQ Server deployment

## Quick Start

1. Review the configuration files in `fluent-bit/`
2. Customize the namespace if needed (default: `iq-ha`)
3. Apply the manifests:

```bash
# Option 1: Using the default namespace (iq-ha)
kubectl apply -f fluent-bit/fluent-bit-configmap.yaml
kubectl apply -f fluent-bit/fluent-bit-daemonset.yaml

# Option 2: Using a custom namespace (replace 'your-namespace')
sed 's/namespace: iq-ha/namespace: your-namespace/g' fluent-bit/fluent-bit-configmap.yaml | kubectl apply -f -
sed 's/namespace: iq-ha/namespace: your-namespace/g' fluent-bit/fluent-bit-daemonset.yaml | kubectl apply -f -
```

> **Note:** The YAML files have `namespace: iq-ha` hardcoded. When using a custom namespace, either use the `sed` approach above or make a local copy of the files and edit them.

## Customization

Each example includes a ConfigMap that you can customize for your environment:

1. **Parser**: Adjust regex patterns if log format changes
2. **Filters**: Add/modify filters to enrich logs with metadata
3. **Outputs**: Configure destination endpoints, credentials, etc.

## Troubleshooting

### Check Log Aggregator Status

```bash
# Using default namespace
kubectl get pods -n iq-ha -l app.kubernetes.io/component=log-aggregator

# Using custom namespace
kubectl get pods -n your-namespace -l app.kubernetes.io/component=log-aggregator
```

### View Aggregator Logs

```bash
# Using default namespace
kubectl logs -n iq-ha -l app.kubernetes.io/component=log-aggregator

# Using custom namespace
kubectl logs -n your-namespace -l app.kubernetes.io/component=log-aggregator
```

### Verify PVC Mount

```bash
# Using default namespace and PVC name
kubectl exec -n iq-ha deployment/iq-cluster-iq-server-deployment -- \
  ls -la /sonatype-work/clm-cluster/log/
```

## References

- [CLM-39987](https://sonatype.atlassian.net/browse/CLM-39987) - Bring your own log aggregation
- [CLM-39117](https://sonatype.atlassian.net/browse/CLM-39117) - Remove Fluentd from Helm chart
- [Fluent Bit Documentation](https://docs.fluentbit.io/)
