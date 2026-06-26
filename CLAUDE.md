# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A polyglot demo application deployed on Kubernetes. A single request fans down a fixed chain of seven services, each calling the next: **NodeJS → Python → Java → Golang → .NET → Ruby → PHP**.

It demonstrates two things end-to-end across languages:
- **Nested JSON responses** — each service wraps the downstream service's JSON, so one call returns the whole chain as a single nested object.
- **Standardized structured JSON logging** — every service logs JSON on a shared schema.

The base manifest (`all.yaml`) is instrumentation-neutral. Distributed tracing is added via a separate manifest (`all-otel.yaml`) using the Elastic Distribution of OpenTelemetry (EDOT) — see "OpenTelemetry / EDOT Instrumentation" below. The original design doc is `docs/superpowers/specs/2026-06-23-json-responses-and-logging-design.md`.

## Architecture

Each language lives in its own subdirectory with a `Dockerfile` and runs as a separate Kubernetes Deployment. Services communicate via Kubernetes Service DNS names (e.g. `all-language-python-lb:5000`), each read from an env var.

| Service | Port | Calls downstream (env var) |
|---------|------|----------------------------|
| nodejs  | 3000 | python (`PYTHON_SERVICE_URL`) |
| python  | 5000 | java (`JAVA_SERVICE_URL`) |
| java    | 8080 | golang (`GOLANG_SERVICE_URL`) |
| golang  | 8000 | dotnet (`DOTNET_SERVICE_URL`) |
| dotnet  | 5555 | ruby (`RUBY_SERVICE_URL`) |
| ruby    | 4567 | php (`PHP_SERVICE_URL`) |
| php     | 80   | — (leaf) |

NodeJS is the only public-facing service (LoadBalancer). All others are ClusterIP. Entry point: `GET /nodejs`.

## Response Envelope Contract

Every chain endpoint returns `Content-Type: application/json` with this shape:

```json
{
  "service": "nodejs",
  "message": "Hello from nodejs",
  "status": "ok",
  "timestamp": "<ISO-8601 UTC>",
  "upstream": { "...downstream service's full envelope, or null..." }
}
```

- Each caller parses the downstream JSON and embeds it as a real nested object (php, the leaf, has `upstream: null`).
- On a downstream failure: HTTP `502`, `status: "error"`, `upstream: null`, plus an `error` field. The 502 propagates up the chain.

## Log Schema

Every log line is JSON. Always present: `timestamp` (ISO-8601 UTC), `level`, `service`, `message`. Request-lifecycle logs add: `method`, `path`, `status_code`, `duration_ms`, `upstream`.

Standardized message strings (identical across services): `request received`, `calling upstream`, `upstream responded`, `request completed`, `upstream call failed`.

Per-language logger: nodejs = Winston · python = python-json-logger · java = logstash-logback-encoder (`logback-spring.xml`) · golang = `log/slog` · dotnet = Serilog (`ExpressionTemplate`) · ruby = stdlib `Logger` + JSON formatter · php = Monolog (custom formatter). Note: `level` is lowercase everywhere except Java (uppercase `INFO`/`ERROR`); php logs to stderr (Apache surfaces it in container logs).

## Kubernetes Deployment

```bash
kubectl apply -f all.yaml                 # all 7 Deployments + Services
kubectl get svc all-language-nodejs-lb    # find the LoadBalancer address
curl http://<LOAD_BALANCER_IP>/nodejs | jq
```

## GKE Terraform Module (`gke/`)


`gke/` provisions a zonal GKE Standard cluster (dedicated VPC + subnet + node pool) via Terraform. `cluster.sh` wraps `terraform` + `gcloud` for one-command up/down. Defaults to `asia-southeast1-a`, `e2-standard-4` × 3. Nodes are amd64, so arm64 EDOT workarounds (dotnet profiler path, golang native build) are not needed on GKE.

Requires Elastic org-policy labels set in `terraform.tfvars` (gitignored — copy from `terraform.tfvars.example`):

```bash
cd gke
cp terraform.tfvars.example terraform.tfvars   # edit project_id + labels
./cluster.sh up      # init + apply + wire kubectl
./cluster.sh down    # destroy everything
```

## OpenTelemetry / EDOT Instrumentation

`all-otel.yaml` mirrors `all.yaml` but wires every service for Elastic Distribution of OpenTelemetry (EDOT) tracing. Prereqs (not created by the file): the OpenTelemetry Operator and an `elastic-instrumentation` CR in `opentelemetry-operator-system`. Instrumentation differs by language:

| Service | Method | Where it lives |
|---------|--------|----------------|
| nodejs / python / java / dotnet | Operator auto-injection | `inject-<lang>` pod-template annotation |
| golang | Operator eBPF injection | `inject-go` + `otel-go-auto-target-exe: /app/hello-world` annotations |
| ruby | Manual OTel Ruby SDK (operator has no `inject-ruby`) | `opentelemetry-sdk`/`-exporter-otlp`/`-instrumentation-all` gems + `OpenTelemetry::SDK.configure(&:use_all)` in `ruby/app.rb` |
| php | EDOT PHP package (operator has no `inject-php`) | `elastic-otel-php` `.deb` installed in `php/Dockerfile` (bundles extension + SDK; no composer/pecl) |

Ruby/PHP read OTLP config from `OTEL_*` env vars set in `all-otel.yaml`. The operator-injected services need nothing in the image.

**Gotchas baked into the manifest/Dockerfiles:**
- **dotnet on arm64**: the operator only emits `linux-x64`/`linux-musl-x64` profiler paths (no arm64 case; it rejects other `otel-dotnet-auto-runtime` values). On arm64 nodes the injected x64 profiler fails to load → no traces. Fix is a deploy-time override: `kubectl set env deploy/all-language-dotnet CORECLR_PROFILER_PATH=/otel-auto-instrumentation-dotnet/<rid>/OpenTelemetry.AutoInstrumentation.Native.so` (rid = `linux-arm64` on arm64, else `linux-x64`). The operator only sets that env "if not already present," so the explicit value wins. The manifest is intentionally left arch-neutral; the override is in the README rollout steps.
- **php image is multi-arch**: `php/Dockerfile` selects the EDOT `.deb` via Docker's `TARGETARCH` build arg, so build with `docker buildx --platform linux/<arch>` (or a native `docker build`) matching the target node.
- **ruby/php instrumentation is in the image** → changes require a rebuild; on kind, `kind load docker-image` (plain `:latest` is `IfNotPresent`, so a restart alone won't refresh it).
- **golang eBPF needs a native image**: the Go agent attaches uprobes to the native binary and finds the process by exe path. An `amd64` image under Rosetta on an arm64 node shows `/proc/<pid>/exe` as `/run/rosetta/rosetta`, so the agent polls forever and never attaches. Build golang with `--platform linux/<node-arch>`. SDK-based services are unaffected by emulation.
- **ruby/php OTLP endpoint**: set manually in the manifest (operator can't inject it). It must point at a real collector Service — `opentelemetry-kube-stack-daemon-collector.opentelemetry-operator-system:4318`. Verify with `kubectl get svc -n opentelemetry-operator-system`.
- **dotnet shim vs `kubectl apply`**: the arm64 `CORECLR_PROFILER_PATH` is applied with `kubectl set env`; a subsequent `kubectl apply -f all-otel.yaml` resets the deployment and wipes it. Re-run the `set env` step after every apply.

See the README "OpenTelemetry tracing (EDOT)" section for the full deploy/rollout commands.

## Building Docker Images

CI (GitHub Actions) builds and pushes to Docker Hub (`kennethfoo49066/all-language-elastic-<service>`) on every push to `main`. Each language has its own workflow in [.github/workflows/](.github/workflows/).

These Dockerfiles `COPY <service>/ ...` paths relative to the **repo root**, so build from the repo root with `-f` (php is the exception — its context is `php/`). Java needs its jar built first.

```bash
docker build -f nodejs/Dockerfile -t kennethfoo49066/all-language-elastic-nodejs:latest .
cd java/app && ./mvnw package -DskipTests && cd ../..   # java: build jar first
docker build -f java/Dockerfile   -t kennethfoo49066/all-language-elastic-java:latest .
docker build -t kennethfoo49066/all-language-elastic-php:latest php/   # php: context is php/
```

## Per-Service Dev Notes

- **NodeJS**: Express + Winston. Run: `cd nodejs && npm install && node index.js`
- **Python**: Flask + python-json-logger. Run: `pip install -r python/requirements.txt && python python/app.py`
- **Java**: Spring Boot (Maven). Source in `java/app/src/`. Build/run: `cd java/app && ./mvnw spring-boot:run`
- **Golang**: stdlib + `log/slog` (needs Go ≥ 1.21). Run: `cd golang && go run main.go`
- **.NET**: ASP.NET Core + Serilog. Run: `cd dotnet && dotnet run`
- **Ruby**: Sinatra. Run: `cd ruby && bundle install && ruby app.rb`
- **PHP**: Apache + Monolog (composer). Local dev: `cd php && ./run.sh` (docker-compose).

PHP dependencies are installed at image-build time; `php/app/vendor/` is gitignored.
