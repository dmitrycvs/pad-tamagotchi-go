-- Bookkeeping of the etl-service.

CREATE TABLE etl_runs (
    run_id         uuid PRIMARY KEY,
    trigger        text NOT NULL,                   -- schedule, manual
    status         text NOT NULL,                   -- running, succeeded, partial, failed
    started_at     timestamptz NOT NULL,
    finished_at    timestamptz,
    duration_ms    bigint,
    rows_extracted bigint NOT NULL DEFAULT 0,
    rows_loaded    bigint NOT NULL DEFAULT 0,
    error          text,
    tables         jsonb NOT NULL DEFAULT '[]'      -- per table: rows extracted and loaded, status, duration, error
);
CREATE INDEX ON etl_runs (started_at DESC);

-- How far each source was read; written in the transaction that loads the rows.
CREATE TABLE etl_watermarks (
    table_name text PRIMARY KEY,
    watermark  timestamptz NOT NULL,
    run_id     uuid NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);
