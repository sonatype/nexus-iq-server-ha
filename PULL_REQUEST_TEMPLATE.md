# Support container-level securityContext and extra volumes for Jobs

Jira: https://sonatype.atlassian.net/browse/CLM-40884
Zendesk: #122471

## Problem

A customer deploying chart 207.1.0 on OpenShift with a restricted SCC and Aurora
PostgreSQL (`sslmode=verify-full`) is blocked by two gaps in the Job templates.

**1. Hardcoded container UID.** Both the `migrate-db` and `git-ssh` Jobs set a
container-level security context inline:

```yaml
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
```

OpenShift's restricted SCC only admits containers whose UID falls inside the
namespace's assigned range (the customer's is `1000710000/10000`). Because this is
set at the container level it overrides anything supplied at the pod level, and no
values.yaml key exists to change it — so the Job pods are rejected at admission and
schema migration never runs. `iq_server.securityContext` covers the Deployment only;
the Jobs have no equivalent.

**2. No way to mount a CA truststore into the Jobs.** The Jobs mount only their own
fixed volumes (config.yml, AWS CSI secrets). `verify-full` requires the driver to
validate the RDS server certificate against a CA the container can read, and there is
no `extraVolumes`/`extraVolumeMounts` hook to get one in. The Deployment has both.

## Change

Adds three keys under `iq_server_jobs`, applied to both Jobs:

| Key | Default | Purpose |
| --- | --- | --- |
| `securityContext` | `{runAsUser: 1000, runAsGroup: 1000}` | Container security context; override for a restricted SCC |
| `extraVolumes` | `[]` | Extra pod volumes (configMap, secret, emptyDir, hostPath, existingClaim) |
| `extraVolumeMounts` | `[]` | Extra container mounts, with `subPath` and `readOnly` support |

The volume templating reuses the pattern already used by the Deployment so the two
stay consistent. The security context is wrapped in `with`, so setting it to `null`
omits the block entirely and lets the pod-level context apply.

No application-side change is needed. `DatabaseConfig.resolveUrlFromFields()` already
appends `iq_server.config.database.parameters` to the JDBC URL, so `sslmode` and
`sslrootcert` reach the PostgreSQL driver as query parameters.

### Files

- `chart/values.yaml` — three new keys with defaults and commented examples
- `chart/templates/iq-server-jobs.yaml` — templated security context and volumes in both Jobs
- `chart/tests/iq-server-jobs_test.yaml` — 9 new cases

## Backward compatibility

The defaults reproduce the previous hardcoded values, and both volume lists default to
empty. Rendering the chart with no overrides produces byte-identical Job manifests, so
existing installs are unaffected and need no action.

## What was tested — and what wasn't

Tested:

- `helm unittest chart` — 144 pass (9 new), covering: default UID unchanged; UID
  overridden to `1000710000`; configMap/secret/emptyDir/hostPath volume types;
  `subPath` and `readOnly` mounts; `securityContext: null` omitting the block; and the
  `git-ssh` Job, not just `migrate-db`.
- The new assertions were mutation-checked: breaking the `extraVolumes` range in the
  template makes exactly the 4 volume tests fail, so they are not passing vacuously.
- `helm lint` clean; rendered output parses as valid YAML.

**Not tested — needs verification before this is called done:**

- No OpenShift cluster was used. That the rendered manifest satisfies restricted-SCC
  admission is inferred from the SCC rules, not observed.
- No Aurora or RDS instance was used. No `verify-full` TLS handshake was performed, and
  the `migrate-db` Job was never executed — only its manifest was rendered.
- The `JAVA_OPTS` truststore path in the deployment guide below is untried. Note that
  `sslrootcert` (a PEM read by the JDBC driver) and
  `-Djavax.net.ssl.trustStore` (a JKS read by the JVM) are two separate mechanisms;
  for PostgreSQL JDBC, `sslrootcert` alone is normally sufficient and the `JAVA_OPTS`
  entry may be unnecessary. This should be confirmed against a real Aurora endpoint
  before being recommended to the customer.

A run against an OpenShift cluster with a restricted SCC and a TLS-enforcing Aurora
endpoint is the remaining gap.

## Deployment guide (to be validated)

Create the truststore and ConfigMap:

```bash
keytool -import -alias rds-ca -file rds-ca.pem \
  -keystore rds-truststore.jks -storepass changeit -noprompt

kubectl create configmap rds-ca-truststore \
  --from-file=rds-truststore.jks --from-file=rds-ca.pem -n iq-server
```

Find the namespace's assigned UID range:

```bash
oc describe project iq-server | grep sa.scc.uid-range
```

Then in values:

```yaml
iq_server:
  securityContext:
    runAsUser: 1000710000      # from the range above
    runAsGroup: 1000710000
    fsGroup: 1000710000
  config:
    database:
      parameters:
        sslmode: verify-full
        sslrootcert: /etc/ssl/certs/rds-ca.pem

iq_server_jobs:
  securityContext:
    runAsUser: 1000710000
    runAsGroup: 1000710000
  extraVolumes:
    - name: rds-truststore
      configMap:
        name: rds-ca-truststore
  extraVolumeMounts:
    - name: rds-truststore
      mountPath: /etc/ssl/certs
      readOnly: true
```

Verify the migration Job actually completed, rather than assuming it did:

```bash
kubectl get job -n iq-server
kubectl logs job/<release>-migrate-db -n iq-server
```

🤖 Generated with [Claude Code](https://claude.com/claude-code)
