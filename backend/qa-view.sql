-- Additive migration for existing deployments; production views are unchanged.
BEGIN;
CREATE OR REPLACE VIEW analytics.qa_events AS
SELECT event_id, install_id, session_id, occurred_at, received_at,
       build_version, platform, environment, name, payload
FROM public.events WHERE environment='test';
GRANT SELECT ON analytics.qa_events TO analytics_reader;
COMMIT;
