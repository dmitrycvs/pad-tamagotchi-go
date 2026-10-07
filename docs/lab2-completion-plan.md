# Lab 2 completion plan

The assignment in `PAD_LAB_2.pdf` lists requirements through Grade 9. To aim for the highest final mark, demonstrate every listed criterion and comply with the presentation House Rules. The final mark remains the instructor's decision.

| Assignment criterion | Evidence needed before presentation | Responsibility / current state |
| --- | --- | --- |
| Grade 1: all services under Docker Compose | Start the full stack on one machine, exercise one real cross-service flow, and retain the command output | Team. Compose syntax passes; a full-stack run remains to be demonstrated. |
| Grade 2: private gateway repository and GitHub workflow | Private repo, CPR submodule, README, collaborators (including professor), protected branches, review rules and PR template | Gateway owner and repository administrators. CPR contains the submodule; settings need GitHub verification. |
| Grade 3: architecture diagram | Diagram includes the gateway and direct WebSocket connections | Team. Diagram is in the CPR README. |
| Grade 4: gateway in the banned language, Compose and DockerHub | Java gateway builds and its Lab 2 image exists on DockerHub | Gateway owner. Java gateway and Compose entry exist; published image needs verification. |
| Grade 5: all REST traffic via gateway | Client and service-to-service smoke flows use port 8080; no required REST call bypasses the gateway | Team. Guild and Registry URLs point to the gateway; whole-stack traffic still needs verification. |
| Grade 6: WebSocket/SSE protocol and negotiation | Gateway returns a direct WebSocket URL and a client exchanges a frame with each live service | Team. Guild has a direct WebSocket and gateway identity delegation; other live services belong to their owners. |
| Grade 7: timeout and concurrent task limit on every service and gateway | Each service returns 504 for timed-out work and 503 with `Retry-After` on overload; long-lived sockets are exempt | Each owner. Guild and Registry implementation and tests are in their feature branches; remaining services need owner verification. |
| Grade 8: automated DockerHub release from main | Each repository's CI passes, release workflow publishes `2.0.0` and `latest`, and version is traceable to a Git tag | Each owner. Guild and Registry workflows are prepared; DockerHub secrets, PR merges and actual releases remain. |
| Grade 9: authorization at gateway | Gateway validates JWT and removes `Authorization`; downstream services receive trusted identity and preserve domain permissions | Team. Guild and Registry use trusted gateway headers and reject direct REST calls. Verify the full stack. |

## Verified for Guild and Registry on 2026-10-07

- `go vet ./...` and `go test -race -count=1 -coverpkg=./...` passed with PostgreSQL: Guild 71.8% coverage, Registry 77.1% coverage.
- `docker compose build guild-service package-registry-service` produced local `2.0.0` images. Gateway, PostgreSQL and both services started healthy using `docker-compose.local-smoke.yml`.
- Both service smoke scripts passed through the gateway, including Guild WebSocket chat, Registry service-token reads, domain permissions, and idempotent writes. Direct REST calls with forged identity headers and no shared secret returned 401.
- Both service repositories now have a remote `develop` branch created from `main`; feature branches and the CPR integration branch are pushed. PRs, branch protection and DockerHub secrets still need GitHub account access.
- The smoke override enables mocks only for unavailable teammate dependencies. It does not prove that all team services run together or that DockerHub images and GitHub branch protection are configured.

For the isolated local check, start `postgres`, `api-gateway`, `guild-service`, and `package-registry-service` with:

```sh
docker compose -f docker-compose.yml -f docker-compose.local-smoke.yml up -d --build postgres api-gateway guild-service package-registry-service
```

Export `JWT_SECRET` and `SERVICE_JWT_SECRET` from your local `.env`, then run each service's `scripts/smoke.sh` from its own directory. Never commit `.env` or print the secrets in logs.

## Guild and Registry execution order

1. Complete and review request limits, context-aware database calls, health checks, and their tests in each service repository.
2. Run `go vet ./...` and `go test -race -count=1 -coverpkg=./... -coverprofile=coverage.out ./...` with `TEST_DATABASE_URL` against PostgreSQL; require at least 70% coverage.
3. Build both Docker images and verify `/health`, 503, 504, authorized REST, rejected direct REST, and Guild WebSocket chat.
4. Commit and push service feature branches, then update their CPR submodule pointers and Compose configuration on the shared feature branch.
5. Configure `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` in both service repositories, protect the new remote `develop` branches, then open PRs according to `RULES.md`.
6. After review and merges to `develop`, merge the release into `main`. Verify both `2.0.0` and `latest` image tags and Git tags, then run a full-stack demonstration with the team.
