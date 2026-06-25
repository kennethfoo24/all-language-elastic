# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A polyglot demo application deployed on Kubernetes. A single request fans down a fixed chain of seven services, each calling the next: **NodeJS → Python → Java → Golang → .NET → Ruby → PHP**.

It demonstrates two things end-to-end across languages:
- **Nested JSON responses** — each service wraps the downstream service's JSON, so one call returns the whole chain as a single nested object.
- **Standardized structured JSON logging** — every service logs JSON on a shared schema.

The app is instrumentation-neutral (no vendor tracing). It is intentionally kept OpenTelemetry-ready so distributed tracing can be added later; see `docs/superpowers/specs/2026-06-23-json-responses-and-logging-design.md`.

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

`golang.yaml` is a standalone manifest for the Golang service with its own LoadBalancer (isolated testing).

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
