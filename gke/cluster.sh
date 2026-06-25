#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# cluster.sh — bring the GKE Standard cluster up or down with Terraform + gcloud.
#
#   ./cluster.sh up      init + apply, then wire kubectl to the new cluster
#   ./cluster.sh down    destroy the cluster, node pool, and VPC
#   ./cluster.sh status  show outputs and node list
#   ./cluster.sh creds    (re)fetch kubectl credentials
#   ./cluster.sh plan     preview changes without applying
# -----------------------------------------------------------------------------
set -euo pipefail

# Always operate from the directory holding the .tf files (this script's dir).
TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$TF_DIR"

die()  { printf 'Error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found on PATH — install it first."; }

usage() {
  # Print the leading comment block (everything after the shebang up to the first
  # non-comment line), stripping the leading "# ".
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

# Fail early with a friendly message if project_id hasn't been supplied anywhere.
require_project() {
  if [ ! -f terraform.tfvars ] && [ -z "${TF_VAR_project_id:-}" ]; then
    die "project_id is not set. Either:
  - cp terraform.tfvars.example terraform.tfvars  (then edit project_id), or
  - export TF_VAR_project_id=<your-gcp-project-id>"
  fi
}

# The Terraform google provider uses Application Default Credentials.
ensure_auth() {
  need gcloud
  if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
    echo "No application-default credentials found — launching login..."
    gcloud auth application-default login
  fi
}

get_creds() {
  need gcloud
  need kubectl
  gcloud container clusters get-credentials \
    "$(terraform output -raw cluster_name)" \
    --zone "$(terraform output -raw location)" \
    --project "$(terraform output -raw project_id)"
}

cmd="${1:-}"
case "$cmd" in
  up)
    need terraform; require_project; ensure_auth
    terraform init -input=false
    terraform apply -input=false -auto-approve
    echo "== Wiring kubectl to the new cluster =="
    get_creds
    kubectl get nodes || true
    echo
    echo "Cluster is up. Deploy the app with:  kubectl apply -f ../all.yaml"
    ;;
  down)
    need terraform; require_project
    # Best-effort: free any L4/L7 load balancers the app created so the VPC can
    # be destroyed cleanly (a lingering Service of type LoadBalancer can block it).
    kubectl delete -f ../all.yaml --ignore-not-found 2>/dev/null || true
    terraform destroy -input=false -auto-approve
    ;;
  status)
    need terraform
    terraform output || true
    echo; kubectl get nodes 2>/dev/null || true
    ;;
  creds)
    need terraform; get_creds ;;
  plan)
    need terraform; require_project; ensure_auth
    terraform init -input=false
    terraform plan -input=false ;;
  ""|-h|--help|help)
    usage ;;
  *)
    usage; exit 1 ;;
esac
