#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
context="${CA2_KUBE_CONTEXT:-ca2-resilience}"
kubectl_cmd=(kubectl --context "$context")

# Fail before changing anything if EKS or the required Karpenter APIs are absent.
"${kubectl_cmd[@]}" get --raw=/readyz --request-timeout=15s
"${kubectl_cmd[@]}" get nodepool/prod-on-demand nodepool/dev-spot
"${kubectl_cmd[@]}" get namespace ca2-prod ca2-dev

"${kubectl_cmd[@]}" apply -f k8s/addons/resources.yaml
"${kubectl_cmd[@]}" wait --for=condition=Ready \
  ec2nodeclass/ca2-addons nodepool/lab-addons --timeout=5m
"${kubectl_cmd[@]}" annotate namespace ca2-prod ca2-dev \
  chaos-mesh.org/inject=enabled --overwrite

helm upgrade --install kubecost oci://public.ecr.aws/kubecost/kubecost \
  --version 3.3.1 --namespace kubecost --kube-context "$context" \
  -f k8s/addons/kubecost-values.yaml --wait --timeout=15m

helm upgrade --install chaos-mesh chaos-mesh \
  --repo https://charts.chaos-mesh.org --version 2.8.8 \
  --namespace chaos-mesh --kube-context "$context" \
  -f k8s/addons/chaos-mesh-values.yaml --wait --timeout=10m

"${kubectl_cmd[@]}" apply -f k8s/addons/chaos-dashboard-access.yaml

"${kubectl_cmd[@]}" get pods -n kubecost
"${kubectl_cmd[@]}" get pods -n chaos-mesh
# echo "Add-ons installed. Dashboard and experiment commands are in README.md."
