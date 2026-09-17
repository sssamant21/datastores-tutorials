/*
 Part 2.10 — WAL and Checkpoint Configuration
 [TUTORIAL-ACCEPTANCE — SAFE-READ]
 Target: PostgreSQL 18

 No DDL/DML; no SET/ALTER SYSTEM; no statistics reset; no CHECKPOINT;
 no slot/archive changes; no WAL manipulation; no reload/restart.
 Archive/replication output is operationally sensitive.
*/
\echo '=== Part 2.10 — WAL and Checkpoint Configuration — SAFE-READ ==='

\echo '--- Server identity ---'
SELECT current_database() AS database_name,
       current_user AS current_user,
       version() AS server_version;

\echo '--- WAL / durability / checkpoint configuration ---'
SELECT name,setting,unit,context,source
FROM pg_settings
WHERE name IN (
 'fsync','synchronous_commit','wal_level','wal_buffers','wal_compression',
 'wal_writer_delay','wal_writer_flush_after','wal_segment_size',
 'full_page_writes','checkpoint_timeout','checkpoint_completion_target',
 'checkpoint_flush_after','checkpoint_warning','max_wal_size','min_wal_size',
 'wal_keep_size','max_slot_wal_keep_size','archive_mode'
)
ORDER BY name;

\echo '--- Current WAL LSN ---'
SELECT pg_current_wal_lsn() AS current_wal_lsn;

\echo '--- PostgreSQL 18 WAL generation statistics ---'
SELECT wal_records,wal_fpi,wal_bytes,wal_buffers_full,stats_reset
FROM pg_stat_wal;

\echo '--- PostgreSQL 18 checkpointer statistics ---'
SELECT num_timed,num_requested,num_done,
       restartpoints_timed,restartpoints_req,restartpoints_done,
       write_time,sync_time,buffers_written,slru_written,stats_reset
FROM pg_stat_checkpointer;

\echo '--- Archive statistics: operationally sensitive ---'
SELECT archived_count,last_archived_wal,last_archived_time,
       failed_count,last_failed_wal,last_failed_time,stats_reset
FROM pg_stat_archiver;

\echo '--- Replication slots: operationally sensitive ---'
SELECT slot_name,slot_type,active,restart_lsn,confirmed_flush_lsn,
       wal_status,safe_wal_size
FROM pg_replication_slots
ORDER BY slot_name;

\echo '=== SAFE-READ COMPLETE: no PostgreSQL state was intentionally changed ==='
