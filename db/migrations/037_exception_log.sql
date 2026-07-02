-- Control-plane exception log (chapter 4.5 Праћење): the exception trace lives in
-- the data layer as the single source of truth. No RLS — an exception can fire
-- before tenant context is set (tenant resolution failure, unauthenticated request),
-- and a fail-closed table would reject exactly the writes that matter most.
-- tenant_id / user_id are nullable diagnostic values, not referential links: the log
-- must record failures even when those ids don't resolve to live rows, and a
-- control-plane table with hard FKs to tenant-plane rows would be wrong-plane coupling.
-- Append-only event log: no updated_at, no set_updated_at trigger.

CREATE TABLE system_impl.exception_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    pg_code         TEXT NOT NULL,
    message         TEXT NOT NULL,
    constraint_name TEXT,
    detail          TEXT,
    http_method     TEXT NOT NULL,
    path            TEXT NOT NULL,
    http_status     INT NOT NULL,
    tenant_id       UUID,
    user_id         UUID
);


CREATE FUNCTION system_spec.log_exception(
    p_pg_code         TEXT,
    p_message         TEXT,
    p_constraint_name TEXT,
    p_detail          TEXT,
    p_http_method     TEXT,
    p_path            TEXT,
    p_http_status     INT,
    p_tenant_id       UUID,
    p_user_id         UUID
) RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO system_impl.exception_log (
        pg_code, message, constraint_name, detail,
        http_method, path, http_status, tenant_id, user_id
    )
    VALUES (
        p_pg_code, p_message, p_constraint_name, p_detail,
        p_http_method, p_path, p_http_status, p_tenant_id, p_user_id
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;


-- EXECUTE inherited by izvor_app via ALTER DEFAULT PRIVILEGES in 00_init (schema
-- system_api); no explicit GRANT, matching every other system_api function.
CREATE FUNCTION system_api.log_exception(
    p_pg_code         TEXT,
    p_message         TEXT,
    p_constraint_name TEXT,
    p_detail          TEXT,
    p_http_method     TEXT,
    p_path            TEXT,
    p_http_status     INT,
    p_tenant_id       UUID,
    p_user_id         UUID
) RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'system_api', 'system_spec', 'system_impl', 'app', 'pg_temp'
AS $$
    SELECT system_spec.log_exception(
        p_pg_code, p_message, p_constraint_name, p_detail,
        p_http_method, p_path, p_http_status, p_tenant_id, p_user_id
    );
$$;
