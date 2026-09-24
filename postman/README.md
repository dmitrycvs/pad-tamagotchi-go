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

You only need `jwt_secret` and `service_jwt_secret` to match the stack. They
default to the values in `.env.example`, so a stack started from an unmodified
`.env.example` works with no setup. If you changed the secrets in `.env`, change
these two variables to match.

The User Management collection is the exception for `jwt`: the **Login** request
stores the real token the service issues, so run **Register** and **Login** first.

## Do not commit

Real tokens or credentials. Generated tokens are written back into the collection
variables at run time; export from a clean copy, not after a run.
