# pad-tamagotchi-go

Common Public Repository for FAF.PAD21.1 — Topic 2: Tamagotchi Go.

## Service Boundaries

The system is split into 8 microservices, each owning a distinct piece of functionality so that services can be developed, deployed and scaled independently. No service reaches into another's data store — cross-service data needs are served through APIs/events, keeping each service's internal model private.

### User Management Service
Owns global user identity: registration, login credentials, email, and which package(s) a user is registered with. Maintains each user's friends and enemies list. Owns the two currencies — package-local currency (scoped to a single package) and global currency (shared across the ecosystem). Is the single source of truth for identity/relationship questions such as "who is this user?" and "are these users friends?" — no other service duplicates this data.

### Battle Service
Owns the execution of turn-based PvP combat once a match is created. Computes damage from Tamagotchi level, type advantage, equipped boosts and current health, and tracks battle/turn state for the duration of a match. Does not own user identity or Tamagotchi definitions — it reads them from User Management and Tamagotchi Service and only owns the transient state of a battle in progress plus its outcome.

### Tamagotchi Service
Owns the globally relevant state of Tamagotchis: identity, owner, combat type, level, sprite references, and package-local health statistics (hunger, tiredness, happiness, etc.), which are intentionally left unnormalized since their meaning is package-specific. Defines the six combat types and their advantage cycle. Secondary Tamagotchis are references to existing entries, not new records, keeping ownership of a given Tamagotchi in exactly one place.

### Notification Service
Owns asynchronous delivery of events to users via Firebase push notifications. Other services publish events (friend request, nearby player, battle request, guild invitation, raid started, etc.) without needing to know how or whether the user is reachable — delivery mechanics are fully encapsulated here.

### Map Service
Owns each user's latest known location: receives continuous geolocation updates, discards stale positions, and computes proximity between users. Emits events when previously unrelated users come within range, without itself deciding what happens next (befriending, battling) — that decision-making stays out of its boundary.

### Monster Raid Service
Owns the state of cooperative raids: the monster's current HP, participating users, damage dealt, timestamps and raid status. Aggregates contributions from multiple guild members' primary Tamagotchis and distributes rewards on completion, using idempotent operations so a reconnect or duplicated event can't double-count damage or rewards.

### Guild Service
Owns guild identity, membership, roles (owner/officer/member) and guild chat. Provides the social grouping used by raids, but does not itself own raid state or battle outcomes — it only answers membership/role questions and carries chat messages.

### Package Registry Service
Owns the catalog of packages (client apps) participating in the ecosystem — their identifiers, versions, status, and which users/moderators/admins are associated with them. Acts as the configuration authority for package-specific Tamagotchi growth mechanics and stat definitions, and for globally-scheduled Monster Raid configuration, without needing every package to share a single data structure.
