# Metrics readiness — 2026-11-11

Check against the running `tamagotchi-go` Compose network with every Lab 4
release image (Message Broker 1.3.1, API Gateway 3.3.0, Service Discovery 3.6.0,
Tamagotchi and Notification 4.1.0, User Management and Battle 4.0.0, Map and
Monster Raid 2.3.0, Guild and Package Registry 3.2.0).
`scripts/check-metrics.py` checks every registered instance plus Service
Discovery itself. **19/19 targets pass.** Prometheus also scrapes itself, so
its targets view shows 20 targets, all up.

| Service | Instances checked | GET /metrics |
| --- | --- | --- |
| message-broker | 1 | 200, valid Prometheus |
| api-gateway | 1 | 200, valid Prometheus |
| service-discovery | 1 | 200, valid Prometheus |
| guild-service | 2 | Both 200, valid Prometheus |
| package-registry-service | 2 | Both 200, valid Prometheus |
| tamagotchi-service | 2 | Both 200, valid Prometheus |
| notification-service | 2 | Both 200, valid Prometheus |
| map-service | 2 | Both 200, valid Prometheus |
| monster-raid-service | 2 | Both 200, valid Prometheus |
| user-management-service | 2 | Both 200, valid Prometheus |
| battle-service | 2 | Both 200, valid Prometheus |

Every business service exports the shared `tamagotchi_in_flight` gauge from
startup. `tamagotchi_http_requests_total` and the duration histogram appear
after a service's first business request, since health checks and scrapes are
not counted.

Logs: Loki's `service` label lists all 11 services (8 business services, gateway,
broker, Service Discovery), shipped by Alloy from the shared
`/var/log/tamagotchi` volume. Grafana's provisioned `tamagotchi-lab4` dashboard
has 12 panels: requests, 5xx errors and p95 latency per service, in-flight
requests, breaker trips, targets up, broker message rate and in-flight
delivery, queue depth, reroutes, dead letters, and the shared service logs.

Container startup readiness and metrics readiness are different checks:
`docker compose up -d --wait` waits for health, and `check-metrics.py` exits
nonzero if any registered instance is missing or serves malformed metrics.
