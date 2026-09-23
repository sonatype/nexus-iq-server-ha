# Quick Start: OpenShift Deployment with Aurora PostgreSQL

## Overview

This guide shows how to deploy nexus-iq-server-ha on OpenShift with:
- **Restricted SCC** (custom UID range)
- **Aurora PostgreSQL** with TLS verification (`sslmode=verify-full`)

## Prerequisites

- OpenShift cluster with restricted SCC
- Aurora PostgreSQL database
- RDS CA certificate file (`rds-ca.pem`)
- Helm 3.x or 4.x
- kubectl CLI

## Step 1: Create Java Truststore

```bash
# Import RDS CA certificate
keytool -import \
  -alias rds-ca \
  -file rds-ca.pem \
  -keystore rds-truststore.jks \
  -storepass changeit \
  -noprompt

# Verify
keytool -list \
  -keystore rds-truststore.jks \
  -storepass changeit
```

## Step 2: Create OpenShift Namespace

```bash
# Create namespace
kubectl create namespace iq-server

# Verify your assigned UID range
oc describe project iq-server | grep sa.scc.uid-range
# Example output: 1000710000/10000
# This means UIDs from 1000710000 to 1000719999 are allowed
```

## Step 3: Create ConfigMap with Truststore

```bash
kubectl create configmap rds-ca-truststore \
  --from-file=rds-truststore.jks \
  --namespace iq-server

# Verify
kubectl get configmap rds-ca-truststore -n iq-server
```

## Step 4: Create Database Secrets

```bash
kubectl create secret generic iq-db-credentials \
  --from-literal=hostname=aurora-cluster.cluster-xyz.us-east-1.rds.amazonaws.com \
  --from-literal=port=5432 \
  --from-literal=name=iqserver \
  --from-literal=username=iq_user \
  --from-literal=password=your-password \
  --namespace iq-server
```

## Step 5: Create values-openshift.yaml

```yaml
# OpenShift + Aurora PostgreSQL Configuration

iq_server:
  useGitSsh: true

  # Pod-level security context for Deployment
  securityContext:
    runAsUser: 1000710000      # Replace with YOUR assigned UID
    runAsGroup: 1000710000     # Replace with YOUR assigned GID
    fsGroup: 1000710000

  # Database connection
  database:
    hostname: aurora-cluster.cluster-xyz.us-east-1.rds.amazonaws.com
    port: 5432
    name: iqserver
    username: iq_user

  # TLS parameters for PostgreSQL JDBC driver
  config:
    database:
      parameters:
        sslmode: verify-full
        sslrootcert: /etc/ssl/certs/rds-ca.pem

iq_server_jobs:
  # Container security context for Jobs
  securityContext:
    runAsUser: 1000710000      # Same as above
    runAsGroup: 1000710000

  # Mount RDS CA truststore
  extraVolumes:
    - name: rds-truststore
      configMap:
        name: rds-ca-truststore

  extraVolumeMounts:
    - name: rds-truststore
      mountPath: /etc/ssl/certs
      readOnly: true

  # Java truststore configuration
  env:
    - name: JAVA_OPTS
      value: "-Djavax.net.ssl.trustStore=/etc/ssl/certs/rds-truststore.jks -Djavax.net.ssl.trustStorePassword=changeit"
```

## Step 6: Deploy

```bash
# Add Helm repository (if not already added)
helm repo add sonatype https://sonatype.github.io/helm3-charts/

# Update dependencies
helm dependency update ./chart

# Install
helm install nexus-iq-server-ha ./chart \
  --namespace iq-server \
  -f values-openshift.yaml \
  --timeout 10m
```

## Step 7: Verify Deployment

```bash
# Check job status
kubectl get jobs -n iq-server

# Expected output:
# NAME                              COMPLETIONS   DURATION   AGE
# nexus-iq-server-ha-migrate-db     1/1           45s        2m
# nexus-iq-server-ha-git-ssh        1/1           10s        2m

# Check job logs
kubectl logs job/nexus-iq-server-ha-migrate-db -n iq-server

# Look for:
# - Successfully connected to database
# - Schema migration completed
# - No TLS errors

# Check pods
kubectl get pods -n iq-server

# Expected output:
# NAME                                          READY   STATUS    RESTARTS   AGE
# nexus-iq-server-ha-iq-server-deployment-xxx   1/1     Running   0          3m
```

## Step 8: Access IQ Server

```bash
# Port forward (for testing)
kubectl port-forward svc/nexus-iq-server-ha-application 8070:8070 -n iq-server

# Open browser
# http://localhost:8070

# Default credentials
# Username: admin
# Password: admin123
```

## Troubleshooting

### Job fails with permission denied

```bash
# Check SCC assignment
oc describe project iq-server | grep sa.scc

# Verify UID in values.yaml matches assigned range
# The runAsUser must be within the assigned UID range
```

### TLS connection fails

```bash
# Verify truststore exists
kubectl exec -it deployment/nexus-iq-server-ha-iq-server-deployment -n iq-server -- \
  ls -la /etc/ssl/certs/

# Check JAVA_OPTS
kubectl exec -it deployment/nexus-iq-server-ha-iq-server-deployment -n iq-server -- \
  env | grep JAVA_OPTS

# Test connection manually
kubectl exec -it deployment/nexus-iq-server-ha-iq-server-deployment -n iq-server -- \
  openssl s_client -connect aurora-cluster.xyz.us-east-1.rds.amazonaws.com:5432 -starttls postgres
```

### Database connection fails

```bash
# Check database secrets
kubectl get secrets -n iq-server

# Verify secrets have correct values
kubectl get secret iq-db-credentials -n iq-server -o yaml
```

## Configuration Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `iq_server_jobs.securityContext.runAsUser` | Container UID | 1000 | Yes (for OpenShift) |
| `iq_server_jobs.securityContext.runAsGroup` | Container GID | 1000 | Yes (for OpenShift) |
| `iq_server_jobs.extraVolumes` | Additional volumes | `[]` | For TLS |
| `iq_server_jobs.extraVolumeMounts` | Volume mounts | `[]` | For TLS |
| `iq_server.config.database.parameters.sslmode` | PostgreSQL SSL mode | - | verify-full |
| `iq_server.config.database.parameters.sslrootcert` | CA certificate path | - | Yes (for TLS) |

## Support

For issues or questions:
- **Jira**: [CLM-40884](https://sonatype.atlassian.net/browse/CLM-40884)
- **Documentation**: See `IMPLEMENTATION_SUMMARY.md` and `INTEGRATION_TEST_REPORT.md`
