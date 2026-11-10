# Lab 4 step 3 handoff for Filip

Step 3 (Denis) added the admin log download, thread-per-request in the broker, the topic list
and gRPC between services and the broker. This note shows where delivery happens on both
transports, where retries would go, where the thread pools live, and what is still open, so
step 4 (durable queues, retries, dead letters) can build on it.

Paths are in `message-broker/src/main/java/com/tamagotchigo/broker/`. Line numbers are from the
1.2.0 source.

## Where delivery happens

Every message ends up in **one method**, `DeliveryService.dispatch` (`delivery/DeliveryService.java:104`).
It is the same for HTTP and gRPC, and for requests and topic events:

1. `queues.acquire(queue)` (line 110, `queues/RequestQueues.java:26`): global and per-queue
   semaphores. Over the limit, it fails fast with 503 and nothing is queued.
2. `balancer.choose(...)` (line 112): round-robin over the registry snapshot. Instances whose
   breaker rejects the call are skipped.
3. `sender.send(instance, outgoing)` (line 128): the only place bytes leave the broker. The
   sender picks the transport per instance:
   - **HTTP**: `DeliveryService.http` (line 162), a JDK `HttpClient` blocking `send`.
   - **gRPC**: `grpc/ConsumerClient.handle` (line 55) for requests, `ConsumerClient.deliver`
     (line 71) for events. These are blocking stubs to the instance's `host:grpc_port`. A transport
     failure is converted to the HTTP path's exceptions (`ConsumerClient.transport`, line 110): a
     deadline becomes `HttpTimeoutException`, anything else `IOException`.
4. Outcome to the breaker (lines 130–145): status ≥ 500, a timeout (504) or a connection
   failure (503) is a failure; anything else is a success.

The entry points that lead into `dispatch`:

| Caller | Transport in | Method |
| --- | --- | --- |
| `web/QueueController` (`/q/{service}/...`, `/api/queues/{service}/requests`) | HTTP | `DeliveryService.deliver` (line 76) |
| `grpc/BrokerGrpcService.call` (line 65) | gRPC `Broker.Call` | `DeliveryService.deliver` |
| `topics/TopicPublisher.deliverTo` (line 127), one call per subscribing service | from HTTP `POST /api/topics/{topic}/events` or gRPC `Broker.Publish` (`BrokerGrpcService.publish`, line 102) | `DeliveryService.deliverEvent` (line 90) |

## Where retries are (not) done

**There are no retries anywhere today.** Each message is sent to exactly one instance, once:

- **Requests.** A failure goes straight back to the caller as 503/504 (HTTP) or
  `UNAVAILABLE`/`DEADLINE_EXCEEDED` with `x-http-status` (gRPC). The caller's own breaker counts it.
- **Topic events.** `TopicPublisher.deliverTo` logs `Event delivery failed ... retry=none`
  (line 149), counts it in `broker_topic_deliveries_total` and `TopicStats` (line 121), and moves
  on to the next subscriber. The publisher only sees the `failed` count.
- **Services.** The C# services (map, raid) do not retry either: one call per peer, 5 s per
  call, inside an 8 s request timeout.

Natural places to add step 4 behaviour:

- **Durable queue, retry and dead letter for events.** Replace the direct loop in
  `TopicPublisher.publish` (line 94) with an enqueue. A worker then calls
  `DeliveryService.deliverEvent` and retries on failure. `event_id` is already the subscribers'
  idempotency key and the `X-Request-Id` of every copy, so a redelivery is safe. Feed
  `broker_dead_letters_total{queue}` and `broker_queue_depth{queue}`; the Grafana panels already
  exist.
- **Rerouting a failed request to another instance.** Inside `dispatch`, after a failure at
  line 128, choose again with the failed instance excluded and count `broker_reroutes_total{queue}`.
  Only reroute when the request has not reached the service, or when it is idempotent (GET, or a
  body with `event_id`). A timeout may already have applied the write.
- Both transports share `dispatch`, so a retry added there covers HTTP and gRPC alike.

## Where the thread pools live

`config/WorkerPools.java` (constructor at line 40) creates both pools. Sizes come from
`config/WorkerPoolProperties.java`:

| Pool | Threads | Configured by | Wired in |
| --- | --- | --- | --- |
| HTTP, `broker-http-N` | `BROKER_WORKER_THREADS` (0 = `BROKER_MAX_CONCURRENT_REQUESTS` + 16 = 216), queue `BROKER_WORKER_QUEUE` (100) | Tomcat's `TaskQueue` | `WorkerPools.brokerHttpExecutor` (line 64) replaces Tomcat's executor |
| gRPC, `broker-grpc-N` | `BROKER_GRPC_THREADS` (0 = the HTTP count), queue `BROKER_GRPC_QUEUE` (100) | fixed `ThreadPoolExecutor` (line 53) | `grpc/GrpcServer.java:44`, `NettyServerBuilder.executor(...)` |

A request holds one worker from start to reply, including the blocking delivery. A background
retry worker should get **its own** bounded executor, so retries never take request threads. The
other background threads are `discovery-cache` (registry refresh), `failed-instance-removal` and
the Discord sender, one thread each. The shared state and its locks are listed in
`message-broker/README.md`, "Concurrency model". Keep that table current when adding a queue.

## gRPC status

- **Contract**: `message-broker/proto/broker.proto`, documented in the broker README "gRPC"
  section (Go and C# examples).
- **Moved** (both directions, `grpc_port: 9000`, `BROKER_GRPC_URL`): map-service, monster-raid-service.
- **Still HTTP**: user-management and battle (Filip); tamagotchi and notification (Dmitrii); guild
  and package-registry (Maxim). The broker keeps using HTTP for them until they register a
  `grpc_port`. The gateway → broker hop stays HTTP by design.
- A service that registers `grpc_port` must serve `Consumer.Handle` for **every** endpoint
  peers call, because the broker never mixes transports for one instance.

## Open items

1. Owners still have to move their services to gRPC (see above) and publish their remaining
   events to topics: `user.friend_request_received`, `battle.request_received`,
   `guild.invitation_sent` still call `/api/notifications/publish`.
2. Owners other than Map and Raid still write flat log files. The gateway's
   `GET /api/admin/logs` serves both layouts. Moving to `<service>/<instance_id>.log` is optional
   but agreed.
3. No durable storage: queued work, topic counts (`GET /api/topics`) and breaker state are in
   memory and lost on broker restart.
4. gRPC calls beyond `BROKER_GRPC_THREADS` + `BROKER_GRPC_QUEUE` are rejected by the executor, and
   the client sees the stream fail. HTTP has the same bound (Tomcat refuses the connection). A
   friendlier `RESOURCE_EXHAUSTED` would need admission control before the executor.
5. The broker → Consumer channel is plaintext inside the Compose network, like HTTP. Trust still
   rests on `X-Gateway-Secret`.
