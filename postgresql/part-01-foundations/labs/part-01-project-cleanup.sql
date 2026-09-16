-- ============================================================
-- [DESTRUCTIVE — LAB CLEANUP ONLY]
-- PostgreSQL Part 1 — Hands-On Project Cleanup
-- Target: PostgreSQL 18
--
-- WARNING:
--   THIS SCRIPT PERMANENTLY REMOVES THE PART 1 LAB.
--
-- TARGETS:
--   Database: healthcare_lab
--   Roles: healthcare_app, healthcare_readonly, healthcare_owner
--
-- DO NOT RUN against production, valuable data, or objects that
-- do not belong to this tutorial. Run from a database other than
-- healthcare_lab, normally postgres.
--
-- This script does NOT automatically terminate sessions.
-- ============================================================

\set ON_ERROR_STOP on

\echo '============================================================'
\echo 'WARNING - DESTRUCTIVE PART 1 LAB CLEANUP'
\echo '============================================================'

SELECT current_database(), current_user;

SELECT datname, pg_get_userbyid(datdba) AS database_owner
FROM pg_database
WHERE datname = 'healthcare_lab';

SELECT rolname, rolcanlogin, rolsuper
FROM pg_roles
WHERE rolname IN ('healthcare_owner','healthcare_app','healthcare_readonly')
ORDER BY rolname;

\echo 'STOP HERE if these objects do not belong to this tutorial.'
\prompt 'Type DELETE-POSTGRESQL-PART-01-LAB to continue: ' cleanup_confirm

\if :'cleanup_confirm' = 'DELETE-POSTGRESQL-PART-01-LAB'
    \echo 'Cleanup confirmed.'
\else
    \echo 'Cleanup cancelled - confirmation did not match.'
    \quit
\endif

SELECT current_database() <> 'healthcare_lab' AS safe_connection
\gset

\if :safe_connection
    \echo 'Connection guard PASS.'
\else
    \echo 'FAIL - connect to postgres or another database first.'
    \quit
\endif

DROP DATABASE healthcare_lab;
DROP ROLE healthcare_app;
DROP ROLE healthcare_readonly;
DROP ROLE healthcare_owner;

\echo '============================================================'
\echo 'Part 1 lab cleanup complete.'
\echo '============================================================'
