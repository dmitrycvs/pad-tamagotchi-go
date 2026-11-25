# Lab 5, Grade 8: two-phase commit end to end

Run on 2026-11-25 against Compose (`docker-compose.yml` of this repository) with `postgres-0..2`, `postgres-failover`,
`service-discovery`, `message-broker` 1.4.0, `tamagotchi-service` 4.1.0 and User Management / Battle built from the
commits released as **4.1.0** (tag `lab5-2pc`). Script: three scenarios, every request and answer below.

1. **Commit**: bob forfeits, alice wins. Battle prepares its part, User Management votes yes, the decision is
   `commit`, both commit; alice +120 and the follow-ups run (bob −60).
2. **Abort**: the winner is unknown to User Management, which votes no (404). The decision is `abort`; neither
   database changes (the battle stays `settling` with `settlement_status: aborted`, no currency row).
3. **Failover**: a transaction prepared at User Management (`PREPARE TRANSACTION`) is still prepared on the promoted
   standby after `docker compose stop` of the primary, and `COMMIT PREPARED` there applies it (alice +7). The commit
   request was retried until User Management had reconnected to the new primary; its first success answered
   `committed` (see the log), the request shown is the idempotent repeat.

Service JWTs are signed with the stack's `SERVICE_JWT_SECRET`; Battle is called with the gateway's identity headers.

## Requests and answers

```text
current primary: postgres-1

===== Setup: two players; the loser gets 500 so the -60 follow-up can apply =====
> POST {broker}/q/user-management-service/api/users/register {"username": "aliceb137e2", "email": "aliceb137e2@e2e.dev", "password": "Secret123!", "package_id": "pkg-e2e"}
< 201 {"user_id":"7920b173-f680-4875-8c5f-e4113c141040","username":"aliceb137e2","packages":["pkg-e2e"],"global_currency":0}
> POST {broker}/q/user-management-service/api/users/register {"username": "bobb137e2", "email": "bobb137e2@e2e.dev", "password": "Secret123!", "package_id": "pkg-e2e"}
< 201 {"user_id":"0dc7ace1-7fed-4d8f-a0ed-92fab4cea839","username":"bobb137e2","packages":["pkg-e2e"],"global_currency":0}
> POST {broker}/q/user-management-service/api/users/0dc7ace1-7fed-4d8f-a0ed-92fab4cea839/currency {"event_id": "e2e-seed-b137e2", "currency": "global", "amount": 500, "reason": "e2e_seed"}
< 200 {"user_id":"0dc7ace1-7fed-4d8f-a0ed-92fab4cea839","currency":"global","balance":500}

===== 1. COMMIT: bob forfeits, alice wins; both databases commit =====
> POST {battle}/api/battles {"challenger_id": "7920b173-f680-4875-8c5f-e4113c141040", "opponent_id": "0dc7ace1-7fed-4d8f-a0ed-92fab4cea839", "challenger_lineup": {"primary_id": "d252f7ac-3c06-4d3e-a24f-540f9eb90d42", "secondary_id": "22ebfcb4-0bf1-4497-b4fc-4ea9f6b2d035", "boosts": []}}
< 201 {"battle_id":"7e208add-3c57-4f49-bc28-60baaac2dc5c","status":"awaiting_opponent","created_at":"2026-11-25T14:35:55.0328307Z"}
> POST {battle}/api/battles/7e208add-3c57-4f49-bc28-60baaac2dc5c/accept {"primary_id": "83f7954a-3a3c-4fbf-b5d6-b4a99c885f3c", "secondary_id": "692663f4-9260-41b9-ab6b-00a635a65459", "boosts": []}
< 200 {"battle_id":"7e208add-3c57-4f49-bc28-60baaac2dc5c","status":"in_progress","turn":"7920b173-f680-4875-8c5f-e4113c141040","state":{"challenger_hp":120,"opponent_hp":120}}
> POST {battle}/api/battles/7e208add-3c57-4f49-bc28-60baaac2dc5c/forfeit
< 200 {"battle_id":"7e208add-3c57-4f49-bc28-60baaac2dc5c","winner_id":"7920b173-f680-4875-8c5f-e4113c141040","loser_id":"0dc7ace1-7fed-4d8f-a0ed-92fab4cea839","rewards":{"winner":{"global_currency":120,"xp":{"primary":60,"secondary":40},"captured_tamagotchi_id":"83f7954a-3a3c-4fbf-b5d6-b4a99c885f3c"},"loser":{"global_currency":-60,"xp":{"primary":24,"secondary":16}}},"settlement_status":"committed","finished_at":"2026-11-25T14:35:56.180336Z"}
alice balance 0 -> 120 (expected +120); bob balance -> 440 (500 - 60)
user_management IdempotencyRecords: battle:7e208add-3c57-4f49-bc28-60baaac2dc5c:winner|{"user_id":"7920b173-f680-4875-8c5f-e4113c141040","currency":"global","balance":120}
battle:7e208add-3c57-4f49-bc28-60baaac2dc5c:loser|{"user_id":"0dc7ace1-7fed-4d8f-a0ed-92fab4cea839","currency":"global","balance":440}

===== 2. ABORT: the winner is unknown to User Management (it votes no 404); neither database changes =====
> POST {battle}/api/battles {"challenger_id": "1fc750fa-fd59-4e57-a107-7c39dddb4121", "opponent_id": "0dc7ace1-7fed-4d8f-a0ed-92fab4cea839", "challenger_lineup": {"primary_id": "249f448c-7d44-4356-9f1c-208b9734df0d", "secondary_id": "3f9176cc-35bb-4ce8-b643-adf45b2551e4", "boosts": []}}
< 201 {"battle_id":"7c0c174e-04d2-47c6-90a9-6a26543e813e","status":"awaiting_opponent","created_at":"2026-11-25T14:35:58.2738885Z"}
> POST {battle}/api/battles/7c0c174e-04d2-47c6-90a9-6a26543e813e/accept {"primary_id": "0dddf82f-de27-48e2-9610-ffb58fd0ba0f", "secondary_id": "d1cec11a-5c62-44ba-9ca3-06f9b1a57146", "boosts": []}
< 200 {"battle_id":"7c0c174e-04d2-47c6-90a9-6a26543e813e","status":"in_progress","turn":"1fc750fa-fd59-4e57-a107-7c39dddb4121","state":{"challenger_hp":120,"opponent_hp":120}}
> POST {battle}/api/battles/7c0c174e-04d2-47c6-90a9-6a26543e813e/forfeit
< 409 {"error":"The battle could not be settled.","settlement_status":"aborted"}
> GET {battle}/api/battles/7c0c174e-04d2-47c6-90a9-6a26543e813e
< 200 {"battle_id":"7c0c174e-04d2-47c6-90a9-6a26543e813e","status":"settling","settlement_status":"aborted","turn":null,"turn_number":1,"participants":[{"user_id":"1fc750fa-fd59-4e57-a107-7c39dddb4121","primary":{"tamagotchi_id":"249f448c-7d44-4356-9f1c-208b9734df0d","type":"flame","level":1,"hp":120},"secondary":{"tamagotchi_id":"3f9176cc-35bb-4ce8-b643-adf45b2551e4","type":"flame","level":1}},{"user_id":"0dc7ace1-7fed-4d8f-a0ed-92fab4cea839","primary":{"tamagotchi_id":"0dddf82f-de27-48e2-9610-ffb58fd0ba0f","type":"flame","level":1,"hp":120},"secondary":{"tamagotchi_id":"d1cec11a-5c62-44ba-9ca3-06f
bob balance 440 -> 440 (unchanged); battle status=settling settlement_status=aborted
user_management rows for the aborted battle: 0

===== 3. FAILOVER: a prepared transaction at User Management survives the loss of the primary =====
> POST {broker}/q/user-management-service/api/tx/e2e-failover-b137e2/prepare {"user_id": "7920b173-f680-4875-8c5f-e4113c141040", "currency": "global", "amount": 7, "event_id": "e2e-failover-b137e2", "reason": "e2e"}
< 200 {"tx_id":"e2e-failover-b137e2","participant":"user-management-service","phase":"prepare","vote":"yes","outcome":"prepared","balance":127,"error":null}
prepared on postgres-1: e2e-failover-b137e2:user-management-service
$ docker compose stop postgres-1
new primary: postgres-0
prepared on postgres-0: e2e-failover-b137e2:user-management-service
> POST {broker}/q/user-management-service/api/tx/e2e-failover-b137e2/commit
< 200 {"tx_id":"e2e-failover-b137e2","participant":"user-management-service","phase":"commit","vote":null,"outcome":"already_committed","balance":null,"error":null}
alice balance 120 -> 127 (expected +7, committed on the new primary)
prepared on postgres-0 after commit: 0
{"commit_battle": "7e208add-3c57-4f49-bc28-60baaac2dc5c", "abort_battle": "7c0c174e-04d2-47c6-90a9-6a26543e813e", "failover_tx": "e2e-failover-b137e2", "new_primary": "postgres-0"}
```

## Battle Service log (coordinator)

```text
2026-11-25T14:35:56.088Z info -> POST /api/battles/7e208add-3c57-4f49-bc28-60baaac2dc5c/forfeit client=::ffff:172.19.0.1
2026-11-25T14:35:56.163Z info Battle forfeited battle_id=7e208add-3c57-4f49-bc28-60baaac2dc5c forfeiting_user_id=0dc7ace1-7fed-4d8f-a0ed-92fab4cea839 winner_id=7920b173-f680-4875-8c5f-e4113c141040
2026-11-25T14:35:56.174Z info 2PC started tx_id=settle-7e208add-3c57-4f49-bc28-60baaac2dc5c battle_id=7e208add-3c57-4f49-bc28-60baaac2dc5c participants=[battle-service, user-management-service] winner_id=7920b173-f680-4875-8c5f-e4113c141040 reward=120
2026-11-25T14:35:56.191Z info 2PC phase=prepare tx_id=settle-7e208add-3c57-4f49-bc28-60baaac2dc5c participant=battle-service vote=yes outcome=prepared duration_ms=14
2026-11-25T14:35:56.286Z info 2PC phase=prepare tx_id=settle-7e208add-3c57-4f49-bc28-60baaac2dc5c participant=user-management-service vote=yes outcome=prepared duration_ms=92
2026-11-25T14:35:56.293Z info 2PC decision tx_id=settle-7e208add-3c57-4f49-bc28-60baaac2dc5c decision=commit votes=battle-service:yes,user-management-service:yes
2026-11-25T14:35:56.298Z info 2PC phase=commit tx_id=settle-7e208add-3c57-4f49-bc28-60baaac2dc5c participant=battle-service decision=commit outcome=done duration_ms=4
2026-11-25T14:35:56.362Z info 2PC phase=commit tx_id=settle-7e208add-3c57-4f49-bc28-60baaac2dc5c participant=user-management-service decision=commit outcome=done duration_ms=64
2026-11-25T14:35:56.829Z info Settlement follow-ups done tx_id=settle-7e208add-3c57-4f49-bc28-60baaac2dc5c battle_id=7e208add-3c57-4f49-bc28-60baaac2dc5c winner_id=7920b173-f680-4875-8c5f-e4113c141040 loser_id=0dc7ace1-7fed-4d8f-a0ed-92fab4cea839 captured_tamagotchi_id=83f7954a-3a3c-4fbf-b5d6-b4a99c885f3c
2026-11-25T14:35:56.970Z info 2PC finished tx_id=settle-7e208add-3c57-4f49-bc28-60baaac2dc5c decision=commit settlement_status=committed duration_ms=796
2026-11-25T14:35:57.009Z info <- POST /api/battles/7e208add-3c57-4f49-bc28-60baaac2dc5c/forfeit status=200 latency_ms=919 caller=user:0dc7ace1-7fed-4d8f-a0ed-92fab4cea839
2026-11-25T14:35:58.758Z info -> POST /api/battles/7c0c174e-04d2-47c6-90a9-6a26543e813e/forfeit client=::ffff:172.19.0.1
2026-11-25T14:35:58.764Z info Battle forfeited battle_id=7c0c174e-04d2-47c6-90a9-6a26543e813e forfeiting_user_id=0dc7ace1-7fed-4d8f-a0ed-92fab4cea839 winner_id=1fc750fa-fd59-4e57-a107-7c39dddb4121
2026-11-25T14:35:58.769Z info 2PC started tx_id=settle-7c0c174e-04d2-47c6-90a9-6a26543e813e battle_id=7c0c174e-04d2-47c6-90a9-6a26543e813e participants=[battle-service, user-management-service] winner_id=1fc750fa-fd59-4e57-a107-7c39dddb4121 reward=120
2026-11-25T14:35:58.774Z info 2PC phase=prepare tx_id=settle-7c0c174e-04d2-47c6-90a9-6a26543e813e participant=battle-service vote=yes outcome=prepared duration_ms=5
2026-11-25T14:35:58.822Z warn 2PC phase=prepare tx_id=settle-7c0c174e-04d2-47c6-90a9-6a26543e813e participant=user-management-service vote=no outcome=refused duration_ms=47
2026-11-25T14:35:58.826Z info 2PC decision tx_id=settle-7c0c174e-04d2-47c6-90a9-6a26543e813e decision=abort votes=battle-service:yes,user-management-service:no
2026-11-25T14:35:58.830Z info 2PC phase=abort tx_id=settle-7c0c174e-04d2-47c6-90a9-6a26543e813e participant=battle-service decision=abort outcome=done duration_ms=4
2026-11-25T14:35:58.871Z info 2PC phase=abort tx_id=settle-7c0c174e-04d2-47c6-90a9-6a26543e813e participant=user-management-service decision=abort outcome=done duration_ms=40
2026-11-25T14:35:58.885Z warn 2PC finished tx_id=settle-7c0c174e-04d2-47c6-90a9-6a26543e813e decision=abort settlement_status=aborted duration_ms=116
2026-11-25T14:35:58.891Z warn Battle forfeit rejected battle_id=7c0c174e-04d2-47c6-90a9-6a26543e813e reason=settlement_aborted
2026-11-25T14:35:58.895Z warn <- POST /api/battles/7c0c174e-04d2-47c6-90a9-6a26543e813e/forfeit status=409 latency_ms=136 caller=user:0dc7ace1-7fed-4d8f-a0ed-92fab4cea839
```

## User Management log (participant)

```text
2PC phase=prepare tx_id=settle-7e208add-3c57-4f49-bc28-60baaac2dc5c participant=user-management-service vote=yes outcome=prepared user_id=7920b173-f680-4875-8c5f-e4113c141040 amount=120 event_id=battle:7e208add-3c57-4f49-bc28-60baaac2dc5c:winner duration_ms=23
<- POST /api/tx/settle-7e208add-3c57-4f49-bc28-60baaac2dc5c/prepare status=200 latency_ms=32 caller=service:battle-service
2PC phase=commit tx_id=settle-7e208add-3c57-4f49-bc28-60baaac2dc5c participant=user-management-service decision=commit outcome=committed duration_ms=9
<- POST /api/tx/settle-7e208add-3c57-4f49-bc28-60baaac2dc5c/commit status=200 latency_ms=15 caller=service:battle-service
2PC phase=prepare tx_id=settle-7c0c174e-04d2-47c6-90a9-6a26543e813e participant=user-management-service vote=no outcome=user_not_found user_id=1fc750fa-fd59-4e57-a107-7c39dddb4121 amount=120 event_id=battle:7c0c174e-04d2-47c6-90a9-6a26543e813e:winner duration_ms=11
<- POST /api/tx/settle-7c0c174e-04d2-47c6-90a9-6a26543e813e/prepare status=404 latency_ms=12 caller=service:battle-service
2PC phase=abort tx_id=settle-7c0c174e-04d2-47c6-90a9-6a26543e813e participant=user-management-service decision=abort outcome=nothing_to_abort duration_ms=2
<- POST /api/tx/settle-7c0c174e-04d2-47c6-90a9-6a26543e813e/abort status=200 latency_ms=3 caller=service:battle-service
2PC phase=prepare tx_id=e2e-failover-b137e2 participant=user-management-service vote=yes outcome=prepared user_id=7920b173-f680-4875-8c5f-e4113c141040 amount=7 event_id=e2e-failover-b137e2 duration_ms=13
<- POST /api/tx/e2e-failover-b137e2/prepare status=200 latency_ms=15 caller=service:battle-service
2PC phase=commit tx_id=e2e-failover-b137e2 participant=user-management-service decision=commit outcome=committed duration_ms=10
<- POST /api/tx/e2e-failover-b137e2/commit status=200 latency_ms=15 caller=service:battle-service
2PC phase=commit tx_id=e2e-failover-b137e2 participant=user-management-service decision=commit outcome=already_committed duration_ms=1
<- POST /api/tx/e2e-failover-b137e2/commit status=200 latency_ms=3 caller=service:battle-service
```
