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
