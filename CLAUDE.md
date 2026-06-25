# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A polyglot demo application deployed on Kubernetes. Each service calls the next in a chain: **NodeJS → Python → Java → Golang → .NET → Ruby → PHP**. The primary purpose is to demonstrate distributed tracing and log correlation across multiple languages.

## Architecture

Each language lives in its own subdirectory with a `Dockerfile` and runs as a separate Kubernetes Deployment. Services communicate via Kubernetes ClusterIP/LoadBalancer DNS names (e.g. `all-language-python-lb:5000`).

| Service | Port | Calls downstream |
|---------|------|-----------------|
| nodejs  | 3000 | Python (env: `PYTHON_SERVICE_URL`) |
| python  | 5000 | Java (env: `JAVA_SERVICE_URL`) |
| java    | 8080 | Golang (env: `GOLANG_SERVICE_URL`) |
| golang  | 8000 | .NET (env: `DOTNET_SERVICE_URL`) |
| dotnet  | 5555 | Ruby (env: `RUBY_SERVICE_URL`) |
| ruby    | 4567 | PHP (hardcoded `all-language-php-lb:80`) |
| php     | 80   | — |

NodeJS is the only public-facing service (LoadBalancer). All others are ClusterIP.

Entry point: `GET /nodejs` on the NodeJS LoadBalancer IP.

## Kubernetes Deployment

```bash
# Deploy all services
kubectl apply -f all.yaml

# Get the NodeJS load balancer IP
kubectl get svc all-language-nodejs-lb
curl http://<LOAD_BALANCER_IP>/nodejs
```

`golang.yaml` is a standalone manifest for the Golang service with a LoadBalancer (used for isolated testing).

## Building & Pushing Docker Images

CI (GitHub Actions) builds and pushes to Docker Hub (`kennethfoo49066/`) on every push to `main`. Each language has its own workflow in [.github/workflows/](.github/workflows/).

To build locally:
```bash
docker build -t kennethfoo49066/all-language-elastic-nodejs:latest ./nodejs
docker build -t kennethfoo49066/all-language-elastic-python:latest ./python
# etc.
```

## Per-Service Dev Notes

- **NodeJS**: Express + Winston (JSON structured logs).
- **Python**: Flask. Run locally: `pip install -r python/requirements.txt && python python/app.py`
- **Java**: Spring Boot (Maven). Source in `java/app/src/`. Build: `cd java/app && ./mvnw package`
- **Golang**: stdlib only. Run: `cd golang && go run main.go`
- **.NET**: ASP.NET Core + Serilog (JSON formatter). Run: `cd dotnet && dotnet run`
- **Ruby**: Sinatra. Run: `cd ruby && bundle install && ruby app.rb`
- **PHP**: Apache-served. Use `php/docker-compose.yaml` for local dev.
