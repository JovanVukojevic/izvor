DROP FUNCTION system_spec.get_tenant_by_subdomain(TEXT);

CREATE FUNCTION system_spec.get_tenant_by_subdomain(p_subdomain TEXT)
RETURNS SETOF system_impl.tenants
LANGUAGE sql
STABLE
AS $$
    SELECT * FROM system_impl.tenants WHERE subdomain = trim(p_subdomain);
$$;

ALTER FUNCTION system_spec.get_tenant_by_subdomain(TEXT) OWNER TO izvor_admin;


CREATE TYPE system_api.tenant AS (
    id          UUID,
    name        TEXT,
    code        TEXT,
    subdomain   TEXT,
    status      TEXT,
    created_at  TIMESTAMPTZ,
    updated_at  TIMESTAMPTZ
);

ALTER TYPE system_api.tenant OWNER TO izvor_admin;


CREATE FUNCTION system_api.create_tenant(
    p_name      TEXT,
    p_code      TEXT,
    p_subdomain TEXT
)
RETURNS UUID
LANGUAGE sql
AS $$
    SELECT system_spec.create_tenant(p_name, p_code, p_subdomain);
$$;

ALTER FUNCTION system_api.create_tenant(TEXT, TEXT, TEXT) OWNER TO izvor_admin;


CREATE FUNCTION system_api.suspend_tenant(p_tenant_id UUID)
RETURNS VOID
LANGUAGE sql
AS $$
    SELECT system_spec.suspend_tenant(p_tenant_id);
$$;

ALTER FUNCTION system_api.suspend_tenant(UUID) OWNER TO izvor_admin;


CREATE FUNCTION system_api.resume_tenant(p_tenant_id UUID)
RETURNS VOID
LANGUAGE sql
AS $$
    SELECT system_spec.resume_tenant(p_tenant_id);
$$;

ALTER FUNCTION system_api.resume_tenant(UUID) OWNER TO izvor_admin;


CREATE FUNCTION system_api.get_tenant_by_subdomain(p_subdomain TEXT)
RETURNS SETOF system_api.tenant
LANGUAGE sql
STABLE
AS $$
    SELECT id, name, code, subdomain, status::text, created_at, updated_at
    FROM system_spec.get_tenant_by_subdomain(p_subdomain);
$$;

ALTER FUNCTION system_api.get_tenant_by_subdomain(TEXT) OWNER TO izvor_admin;


CREATE FUNCTION system_api.list_tenants()
RETURNS SETOF system_api.tenant
LANGUAGE sql
STABLE
AS $$
    SELECT id, name, code, subdomain, status::text, created_at, updated_at
    FROM system_spec.list_tenants();
$$;

ALTER FUNCTION system_api.list_tenants() OWNER TO izvor_admin;
