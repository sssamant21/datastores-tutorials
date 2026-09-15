/*
 PostgreSQL Practical Tutorial
 Part 1.4 — Connection Validation

 Classification: [SAFE-READ]

 Purpose:
 Validate the PostgreSQL server and connection identity.

 Safety:
 - This file is intended to remain read-only.
 - Do not add credentials.
 - Review the connection target before execution.
 - Treat returned infrastructure metadata as potentially sensitive.
*/

SELECT version() AS server_version;

SELECT
    current_database() AS database_name,
    session_user AS session_user,
    current_user AS effective_role,
    inet_server_addr() AS server_address,
    inet_server_port() AS server_port,
    pg_backend_pid() AS backend_pid;

SHOW data_directory;
SHOW config_file;
SHOW hba_file;
SHOW port;
