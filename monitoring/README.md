# Lab 4 monitoring

Prometheus discovers instances from Service Discovery through the broker's
`GET /api/monitoring/targets` adapter. It converts the broker's existing
5-second registry snapshot to Prometheus HTTP SD, so replicas are separate
scrape targets and removed instances disappear on refresh. The registry itself
is included using its configured URL. Every service is scraped at `/metrics`.
A failed target remains visible as `up = 0`; missing instrumentation is not
silently replaced by fabricated metrics.

Grafana: `http://localhost:3000`, credentials from `GRAFANA_ADMIN_USER` and
`GRAFANA_ADMIN_PASSWORD`. The password must be set in `.env`. Prometheus:
`http://localhost:9090/targets`. Both bind to localhost. Loki and Alloy stay
internal to Compose. Loki uses a shell-free image; the `loki-ready` one-shot BusyBox job polls its
real HTTP `/ready` endpoint before Alloy and Grafana start.
All four images are pinned to verified official release
tags; their data uses named volumes.

Grafana provisions the **Tamagotchi Go / Lab 4** dashboard, Prometheus datasource
and Loki datasource on startup. Panels show requests/5xx per service, p95
latency, in-flight load, breaker trips, and scrape readiness. Delivery panels
show broker outcomes and queue load. Queue depth, reroutes and dead-letter
panels are present for later steps and show no data until those metrics exist.

## Shared metrics

| Name | Labels |
| --- | --- |
| `tamagotchi_http_requests_total` | `service`, `method`, `status` |
| `tamagotchi_http_request_duration_seconds_bucket`, `_sum`, `_count` | `service`, `method`; histogram |
| `tamagotchi_in_flight` | `service` |
| `tamagotchi_breaker_trips_total` | `service`, `target` |
| `broker_messages_total` | `queue`, `status` |
| `broker_delivery_duration_seconds_bucket`, `_sum`, `_count` | `queue`; histogram |
| `broker_in_flight` | `queue` |
| `broker_breaker_trips_total` | `target`, `instance` |

Later-step names are fixed: **`broker_queue_depth{queue}`**,
**`broker_reroutes_total{queue}`**, **`broker_dead_letters_total{queue}`**.
Do not rename these when adding topics, rerouting or dead-letter storage.

Broker HTTP metrics include rejected/authentication-failed messages and exclude
health, discovery and scrape traffic. Go services use bounded method labels and
exclude health/scrape requests. Avoid paths, request IDs and user IDs in labels.

## Logs

The `tamagotchi-logs` named volume is mounted at `/var/log/tamagotchi`.
Broker, Guild and Package Registry write stdout and per-instance files there.
Spring's standard `LOGGING_FILE_NAME` also captures Gateway and Discovery logs
without changing their message format. Their default Compose replica count is
one; do not scale these two with a shared filename without adding an instance
suffix. Broker and Go filenames already include instance IDs.

`log-init` initializes the directory before producers start. UID/GID 1000 owns
it, and mode 1777 lets the pre-existing non-root Java images create their own
files while retaining file ownership. Log files are readable by the collector.
Alloy mounts the folder read-only, tails `.log` files, labels service from the
filename, and sends batches to Loki. Its read positions survive restart in the
`alloy-data` volume. No Docker socket or container privileges are required.
The Loki server stores incoming logs; Alloy performs filesystem tailing.

Other owners must write their own per-instance files to the same folder and
mount it in Compose when adding their observability support. Add their names to
the Alloy label rule at that point. Keep tokens, credentials, bodies and query
values out of logs. Broker files rotate at 20 MB / 7 days / 200 MB total;
Spring's default file rotation applies to Gateway and Discovery.

## Validate

```sh
docker compose config --quiet
docker compose up -d --wait
curl http://localhost:8070/health
curl http://localhost:8070/api/monitoring/targets
curl http://localhost:9090/api/v1/targets
curl http://localhost:3000/api/health
python3 scripts/check-metrics.py
```

`check-metrics.py` checks each registered instance and the registry from the
running Compose network; it exits nonzero for missing/malformed metrics. See
`metrics-readiness.md` for the last actual check and owner follow-up. Startup
readiness of the containers is separate from instrumentation readiness.

All five owned/infrastructure service releases are published. The main Compose
file uses their verified versioned image tags; no local source-image override
is required. Released Git commits and immutable image digests are recorded in
`../docs/lab4-releases.json`. `../docs/lab4-handoff.md` tracks the integration
merge, broker ancestry repair, and outstanding owner instrumentation.
