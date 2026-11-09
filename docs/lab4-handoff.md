# Lab 4 step 1 handoff for Dmitrii

Checked 2026-11-09. All five implementation PRs and all five image releases
are complete. The CPR records the released commits and image versions; final
integration PR #56 still needs its manual develop merge. Broker history repair
#3 remains a separate main review/merge before the next Topics release. Other
owners' missing instrumentation remains tracked in issue 55.

Dmitrii can branch from `message-broker`'s `develop` using
`feat/message-broker/AddTopics`. Preserve the existing request/reply contract
and reserved metric names while adding `domain.event` topics. The integration
branch `feat/shared/AddMessageBroker` has the full published-image stack until
CPR #56 merges.

## Image and contract

Published image: **`maxkostov/message-broker:1.0.0`** (also `latest`).
Release [workflow 42645173475](https://github.com/MaxKostov/message-broker/actions/runs/42645173475)
succeeded; Git tag `v1.0.0` points to main commit `8f63750`.
Version and latest resolve to manifest digest
`sha256:877db821a784d77489927be894711c8625549c85dd1a1e09757bde65eaaaddf0`;
image labels confirm version 1.0.0 and the same full source revision.
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
Per the user's preference, merges remain manual (`allow_auto_merge=false`);
merged feature branches are deleted by default (`delete_branch_on_merge=true`).
Main allows merge commits only; feature squash merges remain available on develop.
Protected main/develop branches retain their deletion restriction.

## Released sources and integration

| Service | Image | Released commit | Main PR |
| --- | --- | --- | --- |
| message-broker | `maxkostov/message-broker:1.0.0` | `8f63750` | [#2](https://github.com/MaxKostov/message-broker/pull/2) |
| api-gateway | `dmitrycvs/api-gateway:3.1.0` | `e465371` | [#16](https://github.com/MaxKostov/api-gateway/pull/16) |
| service-discovery | `maxkostov/service-discovery:3.4.0` | `c4ed878` | [#10](https://github.com/MaxKostov/service-discovery/pull/10) |
| guild-service | `maxkostov/guild-service:3.1.0` | `79e4ce9` | [#8](https://github.com/MaxKostov/guild-service/pull/8) |
| package-registry-service | `maxkostov/package-registry-service:3.1.0` | `b536a4e` | [#7](https://github.com/MaxKostov/package-registry-service/pull/7) |

All versioned images were pulled and their OCI revision/version labels checked
against the Git tags and CPR gitlinks. Immutable digests are recorded in
[lab4-releases.json](lab4-releases.json). The merged runtime trees match the
implementations previously tested locally and in CI.

Main releases use **Create a merge commit**; feature PRs squash into develop.
Gateway #16 and Discovery #10 resolved their old squash-history conflicts.
Guild develop also contains its main release through a subsequent history sync.
Keep main/develop; delete merged feature branches.

Broker [history repair #3](https://github.com/MaxKostov/message-broker/pull/3)
is still open. It joins the already-released 1.0.0 histories before the next
Topics release; runtime/build inputs and the published image/tag remain
unchanged. Its documentation/history-only update skips image publication.

The remaining integration action is to review/merge
[CPR #56](https://github.com/dmitrycvs/pad-tamagotchi-go/pull/56) into develop.
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
| Exact Dockerfiles / release | All five published images, source labels, Git tags and CPR release pointers verified |
| Prometheus / Alloy / Loki config validation | Pass with the pinned images |
| Full `docker compose ... up -d --wait` | Exit 0; 25 running containers, two completed initialization jobs |
| Postman regression | 46 requests, 100 assertions, zero failures against all five published releases |
| Actual nested client call | Guild POST → broker → User GET 200 → Guild 201, same request ID |
| All configured peer transport contracts | 18 edges pass; selected-instance/error-origin checks pass |
| Grafana | Dashboard exists; actual Prometheus proxy returns request rates and Loki proxy returns logs for five services |
| Registered `/metrics` | 7/19 pass; 12 owner targets return 404 |

On the 4 GiB Docker VM, the first all-amd64 rollout exhausted free memory and
swap; the gateway's shorter image health window expired before its slow
emulated startup completed, and several requests timed out. Compose now gives
the three Java services a 150-second startup grace and explicit heap/processor
budgets. Full published-image startup and the complete 100-assertion regression
then passed without changing business deadlines or replica counts. The README
still recommends 8 GiB for the full stack. No failed write was replayed.

The Postman run creates uniquely named test users and a guild. Existing databases
and Redis data were retained. Tokens stayed in memory; stored result summaries
contain statuses, assertions and timings without credentials.

## Open work

1. Review/merge CPR #56 into develop. All five service images and release
   pointers are now available. Broker history repair #3 still needs its manual
   main review/merge before the next Topics release.
2. Other owners must add `/metrics` and shared log files for their six services:
   [readiness table](../monitoring/metrics-readiness.md),
   [posted owner follow-up](https://github.com/dmitrycvs/pad-tamagotchi-go/issues/55#issuecomment-6743394529).
3. The six teammate source repos were inaccessible to MaxKostov during the
   source audit (GitHub 404, no pending invitations). Their owners must grant
   intended access for a full source-level client audit.
4. Smoke/transport checks do not cover complete battle settlement, raid
   rewards, proximity notifications or real Firebase delivery. Those deeper
   business-flow scenarios remain additional integration work.
5. Topics (Dmitrii) and gRPC (Denis) are the agreed later steps. Preserve the
   contract and metric names above. The Lab 4 PDF was absent from this checkout;
   implementation scope follows the supplied task text.

## Current local stack

The integration worktree is `/private/tmp/pad-lab4-broker` on
`feat/shared/AddMessageBroker`. The stack now uses only the published images in
`docker-compose.yml`, all on linux/amd64; no local-build image override is used.
Existing databases, Redis, monitoring data and shared log files are retained.
Compose bounds each Java heap to 256 MiB and reports two available processors per JVM by
default, with per-component JAVA_OPTS overrides. Java health checks have a
150-second startup grace for AMD64 emulation. Business request timeouts and
replica counts retain their documented values.

The original `.env` is read in place. The ignored mode-0600 `.env.local` holds
its generated Grafana password and nonsecret image/realtime overrides; existing
credentials were not duplicated. For this verified local environment:

```sh
export CPR_ENV_FILE=/absolute/path/to/your/existing/.env
cd /private/tmp/pad-lab4-broker
docker compose \
  --env-file "$CPR_ENV_FILE" \
  --env-file .env.local \
  -f docker-compose.yml up -d --wait
```

For a fresh checkout after integration merge, configure `.env` using the updated
`.env.example` (including the image tags and Grafana password), then use normal
`docker compose up -d --wait`.

Grafana: `http://localhost:3000/d/tamagotchi-lab4`, username `admin`, password in
`.env.local`. Prometheus: `http://localhost:9090/targets`.
