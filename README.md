# Resilience Testing

<img width="96" height="96" alt="image" src="https://i.pinimg.com/736x/63/38/8f/63388f30b69eb88134ef197c5cdf4385.jpg" /> <img width="96" height="96" alt="image" src="https://avatars.githubusercontent.com/u/13629408?s=200&v=4" /> <img width="96" height="96" alt="image" src="https://github.com/user-attachments/assets/56ab783b-f88f-4f27-8492-33fa6b3d3150" /> <img width="96" height="96" alt="image" src="https://d3g9o9u8re44ak.cloudfront.net/logo/55cad6f2-84cb-49a7-9d60-265f7e4ea91e/8a67fa7b-85bd-44e4-823c-d7d5690777b1.png"/> <img width="96" height="96" alt="image" src="https://i.pinimg.com/736x/28/ec/74/28ec7440a57536eebad2931517aa1cce.jpg" /> <img width="96" height="96" alt="image" src="https://avatars.githubusercontent.com/u/59082378?s=200&v=4" /> <img width="96" height="96" alt="image" src="https://i.pinimg.com/1200x/8b/81/38/8b8138c4491769dd53c5dc09b6548ecf.jpg" /> <img width="96" height="96" alt="image" src="https://avatars.githubusercontent.com/u/45108136?s=200&v=4" /> <img width="96" height="96" alt="image" src="https://avatars.githubusercontent.com/u/15859888?s=200&v=4" /> <img width="96" height="96" alt="image" src="https://avatars.githubusercontent.com/u/3380462?s=200&v=4" /> <img width="96" height="96" alt="image" src="https://avatars.githubusercontent.com/u/7195757?s=200&v=4" />


Terraform provisions the shared EKS cluster and the IAM OIDC provider, Karpenter's AWS roles and node access entry, and the interruption queue. The full plan also includes private Aurora PostgreSQL and RDS PostgreSQL databases. Helm installs the Karpenter controller after EKS is available and annotates its service account with the Terraform-managed controller role for IRSA. Kubernetes manifests define the NodePools and sample services, and Docker Compose runs Prometheus and Grafana locally.

## 1. Prepare and review the plan

Use the personal AWS credentials already configured on this Mac. Set up an AWS cost budget with email alerts before provisioning. Use kubectl 1.35 with this cluster and start Docker Desktop for the monitoring stage.

From the project root:

```sh
aws sts get-caller-identity
export TF_VAR_aws_account_id='<verified personal AWS account ID>'
export TF_VAR_operator_cidr="$(curl -fsS https://checkip.amazonaws.com)/32"
export TF_VAR_enable_databases=true

terraform -chdir=infra init
terraform -chdir=infra plan
terraform -chdir=infra show
```

Set `TF_VAR_enable_databases=false` and save as `ca2.tfplan` for a compute-only rehearsal. The full plan includes three billed database instances. The lab uses public IPv4 egress for the workers, a private EKS API endpoint for in-VPC access, and a public EKS API endpoint limited to the workstation CIDR. The database subnets have no internet route.

## 2. Deploy the AWS infrastructure and Karpenter

After reviewing the plan and setting the billing alert, apply the chosen plan:

```sh
terraform -chdir=infra apply
aws eks update-kubeconfig --region us-east-1 --name ca2-resilience --alias ca2-resilience
kubectl --context ca2-resilience get nodes
```

Before launching Spot nodes, check for the account-level service-linked role:

```sh
aws iam get-role --role-name AWSServiceRoleForEC2Spot
```

If the role lookup returns `NoSuchEntity`, create it once with `aws iam create-service-linked-role --aws-service-name spot.amazonaws.com`. It is shared across the account and lives outside the lab state.

```sh
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.15.1 --namespace kube-system --kube-context ca2-resilience \
  -f k8s/karpenter-values.yaml \
  --set-string settings.clusterName="$(terraform -chdir=infra output -raw cluster_name)" \
  --set-string settings.interruptionQueue="$(terraform -chdir=infra output -raw karpenter_interruption_queue)" \
  --set-string 'serviceAccount.annotations.eks\.amazonaws\.com/role-arn='"$(terraform -chdir=infra output -raw karpenter_controller_role_arn)" \
  --wait --timeout 5m

kubectl --context ca2-resilience apply -f k8s/ec2-node-class-prod.yaml -f k8s/ec2-node-class-dev.yaml -f k8s/nodepool-prod.yaml -f k8s/nodepool-dev.yaml
kubectl --context ca2-resilience wait --for=condition=Ready ec2nodeclass/ca2-prod ec2nodeclass/ca2-dev nodepool/prod-on-demand nodepool/dev-spot --timeout=5m
```

### View Kubernetes resources in the AWS console

Terraform grants Kubernetes admin access to the IAM identity that creates the cluster. A console session signed in as the account root user is a separate identity and needs its own EKS access entry. Select the same AWS account and **US East (N. Virginia), us-east-1**, then open **EKS > ca2-resilience > Resources**.

After each cluster recreation, refresh kubeconfig and apply the restricted viewer role from the project root:

```sh
aws eks update-kubeconfig --region us-east-1 \
  --name ca2-resilience --alias ca2-resilience
kubectl --context ca2-resilience apply -f k8s/console-view.yaml
```

Use an up-to-date AWS CLI v2 for the access-entry commands below. The older CLI used during the initial setup did not expose these commands. Verify that the terminal credentials belong to the lab account before constructing the root principal ARN:

```sh
aws sts get-caller-identity
CA2_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
CA2_ROOT_ARN="arn:aws:iam::${CA2_ACCOUNT_ID}:root"

aws eks create-access-entry --region us-east-1 \
  --cluster-name ca2-resilience \
  --principal-arn "$CA2_ROOT_ARN" --type STANDARD \
  --kubernetes-groups ca2-console-viewers
```

If the entry already exists, inspect its groups and use the following command to set the root entry to the viewer group:

```sh
aws eks describe-access-entry --region us-east-1 \
  --cluster-name ca2-resilience --principal-arn "$CA2_ROOT_ARN"
aws eks update-access-entry --region us-east-1 \
  --cluster-name ca2-resilience --principal-arn "$CA2_ROOT_ARN" \
  --kubernetes-groups ca2-console-viewers
```

The `ca2-console-viewers` group binds to `ca2-console-viewer`, which allows get, list and watch for nodes, namespaces, service accounts, pods, services, endpoints, events and selected workload resources. Secrets and write operations are excluded. Allow time for the access entry to propagate, then refresh the console Resources page.

The root access entry is configured separately from Terraform, and `k8s/console-view.yaml` is applied separately from the workload Kustomize configuration. Repeat both steps after destroying and recreating EKS. Kubernetes API access from an IAM user or role also requires the AWS console IAM permissions documented in the [AWS console resource-viewing guide](https://docs.aws.amazon.com/eks/latest/userguide/view-kubernetes-resources.html).

## 3. Start local monitoring and run the workloads

In a separate terminal, keep the Karpenter metrics port-forward running:

```sh
kubectl --context ca2-resilience -n kube-system port-forward svc/karpenter 18080:http-metrics
```

From the project root in your main terminal:

```sh
docker compose -f monitoring/compose.yaml up -d
kubectl --context ca2-resilience apply -f k8s/workload-prod.yaml -f k8s/workload-dev.yaml
kubectl --context ca2-resilience -n ca2-prod rollout status deploy/checkout --timeout=10m
kubectl --context ca2-resilience -n ca2-dev rollout status deploy/dev-service --timeout=10m
kubectl --context ca2-resilience get nodeclaims
kubectl --context ca2-resilience get nodes -L karpenter.sh/nodepool,karpenter.sh/capacity-type,topology.kubernetes.io/zone,node.kubernetes.io/instance-type
```

Open Grafana at http://127.0.0.1:3001/d/ca2-resilience/ca2-cost-and-resilience. Verify the Karpenter scrape at http://127.0.0.1:9091/targets. The dashboard shows ready pods, NodeClaims, disruption events, and estimated per-node EC2 rates. Both pools use `m5.large` for comparison. If single-AZ Spot capacity is unavailable, record that outcome. If you retry with another instance type, change both pool manifests and the dashboard price filter and label the retry as a separate run.

Run repeated HTTP requests from inside the cluster against `http://checkout.ca2-prod.svc.cluster.local` and `http://dev-service.ca2-dev.svc.cluster.local`. Record UTC timestamps and success/failure. Start with both deployments healthy, simulate the same single-worker loss in each profile, and record the time until HTTP service and the original ready replica count recover. Check placement before each trial. A simulated worker loss is a different event from an AWS Spot reclaim or an AZ outage. Record node runtimes and timestamped Spot and On-Demand rates separately from the shared EKS and bootstrap costs.

For the full deployment, run `terraform -chdir=infra output database_endpoints` to get the endpoints. Test PostgreSQL from a client pod inside the cluster using TLS and the matching RDS-managed Secrets Manager credentials. The HTTP workloads are stand-ins and do not depend on the databases. Run database failover as a separate trial using the Aurora writer endpoint, and report database recovery separately from pod recovery. Keep credentials out of the evidence.

### Optional CPU autoscaling demo

With EKS and both Karpenter NodePools ready, enable the Metrics Server add-on if the cluster does not already have a working Metrics Server. From the project root:

```sh
aws eks create-addon --region us-east-1 --cluster-name ca2-resilience --addon-name metrics-server
aws eks wait addon-active --region us-east-1 --cluster-name ca2-resilience --addon-name metrics-server
kubectl --context ca2-resilience top nodes
kubectl --context ca2-resilience apply -k k8s
node scaling-ui/server.js
```

Open [the local scaling panel](http://127.0.0.1:8088). The optional Kustomize configuration adds an Alpine sidecar that installs `stress-ng` from the Alpine package repository and an HPA for each test deployment. The local backend uses your kubeconfig context `ca2-resilience` by default. Set `CA2_KUBE_CONTEXT` to use another context.

Choose a workload and select **Scale up**. Each pod in that deployment starts running CPU stress when it receives the ConfigMap update. The HPA targets 70% of the stress container's CPU request and can scale from two to six pods. Karpenter can provision workers if pods cannot fit on existing nodes. Select **Scale down** to clear the stress request, or let it expire after ten minutes. Allow time for ConfigMap propagation, metrics sampling, and the 60-second HPA scale-down stabilization window.

While using the demo, use `kubectl apply -k k8s` for the workloads so the HPA controls replicas. When finished, stop the local UI with Ctrl+C. The cleanup below deletes the workload namespaces, which also removes the demo HPAs and ConfigMaps. An EKS-managed Metrics Server add-on is removed with the cluster.

## 4. Kubecost and Chaos Mesh

After recreating EKS, installing Karpenter and applying the workload manifests, run this from the project root:

```sh
./scripts/install-addons.sh
```

The script verifies the cluster and workload namespaces before applying anything. It installs the EKS-optimized Kubecost 3.3.1 configuration and Chaos Mesh 2.8.8. The Kubecost configuration follows the EKS registry and retention settings in the official chart. Run it again to retry a partial installation. Set `CA2_KUBE_CONTEXT` to select another kubeconfig context.

The add-ons use their own `lab-addons` On-Demand NodePool, limited to one `m5.xlarge` worker with a 100 GiB encrypted gp3 root volume. Kubecost's default aggregator memory request exceeds the spare memory of the existing 4 GiB bootstrap worker. The additional worker, its EBS volume and its public IPv4 address add costs beyond the earlier four-worker calculator estimate. Treat these as shared experiment overhead when comparing dev and prod.

Kubecost uses disposable local storage in this lab profile so installation does not require an EBS CSI driver or extra storage IAM configuration. Its cost history and saved reports are lost when the storage pods restart or the add-ons are removed. Export your evidence before teardown.

### Open the dashboards

Keep each command in a separate terminal:

```sh
kubectl --context ca2-resilience -n kubecost \
  port-forward svc/kubecost-frontend 9092:9090

kubectl --context ca2-resilience -n chaos-mesh \
  port-forward svc/chaos-dashboard 2333:2333
```

Open [Kubecost](http://127.0.0.1:9092) and [Chaos Mesh](http://127.0.0.1:2333). Both services use ClusterIP and local port-forwards. Chaos Mesh retains dashboard authentication. Generate a short-lived login token in your own terminal:

```sh
kubectl --context ca2-resilience -n chaos-mesh \
  create token ca2-chaos-operator --duration=1h
```

Paste the token into the dashboard and select `ca2-dev` or `ca2-prod` before opening **Experiments**. The dashboard lists all experiment types in the selected namespace. The operator can read those records and basic workload information in both lab namespaces. Create, update and delete permissions apply to PodChaos in those namespaces.

### Compare workload costs

In Kubecost's allocation view, group by namespace and compare `ca2-dev` with `ca2-prod` over the same observation window. Then group by deployment to inspect `dev-service` and `checkout`. Allow time for the FinOps agent to collect and process samples. Capture the exact window, pod counts and worker counts alongside the export.

This setup provides Kubernetes cost estimates using Kubecost's pricing and metrics collection. AWS billing reconciliation, the Spot data feed and external Aurora/RDS costs require a separate cloud-billing integration. The current setup does not provide an AWS invoice total. Local Prometheus and Grafana continue to collect Karpenter metrics independently.

### Run one failure experiment at a time

Installation enables Chaos Mesh's namespace filter and annotates only `ca2-dev` and `ca2-prod` for fault injection. Its privileged containerd daemons run on the two workload pools. Installing the add-ons does not apply an experiment.

Start a timestamped HTTP probe against the selected Service from an in-cluster client. Verify the deployment has healthy replicas. Applying the following file immediately kills one randomly selected matching pod in development:

```sh
kubectl --context ca2-resilience -n ca2-dev \
  rollout status deployment/dev-service --timeout=10m
kubectl --context ca2-resilience apply \
  -f k8s/addons/chaos-experiments/pod-kill-dev.yaml
kubectl --context ca2-resilience -n ca2-dev get podchaos,pods
```

Watch HTTP failures and pod readiness until the replacement is healthy. A rollout command started immediately after injection can return before the controller updates its status, so keep the probe and pod watch running. Delete the experiment after collecting the results:

```sh
kubectl --context ca2-resilience delete \
  -f k8s/addons/chaos-experiments/pod-kill-dev.yaml
```

Repeat the same steps for production using `pod-kill-prod.yaml`, namespace `ca2-prod` and deployment `checkout`. Delete and recreate a PodChaos object to repeat a completed experiment. These experiments test pod replacement by the Deployment. Karpenter worker replacement and database failover need separate trials.

### Remove the add-ons

Export cost evidence and finish all experiments first. Keep Karpenter running during add-on removal:

```sh
./scripts/uninstall-addons.sh
```

The script deletes PodChaos experiments in the two workload namespaces before uninstalling Chaos Mesh, removes Kubecost and the scoped dashboard roles, and deletes the add-on NodePool so Karpenter terminates its worker. It leaves the workload deployments available for further testing. Stop both dashboard port-forwards. Helm retains Chaos Mesh CRDs until the cluster is destroyed.

Implementation references: [AWS Kubecost installation](https://docs.aws.amazon.com/eks/latest/userguide/cost-monitoring-kubecost.html), [Chaos Mesh Helm installation](https://chaos-mesh.org/docs/production-installation-using-helm/) and [namespace filtering](https://chaos-mesh.org/docs/configure-enabled-namespace/).

## 5. Clean up

If you installed the add-ons, run `./scripts/uninstall-addons.sh` before deleting the workloads or uninstalling Karpenter.

Save the evidence first. Delete workloads and NodePools while Karpenter is still running so it can terminate its EC2 instances.

```sh
kubectl --context ca2-resilience delete -f k8s/workload-prod.yaml -f k8s/workload-dev.yaml
kubectl --context ca2-resilience delete -f k8s/nodepool-prod.yaml -f k8s/nodepool-dev.yaml --timeout=10m
kubectl --context ca2-resilience get nodeclaims
```

Once the NodeClaims and their EC2 instances are gone:

```sh
kubectl --context ca2-resilience delete -f k8s/ec2-node-class-prod.yaml -f k8s/ec2-node-class-dev.yaml
helm uninstall karpenter --namespace kube-system --kube-context ca2-resilience
terraform -chdir=infra destroy
docker compose -f monitoring/compose.yaml down
```

Use the same Terraform inputs as deployment. The lab databases are disposable and configured for deletion without final snapshots. Stop the metrics port-forward and verify that the EKS cluster, database instances, and lab EC2 instances are gone. Compose retains the local metric data.
