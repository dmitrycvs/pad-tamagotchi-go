# Lab 4 step 1 handoff for Dmitrii

Checked 2026-11-09. The broker core, Compose integration and monitoring run
locally; all five service PRs pass CI. Broker PR #1 is approved and merged into
`develop`; the four other service PRs await review. The common integration stays draft
because remaining required reviews, image publication, and other owners' instrumentation
are outstanding. No protected branch was bypassed.

## Image and contract

Release target: **`maxkostov/message-broker:1.0.0`**. **Not published yet.**
`DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` are configured (the user supplied the
token after initial preparation). CI builds the exact multi-stage image without pushing.
The main release workflow verifies tests/coverage, refuses an existing version,
pushes the version plus latest, and creates the matching Git tag.

Reviewable contract:
[Message Broker shared contract](https://github.com/MaxKostov/message-broker/blob/develop/README.md#shared-contract).
This link uses the reviewed develop branch. It documents the
request envelope, raw HTTP reply, queue names, status/error headers, public peer
reads, JWT trust translation and thin prefix. Topics (Dmitrii) and gRPC (Denis)
remain explicit placeholders. Port 9070 is reserved without a listener.

The private repo has `main` and `develop`, the exact Service Discovery rulesets,
and invitations for huntrese, dmitrycvs, aXeeDENt and filipel2004. GitHub review
requirements remain active: one develop approval, two main approvals.

## Source and review sequence

| Repository | Develop PR | Tested source commit | Release target |
| --- | --- | --- | --- |
| Message Broker | [#1](https://github.com/MaxKostov/message-broker/pull/1) | `9bceac6` (reviewed develop) | 1.0.0 |
| API Gateway | [#14](https://github.com/MaxKostov/api-gateway/pull/14) | `cbe6b75` | 3.1.0 |
| Service Discovery | [#8](https://github.com/MaxKostov/service-discovery/pull/8) | `4073f0c` | 3.4.0 |
| Guild | [#7](https://github.com/MaxKostov/guild-service/pull/7) | `c196b68` | 3.1.0 |
| Package Registry | [#6](https://github.com/MaxKostov/package-registry-service/pull/6) | `85ff960` | 3.1.0 |

Broker release [PR #2](https://github.com/MaxKostov/message-broker/pull/2) is
ready against main; both required reviews were requested from Dmitrii and Denis. The merged broker
tree matches the tested feature tree exactly. After reviews, squash the four
remaining service feature PRs into develop, open their release PRs to main, and
wait for successful versioned image publication. Refresh the CPR
gitlinks to the resulting released commits (squash SHAs will differ from this
table). Verify the pinned tags exist, then ready and squash the CPR integration
PR into develop. Do not merge the current draft against unpublished image tags.
The user's original checkout and its uncommitted README edits were preserved.

## Where to build the next steps

Paths below are relative to the `message-broker/` submodule, under
`src/main/java/com/tamagotchigo/broker/`:

| Responsibility | File |
| --- | --- |
| Queue names and bounded synchronous admission | `queues/RequestQueues.java` |
| Envelope and `/q/{service}/api/...` entry points | `web/QueueController.java` |
| One-instance HTTP delivery and response forwarding | `delivery/DeliveryService.java` |
| Service credentials / gateway trust | `auth/BrokerAuthentication.java` |
| Registry snapshot and 5-second refresh | `discovery/InstanceCache.java` |
| Unchanged round-robin counters | `discovery/RoundRobinBalancer.java` |
| Unchanged Lab 3 state machine | `resilience/CircuitBreaker.java` |
| Registry eviction/removal and Discord notices | `resilience/FailedInstanceRemover.java` |
| Metrics and Prometheus HTTP SD adapter | `metrics/BrokerMetrics.java`, `MonitoringController.java` |

Step 1 queues are synchronous dispatch lanes, not persistent storage. There is
no automatic retry of a sent message, delivery acknowledgement, rerouting after
an outcome, or dead-letter store. HTTP client redirects are not followed.
Body/header/status forwarding and a stable `X-Upstream-Instance` preserve
session ownership. Business services retain domain authorization/idempotency.

Gateway mode `MESSAGE_BROKER_URL=http://message-broker:8070` skips gateway HTTP
instance selection and breaker filters. Gateway retains edge JWT checks,
12-second outer deadline, concurrency limit and realtime negotiation. The broker
keeps the old 10-second timeout / 35-second failure window. Services still use
their existing 8-second deadline and peer breakers. Gateway registry state now
serves realtime negotiation; stateful realtime owners remain explicit.

All 18 peer base URLs use `/q/{target-compose-name}`. `API_GATEWAY_URL` remains
Guild's realtime identity endpoint; `SERVICE_DISCOVERY_URL` stays direct.
Anonymous public peer reads (notably Tamagotchi types) are preserved. Other
peer requests require service JWTs and receive the same trusted identity headers
as before. Broker overload/no-healthy-instance errors are 503 with
`{ "error": "..." }`, `X-Broker-Error: true`, and `Retry-After: 1`.

## Metrics for subsequent steps

Common: `tamagotchi_http_requests_total{service,method,status}`,
`tamagotchi_http_request_duration_seconds` histogram,
`tamagotchi_in_flight{service}`, `tamagotchi_breaker_trips_total{service,target}`.

Broker: `broker_messages_total{queue,status}`,
`broker_delivery_duration_seconds` histogram, `broker_in_flight{queue}`,
`broker_breaker_trips_total{target,instance}`.

Reserved dashboard contracts: **`broker_queue_depth{queue}`**,
**`broker_reroutes_total{queue}`**, **`broker_dead_letters_total{queue}`**.
Their panels exist and remain empty until those features are implemented.

Prometheus uses the broker's `/api/monitoring/targets` adapter to the same registry
snapshot. Loki receives the shared folder through Alloy; read positions persist.
Loki's shell-free image uses the `loki-ready` one-shot HTTP probe before consumers
start. Grafana provisions Prometheus, Loki, and the 12-panel dashboard.

## Verification

| Check | Actual result |
| --- | --- |
| Broker `./mvnw -B verify` | 64 tests, 94.25% line coverage |
| Gateway `./mvnw -B verify` | 111 tests, 95.15% line coverage |
| Discovery `./mvnw -B verify` | 54 tests, 95.02% line coverage |
| Guild vet + full PostgreSQL/Redis race suite | Pass, 79.3% aggregate coverage |
| Package Registry vet + full PostgreSQL race suite | Pass, 83.2% aggregate coverage |
| Service CI test/coverage and Docker builds | All five PRs green |
| Exact local Dockerfiles | All five built; Temurin 21 for Java |
| Prometheus / Alloy / Loki config validation | Pass with the pinned images |
| Full `docker compose ... up -d --wait` | Exit 0; 25 running containers, two completed initialization jobs |
| Postman regression | 46 requests, 100 assertions, zero failures |
| Actual nested client call | Guild POST → broker → User GET 200 → Guild 201, same request ID |
| All configured peer transport contracts | 18 edges pass; selected-instance/error-origin checks pass |
| Grafana | Dashboard exists; actual Prometheus proxy returns request rates and Loki proxy returns logs for five services |
| Registered `/metrics` | 7/19 pass; 12 owner targets return 404 |

The first cold-stack Postman attempt hit the User service's own 504 during
login; subsequent auth-dependent requests then failed. Controlled broker logs
show the upstream 504 was forwarded unchanged. After startup settled, login took
1.4 seconds and the complete 100-assertion run passed. Docker had 3.8 GiB RAM
for the whole stack; the README recommends 8 GiB. No failed write was replayed.

The Postman run creates uniquely named test users and a guild. Existing databases
and Redis data were retained. Tokens stayed in memory; stored result summaries
contain statuses, assertions and timings without credentials.

## Open work

1. Obtain required service PR/release reviews. Broker DockerHub credentials are
   now configured; release PR #2 is ready. Publish the five target versions and
   refresh gitlinks to release SHAs.
2. Other owners must add `/metrics` and shared log files for their six services:
   [readiness table](../monitoring/metrics-readiness.md),
   [posted owner follow-up](https://github.com/dmitrycvs/pad-tamagotchi-go/issues/55#issuecomment-6743394529).
3. Those six source repos are inaccessible to MaxKostov (GitHub 404, no pending
   invitations). Grant intended access for a full source-level client audit.
4. The smoke/transport checks do not cover complete battle settlement, raid
   reward distribution, proximity notifications, or real Firebase delivery.
   Those deeper business flows remain additional integration work.
5. Implement Topics and gRPC in their agreed later steps; preserve the metric
   names above. The Lab 4 PDF was absent from this checkout; implementation scope
   follows the supplied task text.

## Current local stack

The tested integration worktree is `/private/tmp/pad-lab4-broker` on
`feat/shared/AddMessageBroker`. Local-only source images use `*:lab4-local` tags;
they are intentionally not tagged as published releases. ARM images for the
four existing Java/Go services run natively locally; CI verifies amd64 release
builds. Broker's local image is amd64. No published version was overwritten.

The original `.env` is read in place. The ignored, mode-0600 `.env.local` contains
a newly generated Grafana password plus nonsecret test overrides; existing
credentials were not duplicated. `docker-compose.local.yml` is ignored and selects
the local images. Reproduce the verified stack with:

```sh
export CPR_ENV_FILE=/absolute/path/to/your/existing/.env
cd /private/tmp/pad-lab4-broker
docker compose \
  --env-file "$CPR_ENV_FILE" \
  --env-file .env.local \
  -f docker-compose.yml -f docker-compose.local.yml up -d --wait
```

Open Grafana at `http://localhost:3000/d/tamagotchi-lab4`; username `admin`,
password in `.env.local`. Prometheus targets: `http://localhost:9090/targets`.
Published-image startup will use the regular `.env` after the releases exist.
