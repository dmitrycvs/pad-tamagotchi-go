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

For individual endpoints, the nine detailed collections are in
[services/](./services). Import only the service you want to inspect. Their REST
requests use the gateway at port 8080; direct ports are used for service health
checks and the Guild WebSocket. Most detailed collections generate test JWTs and
need the local `tamagotchi.local.postman_environment.json` selected in Postman.
That ignored file must contain `jwt_secret` and `service_jwt_secret` matching
`.env`. Some requests need package, monster, Tamagotchi, guild, or battle records
created first.

Do not commit the local environment or export collections after running them
with populated JWT variables.
