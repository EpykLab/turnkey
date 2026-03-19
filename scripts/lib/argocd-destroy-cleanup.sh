#!/usr/bin/env bash
# Clear Argo CD CR finalizers and help release a stuck argocd namespace before/after Pulumi destroy.
# Caller must set KUBECONFIG to a valid kubeconfig.
set -euo pipefail

argocd_destroy_cleanup() {
  local ns="${ARGOCD_NAMESPACE:-argocd}"
  if ! kubectl get ns "${ns}" &>/dev/null; then
    return 0
  fi

  echo "    (${ns}) delete Application / ApplicationSet / AppProject CRs (drop finalizers)"
  kubectl delete applications.argoproj.io --all -n "${ns}" --wait=false 2>/dev/null || true
  kubectl delete applicationsets.argoproj.io --all -n "${ns}" --wait=false 2>/dev/null || true
  kubectl delete appprojects.argoproj.io --all -n "${ns}" --wait=false 2>/dev/null || true

  sleep 3

  local r
  for r in $(kubectl get applications.argoproj.io -n "${ns}" -o name 2>/dev/null || true); do
    kubectl patch "${r}" -n "${ns}" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  done
  for r in $(kubectl get applicationsets.argoproj.io -n "${ns}" -o name 2>/dev/null || true); do
    kubectl patch "${r}" -n "${ns}" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  done
  for r in $(kubectl get appprojects.argoproj.io -n "${ns}" -o name 2>/dev/null || true); do
    kubectl patch "${r}" -n "${ns}" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  done

  echo "    (${ns}) clear namespace spec.finalizers (if terminating)"
  kubectl patch namespace "${ns}" --type=merge -p '{"spec":{"finalizers":[]}}' 2>/dev/null || true

  kubectl delete namespace "${ns}" --wait=false --ignore-not-found=true 2>/dev/null || true
}
