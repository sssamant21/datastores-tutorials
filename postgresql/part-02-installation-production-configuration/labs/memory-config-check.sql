-- Part 2.8 — Memory and Resource Configuration
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
\set ON_ERROR_STOP on
\pset pager off

SELECT current_setting('server_version') AS server_version;

SELECT name, setting, unit, context, source, pending_restart
FROM pg_settings
WHERE name IN (
  'shared_buffers','work_mem','maintenance_work_mem','autovacuum_work_mem',
  'temp_buffers','huge_pages','effective_cache_size','max_connections',
  'max_worker_processes','max_parallel_workers','max_parallel_workers_per_gather'
)
ORDER BY name;

SELECT count(*) AS current_connections FROM pg_stat_activity;
