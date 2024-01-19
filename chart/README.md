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
# Sonatype IQ Server High Availability Helm Chart

This repository is intended to store a helm chart to create a cluster of Sonatype IQ Server nodes.

## General Requirements
- A copy of the helm chart
- A Sonatype IQ Server license that supports the High Availability (HA) feature
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl) (1.23+) to run commands against a Kubernetes cluster
- [helm](https://helm.sh/docs/helm/) (3.9.3+) to install or upgrade the helm chart
- A PostgreSQL (10.7 or newer) database or a PostgreSQL-compatible service
- A Kubernetes cluster to run the helm chart on
- A shared file system to share files between all Sonatype IQ Server pods in the cluster
- A load balancer to distribute requests between the Sonatype IQ Server pods

## Nice to have
- A [storage class](https://kubernetes.io/docs/concepts/storage/storage-classes/) for dynamic provisioning

## Running

1. Start your Kubernetes cluster if needed
2. Open a console/terminal
3. Switch to the correct context to use your cluster if needed (e.g. `kubectl config use-context my-context`)
4. Add the helm chart repository via
   `helm repo add sonatype https://sonatype.github.io/helm3-charts/`
5. Install the helm chart via
   `helm install --namespace <namespace> <name> --dependency-update <overrides> sonatype/nexus-iq-server-ha --version <version>`
where
   1. `<namespace>` can be an existing namespace for the helm chart (created prior via
      `kubectl create namespace <namespace>`, or to create automatically include the flag `--create-namespace`)
   2. `<name>` can be any name for the helm chart
   3. `<overrides>` is a set of overrides for values in the helm chart (see below)
   4. `<version>` is the version of the helm chart to use
6. Expose the ingress if needed, which uses port `80` for http and port `443` for https by default

## Overrides

### License (required)

A Sonatype IQ Server license that supports the HA feature must be installed either before the cluster starts or as it is
starting to allow multiple pods to start successfully.

The license file can either be passed directly
   ```
   --set-file iq_server.license=<license file>
   ```
where `<license file>` is the path to your Sonatype IQ Server product license file

or via an existing secret
   ```
   --set iq_server.licenseSecret=<license secret>
   ```

### Database (required)

An existing database can be configured as follows
   ```
   --set iq_server.database.hostname=<database hostname>
   --set iq_server.database.port=<database port>
   --set iq_server.database.name=<database name>
   --set iq_server.database.username=<database username>
   ```
the database password can either be passed directly
   ```
   --set iq_server.database.password=<database password>
   ```
or via an existing secret
   ```
   --set iq_server.database.passwordSecret=<database password secret>
   ```

### Shared File System (required)

By default, the helm chart will create both a [Persistent Volume (PV)](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistent-volumes)
using the configured storage and a corresponding
[Persistent Volume Claim (PVC)](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims).

However, there are various configuration options.
* If a PV is created, then it will match the configuration.
* If a PVC is created, then it will only bind to a PV that satisfies the configuration.

#### Size

The [capcity](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#capacity) or size can be set via
   ```
   --set iq_server.persistence.size=<storage size, default "1Gi">
   ```

#### Access Mode(s)

The [access mode(s)](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes) can be set via
   ```
   --set iq_server.persistence.accessModes[0]=<access mode, default "ReadWriteMany">
   ```
Note that this should correspond to the type of PV being used.

If you have multiple nodes in your Kubernetes cluster, and a Sonatype IQ Server pod is running on 2 or more of
them, then this must be set to `ReadWriteMany` and you must use a type of PV that supports it.

#### Storage Class Name

The [storage class](https://kubernetes.io/docs/concepts/storage/storage-classes/) name can be set via
   ```
   --set iq_server.persistence.storageClassName=<storage class name, default "">
   ```

#### Type

The [type](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#types-of-persistent-volumes) can be
configured as follows.

Note a PV can only have one type, so if multiple are configured, then only one will be used. The priority for which type
will be selected if multiple are configured is shown below i.e. a type with a lower number in the below list will be
chosen above a type with a higher number.

1. **csi**
   ```
   --set iq_server.persistence.csi.driver=<csi driver name>
   --set iq_server.persistence.csi.fsType=<filesystem type>
   --set iq_server.persistence.csi.volumeHandle=<volume handle>
   --set iq_server.persistence.csi.volumeAttributes=<volume attributes>
   ```
2. **nfs**
   ```
   --set iq_server.persistence.nfs.server=<nfs server hostname>
   --set iq_server.persistence.nfs.path=<nfs server path, default "/">
   ```

#### Existing PV and PVC

If you have an existing PV and PVC you wish to use, then you only need to set the PVC via
   ```
   --set iq_server.persistence.existingPersistentVolumeClaimName=<existing persistent volume claim name>
   ```

#### Existing PV

If you have an existing PV you wish to use, then you can set the PV via
   ```
   --set iq_server.persistence.existingPersistentVolumeName=<existing persistent volume name>
   ```
However, you may need to configure the PVC that will be created to allow it to bind to the PV using the previously
mentioned configuration options.


### Load Balancer (required)

An [ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) can be enabled with a particular [class
name](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-class) to use an existing load balancer
as follows
   ```
   --set ingress.enabled=<true|false, default false>
   --set ingress.ingressClassName=<ingress class name, default "nginx">
   --set ingress.pathType=<ingress path type, default "Prefix">
   --set ingress.hostApplicationPath=<application path, default iq_server.config.server.applicationContextPath>
   --set ingress.hostAdminPath=<admin path, default iq_server.config.server.adminContextPath>
   --set ingress.hostApplication=<application hostname>
   --set ingress.hostAdmin=<admin hostname>
   --set ingress.annotations=<ingress annotations>
   ```
Note that if you want both the application and admin endpoints to be accessible, then they will need to be set to have
either different hostnames via e.g.
   ```
   --set iq_server.config.server.hostApplication="app.domain"
   --set iq_server.config.server.hostAdmin="admin.domain"
   ```
or different paths via e.g.
   ```
   --set iq_server.config.server.applicationContextPath="/"
   --set iq_server.config.server.adminContextPath="/admin"
   ```

Note that if no hostnames are specified, then any web traffic to the IP address of your ingress controller can be
matched without a name based virtual host being required.

#### TLS

If your [ingress class](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-class) supports 
specifying TLS options directly based on your [ingress controller](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/),
then you can specify them as follows.

A TLS certificate and private key can either be passed directly
   ```
   --set ingress.tls[0].certificate=<tls certificate file>
   --set ingress.tls[0].key=<tls private key file>
   ```
where `<tls certificate file>` is the path to your TLS certificate file and `<tls private key file>` is the path to your
TLS private key file, or via an existing secret
   ```
   --set ingress.tls[0].secretName=<tls secret name>
   ```
The TLS secret must contain keys named `tls.cert` for the TLS certificate and `tls.key` for the TLS private key.

Additionally multiple hosts can be specified as follows
   ```
   --set ingress.tls[0].hosts[0]=<tls hostname>
   ```

Alternatively some ingress classes may support specifying TLS options through annotations.

### Domain Name System (DNS) Records (optional)

DNS records can be automatically managed using [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) based on
an ingress. This is included in the chart and can be enabled via
   ```
   --set externalDns.enabled=true
   ```
and configured via
   ```
   --set externalDns.args=<array of arguments>
   ```

### Sonatype IQ Server Configuration (optional)

The number of pods can be specified as follows
   ```
   --set iq_server.replicas=<number of pods, default 2>
   ```

The initial admin password can either be passed directly
   ```
   --set iq_server.initialAdminPassword=<initial admin password>
   ```
or via an existing secret
   ```
   --set iq_server.initialAdminPasswordSecret=<initial admin password secret>
   ```

If planning to use ssh for git operations, enable the following flag to generate a private/public key pair.
You can retrieve the public key from the pod at <clusterDirectory>/.ssh/id_rsa.pub.
   ```
   --set iq_server.useGitSsh=<true/false>
   ```

A `config.yml` file is required to run. This is generated using the `iq_server.config` value. Care should be taken if
updating this as many values within it are fine-tuned to allow the helm chart to function.

### Logging (required)

Each Sonatype IQ Server pod has a container running Sonatype IQ Server, which outputs the following log files
* `clm-server.log`
* `request.log`
* `audit.log`
* `policy-violation.log`
* `stderr.log`

by default to `/var/log/nexus-iq-server`.

A fluentd sidecar container in the same pod tails these log files and forwards the content to a fluentd daemonset
aggregator.

For each log file, the aggregator combines its content from each pod into an aggregated log file in
[ndjson format](http://ndjson.org/), which is output with the current date to the shared file system PV by default to
`/log` such that you end up with
* `clm-server.<yyyyMMdd>.log`
* `request.<yyyyMMdd>.log`
* `audit.<yyyyMMdd>.log`
* `policy-violation.<yyyyMMdd>.log`
* `stderr.<yyyyMMdd>.log`

where `<yyyyMMdd>` is the current date.

The aggregate log files may be required for a support request and by default will be included when generating a support
zip inside a top-level `cluster_log` directory.

By default, aggregate log files that have a last modified time older than 50 days are scheduled to be deleted every day
at 1 am. This can be customized as follows
   ```
   --set aggregateLogFileRetention.deleteCron=<Cron schedule expression, default "0 1 * * *">
   --set aggregateLogFileRetention.maxLastModifiedDays=<max last modified time in days, default 7>
   ```
Note that setting `aggregateLogFileRetention.maxLastModifiedDays` to 0 disables deletion.

Note that the fluentd daemonset aggregator has separate settings for its PVC and should normally be configured to use
the same PVC as the Sonatype IQ Server pods as follows
   ```
   --set fluentd.aggregator.extraVolumes[0].name="iq-server-pod-volume"
   --set fluentd.aggregator.extraVolumes[0].persistentVolumeClaim.claimName=<PVC name, default "iq-server-pvc">
   ```

### Image (optional)

By default, the
[latest publicly available Sonatype IQ Server docker image](https://hub.docker.com/r/sonatype/nexus-iq-server)
will be used.

The image registry, image, tag, and imagePullPolicy can be overridden using
   ```
   --set iq_server.imageRegistry=<image registry, default nil meaning use the Docker public registry>
   --set iq_server.image=<image, default "sonatype/nexus-iq-server">
   --set iq_server.tag=<tag, default most recent version of Sonatype IQ Server>
   --set iq_server.imagePullPolicy=<imagePullPolicy, default "IfNotPresent">
   ```

## Amazon Web Services (AWS)

### Satisfying General Requirements
- [Relational Database Service (RDS) for PostgreSQL](https://aws.amazon.com/rds/) for a PostgreSQL database
- [Elastic Kubernetes Service (EKS)](https://aws.amazon.com/eks/) for a cluster
- [Elastic File System (EFS)](https://aws.amazon.com/efs/) with mount targets for a shared file system
- [Application Load Balancer (ALB)](https://aws.amazon.com/elasticloadbalancing/application-load-balancer/) for a load
balancer

### Additional Requirements
- [Virtual Private Cloud](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html) for the AWS
resources to communicate with each other
- [Amazon EFS CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html) pre-installed and configured in
the cluster

### Nice to have
- [EFS Storage Class](https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/master/examples/kubernetes/dynamic_provisioning/specs/storageclass.yaml)
pre-installed and configured in the cluster for [dynamic provisioning](https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/)
- [AWS Load Balancer Controller add-on](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html)
pre-installed and configured in the cluster to automatically provision an ALB based on an ingress
- [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) pre-installed/enabled and configured in the cluster to
automatically provision DNS records for [AWS Route 53](https://aws.amazon.com/route53/) based on an ingress.
- [Kubernetes Secrets Store CSI Driver](https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver.html)
pre-installed and configured in the cluster to enable AWS Secrets Manager access i.e. via
   1. `helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts`
   2. `helm repo update`
   3. `helm upgrade --install --namespace kube-system csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver --set grpcSupportedProviders="aws" --set syncSecret.enabled=true`
   4. `kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml`
- [AWS CloudWatch](https://aws.amazon.com/cloudwatch/) configuration for fluentd to send aggregated logs to
- [`aws-vault`](https://github.com/99designs/aws-vault) [pre-installed and configured](https://github.com/99designs/aws-vault/blob/master/USAGE.md#config)
  to ease authentication, in which case prefix the aws/kubectl/helm commands below with `aws-vault exec <aws-profile> -- <command>`.

### EKS

An existing EKS cluster is required to run the helm chart on.

To lookup existing clusters, run `aws eks --region <aws_region> list-clusters`.

To import the context for a cluster into your kubeconfig file, run
`aws eks --region <aws_region> update-kubeconfig --name <cluster_name>`.

### EFS

An existing EFS drive with mount targets can be used for the PV.

The PV can be provisioned statically or dynamically.

In either case, a CSI volume should be configured with
   ```
   --set iq_server.persistence.csi.driver="efs.csi.aws.com"
   --set iq_server.persistence.csi.fsType=""
   ```

and the access modes should be set as follows
   ```
   --set iq_server.persistence.accessModes[0]="ReadWriteMany"
   ```

#### Static Provisioning

To statically provision the PV use the following

   ```
   --set iq_server.persistence.csi.volumeHandle=<EFS file system ID>[:<EFS file system path>]
   ```
where `<EFS file system ID>` is your EFS file system ID, which typically looks like e.g. "fs-0ac8d13f38bfc99df" and
`<EFS file system path>` is an optional path into the file system e.g. ":/".

#### Dynamic Provisioning

To dynamically provision the PV via an EFS storage class use the following
   ```
   --set iq_server.persistence.persistentVolumeName=""
   --set iq_server.persistence.storageClassName=<EFS storage class name>
   ```

### AWS Secrets

The [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/) can be used to store AWS secrets, which can be used
to pass the following

The product license file
   ```
   --set secret.license.arn=<aws secret arn containing product license file binary content>
   ```

The database settings
   ```
   --set secret.rds.arn=<aws secret arn containing database host, port, name, username, and password keys>
   ```

The initial admin password
   ```
   --set secret.license.arn=<aws secret arn containing the initial admin password in an initial_admin_password key>
   ```

### ALB

For an ALB load balancer to work you will need to change the Sonatype IQ Server [service type](https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types)
from its default of `ClusterIP` to `NodePort` via the following
   ```
   --set iq_server.serviceType=NodePort
   ```

#### Static Provisioning

To use an existing ALB and target groups via the AWS Load Balancer Controller add-on use the following

For the application endpoints
   ```
   --set existingApplicationLoadBalancer.applicationTargetGroupARN=<application target group arn>
   ```
For the admin endpoints
   ```
   --set existingApplicationLoadBalancer.adminTargetGroupARN=<admin target group arn>
   ```
Each command will create a target group binding, which will automatically synchronize targets to the given target group
pointing to the application/admin Sonatype IQ Server service endpoints.

Note that with static provisioning, you do not need to enable an ingress.

#### Dynamic Provisioning

To dynamically provision an ALB via the AWS Load Balancer Controller add-on use the following
   ```
   --set ingress.enabled=true
   --set ingress.ingressClassName=alb
   ```
and ensure that the [appropriate annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/)
are set e.g.
   ```
   --set ingress.annotations."alb\.ingress\.kubernetes\.io/scheme"="internet-facing"
   --set ingress.annotations."alb\.ingress\.kubernetes\.io/target-type"="ip"
   --set ingress.annotations."alb\.ingress\.kubernetes\.io/healthcheck-path"="/ping"
   --set ingress.annotations."alb\.ingress\.kubernetes\.io/certificate-arn"="arn:aws:acm:<region>:<aws_account_id>:certificate/<certificate_id>"
   --set ingress.annotations."alb\.ingress\.kubernetes\.io/ssl-policy"="ELBSecurityPolicy-FS-1-2-Res-2020-10"
   --set ingress.annotations."alb\.ingress\.kubernetes\.io/listen-ports"='\[\{\"HTTPS\":80\}\,\{\"HTTPS\":443\}\]'
   --set ingress.annotations."alb\.ingress\.kubernetes\.io/actions\.ssl-redirect"='\{\"Type\": \"redirect\"\,\"RedirectConfig\":\{\"Protocol\":\"HTTPS\"\,\"Port\":\"443\"\,\"StatusCode\":\"HTTP_301\"\}\}'
   --set ingress.annotations."alb\.ingress\.kubernetes\.io/actions\.response-404"='\{\"type\":\"fixed-response\"\,\"fixedResponseConfig\":\{\"contentType\":\"text/plain\"\,\"statusCode\":\"404\"\,\"messageBody\":\"404_Not_Found\"\}\}'
   --set ingress.annotations."alb\.ingress\.kubernetes\.io/actions\.redirect-domain"='\{\"Type\":\"redirect\"\,\"RedirectConfig\":\{\"Host\":\"domain\"\,\"Path\":\"/#\{path\}\"\,\"Port\":\"443\"\,\"Protocol\":\"HTTPS\"\,\"Query\":\"#\{query\}\"\,\"StatusCode\":\"HTTP_301\"\}\}'
   --set ingress.annotations."alb\.ingress\.kubernetes\.io/load-balancer-attributes"="idle_timeout.timeout_seconds=600"
   ```
Note that if the application and admin services are separated by path rather than hostname, then multiple healthchecks
will need to be configured. This can be achieved by adding the healthcheck annotations at the service level rather than
the ingress level e.g.
   ```
   --set iq_server.applicationServiceAnnotations."alb\.ingress\.kubernetes\.io/healthcheck-path"="/ping"
   --set iq_server.adminServiceAnnotations."alb\.ingress\.kubernetes\.io/healthcheck-path"="/admin/ping"
   ```

### EFS Storage Class

If you want to use dynamic provisioning, then an EFS storage class should be pre-installed and configured in the cluster
with the correct settings to allow read/write access to the Sonatype IQ Server pod users, which have UID 1000 and GID 1000
by default e.g.
   ```
   kind: StorageClass
   apiVersion: storage.k8s.io/v1
     metadata:
     name: efs-sc
   provisioner: efs.csi.aws.com
   parameters:
     provisioningMode: efs-ap
     fileSystemId: <EFS file system ID>
     directoryPerms: "777"
     gidRangeStart: "1000"
     gidRangeEnd: "1000"
     basePath: "/"
   ```

### CloudWatch

The fluentd aggregator can be configured to send aggregated logs to CloudWatch using the
[fluent-plugin-cloudwatch-logs plugin](https://github.com/fluent-plugins-nursery/fluent-plugin-cloudwatch-logs).

This requires fluentd aggregator pods to have the [correct permissions](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-prerequisites.html)
, which can either be associated with a service account the fluentd aggregator uses, or with the EKS worker nodes.

Once the permissions are established, you can enable sending aggregated logs to CloudWatch, set the AWS region,
log group name, and log stream name as follows
   ```
   --set cloudwatch.enabled=true
   --set cloudwatch.region=<AWS region>
   --set cloudwatch.logGroupName=<CloudWatch log group name>
   --set cloudwatch.logStreamName=<CloudWatch log stream name>
   ```

### Examples

Some example commands are shown below.

#### External Database, Static EFS, and Dynamic ALB
   ```
   helm install --namespace staging mycluster --dependency-update
   --set-file iq_server.license="license.lic"
   --set iq_server.database.hostname=myhost
   --set iq_server.database.port=5432
   --set iq_server.database.name=iq
   --set iq_server.database.username=postgres
   --set iq_server.database.password=admin123
   --set iq_server.config.server.adminContextPath="/admin"
   --set iq_server.persistence.accessModes[0]="ReadWriteMany"
   --set iq_server.persistence.csi.driver="efs.csi.aws.com"
   --set iq_server.persistence.csi.fsType=""
   --set iq_server.persistence.csi.volumeHandle="fs-0ac8d13f38bfc99df:/"
   --set iq_server.serviceType=NodePort
   --set ingress.enabled=true
   --set ingress.ingressClassName=alb
   --set ingress.annotations."alb\.ingress\.kubernetes\.io/scheme"="internet-facing"
   --set ingress.annotations."alb\.ingress\.kubernetes\.io/healthcheck-path"="/ping" 
   sonatype/nexus-iq-server-ha --version <version>
   ```

#### External Database, Dynamic EFS, Dynamic ALB, and Secrets
   ```
   helm install --namespace staging mycluster --dependency-update
   --set iq_server.serviceAccountName=<service account name, default "default">
   --set serviceAccount.create=true
   --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::<aws_account_id>:role/<role_name>"
   --set secret.arn="arn:aws:secretsmanager:<region>:<aws_account_id>:secret:<secret_name>"
   --set secret.license.arn="arn:aws:secretsmanager:<region>:<aws_account_id>:secret:<secret_name>"
   --set secret.rds.arn="arn:aws:secretsmanager:<region>:<aws_account_id>:secret:<rds_secret_name>"
   --set iq_server.config.server.adminContextPath="/admin"
   --set iq_server.persistence.accessModes[0]="ReadWriteMany"
   --set iq_server.persistence.persistentVolumeName=""
   --set iq_server.persistence.storageClassName="efs-storage-class-name"
   --set iq_server.persistence.csi.driver="efs.csi.aws.com"
   --set iq_server.persistence.csi.fsType=""
   --set iq_server.serviceType=NodePort
   --set ingress.enabled=true
   --set ingress.ingressClassName=alb
   --set ingress.annotations."alb\.ingress\.kubernetes\.io/scheme"="internet-facing"
   --set ingress.annotations."alb\.ingress\.kubernetes\.io/healthcheck-path"="/ping" 
   sonatype/nexus-iq-server-ha --version <version>
   ```

### Autoscaling (@since 166.0.0)

Sonatype IQ Server HA helm chart includes support for Kubernetes Horizontal Pod Autoscaling (HPA). With this enabled you can set the
cluster to automatically scale up/down based on cpu and/or memory utilization.

#### Pre-requisites for autoscaling
Horizontal Pod Autoscaler depends on [metrics-server](https://github.com/kubernetes-sigs/metrics-server) being 
installed and available in the cluster. Please refer to the metrics-server [requirements](https://github.com/kubernetes-sigs/metrics-server/#requirements) 
and [installation](https://github.com/kubernetes-sigs/metrics-server/#installation) instructions for setting it up    

#### Configuring IQ server autoscaling
(Note: When setting auto-scaling parameters please make sure to have sufficient hardware resources available in the
underlying nodes meet the max pod demands.)

HPA is disabled by default. If you want to enable it, you need to set the `hpa.enabled` parameter to `true`.

   ```
   --set hpa.enabled=true
   ```
Defined resources requests for all the containers in the IQ Server pod are required for HPA to be able to compute
metrics. As a result, if you are scaling based on CPU usage you need to specify CPU requests for the IQ server and fluentd
sidecar. 

Please refer to the "Chart Configuration Options" table below for detailed parameters for adjusting HPA configuration
to match your needs.

#### Autoscaling examples

Some example commands are shown below.

   ```
   helm install --namespace staging mycluster --dependency-update
    ...
    --set hpa.enabled=true
    --set iq_server.resources.requests.cpu="500m"
    --set iq_server.resources.limits.cpu="1000m"    
    --set fluentd.resources.requests.cpu="200m"
    --set fluentd.resources.limits.cpu="500m"
    ...
   sonatype/nexus-iq-server-ha --version <version>
   ```

## On-Premises

### Satisfying General Requirements
* Any PostgreSQL database, we recommend one [setup for HA](https://www.postgresql.org/docs/current/high-availability.html)
* Any Kubernetes cluster, we recommend a multi-node cluster [setup for HA](https://kubernetes.io/docs/setup/production-environment/)
* Any shared file system, we recommend a [Network File System (NFS)](https://en.wikipedia.org/wiki/Network_File_System)
* Any [ingress controller](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/) pre-installed
and configured in the cluster, we recommend the [ingress-nginx controller](https://github.com/kubernetes/ingress-nginx)

### Example

An example command is shown below.

#### External Database, NFS, and ingress-nginx
   ```
   helm install --namespace staging mycluster --dependency-update
   --set-file iq_server.license="license.lic"
   --set iq_server.database.hostname=myhost
   --set iq_server.database.port=5432
   --set iq_server.database.name=iq
   --set iq_server.database.username=postgres
   --set iq_server.database.password=admin123
   --set iq_server.config.server.adminContextPath="/admin"
   --set iq_server.persistence.accessModes[0]="ReadWriteMany"
   --set iq_server.persistence.nfs.server=10.109.77.85
   --set iq_server.persistence.nfs.path=/
   --set iq_server.serviceType=NodePort
   --set ingress.enabled=true
   --set ingress-nginx.enabled=true
   sonatype/nexus-iq-server-ha --version <version>
   ```

## Upgrading

To upgrade Sonatype IQ Server and ensure a successful data migration, the following steps are recommended:

1. **Scale your pods down to zero.** This will delete the existing pods.
2. **Backup the database.** See the [IQ server backup guidelines](https://links.sonatype.com/products/nxiq/doc/backup) for more details.
3. **Update the helm chart.** Typically, this will also update the Sonatype IQ Server version.
4. **Run your helm chart upgrade command.** The deleted pods will be re-created with the updates.

## Chart Configuration Options
| Parameter                                                   | Description                                                                                          | Default                    |
|-------------------------------------------------------------|------------------------------------------------------------------------------------------------------|----------------------------|
| `iq_server.imageRegistry`                                   | Container image registry, if not specified the Docker public registry will be used                   | `nil`                      |
| `iq_server.image`                                           | Sonatype IQ Server docker image                                                                      | `sonatype/nexus-iq-server` |
| `iq_server.imagePullPolicy`                                 | Sonatype IQ Server image pull policy                                                                 | `IfNotPresent`             |
| `iq_server.tag`                                             | Sonatype IQ Server image tag                                                                         | See `values.yaml`          |
| `iq_server.resources.requests.cpu`                          | Request for CPU resources in CPU units                                                               | `nil`                      |
| `iq_server.resources.requests.memory`                       | Request for memory resources in bytes                                                                | `nil`                      |
| `iq_server.resources.limits.cpu`                            | Limit for CPU resources in CPU units                                                                 | `nil`                      |
| `iq_server.resources.limits.memory`                         | Limit for memory resources in bytes                                                                  | `nil`                      |
| `iq_server.javaOpts`                                        | Value for the JAVA_OPTS environment variable to pass custom settings to the JVM                      | `nil`                      |
| `iq_server.license`                                         | Path to your Sonatype IQ Server product license file                                                 | `nil`                      |
| `iq_server.licenseSecret`                                   | The name of the license secret                                                                       | `nil`                      |
| `iq_server.serviceType`                                     | Sonatype IQ Server service type                                                                      | `ClusterIP`                |
| `iq_server.database.hostname`                               | Database hostname                                                                                    | `nil`                      |
| `iq_server.database.port`                                   | Database port                                                                                        | `5432`                     |
| `iq_server.database.name`                                   | Database name                                                                                        | `nil`                      |
| `iq_server.database.username`                               | Database username                                                                                    | `postgres`                 |
| `iq_server.database.password`                               | Database password                                                                                    | `nil`                      |
| `iq_server.database.passwordSecret`                         | Database password secret                                                                             | `nil`                      |
| `iq_server.persistence.existingPersistentVolumeClaimName`   | Existing persistent volume claim name                                                                | `nil`                      |
| `iq_server.persistence.existingPersistentVolumeName`        | Existing persistent volume name                                                                      | `nil`                      |
| `iq_server.persistence.persistentVolumeName`                | Persistent volume name                                                                               | `iq-server-pv`             |
| `iq_server.persistence.persistentVolumeClaimName`           | Persistent volume claim name                                                                         | `iq-server-pvc`            |
| `iq_server.persistence.persistentVolumeRetainPolicy`        | Persistent volume retain policy                                                                      | `keep`                     |
| `iq_server.persistence.persistentVolumeClaimRetainPolicy`   | Persistent volume claim retain policy                                                                | `keep`                     |
| `iq_server.persistence.size`                                | Storage capacity for PV/PVC to provision/request                                                     | `1Gi`                      |
| `iq_server.persistence.storageClassName`                    | Storage class name for the PV/PVC                                                                    | `""`                       |
| `iq_server.persistence.accessModes[0]`                      | Access mode for the PV/PVC                                                                           | `ReadWriteOnce`            |
| `iq_server.persistence.csi.driver`                          | CSI driver name                                                                                      | `nil`                      |
| `iq_server.persistence.csi.fsType`                          | File system type                                                                                     | `nil`                      |
| `iq_server.persistence.csi.volumeHandle`                    | Volume handle                                                                                        | `nil`                      |
| `iq_server.persistence.nfs.server`                          | NFS server hostname                                                                                  | `nil`                      |
| `iq_server.persistence.nfs.path`                            | NFS server path                                                                                      | `/`                        |
| `iq_server.podAnnotations`                                  | Annotations for the Sonatype IQ Server pods                                                          | `nil`                      |
| `iq_server.serviceAccountName`                              | Sonatype IQ Server service account name                                                              | `default`                  |
| `iq_server.serviceType`                                     | Sonatype IQ Server service type                                                                      | `ClusterIP`                |
| `iq_server.applicationServiceAnnotations`                   | Annotations for the Sonatype IQ Server application service                                           | `nil`                      |
| `iq_server.adminServiceAnnotations`                         | Annotations for the Sonatype IQ Server admin service                                                 | `nil`                      |
| `iq_server.replicas`                                        | Number of replicas                                                                                   | `2`                        |
| `iq_server.initialAdminPassword`                            | Initial admin password                                                                               | `admin123`                 |
| `iq_server.initialAdminPasswordSecret`                      | Initial admin password secret                                                                        | `nil`                      |
| `iq_server.readinessProbe.initialDelaySeconds`              | Initial delay seconds for readiness probe                                                            | `45`                       |
| `iq_server.readinessProbe.periodSeconds`                    | Period seconds for readiness probe                                                                   | `15`                       |
| `iq_server.readinessProbe.timeoutSeconds`                   | Timeout seconds for readiness probe                                                                  | `5`                        |
| `iq_server.readinessProbe.failureThreshold`                 | Failure threshold for readiness probe                                                                | `4`                        |
| `iq_server.livenessProbe.initialDelaySeconds`               | Initial delay seconds for liveness probe                                                             | `180`                      |
| `iq_server.livenessProbe.periodSeconds`                     | Period seconds for liveness probe                                                                    | `20`                       |
| `iq_server.livenessProbe.timeoutSeconds`                    | Timeout seconds for liveness probe                                                                   | `3`                        |
| `iq_server.livenessProbe.failureThreshold`                  | Failure threshold for liveness probe                                                                 | `3`                        |
| `iq_server.fluentd.forwarder.enabled`                       | Enable Fluentd forwarder                                                                             | `true`                     |
| `iq_server.config`                                          | A YAML block which will be used as a configuration block for IQ Server                               | See `values.yaml`          |
| `iq_server.useGitSsh`                                       | Use SSH to execute git operations for SCM integrations                                               | `false`                    |
| `iq_server.sshPrivateKey`                                   | SSH private key file to store on the nodes for ssh git operations                                    | `nil`                      |
| `iq_server.sshPrivateKeySecret`                             | SSH private key stored in k8s secret to be used for ssh git operations                               | `nil`                      |
| `iq_server.sshKnownHosts`                                   | SSH known hosts file to store on the nodes for ssh git operations                                    | `nil`                      |
| `iq_server.sshKnownHostsSecret`                             | SSH known hosts stored in k8s secret to be used for ssh git operations                               | `nil`                      |
| `ingress.enabled`                                           | Enable ingress                                                                                       | `false`                    |
| `ingress.className`                                         | Ingress class name                                                                                   | `nginx`                    |
| `ingress.pathType`                                          | Ingress path type                                                                                    | `Prefix`                   |
| `ingress.annotations`                                       | Ingress annotations                                                                                  | `nil`                      |
| `ingress.hostApplication`                                   | Ingress host for application                                                                         | `nil`                      |
| `ingress.hostApplicationPath`                               | Ingress path for application                                                                         | `nil`                      |
| `ingress.hostAdmin`                                         | Ingress host for admin application                                                                   | `nil`                      |
| `ingress.hostAdminPath`                                     | Ingress path for admin application                                                                   | `nil`                      |
| `ingress.tls`                                               | Ingress TLS configuration                                                                            | `nil`                      |
| `ingress-nginx.enable`                                      | Enable ingress-nginx                                                                                 | `false`                    |
| `ingress-nginx.controller`                                  | Ingress controller configuration for Nginx                                                           | See `values.yaml`          |
| `externalDns.enabled`                                       | Enable external-dns                                                                                  | `false`                    |
| `externalDns.args`                                          | Array of arguments to pass to the external-dns container                                             | See `values.yaml`          |
| `serviceAccount.create`                                     | Create service account                                                                               | `false`                    |
| `serviceAccount.labels`                                     | Service account labels                                                                               | `nil`                      |
| `serviceAccount.annotations`                                | Service account annotations                                                                          | `nil`                      |
| `serviceAccount.autoMountServiceAccountToken`               | Auto mount service account token                                                                     | `false`                    |
| `secret.arn`                                                | AWS secret arn containing initial admin password in a initial_admin_password key                     | `nil`                      |
| `secret.license.arn`                                        | AWS secret arn containing the binary content of your Sonatype IQ Server license                      | `nil`                      |
| `secret.rds.arn`                                            | AWS secret arn containing host, port, name (database name), username, and password keys              | `nil`                      |
| `secret.sshPrivateKey.arn`                                  | AWS secret arn containing the binary content of your SSH private key for use with ssh git operations | `nil`                      |
| `secret.sshKnownHosts.arn`                                  | AWS secret arn containing the binary content of your SSH known hosts for use with ssh git operations | `nil`                      |
| `cloudwatch.enabled`                                        | Enable CloudWatch logging                                                                            | `false`                    |
| `cloudwatch.region`                                         | CloudWatch region                                                                                    | `nil`                      |
| `cloudwatch.logGroupName`                                   | CloudWatch log group name                                                                            | `nil`                      |
| `cloudwatch.logStreamName`                                  | CloudWatch log stream name                                                                           | `nil`                      |
| `existingApplicationLoadBalancer.applicationTargetGroupARN` | Target group ARN for target synchronization with application endpoints                               | `nil`                      |
| `existingApplicationLoadBalancer.adminTargetGroupARN`       | Target group ARN for target synchronization with admin endpoints                                     | `nil`                      |
| `aggregateLogFileRetention.deleteCron`                      | Cron schedule expression for when to delete old aggregate log files if needed                        | `0 1 * * *`                |
| `aggregateLogFileRetention.maxLastModifiedDays`             | Maximum last modified time of an aggregate log file in days (0 disables deletion)                    | 50                         |
| `fluentd.enabled`                                           | Enable Fluentd                                                                                       | `true`                     |
| `fluentd.resources.requests.cpu`                            | Fluentd sidecar cpu request                                                                          | `nil`                      |
| `fluentd.resources.limits.cpu`                              | Fluentd sidecar cpu limit                                                                            | `nil`                      |
| `fluentd.resources.requests.memory`                         | Fluentd sidecar memory request                                                                       | `nil`                      |
| `fluentd.resources.limits.memory`                           | Fluentd sidecar memory limit                                                                         | `nil`                      |
| `fluentd.config`                                            | Fluentd configuration                                                                                | See `values.yaml`          |
| `hpa.enabled`                                               | Enable Horizontal Pod Autoscaler                                                                     | `false`                    |
| `hpa.minReplicas`                                           | Minimum number of replicas                                                                           | `2`                        |
| `hpa.maxReplicas`                                           | Maximum number of replicas                                                                           | `4`                        |
| `hpa.resource.cpu.enabled`                                  | Enable CPU-based autoscaling                                                                         | `true`                     |
| `hpa.resource.cpu.average.threshold`                        | Average CPU threshold for autoscaling                                                                | `50`                       |
| `hpa.resource.memory.enabled`                               | Enable memory-based autoscaling                                                                      | `false`                    |
| `hpa.resource.memory.average.threshold`                     | Average memory threshold for autoscaling                                                             | `50`                       |
| `busybox.imageRegistry`                                     | Container image registry, if not specified the Docker public registry will be used                   | `nil`                      |
| `busybox.image`                                             | BusyBox docker image                                                                                 | `busybox`                  |
| `busybox.tag`                                               | BusyBox image tag                                                                                    | See `values.yaml`          |
