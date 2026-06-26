# all-language

A polyglot demo where one request fans down a chain of seven services, each calling the next:

**NodeJS → Python → Java → Golang → .NET → Ruby → PHP**

Every service returns a **nested JSON envelope** (so a single call shows the whole chain) and logs in **structured JSON**.

## Prerequisites

- `kubectl`
- `jq` (optional, for pretty output)
- A Kubernetes cluster — either a local **kind** cluster (below) or a managed one like **GKE**

> Images are prebuilt on Docker Hub (`kennethfoo49066/all-language-elastic-<service>`) and referenced in `all.yaml`, so you don't need to build anything to run this.

---

## Option A — Local kind cluster

`kind` runs Kubernetes inside Docker, so you also need Docker (Docker Desktop on Mac).

**Install kind:**
```bash
brew install kind          # macOS (Homebrew)
```

**Create the cluster and deploy:**
```bash
kind create cluster --name all-language
kubectl apply -f all.yaml
kubectl get pods -w        # wait until all 7 are Running (Ctrl-C to stop watching)
```

**Reach the app.** kind has no LoadBalancer, so the `all-language-nodejs-lb` service stays `<pending>` — use port-forward:
```bash
kubectl port-forward svc/all-language-nodejs-lb 8080:80
# in another terminal:
curl http://localhost:8080/nodejs | jq
```

**Tear down:**
```bash
kubectl delete -f all.yaml
kind delete cluster --name all-language
```

> **Apple Silicon (M-series):** the prebuilt Docker Hub images used by `all.yaml` are `linux/amd64` and run under emulation — if a pod shows `exec format error`, enable Docker Desktop → Settings → General → **"Use Rosetta for x86/amd64 emulation"**. If you build the images yourself (e.g. for the EDOT tracing workflow), build them natively for your node's architecture with `docker buildx build --platform linux/arm64 …` so auto-instrumentation loads the matching native libraries (see the OpenTelemetry section below).

---

## Option B — GKE (Terraform)

The `gke/` directory contains a Terraform module that provisions a zonal GKE Standard cluster (VPC + subnet + node pool). See [gke/README.md](gke/README.md) for full setup steps.

```bash
cd gke
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — set project_id and org-policy labels
./cluster.sh up       # provisions cluster and wires kubectl
```

Or point `kubectl` at any existing GKE cluster manually:
```bash
gcloud container clusters get-credentials <CLUSTER_NAME> \
  --zone <ZONE> --project <PROJECT_ID>
```

**Deploy:**
```bash
kubectl apply -f all.yaml
kubectl get pods           # wait until all 7 are Running
```

**Reach the app.** A real cloud cluster provisions an external IP for the `nodejs` LoadBalancer:
```bash
kubectl get svc all-language-nodejs-lb -w     # wait for EXTERNAL-IP to appear
curl http://<EXTERNAL-IP>/nodejs | jq
```

**Tear down:**
```bash
kubectl delete -f all.yaml
```

---

## Call each service individually

Each service exposes its own `GET /<service>` route and, when called, runs the rest of the chain *below* it (e.g. curling `java` returns java → golang → dotnet → ruby → php; `php` is the leaf and returns just itself).

| Service | Route | Pod port | Service (in-cluster DNS) |
|---------|-------|----------|--------------------------|
| nodejs  | `/nodejs` | 3000 | `all-language-nodejs-lb:80` *(LoadBalancer — public)* |
| python  | `/python` | 5000 | `all-language-python-lb:5000` |
| java    | `/java`   | 8080 | `all-language-java-lb:8080` |
| golang  | `/golang` | 8000 | `all-language-golang-lb:8000` |
| dotnet  | `/dotnet` | 5555 | `all-language-dotnet-lb:5555` |
| ruby    | `/ruby`   | 4567 | `all-language-ruby-lb:80` |
| php     | `/php`    | 80   | `all-language-php-lb:80` |

Only `nodejs` is a LoadBalancer. The other six are `ClusterIP`, so to curl them directly use `kubectl port-forward` (each line below maps `localhost:8080` → that service; run one at a time, then curl in another terminal):

```bash
# nodejs  (public via LoadBalancer — no port-forward needed on a cloud cluster)
curl http://<EXTERNAL-IP>/nodejs | jq

# python
kubectl port-forward svc/all-language-python-lb 8080:5000
curl http://localhost:8080/python | jq

# java
kubectl port-forward svc/all-language-java-lb 8080:8080
curl http://localhost:8080/java | jq

# golang
kubectl port-forward svc/all-language-golang-lb 8080:8000
curl http://localhost:8080/golang | jq

# dotnet
kubectl port-forward svc/all-language-dotnet-lb 8080:5555
curl http://localhost:8080/dotnet | jq

# ruby
kubectl port-forward svc/all-language-ruby-lb 8080:80
curl http://localhost:8080/ruby | jq

# php  (leaf — returns only itself, "upstream": null)
kubectl port-forward svc/all-language-php-lb 8080:80
curl http://localhost:8080/php | jq
```

> Prefer not to port-forward? Curl from a throwaway pod inside the cluster using the in-cluster DNS names above, e.g.:
> ```bash
> kubectl run curl --rm -it --image=curlimages/curl --restart=Never -- \
>   curl -s http://all-language-java-lb:8080/java
> ```

## What you get back

A JSON response nested seven levels deep — each service wrapping the one it called, ending at php (`"upstream": null`):

```json
{
  "service": "nodejs",
  "message": "Hello from nodejs",
  "status": "ok",
  "timestamp": "...",
  "upstream": { "service": "python", "upstream": { "service": "java", "...": "..." } }
}
```

## View logs

Every service logs JSON on the same schema:

```bash
kubectl logs deploy/all-language-nodejs | jq
```

## OpenTelemetry tracing (EDOT)

`all-otel.yaml` is the same topology wired for the Elastic Distribution of OpenTelemetry
(EDOT). It assumes the OpenTelemetry Operator + an `elastic-instrumentation` CR are
already installed (see the header of that file). How each service is instrumented:

| Service | Method |
|---------|--------|
| nodejs / python / java / dotnet | Operator auto-injection (`inject-*` annotation) |
| golang  | Operator eBPF injection (`inject-go` + `otel-go-auto-target-exe`) |
| ruby    | Manual OTel Ruby SDK in the app (no operator support) |
| php     | EDOT PHP package baked into the image (no operator support) |

### Deploy

```bash
kubectl apply -f all-otel.yaml
```

`ruby` and `php` carry their instrumentation **inside the image**, so if you change
them you must rebuild. On **kind**, load the image into the node (the prebuilt
Docker Hub `:latest` is `IfNotPresent`, so a plain restart won't pick up a new build):

```bash
# Build for the node's architecture (arm64 on Apple Silicon, amd64 on a cloud cluster)
docker build -f ruby/Dockerfile -t kennethfoo49066/all-language-elastic-ruby:latest .
docker build               -t kennethfoo49066/all-language-elastic-php:latest  php/

# kind: load images into the cluster, then restart
kind load docker-image kennethfoo49066/all-language-elastic-ruby:latest --name kind
kind load docker-image kennethfoo49066/all-language-elastic-php:latest  --name kind
kubectl rollout restart deploy/all-language-golang deploy/all-language-ruby deploy/all-language-php

# Standard cluster (e.g. GKE): push to Docker Hub instead of `kind load`, then restart
#   docker push kennethfoo49066/all-language-elastic-ruby:latest
#   docker push kennethfoo49066/all-language-elastic-php:latest
```

### .NET on arm64 (e.g. kind on Apple Silicon)

The OpenTelemetry Operator only knows the `linux-x64` / `linux-musl-x64` .NET profiler
paths — it has no arm64 case and injects the x64 path even on arm64 nodes, so the CLR
profiler fails to load and no .NET traces appear. EDOT's image *does* ship the arm64
native profiler, so the fix is to point `CORECLR_PROFILER_PATH` at it. The operator only
sets that env var "if not already present," so an explicit value always wins. Pick the
path from the node arch — safe to run on either cluster (on x86 it resolves to
`linux-x64`, the same value the operator would have used):

```bash
ARCH=$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.architecture}')
[ "$ARCH" = "arm64" ] && RID=linux-arm64 || RID=linux-x64
kubectl set env deploy/all-language-dotnet \
  CORECLR_PROFILER_PATH=/otel-auto-instrumentation-dotnet/$RID/OpenTelemetry.AutoInstrumentation.Native.so
```

### Golang eBPF requires a native (non-emulated) image

The Go agent is eBPF-based: it attaches uprobes to the **native** binary and discovers
the process by its executable path. If the golang image is `amd64` running under Rosetta
emulation on an arm64 node, the process's `/proc/<pid>/exe` resolves to `/run/rosetta/rosetta`
(not `/app/hello-world`), so the agent polls forever and never attaches — and uprobes
can't instrument a translated binary anyway. Build golang for the node's architecture:

```bash
docker build --platform linux/arm64 -f golang/Dockerfile -t kennethfoo49066/all-language-elastic-golang:latest .
kind load docker-image kennethfoo49066/all-language-elastic-golang:latest --name kind
kubectl rollout restart deploy/all-language-golang
# Confirm attach: the sidecar log should reach "instrumentation loaded successfully, starting..."
kubectl logs deploy/all-language-golang -c opentelemetry-auto-instrumentation | tail
```

The SDK-based services (node/python/java/dotnet/ruby) instrument *inside* the runtime, so
they work fine under emulation — only golang's eBPF approach needs the native build.

> **Order matters:** the `.NET` arch shim above is set with `kubectl set env`, which a later
> `kubectl apply -f all-otel.yaml` will wipe (the manifest is intentionally arch-neutral).
> Always re-run the dotnet `kubectl set env` step *after* any `kubectl apply`.

### Generate traffic, then check Elastic for all 7 services

```bash
kubectl port-forward svc/all-language-nodejs-lb 8080:80 &
curl -s http://localhost:8080/nodejs | jq .service
```
