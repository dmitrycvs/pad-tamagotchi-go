-- Facts. The natural id of the source row is the primary key, so loading a row again updates it.

-- One row per battle (Battle: "Battles").
CREATE TABLE fact_battle (
    battle_id                 text PRIMARY KEY,
    challenger_key            bigint NOT NULL REFERENCES dim_user,
    opponent_key              bigint NOT NULL REFERENCES dim_user,
    winner_key                bigint NOT NULL REFERENCES dim_user,       -- 0 until it is finished
    loser_key                 bigint NOT NULL REFERENCES dim_user,
    challenger_tamagotchi_key bigint NOT NULL REFERENCES dim_tamagotchi, -- primary of the lineup
    opponent_tamagotchi_key   bigint NOT NULL REFERENCES dim_tamagotchi,
    package_key               bigint NOT NULL REFERENCES dim_package,    -- of the challenger's primary
    created_date_key          integer NOT NULL REFERENCES dim_date,
    finished_date_key         integer REFERENCES dim_date,
    status                    text NOT NULL,
    turns                     integer NOT NULL,
    challenger_hp             integer NOT NULL,
    opponent_hp               integer NOT NULL,
    duration_seconds          integer,
    created_at                timestamptz NOT NULL,
    finished_at               timestamptz
);

-- One row per participant of a raid (Monster Raid: "Participants" and "Raids").
CREATE TABLE fact_raid_damage (
    raid_id          text NOT NULL,
    user_key         bigint NOT NULL REFERENCES dim_user,
    guild_key        bigint NOT NULL REFERENCES dim_guild,
    tamagotchi_key   bigint NOT NULL REFERENCES dim_tamagotchi,
    joined_date_key  integer NOT NULL REFERENCES dim_date,
    monster_id       text NOT NULL,
    monster_name     text NOT NULL,
    raid_status      text NOT NULL,            -- an expired raid counts as failed
    monster_max_hp   integer NOT NULL,
    damage_per_hit   integer NOT NULL,
    damage_dealt     integer NOT NULL,
    damage_share     double precision NOT NULL, -- of the monster's max HP
    joined_at        timestamptz NOT NULL,
    PRIMARY KEY (raid_id, user_key)
);

-- One row per applied currency change (User Management: "IdempotencyRecords" of POST .../currency).
-- The source keeps only the balance after each change, so the amount is the difference from the
-- user's previous balance.
CREATE TABLE fact_currency_change (
    event_id         text PRIMARY KEY,
    user_key         bigint NOT NULL REFERENCES dim_user,
    date_key         integer NOT NULL REFERENCES dim_date,
    currency         text NOT NULL,
    amount           bigint NOT NULL,
    balance_after    bigint NOT NULL,
    reason           text NOT NULL,            -- battle_won, battle_lost, raid, other
    battle_id        text,
    changed_at       timestamptz NOT NULL
);
CREATE INDEX ON fact_currency_change (user_key, currency, changed_at);

-- One row per notification (Notification: notifications).
CREATE TABLE fact_notification (
    notification_id text PRIMARY KEY,
    user_key        bigint NOT NULL REFERENCES dim_user,   -- 0 when a guild is the recipient
    guild_key       bigint NOT NULL REFERENCES dim_guild,
    date_key        integer NOT NULL REFERENCES dim_date,
    type            text NOT NULL,
    status          text NOT NULL,
    is_read         boolean NOT NULL,
    attempts        integer NOT NULL,
    created_at      timestamptz NOT NULL
);

-- One row per user and day (Map: "Locations"). Map keeps only the latest location, so every ETL run
-- adds what it sees; a location that was already counted is ignored.
CREATE TABLE fact_location_daily (
    user_key           bigint NOT NULL REFERENCES dim_user,
    date_key           integer NOT NULL REFERENCES dim_date,
    observations       integer NOT NULL,
    first_seen_at      timestamptz NOT NULL,
    last_seen_at       timestamptz NOT NULL,
    last_latitude      double precision NOT NULL,
    last_longitude     double precision NOT NULL,
    min_latitude       double precision NOT NULL,
    max_latitude       double precision NOT NULL,
    min_longitude      double precision NOT NULL,
    max_longitude      double precision NOT NULL,
    accuracy_sum       double precision NOT NULL,          -- average = accuracy_sum / observations
    PRIMARY KEY (user_key, date_key)
);

CREATE INDEX ON fact_battle (created_date_key);
CREATE INDEX ON fact_raid_damage (guild_key);
CREATE INDEX ON fact_notification (date_key, type);
CREATE INDEX ON fact_location_daily (date_key);
