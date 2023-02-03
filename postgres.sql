-- Connections by user 
select
    now() as date,
    usename as user,
    sum(cast(case when state<>'active' then 1 else 0 end as integer)) as sleeping,
    sum(cast(case when state='active' then 1 else 0 end as integer)) as active,
    sum(cast(case when state='active' and now() - query_start > '1 seconds'::interval then 1 else 0 end as integer)) as slow
from pg_stat_activity
group by usename;

-- Connections by user, ip
select
    now() as date,
    usename as user,
    client_addr as address,
    sum(cast(case when state<>'active' then 1 else 0 end as integer)) as sleeping,
    sum(cast(case when state='active' then 1 else 0 end as integer)) as active,
    sum(cast(case when state='active' and now() - query_start > '1 seconds'::interval then 1 else 0 end as integer)) as slow
from pg_stat_activity
group by usename, client_addr;

-- Show running queries
SELECT pid, age(clock_timestamp(), query_start), usename, query 
FROM pg_stat_activity 
WHERE query != '<IDLE>' AND query NOT ILIKE '%pg_stat_activity%' 
ORDER BY query_start desc;

-- Slow queries
SELECT now() - query_start as "runtime", usename, datname, waiting, state, query
  FROM  pg_stat_activity
  WHERE now() - query_start > '2 minutes'::interval
 ORDER BY runtime DESC;

 -- Waiting queries
 SELECT wait_event || ':' || wait_event_type AS type, count(*) AS number_of_occurences
  FROM pg_stat_activity
 WHERE state != 'idle'
GROUP BY wait_event, wait_event_type
ORDER BY number_of_occurences DESC;

-- List all activity
SELECT * FROM pg_stat_activity;

-- Queries per second
SELECT sum(numbackends) AS active_connections,
       sum(xact_commit) AS transactions,
       sum(xact_rollback) AS rollbacks,
       sum(blks_read) AS blocks_read,
       sum(blks_hit) AS blocks_hit,
       sum(tup_returned) AS rows_returned,
       sum(tup_fetched) AS rows_fetched,
       sum(tup_inserted) AS rows_inserted,
       sum(tup_updated) AS rows_updated,
       sum(tup_deleted) AS rows_deleted,
       sum(conflicts) AS conflicts,
       (sum(tup_returned) + sum(tup_fetched) + sum(tup_inserted) + sum(tup_updated) + sum(tup_deleted)) / extract(epoch from now() - pg_postmaster_start_time()) AS queries_per_second
FROM pg_stat_database;

-- cache hit rates (should not be less than 0.99)
SELECT sum(heap_blks_read) as heap_read, sum(heap_blks_hit)  as heap_hit, (sum(heap_blks_hit) - sum(heap_blks_read)) / sum(heap_blks_hit) as ratio
FROM pg_statio_user_tables;

-- Table index usage rates (should not be less than 0.99)
SELECT relname, 100 * idx_scan / (seq_scan + idx_scan) percent_of_times_index_used, n_live_tup rows_in_table
FROM pg_stat_user_tables 
ORDER BY n_live_tup DESC;

-- How many indexes are in cache
SELECT sum(idx_blks_read) as idx_read, sum(idx_blks_hit)  as idx_hit, (sum(idx_blks_hit) - sum(idx_blks_read)) / sum(idx_blks_hit) as ratio
FROM pg_statio_user_indexes;

-- Locks
 SELECT t.relname, l.locktype, page, virtualtransaction, pid, mode, granted 
FROM pg_locks l, pg_stat_all_tables t 
WHERE l.relation = t.relid ORDER BY relation asc;

-- Locking query
select pid, 
       usename, 
       pg_blocking_pids(pid) as blocked_by, 
       query as blocked_query
from pg_stat_activity
where cardinality(pg_blocking_pids(pid)) > 0;

-- Another locking query view
SELECT blocked_locks.pid     AS blocked_pid,
  blocked_activity.usename  AS blocked_user,
  blocking_locks.pid     AS blocking_pid,
  blocking_activity.usename AS blocking_user,
  blocked_activity.query    AS blocked_statement,
  blocking_activity.query   AS current_statement_in_blocking_process
FROM  pg_catalog.pg_locks         blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity  ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks         blocking_locks 
  ON blocking_locks.locktype = blocked_locks.locktype
  AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
  AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
  AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
  AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
  AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
  AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
  AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
  AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
  AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
  AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.GRANTED;

-- find tables with missing indexes
SELECT
    relname as table,
    pg_size_pretty(pg_relation_size(relid::regclass)) AS size,
    seq_scan as sequential_scans,
    idx_scan as index_scans,
    seq_scan - idx_scan AS difference,
    CASE WHEN seq_scan - idx_scan > 0 THEN
        'Missing Index?'
    ELSE
        'OK'
    END AS status
FROM
    pg_stat_all_tables
WHERE
    schemaname = 'public'
    AND pg_relation_size(relid::regclass) > 80000
ORDER BY
    difference DESC;

-- Find tables with unused indexes
SELECT
    schemaname AS schemaname,
    relname AS tablename,
    indexrelname AS indexname,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS size,
    idx_scan AS indexscans
FROM
    pg_stat_user_indexes ui
INNER JOIN pg_index i ON ui.indexrelid = i.indexrelid
WHERE
    NOT indisunique
    AND idx_scan <= 50
ORDER BY
    pg_relation_size(i.indexrelid) DESC,
    relname ASC;

-- All tables and their size
SELECT
  schema_name,
  relname,
  pg_size_pretty(table_size) AS size,
  table_size

FROM (
       SELECT
         pg_catalog.pg_namespace.nspname           AS schema_name,
         relname,
         pg_relation_size(pg_catalog.pg_class.oid) AS table_size

       FROM pg_catalog.pg_class
         JOIN pg_catalog.pg_namespace ON relnamespace = pg_catalog.pg_namespace.oid
     ) t
WHERE schema_name NOT LIKE 'pg_%'
ORDER BY table_size DESC;

-- Size of table on disk
SELECT nspname || '.' || relname AS "relation",
   pg_size_pretty(pg_total_relation_size(C.oid)) AS "total_size"
 FROM pg_class C
 LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
 WHERE nspname NOT IN ('pg_catalog', 'information_schema')
   AND C.relkind <> 'i'
   AND nspname !~ '^pg_toast'
 ORDER BY pg_total_relation_size(C.oid) DESC;
 
-- List all indexes
SELECT
    schemaname AS schemaname,
    t.relname AS tablename,
    ix.relname AS indexname,
    regexp_replace(pg_get_indexdef(i.indexrelid), '^[^\(]*\((.*)\)$', '\1') AS columns,
    regexp_replace(pg_get_indexdef(i.indexrelid), '.* USING ([^ ]*) \(.*', '\1') AS algorithm,
    indisunique AS UNIQUE,
    indisprimary AS PRIMARY,
    indisvalid AS valid,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS size,
    idx_scan AS indexscans,
    idx_tup_read AS tuplereads,
    idx_tup_fetch AS tuplefetches,
    pg_get_indexdef(i.indexrelid) AS definition
FROM
    pg_index i
    INNER JOIN pg_class t ON t.oid = i.indrelid
    INNER JOIN pg_class ix ON ix.oid = i.indexrelid
    LEFT JOIN pg_stat_user_indexes ui ON ui.indexrelid = i.indexrelid
WHERE
    schemaname IS NOT NULL
ORDER BY
    schemaname ASC,
    tablename ASC,
    indexname ASC;

SELECT * FROM pg_stat_user_indexes;

-- View number of dead tuples
SELECT
    relname AS TableName,
    n_live_tup AS LiveTuples,
    n_dead_tup AS DeadTuples,
    last_autovacuum AS Autovacuum,
    last_autoanalyze AS Autoanalyze
FROM pg_stat_user_tables
order by n_dead_tup desc;

-- Last time autovacuum ran
SELECT 
    relname, 
    last_autovacuum,
    last_autoanalyze
FROM pg_stat_user_tables
ORDER BY last_autovacuum desc;

-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
-- CREATE EXTENSION IF NOT EXISTS pg_stat_monitor;
-- GRANT EXECUTE ON FUNCTION pg_stat_statements_reset(oid, oid, bigint) TO youruser;
-- GRANT EXECUTE ON FUNCTION SELECT pg_stat_reset() TO youruser;

-- Flush statistics
SELECT pg_stat_statements_reset();

-- Top queries
SELECT
	userid::regrole, 
	dbid, 
	SUM(calls) AS total,
	query
FROM pg_stat_statements
GROUP BY userid::regrole, dbid, query
ORDER BY 3 DESC
LIMIT 10;

-- Top CPU queries
SELECT
	userid::regrole,
	dbid,
	query
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;

-- Top IO queries
SELECT
	userid::regrole, 
	dbid, 
	query
FROM pg_stat_statements
ORDER BY (blk_read_time+blk_write_time)/calls DESC
LIMIT 10;

-- Top memory queries
SELECT
	userid::regrole, 
	dbid, 
	query
FROM pg_stat_statements
ORDER BY (shared_blks_hit+shared_blks_dirtied) DESC
LIMIT 10;

-- Show current configuration
SHOW ALL;

-- Show file configuration
SELECT * FROM pg_file_settings;

-- Show max connections
SHOW max_connections;

-- Show shared buffers 25%
SHOW shared_buffers;

-- Show temp buffers for sessions
SHOW temp_buffers;

-- Show working memory for queries
SHOW work_mem;

-- Show working memory for maintenance queries
SHOW maintenance_work_mem;

-- List schemas
SELECT schema_name FROM information_schema.schemata;

-- Kill running query
SELECT pg_cancel_backend(procpid);

-- Kill idle query
SELECT pg_terminate_backend(procpid);

-- Vacuum command
VACUUM (VERBOSE, ANALYZE);

-- Describe table
SELECT
   table_name, 
   column_name, 
   data_type 
FROM 
   information_schema.columns
WHERE table_name = '_cs_incident';

-- All database users
select * from pg_stat_activity where current_query not like '<%';

-- All databases and their sizes
select * from pg_user;

## access the PostgreSQL database server:
psql -U [username]

## Dump database on remote host to file
pg_dump -U username -h hostname databasename > dump.sql

## Import dump into existing database
psql -d newdb -f dump.sql

-- Connect to a specific database:
\c database_name;

-- List all databases in the PostgreSQL database server
\l

-- List all schemas:
\dn

-- List all stored procedures and functions:
\df

-- List all views:
\dv
select table_name from INFORMATION_SCHEMA.views;

-- Describe view
\dS+ table_name;

-- Lists all tables in a current database.
\dt+
SELECT *
FROM information_schema.tables
WHERE table_schema<>'pg_catalog'

-- Get detailed information on a table.
\d+ table_name
SELECT *
FROM information_schema.columns 
WHERE table_name = 'your_table';

-- List tables in schema
\dt schema.

-- Get current server character set
SELECT character_set_name 
FROM information_schema.character_sets;

-- Show a stored procedure or function code:
\df+ function_name

-- Show query output in the pretty-format:
\x

-- List all users:
\du

-- List extensions
\dx

-- Create database with user
CREATE DATABASE yourdbname;
CREATE USER youruser WITH ENCRYPTED PASSWORD 'yourpass';
GRANT ALL PRIVILEGES ON DATABASE yourdbname TO youruser;
ALTER DATABASE yourdbname OWNER TO youruser;

-- Create super user
ALTER ROLE youruser SUPERUSER;

-- Update user password
ALTER USER <username> WITH PASSWORD 'new_password';

-- Create a new role:
CREATE ROLE role_name;

-- Create a new role with a username and password:
CREATE ROLE username NOINHERIT LOGIN PASSWORD password;

-- Change role for the current session to the new_role:
SET ROLE new_role;

-- Allow role_1 to set its role as role_2:
GRANT role_2 TO role_1;

-- Drop all tables in public schema
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO public;
ALTER SCHEMA public OWNER to postgres;
