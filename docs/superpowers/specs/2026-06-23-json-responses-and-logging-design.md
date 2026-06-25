# Design: Standardized JSON Responses + JSON Logging Across the Service Chain

**Date:** 2026-06-23
**Status:** Implemented (see commit history on branch `json-responses-and-logging`)
**Repo:** all-language (polyglot demo: nodejs → python → java → golang → dotnet → ruby → php)

## Context

This repository is a polyglot demo where a single inbound call fans down a fixed
chain of seven services, each calling the next. The goal of this demo is that
**one call to the front service cascades through all seven**, so that when the
application is traced later it will chain together into a single flamegraph.

Datadog instrumentation was recently removed to keep the project vendor-neutral
and OpenTelemetry-ready. With auto-instrumentation gone, two things need to be
made deliberate and consistent so the demo is clean and ready for OTel:

1. **Service-to-service output** is currently inconsistent — nodejs and python
   emit JSON, but java/golang/dotnet/ruby/php emit plain text, and each upstream
   service stuffs the downstream plain-text blob into a string. The final
   response is a JSON object wrapping a nested text blob rather than clean
   structured JSON.
2. **Logging** is inconsistent — only nodejs emits JSON (mixed with plain
   `console.log`), dotnet has Serilog configured but unwired (dead code), and
   python/java/golang/ruby/php log plain text with no shared schema.

This design standardizes both, without yet adding tracing. Tracing
(OpenTelemetry, `traceparent` propagation, span export, `trace_id` in logs) is
**deliberately deferred** so we can later observe the contrast between the
vanilla baseline and an OTel-instrumented setup.

## Goals

- Confirm the call chain links end-to-end (verified — it does).
- Every service returns a **nested JSON envelope** embedding the downstream
  service's JSON as a real nested object.
- Every service emits **structured JSON logs** on a single shared schema using
  each language's idiomatic logger.
- Keep the wiring clean so OpenTelemetry can be added later with minimal change.

## Non-Goals (Deferred)

- OpenTelemetry SDKs / zero-code agents.
- W3C `traceparent` propagation and span export to a collector/backend.
- A `trace_id` field in the log schema (intentionally omitted — vanilla baseline,
  so the later OTel addition is observable as a before/after contrast).
- Adding new correlation headers. Existing `X-Request-ID` forwarding is left
  as-is (harmless); no new ones are added.

## Current State (verified)

Chain (links end-to-end; each hop reads the next URL from an env var in
`all.yaml`, except ruby→php which is hardcoded in `ruby/app.rb`):

```
nodejs /nodejs  →  python /python  →  java /java  →  golang /golang
  →  dotnet /dotnet  →  ruby /ruby  →  php /php  →  returns "Hello, World!"
```

| Service | Output today | Logging today |
|---|---|---|
| nodejs | JSON `{message, otherServiceData}` | Winston JSON **mixed with** plain `console.log`/`console.error` |
| python | JSON, but embeds java's plain text as a string | Flask default (plain text) |
| java | plain text (forwards golang body) | Spring Boot default (plain text) |
| golang | plain text greeting + dotnet body | `log.Printf` (plain text) |
| dotnet | plain text greeting + ruby body | Serilog JSON configured but **never wired** (dead code) → default plain text |
| ruby | plain text | Sinatra default (plain text) |
| php | plain text `"Hello, World!"` | none |

## Design

### Response Envelope Contract

Every chain endpoint returns exactly this shape with `Content-Type:
application/json`:

```json
{
  "service": "nodejs",
  "message": "Hello from nodejs",
  "status": "ok",
  "timestamp": "2026-06-23T10:00:00.123Z",
  "upstream": { "...downstream service's full envelope, or null..." }
}
```

Rules:
- **Field set:** `service` (string), `message` (string), `status` (`"ok"` |
  `"error"`), `timestamp` (ISO-8601 UTC), `upstream` (object | null).
- **`message`** is `"Hello from <service>"`.
- **Leaf (php):** `upstream` is `null`.
- **Embedding:** each caller MUST parse the downstream JSON response body and
  embed it as a nested **object** — never as a stringified blob. (e.g. python
  uses `resp.json()`, not `resp.text`; dotnet/golang/java/ruby deserialize then
  re-embed.)
- **Downstream failure:** the service returns HTTP `502` with a valid envelope
  where `status` is `"error"`, `upstream` is `null`, and an additional `error`
  field carries the failure reason (string). The 502 propagates up the chain;
  each upstream caller treats a non-2xx downstream as a failed upstream call and
  emits its own `status: "error"` envelope.
- Endpoints are unchanged: `/nodejs`, `/python`, `/java`, `/golang`, `/dotnet`,
  `/ruby`, `/php`.

### Log Schema

Every log line is a single JSON object. Always present:

- `timestamp` — ISO-8601 UTC
- `level` — `info` | `error`
- `service` — service name
- `message` — one of the standardized strings below

Request-lifecycle logs additionally carry, where known: `method`, `path`,
`status_code`, `duration_ms`, `upstream`.

No `trace_id` field (deferred by design).

### Standardized Log Event Vocabulary

Identical message strings across all seven services:

| Event | level | message | extra fields |
|---|---|---|---|
| Request arrives | info | `request received` | method, path |
| About to call next service | info | `calling upstream` | upstream |
| Downstream succeeded | info | `upstream responded` | upstream, status_code |
| Request done | info | `request completed` | method, path, status_code, duration_ms |
| Downstream failed | error | `upstream call failed` | upstream, error |

`upstream` is the **name** of the next service (e.g. `"python"`), not a URL.
The leaf service (php) does not emit `calling upstream` / `upstream responded` /
`upstream call failed`.

### Per-Service Implementation Plan

Logging uses each ecosystem's idiomatic structured logger (Approach A), with the
field schema pinned explicitly so output is as identical as the libraries allow.

| Service | Endpoint | Response change | Logger |
|---|---|---|---|
| nodejs | `/nodejs` | Rename `otherServiceData`→`upstream`; add `service`/`status`/`timestamp`; embed parsed python JSON (axios already parses). Remove all `console.log`/`console.error`. | **Winston** (present); set a default `service` field; use it exclusively |
| python | `/python` | Parse java with `resp.json()`; build envelope. | **python-json-logger** (new dep in `python/requirements.txt`) |
| java | `/java` | Deserialize golang JSON (Jackson), re-embed as nested object; return envelope as POJO/Map. | **logstash-logback-encoder** (new dep in `java/app/pom.xml`) + `logback-spring.xml` |
| golang | `/golang` | Parse dotnet JSON; build envelope struct; `encoding/json`. | **`log/slog`** JSON handler (stdlib; bump `go` directive in `golang/go.mod` to 1.21+ — build image is already golang:1.23) |
| dotnet | `/dotnet` | Parse ruby JSON (`System.Text.Json`); build envelope; return JSON. | **Serilog** (present) — wire it via `builder.Host.UseSerilog(...)`; currently dead code |
| ruby | `/ruby` | Parse php JSON; build envelope; `content_type :json`. | **ougai** (new gem in `ruby/Gemfile`) |
| php | `/php` | Return JSON envelope with `upstream: null` instead of `"Hello, World!"`. | **monolog** (new dep via a new `php/composer.json`; Dockerfile installs deps) |

### Minor Wiring Cleanups

- Make ruby→php URL an env var `PHP_SERVICE_URL` in `ruby/app.rb` and `all.yaml`
  (currently hardcoded), matching the pattern of every other hop.
- golang's `/` → `/internal-work` self-call is **not** part of the chain (java
  calls `/golang` → `helloService`); leave untouched, noted here for clarity.
- php gains a `composer.json` (none exists today); its Dockerfile installs
  composer dependencies for monolog.

## Verification

- **Build:** `docker build` each changed image. (This dev shell has no
  go/php/ruby/dotnet runtimes, so Docker is the build/verify path; java needs
  `cd java/app && ./mvnw package` first, as today.)
- **End-to-end success path:** deploy `all.yaml`, then
  `curl http://<nodejs-LB>/nodejs | jq` → expect a **7-level nested envelope**
  ending at php with `upstream: null`. Each level has
  `service`/`message`/`status`/`timestamp`/`upstream`.
- **Error path:** scale php to 0 replicas, curl again → the ruby level shows
  `status: "error"`, `upstream: null`, populated `error`, and a 502 propagates
  to the top.
- **Logs:** `kubectl logs deploy/all-language-<svc>` for each service → every
  line parses as JSON and carries the standard fields and standardized messages.
- **Schema check:** pipe one log line per service through `jq`, asserting the
  required keys exist and `message` is from the standardized vocabulary.

## Future Work (explicitly out of scope here)

- Add OpenTelemetry (SDK or zero-code) per service + an OTel Collector to produce
  the cross-service flamegraph; observe `trace_id` appearing in logs vs. this
  vanilla baseline.
- Standardize `traceparent` propagation across all hops once OTel is adopted.

## Implementation Notes (deviations from this design)

- **ruby logger:** used the stdlib `Logger` with a JSON formatter instead of the
  `ougai` gem — still idiomatic, no new dependency, and an exact schema match.
- **golang:** removed the unused `/` (`sayHello`) and `/internal-work` demo
  endpoints (Datadog-era span demos, not part of the chain) rather than leaving
  them. The chain endpoint `/golang` is unchanged in purpose.
- **log `level` casing:** lowercase everywhere except Java, which emits uppercase
  `INFO`/`ERROR` via logstash-logback-encoder. Field names and message strings
  are identical across all services.
- **php logs:** written to stderr (Apache surfaces it in container logs).
- **registry:** images are published to `kennethfoo49066/all-language-elastic-<service>`.
