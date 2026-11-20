#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
context="${CA2_KUBE_CONTEXT:-ca2-resilience}"
kubectl_cmd=(kubectl --context "$context")

# A partial install may not have registered the Chaos Mesh APIs yet.
chaos_resources=$("${kubectl_cmd[@]}" api-resources \
  --api-group=chaos-mesh.org -o name)
if [[ "$chaos_resources" == *"podchaos.chaos-mesh.org"* ]]; then
  # Finish experiment finalizers while the controller is still running.
  for namespace in ca2-prod ca2-dev; do
    "${kubectl_cmd[@]}" delete podchaos --all --namespace "$namespace" \
      --ignore-not-found --timeout=5m
  done
fi
"${kubectl_cmd[@]}" delete -f k8s/addons/chaos-dashboard-access.yaml \
  --ignore-not-found
helm uninstall chaos-mesh --namespace chaos-mesh \
  --kube-context "$context" --ignore-not-found --wait --timeout=5m
helm uninstall kubecost --namespace kubecost \
  --kube-context "$context" --ignore-not-found --wait --timeout=5m

# Skip namespaces already deleted during full-lab cleanup.
for namespace in ca2-prod ca2-dev; do
  existing=$("${kubectl_cmd[@]}" get namespace "$namespace" \
    --ignore-not-found -o name)
  if [ -n "$existing" ]; then
    "${kubectl_cmd[@]}" annotate namespace "$namespace" \
      chaos-mesh.org/inject- --overwrite
  fi
done

"${kubectl_cmd[@]}" delete nodepool lab-addons --ignore-not-found \
  --cascade=foreground --timeout=10m
"${kubectl_cmd[@]}" delete ec2nodeclass ca2-addons --ignore-not-found
"${kubectl_cmd[@]}" delete namespace chaos-mesh kubecost --ignore-not-found \
  --timeout=5m
