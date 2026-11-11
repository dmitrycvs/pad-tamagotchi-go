# Postman: start here

Import [lab2-smoke.postman_collection.json](./lab2-smoke.postman_collection.json).
Select **No Environment**, then send requests **01–18 in order**, one by one, or
run the whole collection with Postman's Collection Runner. Its scripts only
create a unique test user and copy the returned JWT and IDs into collection
variables. You can open any request, change it, and press **Send** manually.

Start the published stack first:

```sh
docker compose pull
docker compose up -d --no-build --pull never
```

The smoke check uses `http://localhost:8080` and requires no local secrets. It
creates a test user and a guild. `404` for the nonexistent Package Registry and
Battle IDs, and `401` for the last request without a JWT, are **expected**.
A successful run has 18 requests and 30 passing assertions. It checks gateway
routing and authentication, but not a complete battle, raid participation, or
Firebase push delivery.

For individual endpoints, the ten detailed collections are in
[services/](./services): one per business service, the API Gateway, and
**Service Discovery**. Import only the one you want to inspect. Their REST
requests use the gateway at port 8080, and the Service Discovery collection uses
port 8761.

Every collection starts with **Health (every replica)**. Since the Lab 3 scaling,
replicas have no fixed host ports. This request shows the latest `/health`
result of each replica, which Service Discovery polls every 15 s. Public
requests, such as these health checks, the gateway's `/health` and the whole
Service Discovery collection, need no environment.

Requests that send a JWT generate it from the local
`tamagotchi.local.postman_environment.json`, which must be selected in Postman.
That ignored file must contain `jwt_secret` and `service_jwt_secret` matching
`.env`. Some requests need package, monster, Tamagotchi, guild, or battle records
created first.

Do not commit the local environment or export collections after running them
with populated JWT variables.

## Lab 3: scaling check

Import [lab3-scaling.postman_collection.json](./lab3-scaling.postman_collection.json)
and run the **whole collection with the Collection Runner** (or
`npx newman run postman/lab3-scaling.postman_collection.json`). Some requests
repeat themselves, so sending them one by one does not run their checks. It
needs no environment or secrets: it signs up its own test user, and every run
uses fresh ids.

Start the stack and give the gateway the per-instance WebSocket URLs first:

```sh
docker compose up -d --wait
export WS_PUBLIC_INSTANCE_URLS="$(python3 scripts/realtime-instance-urls.py)"
docker compose up -d api-gateway
```

| Folder | Grade point | What it proves |
| --- | --- | --- |
| 1. Status endpoints and registration | Status endpoint, register on startup | Service Discovery and the gateway answer `/health` in the shared shape. Every business service has at least 2 registered replicas with distinct ids, and the health poller reports each one healthy. |
| 2. Registry API | Service Discovery with a register endpoint | Register (201), re-register (200), heartbeat, lookup, deregister (204), plus the 400 and 404 errors. |
| 3. Gateway routes every service through Service Discovery | Hook services up to Discovery and Gateway | One call to each of the 8 services. Its `X-Upstream-Instance` header must name one of that service's registered instances. |
| 4. Round-robin load balancing | Round-robin load balancer | Repeated calls rotate through every replica, never the same one twice in a row. |
| 5. Realtime connections | Instance-aware business logic | WebSocket negotiation returns a registered guild-service `instance_id`. |
| 6. Circuit breaker and expiry | Circuit breaker removes a service; dynamic removal | A fake instance with an unresolvable host is added to tamagotchi-service. It fails exactly 3 times (503), its breaker opens, the real replicas keep serving, and the gateway removes it from Service Discovery before the 30 s heartbeat timeout. An instance that never sends heartbeats is dropped after 30 s. |

A successful run has 45 requests (28 plus repeats), 91 passing assertions, and
takes about 40 s. Not checked here: Discord alerts (they need
`DISCORD_WEBHOOK_URL`) and the services' own circuit breakers. For those, stop
a dependency (for example `docker compose stop user-management-service`), call
an endpoint that uses it 3 times, and
`docker compose logs | grep "Circuit breaker opened"`.


## Lab 4: final check

Import [lab4-final.postman_collection.json](./lab4-final.postman_collection.json),
select the local Tamagotchi environment (`jwt_secret` and `service_jwt_secret`
from `.env`) and run the **whole collection** with the Collection Runner, or:

```sh
npx newman run postman/lab4-final.postman_collection.json -e postman/tamagotchi.local.postman_environment.json
```

It signs up its own test user, and every run uses fresh ids. A successful run
has 23 requests (37 with the ones its scripts send) and 60 passing assertions,
and takes about 5 s.

| Folder | Grade | What it proves |
| --- | --- | --- |
| 1. Gateway to broker | 2, 5, 6 | Gateway requests go through the broker's queue to a registered replica (`X-Upstream-Instance`). All 8 services run 2 replicas, each registered with `grpc_port` 9000; Notification registers its six topics. |
| 2. Internal routes are not public | 8 | Service-to-service routes answer 404 at the gateway, with a user or a service token, and are never relayed. |
| 3. Log download | 4 | An admin downloads a zip of the last hour's logs; a non-admin gets 403. |
| 4. Topics | 6, 7 | `GET /api/topics` lists every topic with its subscribers. An event published to `tamagotchi.captured` reaches Notification and shows up in the user's notifications. |
| 5. Durable queues and dead letters | 9 | An event Notification rejects is stored, dead-lettered, listed from the durable store and retried. |
| 6. Load-based routing and failover | 10 | Repeated requests reach both replicas; the broker exports queue depth, reroutes, dead letters and chosen-instance load. |
| 7. Monitoring | 10 | Every Prometheus target is up, every business service exports the shared `tamagotchi_*` metrics, and Grafana is healthy. |

Failover after a breaker trips needs a stopped replica, so it is a manual step:
`docker kill` one Battle replica, read a battle a few times through the gateway
(every call returns 200), and `docker compose logs message-broker | grep Rerouting`.

## Lab 4 broker regression

Import [lab3-broker.postman_collection.json](./lab3-broker.postman_collection.json).
It retains the 18-request Lab 3 baseline, adds broker health, metrics,
authentication/error/envelope checks and all 18 configured peer transport edges.
For the final edge folder, set `service_jwt_secret` in a local secret Postman
environment. Generated service tokens exist only at runtime. Never export or
commit populated environments or collections.

The transport folder verifies broker selection and target replies; it does not
execute every source service's HTTP client. Full battle/raid/proximity and
Firebase delivery remain separate integration scenarios. See [issue #55](https://github.com/dmitrycvs/pad-tamagotchi-go/issues/55)
for actual results and owner blockers.
