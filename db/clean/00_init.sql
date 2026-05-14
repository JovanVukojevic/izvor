-- ============================================================
-- Izvor — database bootstrap
-- Runs once on first container startup (empty pgdata volume).
-- Executed as the POSTGRES_USER superuser, inside the `izvor` database.
--
-- Role passwords below are intentionally hardcoded as dev-only
-- values. This database runs locally (bound to localhost via
-- Docker) and is not exposed beyond the developer's machine.
-- These strings are not secrets — they are identical for every
-- clone of this repo and are part of the bootstrap contract.
--
-- Production deployment (out of scope — see diplomski-plan
-- section 15) would replace this with managed secrets and role
-- creation handled outside of source-controlled SQL.
-- ============================================================


-- === Extensions ===

CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- === Schemas ===

CREATE SCHEMA app;

CREATE SCHEMA impl;
CREATE SCHEMA spec;
CREATE SCHEMA api;

CREATE SCHEMA system_impl;
CREATE SCHEMA system_spec;
CREATE SCHEMA system_api;


-- === Roles ===

CREATE ROLE izvor_admin LOGIN PASSWORD 'izvor_admin_dev';
CREATE ROLE izvor_app   LOGIN PASSWORD 'izvor_app_dev';


-- === Grants: izvor_admin ===

GRANT CONNECT ON DATABASE izvor TO izvor_admin;

GRANT ALL ON SCHEMA app,
                    impl, spec, api,
                    system_impl, system_spec, system_api
          TO izvor_admin;


-- === Grants: izvor_app ===

GRANT CONNECT ON DATABASE izvor TO izvor_app;

GRANT USAGE ON SCHEMA app        TO izvor_app;
GRANT USAGE ON SCHEMA api        TO izvor_app;
GRANT USAGE ON SCHEMA system_api TO izvor_app;


-- === Default Privileges ===

ALTER DEFAULT PRIVILEGES FOR ROLE izvor_admin IN SCHEMA api
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO izvor_app;
ALTER DEFAULT PRIVILEGES FOR ROLE izvor_admin IN SCHEMA api
    GRANT EXECUTE                        ON FUNCTIONS TO izvor_app;
ALTER DEFAULT PRIVILEGES FOR ROLE izvor_admin IN SCHEMA api
    GRANT USAGE, SELECT                  ON SEQUENCES TO izvor_app;

ALTER DEFAULT PRIVILEGES FOR ROLE izvor_admin IN SCHEMA system_api
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO izvor_app;
ALTER DEFAULT PRIVILEGES FOR ROLE izvor_admin IN SCHEMA system_api
    GRANT EXECUTE                        ON FUNCTIONS TO izvor_app;
ALTER DEFAULT PRIVILEGES FOR ROLE izvor_admin IN SCHEMA system_api
    GRANT USAGE, SELECT                  ON SEQUENCES TO izvor_app;

ALTER DEFAULT PRIVILEGES FOR ROLE izvor_admin IN SCHEMA app
    GRANT EXECUTE ON FUNCTIONS TO izvor_app;


-- === Session-Context Helpers ===

CREATE OR REPLACE FUNCTION app.current_tenant()
RETURNS uuid
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    raw_value text;
BEGIN
    raw_value := current_setting('app.current_tenant', true);
    IF raw_value IS NULL OR raw_value = '' THEN
        RAISE EXCEPTION
            'app.current_tenant is not set — refusing to proceed'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN raw_value::uuid;
END
$$;

CREATE OR REPLACE FUNCTION app.current_user_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    raw_value text;
BEGIN
    raw_value := current_setting('app.current_user', true);
    IF raw_value IS NULL OR raw_value = '' THEN
        RAISE EXCEPTION
            'app.current_user is not set — refusing to proceed'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN raw_value::uuid;
END
$$;


-- === Ownership ===

ALTER SCHEMA app          OWNER TO izvor_admin;
ALTER SCHEMA impl         OWNER TO izvor_admin;
ALTER SCHEMA spec         OWNER TO izvor_admin;
ALTER SCHEMA api          OWNER TO izvor_admin;
ALTER SCHEMA system_impl  OWNER TO izvor_admin;
ALTER SCHEMA system_spec  OWNER TO izvor_admin;
ALTER SCHEMA system_api   OWNER TO izvor_admin;

ALTER FUNCTION app.current_tenant()   OWNER TO izvor_admin;
ALTER FUNCTION app.current_user_id()  OWNER TO izvor_admin;
