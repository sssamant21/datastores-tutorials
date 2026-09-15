/*
 PostgreSQL Practical Tutorial
 Part 1.5 — Object Hierarchy Validation

 Classification: [SAFE-READ]

 Purpose:
 Validate database context and inspect schemas,
 tables, and columns used by the tutorial.

 Safety:
 - Read-only.
 - Contains no credentials.
 - Returned metadata can be sensitive outside
   the tutorial environment.
 - Results reflect the current database and
   current access/visibility context.
*/

SELECT
    current_database() AS database_name,
    session_user AS session_user,
    current_user AS effective_role;

SHOW search_path;

SELECT current_schemas(true) AS effective_search_path;

SELECT
    schema_name
FROM information_schema.schemata
WHERE schema_name IN ('clinical', 'archive', 'public')
ORDER BY schema_name;

SELECT
    table_schema,
    table_name,
    table_type
FROM information_schema.tables
WHERE table_schema IN ('clinical', 'archive')
ORDER BY
    table_schema,
    table_name;

SELECT
    table_schema,
    table_name,
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema IN ('clinical', 'archive')
ORDER BY
    table_schema,
    table_name,
    ordinal_position;
