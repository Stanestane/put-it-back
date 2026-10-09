BEGIN;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE TABLE IF NOT EXISTS schema_version (version integer PRIMARY KEY);
INSERT INTO schema_version VALUES (1) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS events (
    event_id uuid PRIMARY KEY,
    install_id uuid NOT NULL,
    session_id uuid NOT NULL,
    sequence integer NOT NULL,
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    build_version varchar(32) NOT NULL,
    platform varchar(16) NOT NULL,
    environment varchar(16) NOT NULL,
    name varchar(32) NOT NULL,
    payload jsonb NOT NULL,
    fingerprint char(64) NOT NULL
);
CREATE INDEX IF NOT EXISTS events_time ON events(occurred_at);
CREATE INDEX IF NOT EXISTS events_install_time ON events(install_id, occurred_at);
CREATE INDEX IF NOT EXISTS events_type_time ON events(name, occurred_at) WHERE environment='production';
CREATE TABLE IF NOT EXISTS installations (
    install_id uuid NOT NULL,
    environment varchar(16) NOT NULL,
    first_seen timestamptz NOT NULL,
    PRIMARY KEY (install_id, environment)
);
CREATE SCHEMA IF NOT EXISTS analytics;
-- Only gameplay/lifecycle events qualify as player activity; ads alone do not.
CREATE OR REPLACE VIEW analytics.activity AS
SELECT DISTINCT (occurred_at AT TIME ZONE 'UTC')::date AS day, install_id
FROM events WHERE environment='production'
AND name IN ('first_open','session_started','activity_checkpoint','round_started','round_finished');
CREATE OR REPLACE VIEW analytics.audience AS
WITH days AS (
    SELECT generate_series((CURRENT_DATE - 89)::timestamp, CURRENT_DATE::timestamp, '1 day')::date AS day
)
SELECT d.day,
 (SELECT count(*) FROM analytics.activity a WHERE a.day=d.day) AS dau,
 (SELECT count(DISTINCT install_id) FROM analytics.activity a WHERE a.day BETWEEN d.day-6 AND d.day) AS wau,
 (SELECT count(DISTINCT install_id) FROM analytics.activity a WHERE a.day BETWEEN d.day-29 AND d.day) AS mau,
 (SELECT count(*) FROM installations i WHERE i.environment='production'
    AND (i.first_seen AT TIME ZONE 'UTC')::date=d.day) AS new_installations
FROM days d;
CREATE OR REPLACE VIEW analytics.retention AS
SELECT (i.first_seen AT TIME ZONE 'UTC')::date AS cohort_day, n.day_number,
 count(*) AS cohort_size, count(a.install_id) AS returned,
 round(100.0 * count(a.install_id)/NULLIF(count(*),0),2) AS retention_percent
FROM installations i CROSS JOIN (VALUES(1),(7),(30)) n(day_number)
LEFT JOIN analytics.activity a ON a.install_id=i.install_id
 AND a.day=(i.first_seen AT TIME ZONE 'UTC')::date+n.day_number
WHERE i.environment='production'
 AND (i.first_seen AT TIME ZONE 'UTC')::date >= CURRENT_DATE-89
 AND (i.first_seen AT TIME ZONE 'UTC')::date+n.day_number < CURRENT_DATE
GROUP BY 1,2;
CREATE OR REPLACE VIEW analytics.engagement AS
SELECT (occurred_at AT TIME ZONE 'UTC')::date AS day, platform, build_version,
 count(DISTINCT install_id) AS active_installations,
 count(DISTINCT (install_id,session_id)) AS observed_sessions,
 count(*) FILTER (WHERE name='round_started') AS rounds_started,
 coalesce(sum((payload->>'foreground_seconds')::numeric) FILTER (WHERE name='activity_checkpoint'),0) AS foreground_seconds,
 coalesce(sum((payload->>'gameplay_seconds')::numeric) FILTER (WHERE name='activity_checkpoint'),0) AS gameplay_seconds
FROM events WHERE environment='production'
 AND name IN ('first_open','session_started','activity_checkpoint','round_started','round_finished')
GROUP BY 1,2,3;
CREATE OR REPLACE VIEW analytics.levels AS
WITH rounds AS (
 SELECT install_id,payload->>'round_id' AS round_id, payload->>'level_id' AS level_id,
 payload->>'mode' AS mode,payload->>'puzzle_revision' AS puzzle_revision,build_version,platform,
 bool_or(name='round_started') AS started,
 bool_or(name='round_finished') AS finished,
 bool_or(payload->>'outcome'='win') AS won,
 bool_or(payload->>'outcome'='timeout') AS timed_out,
 bool_or(payload->>'outcome'='abandoned') AS abandoned,
 max((payload->>'active_seconds')::numeric) FILTER(WHERE name='round_finished') AS solve_seconds,
 max((payload->>'incorrect_actions')::integer) FILTER(WHERE name='round_finished') AS incorrect_actions
 FROM events WHERE environment='production' AND name IN ('round_started','round_finished')
 GROUP BY 1,2,3,4,5,6,7
)
SELECT level_id,mode,puzzle_revision,build_version,platform,
 count(*) FILTER(WHERE started) AS starts,count(*) FILTER(WHERE finished) AS finishes,
 count(*) FILTER(WHERE won) AS wins,count(*) FILTER(WHERE timed_out) AS timeouts,
 count(*) FILTER(WHERE abandoned) AS explicit_abandonments,
 count(*) FILTER(WHERE started AND NOT finished) AS incomplete,
 round(100.0*count(*) FILTER(WHERE won)/NULLIF(count(*) FILTER(WHERE finished),0),2) AS completed_win_percent,
 round(avg(solve_seconds) FILTER(WHERE won),2) AS mean_win_seconds,
 sum(incorrect_actions) AS incorrect_actions
FROM rounds GROUP BY 1,2,3,4,5;
CREATE OR REPLACE VIEW analytics.ad_revenue AS
SELECT (occurred_at AT TIME ZONE 'UTC')::date AS day, payload->>'currency' AS currency,
 payload->>'precision' AS precision, sum((payload->>'value_micros')::bigint)/1000000.0 AS revenue
FROM events WHERE environment='production' AND name='ad_revenue' AND payload->>'test_ad'='false'
GROUP BY 1,2,3;
CREATE OR REPLACE VIEW analytics.ingestion AS
SELECT (received_at AT TIME ZONE 'UTC')::date AS received_day,environment,name,count(*) AS events,
 round(avg(extract(epoch FROM received_at-occurred_at))) AS mean_delay_seconds
FROM events GROUP BY 1,2,3;
CREATE OR REPLACE VIEW analytics.onboarding AS
WITH per_install AS (
 SELECT i.install_id, (i.first_seen AT TIME ZONE 'UTC')::date AS cohort_day,
 count(DISTINCT e.payload->>'round_id') FILTER(WHERE e.name='round_started') AS rounds_started,
 bool_or(e.name='round_finished' AND e.payload->>'outcome'='win') AS had_win
 FROM installations i LEFT JOIN events e ON e.install_id=i.install_id AND e.environment='production'
 WHERE i.environment='production' AND (i.first_seen AT TIME ZONE 'UTC')::date >= CURRENT_DATE-89
 GROUP BY 1,2
)
SELECT cohort_day,count(*) AS observed_installations,
 count(*) FILTER(WHERE rounds_started>=1) AS started_first_round,
 count(*) FILTER(WHERE had_win) AS won_a_round,
 count(*) FILTER(WHERE rounds_started>=10) AS started_ten_rounds
FROM per_install GROUP BY 1;
CREATE OR REPLACE VIEW analytics.ad_delivery AS
SELECT (occurred_at AT TIME ZONE 'UTC')::date AS day,
 count(*) FILTER(WHERE name='ad_requested') AS requests,
 count(*) FILTER(WHERE name='ad_loaded') AS loads,
 count(*) FILTER(WHERE name='ad_failed') AS failures,
 count(*) FILTER(WHERE name='ad_impression') AS impressions,
 count(*) FILTER(WHERE name='ad_closed') AS closes
FROM events WHERE environment='production' AND payload->>'test_ad'='false'
 AND name IN ('ad_requested','ad_loaded','ad_failed','ad_impression','ad_closed')
GROUP BY 1;
CREATE OR REPLACE VIEW analytics.monetization AS
WITH daily_revenue AS (
 SELECT day,currency,sum(revenue) AS revenue FROM analytics.ad_revenue GROUP BY 1,2
)
SELECT r.day,r.currency,r.revenue,a.dau,d.impressions,
 r.revenue/NULLIF(a.dau,0) AS arpdau,
 -- An eCPM is only comparable when the day's revenue has a single currency.
 CASE WHEN (SELECT count(*) FROM daily_revenue x WHERE x.day=r.day)=1
 THEN 1000*r.revenue/NULLIF(d.impressions,0) END AS ecpm
FROM daily_revenue r LEFT JOIN analytics.audience a ON a.day=r.day
LEFT JOIN analytics.ad_delivery d ON d.day=r.day;
-- QA reports can inspect test events without access to the underlying raw table.
CREATE OR REPLACE VIEW analytics.qa_events AS
SELECT event_id, install_id, session_id, occurred_at, received_at,
       build_version, platform, environment, name, payload
FROM public.events WHERE environment='test';
GRANT USAGE ON SCHEMA public TO telemetry_api;
GRANT SELECT,INSERT ON events TO telemetry_api;
GRANT SELECT,INSERT,UPDATE ON installations TO telemetry_api;
GRANT USAGE ON SCHEMA analytics TO analytics_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO analytics_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA analytics GRANT SELECT ON TABLES TO analytics_reader;
ALTER ROLE analytics_reader SET statement_timeout='30s';
ALTER ROLE analytics_reader SET default_transaction_read_only=on;
COMMIT;
