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

> **Apple Silicon (M-series):** the prebuilt images are `linux/amd64` and run under emulation. If a pod shows `exec format error`, enable Docker Desktop → Settings → General → **"Use Rosetta for x86/amd64 emulation"**.

---

## Option B — Standard Kubernetes (e.g. GKE)

Point `kubectl` at your cluster, then deploy. For GKE:
```bash
gcloud container clusters get-credentials <CLUSTER_NAME> \
  --region <REGION> --project <PROJECT_ID>
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
