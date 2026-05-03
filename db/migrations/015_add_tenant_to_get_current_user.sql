CREATE TYPE api.user_with_tenant AS (
    id                UUID,
    email             TEXT,
    role              TEXT,
    created_at        TIMESTAMPTZ,
    updated_at        TIMESTAMPTZ,
    tenant_id         UUID,
    tenant_name       TEXT,
    tenant_subdomain  TEXT
);

ALTER TYPE api.user_with_tenant OWNER TO izvor_admin;


DROP FUNCTION api.get_current_user();
DROP FUNCTION spec.get_current_user();


-- Cross-ATP read: joins impl.users (tenant plane, under RLS) with
-- system_impl.tenants (control plane, no RLS). Second legitimate cross-ATP
-- function after system_api.create_tenant_with_admin from Phase 7.0; both
-- are control-plane-aware tenant operations executed under SECURITY DEFINER.
CREATE FUNCTION spec.get_current_user()
RETURNS SETOF api.user_with_tenant
LANGUAGE sql
STABLE
AS $$
    SELECT
        u.id,
        u.email,
        u.role::text,
        u.created_at,
        u.updated_at,
        t.id,
        t.name,
        t.subdomain
    FROM impl.users u
    JOIN system_impl.tenants t ON t.id = u.tenant_id
    WHERE u.id = app.current_user_id() AND u.is_active = true;
$$;

ALTER FUNCTION spec.get_current_user() OWNER TO izvor_admin;


CREATE FUNCTION api.get_current_user()
RETURNS SETOF api.user_with_tenant
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.get_current_user();
$$;

ALTER FUNCTION api.get_current_user() OWNER TO izvor_admin;
