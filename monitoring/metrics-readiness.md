# Metrics readiness — 2026-11-09

Actual check against the running `tamagotchi-go` Compose network, after local
source-image integration. `scripts/check-metrics.py` checks every registered
instance plus Service Discovery itself. **7/19 targets pass; 12 return 404.**
Prometheus additionally scrapes itself, so its targets view has 20 targets.

| Service | Instances checked | GET /metrics | Owner / next action |
| --- | --- | --- | --- |
| message-broker | 1 | 200, valid Prometheus | Max; PR 1, release target 1.0.0 |
| api-gateway | 1 | 200, valid Prometheus | Max / Dmitrii; PR 14, target 3.1.0 |
| service-discovery | 1 | 200, valid Prometheus | Max; PR 8, target 3.4.0 |
| guild-service | 2 | Both 200, valid Prometheus | Max; PR 7, target 3.1.0 |
| package-registry-service | 2 | Both 200, valid Prometheus | Max; PR 6, target 3.1.0 |
| tamagotchi-service | 2 | Both 404 | Dmitrii; checked image 2.2.0 |
| notification-service | 2 | Both 404 | Dmitrii; checked image 2.2.0 |
| map-service | 2 | Both 404 | Denis; checked image 2.2.0 |
| monster-raid-service | 2 | Both 404 | Denis; checked image 2.2.0 |
| user-management-service | 2 | Both 404 | Filip; checked image 3.0.0 |
| battle-service | 2 | Both 404 | Filip; checked image 3.0.0 |

Owner follow-up with shared metric/log contracts and source-access requests:
[issue 55 comment](https://github.com/dmitrycvs/pad-tamagotchi-go/issues/55#issuecomment-6743394529).
All six teammate source repositories return “Repository not found” for the
authenticated MaxKostov account, with no pending repository invitations.

Grafana's provisioned `tamagotchi-lab4` dashboard has 12 panels. Its actual
Prometheus datasource proxy returns request counters/rates for Broker, Gateway,
Discovery, Guild and Package Registry. Its Loki proxy returns log counts for
the same five service names. Shared per-instance files and Alloy tailing were
verified. Later-step queue-depth/reroute/dead-letter panels correctly have no
data until implemented; missing owner metrics remain visible as down targets.

Container startup readiness and metrics readiness are different checks:
`docker compose ... up -d --wait` passes, while `check-metrics.py` intentionally
exits nonzero until owners publish the missing endpoints. Local source images
are not published release artifacts.
