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
| `jwt` | a user token issued by the User Management Service |
| `service_jwt` | a service-to-service token |

Service ports are listed in [`docker-compose.yml`](../docker-compose.yml).

## Do not commit

Real tokens or credentials. Leave `jwt` and `service_jwt` empty in the exported
file and set them in a Postman environment that stays local.
