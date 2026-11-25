# Lab 5, Grade 9: the battle settlement saga end to end

Run on 2026-11-25 against Compose (`docker-compose.yml` of this repository) with `postgres-0..2`, `postgres-failover`,
`service-discovery`, **Message Broker 1.4.0** (the saga coordinator), `tamagotchi-service` 4.1.0, and User Management /
Battle built from the commits released as **5.0.0** (Battle 5.0.1 only removes code no longer called). The battle is
ended by a forfeit; Battle sends one saga `settle-{battle_id}` with 8 steps (settlement, winner +120, loser −60, four
XP awards, capture), each with its compensation.

1. **Completed**: every step is acknowledged; alice +120, bob 500 → 440.
2. **Compensated on a 409**: carol (no currency) loses; step 3 (her −60) is rejected with `409 Insufficient global
   currency.`, the broker undoes step 2 (alice's +120) and step 1 (the settlement); the forfeit answers 409
   `compensated`, the battle is back to `settling`, alice's balance is unchanged.
3. **Compensated at the XP step**: `docker compose stop tamagotchi-service` after the battle started; step 4 (XP) is
   retried 5 times (1, 2, 4, 8 s) and fails, the broker undoes steps 3, 2 and 1. The forfeit answered while the saga
   was still running (step 1 had finished the battle); Battle's poller then stored `compensated`, and both balances are
   back where they were.

Saga states are read from `GET http://localhost:8070/api/transactions/settle-{battle_id}` with a service JWT.

## Requests, answers and saga states

```text
===== 1. COMPLETED: bob forfeits, alice wins; all 8 steps complete =====
> POST {battle}/api/battles/a605fdf2-405c-456a-ba41-cfb81817d655/forfeit
< 200 {"battle_id":"a605fdf2-405c-456a-ba41-cfb81817d655","winner_id":"9b526a30-72bb-47a1-8938-1c27e4d5600b","loser_id":"c6fe0b64-9021-4dc6-90f9-23552fb0843e","rewards":{"winner":{"global_currency":120,"xp":{"primary":60,"secondary":40},"captured_tamagotchi_id":"a0eac65c-b9ff-44d8-9787-c2f651477673"},"loser":{"global_currency":-60,"xp":{"primary":24,"secondary":16}}},"settlement_status":"completed","finished_at":"2026-11-25T14:58:20.184013Z"}
  saga settle-a605fdf2-405c-456a-ba41-cfb81817d655: status=completed error=None
    step 1 battle-service           POST /api/battles/a605fdf2-405c-456a-ba41-cfb81817d655/settlement   completed    http=200 attempts=1 compensation_http=None
    step 2 user-management-service  POST /api/users/9b526a30-72bb-47a1-8938-1c27e4d5600b/currency       completed    http=200 attempts=1 compensation_http=None
    step 3 user-management-service  POST /api/users/c6fe0b64-9021-4dc6-90f9-23552fb0843e/currency       completed    http=200 attempts=1 compensation_http=None
    step 4 tamagotchi-service       POST /api/tamagotchis/f2da86f6-2db1-4596-8cef-bc49ab6a7a59/xp       completed    http=200 attempts=1 compensation_http=None
    step 5 tamagotchi-service       POST /api/tamagotchis/c308eb1a-8a4b-4966-9df0-ebc228056e9a/xp       completed    http=200 attempts=1 compensation_http=None
    step 6 tamagotchi-service       POST /api/tamagotchis/a0eac65c-b9ff-44d8-9787-c2f651477673/xp       completed    http=200 attempts=1 compensation_http=None
    step 7 tamagotchi-service       POST /api/tamagotchis/1712cad6-d95a-47a6-a202-d5da24a01d1e/xp       completed    http=200 attempts=1 compensation_http=None
    step 8 tamagotchi-service       POST /api/tamagotchis/a0eac65c-b9ff-44d8-9787-c2f651477673/transfer completed    http=200 attempts=1 compensation_http=None
alice balance -> 120 (+120); bob balance -> 440 (500 - 60)

===== 2. COMPENSATED ON 409: carol has no currency, loses; the penalty step gets 409 and the saga compensates =====
> POST {battle}/api/battles/63384309-d5e8-4671-81e5-91686b362ba0/forfeit
< 409 {"error":"The battle could not be settled.","settlement_status":"compensated"}
  saga settle-63384309-d5e8-4671-81e5-91686b362ba0: status=compensated error=step 3 user-management-service POST /api/users/c296f31f-2c07-4ff4-baee-8c26d9fa28fc/currency failed: rejected with status 409
    step 1 battle-service           POST /api/battles/63384309-d5e8-4671-81e5-91686b362ba0/settlement   compensated  http=200 attempts=1 compensation_http=200
    step 2 user-management-service  POST /api/users/9b526a30-72bb-47a1-8938-1c27e4d5600b/currency       compensated  http=200 attempts=1 compensation_http=200
    step 3 user-management-service  POST /api/users/c296f31f-2c07-4ff4-baee-8c26d9fa28fc/currency       failed       http=409 attempts=1 compensation_http=None
    step 4 tamagotchi-service       POST /api/tamagotchis/ed243215-be39-4503-af35-77866ae7688b/xp       skipped      http=None attempts=0 compensation_http=None
    step 5 tamagotchi-service       POST /api/tamagotchis/9e8a0cdb-72ca-4bd4-ba29-5d92b988ca58/xp       skipped      http=None attempts=0 compensation_http=None
    step 6 tamagotchi-service       POST /api/tamagotchis/172abd0f-e39f-4dc9-9746-a2e32a53161c/xp       skipped      http=None attempts=0 compensation_http=None
    step 7 tamagotchi-service       POST /api/tamagotchis/0516ea6d-2a9d-492f-8f49-399db1a9dc3e/xp       skipped      http=None attempts=0 compensation_http=None
    step 8 tamagotchi-service       POST /api/tamagotchis/172abd0f-e39f-4dc9-9746-a2e32a53161c/transfer skipped      http=None attempts=0 compensation_http=None
> GET {battle}/api/battles/63384309-d5e8-4671-81e5-91686b362ba0
< 200 {"battle_id":"63384309-d5e8-4671-81e5-91686b362ba0","status":"settling","settlement_status":"compensated","turn":null,"turn_number":1,"participants":[{"user_id":"9b526a30-72bb-47a1-8938-1c27e4d5600b","primary":{"tamagotchi_id":"ed243215-be39-4503-af35-77866ae7688b","type":"flame","level":1,"hp":120},"secondary":{"tamagotchi_id":"9e8a0cdb-72ca-4bd4-ba29-5d92b988ca58","type":"flame","level":1}},{"user_id":"c296f31f-2c07-4ff4-baee-8c26d9fa28fc","primary":{"tamagotchi_id":"172abd0f-e39f-4dc9-9746-a2e32a53161c","type":"flame","level":1,"hp":120},"secondary":{"tamagotchi_id":"0516ea6d-2a9d-492f-8f49
alice balance 120 -> 120 (reward paid, then undone); carol balance -> 0

===== 3. COMPENSATED AT THE XP STEP: Tamagotchi is stopped after the battle starts; XP fails after its retries =====
$ docker compose stop tamagotchi-service
> POST {battle}/api/battles/1c84c295-c3ad-442f-843c-ed60af2abb8f/forfeit
< 200 {"battle_id":"1c84c295-c3ad-442f-843c-ed60af2abb8f","winner_id":"a19a07b9-adb1-4cad-86f4-8459e7f4204e","loser_id":"b022ef85-2688-49e2-931c-b183a55f011f","rewards":{"winner":{"global_currency":120,"xp":{"primary":60,"secondary":40},"captured_tamagotchi_id":"c8e296e6-f4e3-40c9-85fb-5b06fac3e116"},"loser":{"global_currency":-60,"xp":{"primary":24,"secondary":16}}},"settlement_status":"running","finished_at":"2026-11-25T14:58:25.710805Z"}
  saga settle-1c84c295-c3ad-442f-843c-ed60af2abb8f: status=compensated error=step 4 tamagotchi-service POST /api/tamagotchis/2dc718ea-70ec-45fd-8809-a890b6cc0e5c/xp failed: still failing after 5 attempts: no registered instance
    step 1 battle-service           POST /api/battles/1c84c295-c3ad-442f-843c-ed60af2abb8f/settlement   compensated  http=200 attempts=1 compensation_http=200
    step 2 user-management-service  POST /api/users/a19a07b9-adb1-4cad-86f4-8459e7f4204e/currency       compensated  http=200 attempts=1 compensation_http=200
    step 3 user-management-service  POST /api/users/b022ef85-2688-49e2-931c-b183a55f011f/currency       compensated  http=200 attempts=1 compensation_http=200
    step 4 tamagotchi-service       POST /api/tamagotchis/2dc718ea-70ec-45fd-8809-a890b6cc0e5c/xp       failed       http=503 attempts=5 compensation_http=None
    step 5 tamagotchi-service       POST /api/tamagotchis/8a9ab142-fed2-48c9-b868-2827b26a7ff8/xp       skipped      http=None attempts=0 compensation_http=None
    step 6 tamagotchi-service       POST /api/tamagotchis/c8e296e6-f4e3-40c9-85fb-5b06fac3e116/xp       skipped      http=None attempts=0 compensation_http=None
    step 7 tamagotchi-service       POST /api/tamagotchis/e9c3a60f-3a92-43a8-8ab6-61341f10773a/xp       skipped      http=None attempts=0 compensation_http=None
    step 8 tamagotchi-service       POST /api/tamagotchis/c8e296e6-f4e3-40c9-85fb-5b06fac3e116/transfer skipped      http=None attempts=0 compensation_http=None
$ docker compose start tamagotchi-service
> GET {battle}/api/battles/1c84c295-c3ad-442f-843c-ed60af2abb8f
< 200 {"battle_id":"1c84c295-c3ad-442f-843c-ed60af2abb8f","status":"settling","settlement_status":"compensated","turn":null,"turn_number":1,"participants":[{"user_id":"a19a07b9-adb1-4cad-86f4-8459e7f4204e","primary":{"tamagotchi_id":"2dc718ea-70ec-45fd-8809-a890b6cc0e5c","type":"flame","level":1,"hp":120},"secondary":{"tamagotchi_id":"8a9ab142-fed2-48c9-b868-2827b26a7ff8","type":"flame","level":1}},{"user_id":"b022ef85-2688-49e2-931c-b183a55f011f","primary":{"tamagotchi_id":"c8e296e6-f4e3-40c9-85fb-5b06fac3e116","type":"flame","level":1,"hp":120},"secondary":{"tamagotchi_id":"e9c3a60f-3a92-43a8-8ab6
dave balance -> 0 (reward undone); erin balance -> 500 (penalty undone)
```

## Message Broker log (coordinator)

```text
14:58:20,124 INFO Saga started tx_id=settle-a605fdf2-405c-456a-ba41-cfb81817d655 steps=8 caller=battle-service services=[battle-service, user-management-service, user-management-service, tamagotchi-service, tamagotchi-service, tamagotchi-service, tamagotchi-service, tamagotchi-service]
14:58:20,224 INFO Saga step tx_id=settle-a605fdf2-405c-456a-ba41-cfb81817d655 step=1/8 service=battle-service method=POST path=/api/battles/a605fdf2-405c-456a-ba41-cfb81817d655/settlement outcome=completed status=200 attempt=1 duration_ms=97
14:58:20,268 INFO Saga step tx_id=settle-a605fdf2-405c-456a-ba41-cfb81817d655 step=2/8 service=user-management-service method=POST path=/api/users/9b526a30-72bb-47a1-8938-1c27e4d5600b/currency outcome=completed status=200 attempt=1 duration_ms=34
14:58:20,296 INFO Saga step tx_id=settle-a605fdf2-405c-456a-ba41-cfb81817d655 step=3/8 service=user-management-service method=POST path=/api/users/c6fe0b64-9021-4dc6-90f9-23552fb0843e/currency outcome=completed status=200 attempt=1 duration_ms=20
14:58:20,319 INFO Saga step tx_id=settle-a605fdf2-405c-456a-ba41-cfb81817d655 step=4/8 service=tamagotchi-service method=POST path=/api/tamagotchis/f2da86f6-2db1-4596-8cef-bc49ab6a7a59/xp outcome=completed status=200 attempt=1 duration_ms=15
14:58:20,337 INFO Saga step tx_id=settle-a605fdf2-405c-456a-ba41-cfb81817d655 step=5/8 service=tamagotchi-service method=POST path=/api/tamagotchis/c308eb1a-8a4b-4966-9df0-ebc228056e9a/xp outcome=completed status=200 attempt=1 duration_ms=10
14:58:20,355 INFO Saga step tx_id=settle-a605fdf2-405c-456a-ba41-cfb81817d655 step=6/8 service=tamagotchi-service method=POST path=/api/tamagotchis/a0eac65c-b9ff-44d8-9787-c2f651477673/xp outcome=completed status=200 attempt=1 duration_ms=11
14:58:20,382 INFO Saga step tx_id=settle-a605fdf2-405c-456a-ba41-cfb81817d655 step=7/8 service=tamagotchi-service method=POST path=/api/tamagotchis/1712cad6-d95a-47a6-a202-d5da24a01d1e/xp outcome=completed status=200 attempt=1 duration_ms=15
14:58:20,541 INFO Saga step tx_id=settle-a605fdf2-405c-456a-ba41-cfb81817d655 step=8/8 service=tamagotchi-service method=POST path=/api/tamagotchis/a0eac65c-b9ff-44d8-9787-c2f651477673/transfer outcome=completed status=200 attempt=1 duration_ms=141
14:58:20,601 INFO Saga finished tx_id=settle-a605fdf2-405c-456a-ba41-cfb81817d655 status=completed steps=8 duration_ms=482
14:58:21,879 INFO Saga started tx_id=settle-63384309-d5e8-4671-81e5-91686b362ba0 steps=8 caller=battle-service services=[battle-service, user-management-service, user-management-service, tamagotchi-service, tamagotchi-service, tamagotchi-service, tamagotchi-service, tamagotchi-service]
14:58:21,948 INFO Saga step tx_id=settle-63384309-d5e8-4671-81e5-91686b362ba0 step=1/8 service=battle-service method=POST path=/api/battles/63384309-d5e8-4671-81e5-91686b362ba0/settlement outcome=completed status=200 attempt=1 duration_ms=67
14:58:21,983 INFO Saga step tx_id=settle-63384309-d5e8-4671-81e5-91686b362ba0 step=2/8 service=user-management-service method=POST path=/api/users/9b526a30-72bb-47a1-8938-1c27e4d5600b/currency outcome=completed status=200 attempt=1 duration_ms=27
14:58:22,017 INFO Saga step tx_id=settle-63384309-d5e8-4671-81e5-91686b362ba0 step=3/8 service=user-management-service method=POST path=/api/users/c296f31f-2c07-4ff4-baee-8c26d9fa28fc/currency outcome=failed status=409 attempt=1 duration_ms=24 error="status 409 from d1cab392cd6c: {"error":"Insufficient global currency."}"
14:58:22,023 WARN Saga compensating tx_id=settle-63384309-d5e8-4671-81e5-91686b362ba0 failed_step=3 service=user-management-service compensations=2 reason="rejected with status 409"
14:58:22,060 INFO Saga compensation tx_id=settle-63384309-d5e8-4671-81e5-91686b362ba0 step=2/8 service=user-management-service method=POST path=/api/users/9b526a30-72bb-47a1-8938-1c27e4d5600b/currency outcome=compensated status=200 attempt=1 duration_ms=25
14:58:22,101 INFO Saga compensation tx_id=settle-63384309-d5e8-4671-81e5-91686b362ba0 step=1/8 service=battle-service method=POST path=/api/battles/63384309-d5e8-4671-81e5-91686b362ba0/settlement/cancel outcome=compensated status=200 attempt=1 duration_ms=29
14:58:22,124 WARN Saga finished tx_id=settle-63384309-d5e8-4671-81e5-91686b362ba0 status=compensated steps=8 duration_ms=268 error="step 3 user-management-service POST /api/users/c296f31f-2c07-4ff4-baee-8c26d9fa28fc/currency failed: rejected with status 409"
14:58:25,701 INFO Saga started tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f steps=8 caller=battle-service services=[battle-service, user-management-service, user-management-service, tamagotchi-service, tamagotchi-service, tamagotchi-service, tamagotchi-service, tamagotchi-service]
14:58:25,723 INFO Saga step tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f step=1/8 service=battle-service method=POST path=/api/battles/1c84c295-c3ad-442f-843c-ed60af2abb8f/settlement outcome=completed status=200 attempt=1 duration_ms=20
14:58:25,760 INFO Saga step tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f step=2/8 service=user-management-service method=POST path=/api/users/a19a07b9-adb1-4cad-86f4-8459e7f4204e/currency outcome=completed status=200 attempt=1 duration_ms=26
14:58:25,793 INFO Saga step tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f step=3/8 service=user-management-service method=POST path=/api/users/b022ef85-2688-49e2-931c-b183a55f011f/currency outcome=completed status=200 attempt=1 duration_ms=23
14:58:27,816 WARN Saga step tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f step=4/8 service=tamagotchi-service method=POST path=/api/tamagotchis/2dc718ea-70ec-45fd-8809-a890b6cc0e5c/xp outcome=retry status=503 attempt=1/5 duration_ms=2013 next_attempt_in_ms=1000 error="connection failed (ad3d9c0dc8a0)"
14:58:29,539 WARN Saga step tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f step=4/8 service=tamagotchi-service method=POST path=/api/tamagotchis/2dc718ea-70ec-45fd-8809-a890b6cc0e5c/xp outcome=retry status=503 attempt=2/5 duration_ms=0 next_attempt_in_ms=2000 error="no registered instance"
14:58:31,554 WARN Saga step tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f step=4/8 service=tamagotchi-service method=POST path=/api/tamagotchis/2dc718ea-70ec-45fd-8809-a890b6cc0e5c/xp outcome=retry status=503 attempt=3/5 duration_ms=1 next_attempt_in_ms=4000 error="no registered instance"
14:58:35,570 WARN Saga step tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f step=4/8 service=tamagotchi-service method=POST path=/api/tamagotchis/2dc718ea-70ec-45fd-8809-a890b6cc0e5c/xp outcome=retry status=503 attempt=4/5 duration_ms=0 next_attempt_in_ms=8000 error="no registered instance"
14:58:43,597 INFO Saga step tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f step=4/8 service=tamagotchi-service method=POST path=/api/tamagotchis/2dc718ea-70ec-45fd-8809-a890b6cc0e5c/xp outcome=failed status=503 attempt=5 duration_ms=3 error="no registered instance"
14:58:43,599 WARN Saga compensating tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f failed_step=4 service=tamagotchi-service compensations=3 reason="still failing after 5 attempts: no registered instance"
14:58:43,657 INFO Saga compensation tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f step=3/8 service=user-management-service method=POST path=/api/users/b022ef85-2688-49e2-931c-b183a55f011f/currency outcome=compensated status=200 attempt=1 duration_ms=40
14:58:43,715 INFO Saga compensation tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f step=2/8 service=user-management-service method=POST path=/api/users/a19a07b9-adb1-4cad-86f4-8459e7f4204e/currency outcome=compensated status=200 attempt=1 duration_ms=38
14:58:43,821 INFO Saga compensation tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f step=1/8 service=battle-service method=POST path=/api/battles/1c84c295-c3ad-442f-843c-ed60af2abb8f/settlement/cancel outcome=compensated status=200 attempt=1 duration_ms=77
14:58:43,954 WARN Saga finished tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f status=compensated steps=8 duration_ms=18197 error="step 4 tamagotchi-service POST /api/tamagotchis/2dc718ea-70ec-45fd-8809-a890b6cc0e5c/xp failed: still failing after 5 attempts: no registered instance"
```

## Battle Service log

```text
2026-11-25T14:58:19.845Z info -> POST /api/battles/a605fdf2-405c-456a-ba41-cfb81817d655/forfeit client=::ffff:172.19.0.1
2026-11-25T14:58:19.972Z info Battle forfeited battle_id=a605fdf2-405c-456a-ba41-cfb81817d655 forfeiting_user_id=c6fe0b64-9021-4dc6-90f9-23552fb0843e winner_id=9b526a30-72bb-47a1-8938-1c27e4d5600b
2026-11-25T14:58:20.000Z info Saga settlement started tx_id=settle-a605fdf2-405c-456a-ba41-cfb81817d655 battle_id=a605fdf2-405c-456a-ba41-cfb81817d655 winner_id=9b526a30-72bb-47a1-8938-1c27e4d5600b loser_id=c6fe0b64-9021-4dc6-90f9-23552fb0843e steps=8
2026-11-25T14:58:20.194Z info Saga step settlement battle_id=a605fdf2-405c-456a-ba41-cfb81817d655 event_id=battle-a605fdf2-405c-456a-ba41-cfb81817d655-settle winner_id=9b526a30-72bb-47a1-8938-1c27e4d5600b loser_id=c6fe0b64-9021-4dc6-90f9-23552fb0843e outcome=settled
2026-11-25T14:58:20.666Z info Saga settlement status tx_id=settle-a605fdf2-405c-456a-ba41-cfb81817d655 status=completed http_status=200 duration_ms=669
2026-11-25T14:58:20.772Z info <- POST /api/battles/a605fdf2-405c-456a-ba41-cfb81817d655/forfeit status=200 latency_ms=926 caller=user:c6fe0b64-9021-4dc6-90f9-23552fb0843e
2026-11-25T14:58:21.742Z info -> POST /api/battles/63384309-d5e8-4671-81e5-91686b362ba0/forfeit client=::ffff:172.19.0.1
2026-11-25T14:58:21.747Z info Battle forfeited battle_id=63384309-d5e8-4671-81e5-91686b362ba0 forfeiting_user_id=c296f31f-2c07-4ff4-baee-8c26d9fa28fc winner_id=9b526a30-72bb-47a1-8938-1c27e4d5600b
2026-11-25T14:58:21.759Z info Saga settlement started tx_id=settle-63384309-d5e8-4671-81e5-91686b362ba0 battle_id=63384309-d5e8-4671-81e5-91686b362ba0 winner_id=9b526a30-72bb-47a1-8938-1c27e4d5600b loser_id=c296f31f-2c07-4ff4-baee-8c26d9fa28fc steps=8
2026-11-25T14:58:21.941Z info Saga step settlement battle_id=63384309-d5e8-4671-81e5-91686b362ba0 event_id=battle-63384309-d5e8-4671-81e5-91686b362ba0-settle winner_id=9b526a30-72bb-47a1-8938-1c27e4d5600b loser_id=c296f31f-2c07-4ff4-baee-8c26d9fa28fc outcome=settled
2026-11-25T14:58:22.093Z warn Saga compensation settlement_cancel battle_id=63384309-d5e8-4671-81e5-91686b362ba0 event_id=battle-63384309-d5e8-4671-81e5-91686b362ba0-settle-cancel outcome=cancelled
2026-11-25T14:58:22.133Z warn Saga settlement status tx_id=settle-63384309-d5e8-4671-81e5-91686b362ba0 status=compensated http_status=200 duration_ms=374
2026-11-25T14:58:22.145Z warn Battle forfeit rejected battle_id=63384309-d5e8-4671-81e5-91686b362ba0 reason=settlement_compensated
2026-11-25T14:58:22.148Z warn <- POST /api/battles/63384309-d5e8-4671-81e5-91686b362ba0/forfeit status=409 latency_ms=405 caller=user:c296f31f-2c07-4ff4-baee-8c26d9fa28fc
2026-11-25T14:58:25.666Z info -> POST /api/battles/1c84c295-c3ad-442f-843c-ed60af2abb8f/forfeit client=::ffff:172.19.0.1
2026-11-25T14:58:25.669Z info Battle forfeited battle_id=1c84c295-c3ad-442f-843c-ed60af2abb8f forfeiting_user_id=b022ef85-2688-49e2-931c-b183a55f011f winner_id=a19a07b9-adb1-4cad-86f4-8459e7f4204e
2026-11-25T14:58:25.674Z info Saga settlement started tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f battle_id=1c84c295-c3ad-442f-843c-ed60af2abb8f winner_id=a19a07b9-adb1-4cad-86f4-8459e7f4204e loser_id=b022ef85-2688-49e2-931c-b183a55f011f steps=8
2026-11-25T14:58:25.719Z info Saga step settlement battle_id=1c84c295-c3ad-442f-843c-ed60af2abb8f event_id=battle-1c84c295-c3ad-442f-843c-ed60af2abb8f-settle winner_id=a19a07b9-adb1-4cad-86f4-8459e7f4204e loser_id=b022ef85-2688-49e2-931c-b183a55f011f outcome=settled
2026-11-25T14:58:31.711Z info Saga settlement status tx_id=settle-1c84c295-c3ad-442f-843c-ed60af2abb8f status=running http_status=202 duration_ms=6037
2026-11-25T14:58:31.760Z info <- POST /api/battles/1c84c295-c3ad-442f-843c-ed60af2abb8f/forfeit status=200 latency_ms=6094 caller=user:b022ef85-2688-49e2-931c-b183a55f011f
2026-11-25T14:58:43.809Z warn Saga compensation settlement_cancel battle_id=1c84c295-c3ad-442f-843c-ed60af2abb8f event_id=battle-1c84c295-c3ad-442f-843c-ed60af2abb8f-settle-cancel outcome=cancelled
```
