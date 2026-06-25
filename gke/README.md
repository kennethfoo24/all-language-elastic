# GKE Standard cluster (Terraform)

Provisions a **zonal GKE Standard cluster** for running the all-language demo on a
real cloud cluster (README "Option B"). Terraform creates a dedicated VPC + subnet
and one managed node pool; `cluster.sh` wraps `terraform` + `gcloud` for one-command
up/down.

Defaults: `asia-southeast1-a`, `e2-standard-4` × 3, Regular release channel.

## Prerequisites

- [`terraform`](https://developer.hashicorp.com/terraform/install) ≥ 1.5
- [`gcloud`](https://cloud.google.com/sdk/docs/install) (authenticated: `gcloud auth login`)
- `kubectl`
- A GCP project with billing enabled, and permission to create GKE clusters / networks.

## Configure

```bash
cd gke
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars and set project_id  (or: export TF_VAR_project_id=<id>)
```

Only `project_id` is required. Override region/zone/size/etc. in `terraform.tfvars`
(see `variables.tf` for all options).

## Bring it up / down

```bash
./cluster.sh up       # init + apply, then point kubectl at the cluster
./cluster.sh status   # outputs + `kubectl get nodes`
./cluster.sh plan     # preview without applying
./cluster.sh creds    # re-fetch kubectl credentials
./cluster.sh down     # destroy everything (cluster, node pool, VPC)
```

`up` also runs `gcloud auth application-default login` if needed (Terraform's Google
provider authenticates via Application Default Credentials).

## Deploy the app

```bash
kubectl apply -f ../all.yaml
kubectl get svc all-language-nodejs-lb -w     # wait for the LoadBalancer EXTERNAL-IP
curl http://<EXTERNAL-IP>/nodejs | jq
```

## Notes

- **Nodes are amd64.** The EDOT arm64 workarounds from the local kind setup are **not
  needed here**: the operator's default `linux-x64` .NET profiler path is correct, and
  the golang eBPF agent attaches to the native amd64 binary. Use the stock amd64 images.
- **Cost.** A zonal cluster has no control-plane fee beyond GKE's free tier allowance;
  you pay for the 3 `e2-standard-4` nodes + disks + the LoadBalancer while it's up. Run
  `./cluster.sh down` when finished.
- **`down` deletes the app's LoadBalancer first** so a lingering forwarding rule can't
  block VPC teardown. `deletion_protection` is disabled on the cluster so destroy works.
- **State is local.** `terraform.tfstate` lives in this directory (gitignored). For team
  use, switch to a remote GCS backend.
