# Postman Collections

One collection per microservice, exported from Postman as **Collection v2.1**.

## Naming

```
<service-name>.postman_collection.json
```

e.g. `tamagotchi-service.postman_collection.json`

## What a collection must contain

- One request per endpoint in that service's section of the [communication contract](../README.md#communication-contract)
- A request body matching the documented payload
- A saved example response for at least the success case, and for any documented error case (401, 403, 409)

## Variables

Use collection variables rather than hardcoded hosts, so a collection runs against
either a locally built service or the composed stack:

| Variable | Local default |
|---|---|
| `base_url` | `http://localhost:<service port>` |
| `jwt_secret` | must equal `JWT_SECRET` in your `.env` |
| `service_jwt_secret` | must equal `SERVICE_JWT_SECRET` in your `.env` |

Service ports are listed in [`docker-compose.yml`](../docker-compose.yml).

## Tokens are generated automatically

Every collection has a collection-level pre-request script that signs the tokens
it needs (`jwt`, `service_jwt`, `admin_jwt`, …) before each request, as HS256 JWTs
with the claims the services verify: `sub`, `package_id`, `roles`, `exp`. Each
token's `sub` is the user id that collection puts in its URLs, so ownership checks
pass.

You need `jwt_secret` and `service_jwt_secret` to match the stack. Guild and
Package Registry exports keep these fields empty. Create a local Postman
environment with `jwt_secret` set to `JWT_SECRET` and `service_jwt_secret` set to
`SERVICE_JWT_SECRET` from your stack `.env`, then select that environment. If you
already have `tamagotchi.local.postman_environment.json`, import and select
**Tamagotchi — Local Gateway** instead. Environment values override collection
fields; local environment exports are ignored by Git. Update the environment
when stack signing secrets change. The pre-request
scripts report a configuration error if either secret is missing or too short.
Other collection defaults use `.env.example`; update their variables when using
different stack secrets.

The User Management collection is the exception for `jwt`: the **Login** request
stores the real token the service issues, so run **Register** and **Login** first.

## Do not commit

Real tokens or credentials. Generated tokens are written back into the collection
variables at run time; export from a clean copy, not after a run.

Guild and Package Registry REST collections use the gateway at `http://localhost:8080`. Clients still send bearer JWTs; the gateway validates them and supplies trusted identity headers. Guild WebSocket connects directly to port 8087, and Guild Service delegates token validation to the gateway. Set the same non-empty `GATEWAY_SHARED_SECRET` on the gateway and both services.
