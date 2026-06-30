-- === Composite Types ===


CREATE TYPE system_api.tenant AS (
	id uuid,
	name text,
	code text,
	subdomain text,
	status text,
	created_at timestamp with time zone,
	updated_at timestamp with time zone
);


CREATE TYPE system_api.tenant_with_admin AS (
	tenant_id uuid,
	tenant_code text,
	subdomain text,
	admin_user_id uuid,
	admin_email text
);

-- === Wrappers: Tenants ===


CREATE FUNCTION system_api.create_tenant(p_name text, p_code text, p_subdomain text) RETURNS uuid
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'system_api', 'system_spec', 'system_impl', 'app', 'pg_temp'
    AS $$
    SELECT system_spec.create_tenant(p_name, p_code, p_subdomain);
$$;


CREATE FUNCTION system_api.get_tenant_by_subdomain(p_subdomain text) RETURNS SETOF system_api.tenant
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'system_api', 'system_spec', 'system_impl', 'app', 'pg_temp'
    AS $$
    SELECT id, name, code, subdomain, status::text, created_at, updated_at
    FROM system_spec.get_tenant_by_subdomain(p_subdomain);
$$;


CREATE FUNCTION system_api.list_tenants() RETURNS SETOF system_api.tenant
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'system_api', 'system_spec', 'system_impl', 'app', 'pg_temp'
    AS $$
    SELECT id, name, code, subdomain, status::text, created_at, updated_at
    FROM system_spec.list_tenants();
$$;


CREATE FUNCTION system_api.suspend_tenant(p_tenant_id uuid) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'system_api', 'system_spec', 'system_impl', 'app', 'pg_temp'
    AS $$
    SELECT system_spec.suspend_tenant(p_tenant_id);
$$;


CREATE FUNCTION system_api.resume_tenant(p_tenant_id uuid) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'system_api', 'system_spec', 'system_impl', 'app', 'pg_temp'
    AS $$
    SELECT system_spec.resume_tenant(p_tenant_id);
$$;


CREATE FUNCTION system_api.create_tenant_with_admin(p_tenant_name text, p_tenant_code text, p_subdomain text, p_admin_email text, p_admin_password_hash text) RETURNS system_api.tenant_with_admin
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'system_api', 'system_spec', 'system_impl', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
DECLARE
    v_tenant_id UUID;
    v_admin_id  UUID;
    v_result    system_api.tenant_with_admin;
BEGIN
    v_tenant_id := system_spec.create_tenant(p_tenant_name, p_tenant_code, p_subdomain);

    PERFORM set_config('app.current_tenant', v_tenant_id::text, true);

    INSERT INTO impl.roles (tenant_id, code, description, rank) VALUES
        (v_tenant_id, 'admin',   'Full administrative access within the organization', 100),
        (v_tenant_id, 'author',  'Can create and manage course content',                50),
        (v_tenant_id, 'learner', 'Can browse and complete courses',                     10);

    v_admin_id := spec.create_user_internal(p_admin_email, p_admin_password_hash, 'admin');

    v_result := (v_tenant_id, p_tenant_code, p_subdomain, v_admin_id, p_admin_email);
    RETURN v_result;
END;
$$;
