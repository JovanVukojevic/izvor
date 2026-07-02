-- === Procedures: Tenants ===


CREATE FUNCTION system_spec.create_tenant(p_name text, p_code text, p_subdomain text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID;
BEGIN
    IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
        RAISE EXCEPTION 'Tenant name is required';
    END IF;
    IF p_code IS NULL OR length(trim(p_code)) = 0 THEN
        RAISE EXCEPTION 'Tenant code is required';
    END IF;
    IF p_subdomain IS NULL OR length(trim(p_subdomain)) = 0 THEN
        RAISE EXCEPTION 'Tenant subdomain is required';
    END IF;

    INSERT INTO system_impl.tenants (name, code, subdomain)
    VALUES (trim(p_name), trim(p_code), trim(p_subdomain))
    RETURNING id INTO v_id;

    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        IF SQLERRM LIKE '%tenants_code_key%' THEN
            RAISE EXCEPTION 'Tenant with code % already exists', p_code;
        ELSIF SQLERRM LIKE '%tenants_subdomain_key%' THEN
            RAISE EXCEPTION 'Tenant with subdomain % already exists', p_subdomain;
        END IF;
        RAISE;
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid tenant data: %', SQLERRM;
END;
$$;


CREATE FUNCTION system_spec.get_tenant_by_subdomain(p_subdomain text) RETURNS SETOF system_impl.tenants
    LANGUAGE sql STABLE
    AS $$
    SELECT * FROM system_impl.tenants WHERE subdomain = trim(p_subdomain);
$$;


CREATE FUNCTION system_spec.list_tenants() RETURNS SETOF system_impl.tenants
    LANGUAGE sql STABLE
    AS $$
    SELECT * FROM system_impl.tenants ORDER BY created_at DESC;
$$;


CREATE FUNCTION system_spec.suspend_tenant(p_tenant_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_status system_impl.tenant_status;
BEGIN
    SELECT status INTO v_status
    FROM system_impl.tenants
    WHERE id = p_tenant_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tenant % not found', p_tenant_id;
    END IF;

    IF v_status = 'suspended' THEN
        RAISE EXCEPTION 'Tenant % is already suspended', p_tenant_id;
    END IF;

    UPDATE system_impl.tenants
    SET status = 'suspended'
    WHERE id = p_tenant_id;
END;
$$;


CREATE FUNCTION system_spec.resume_tenant(p_tenant_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_status system_impl.tenant_status;
BEGIN
    SELECT status INTO v_status
    FROM system_impl.tenants
    WHERE id = p_tenant_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tenant % not found', p_tenant_id;
    END IF;

    IF v_status = 'active' THEN
        RAISE EXCEPTION 'Tenant % is already active', p_tenant_id;
    END IF;

    UPDATE system_impl.tenants
    SET status = 'active'
    WHERE id = p_tenant_id;
END;
$$;

-- === Procedures: Exception Log ===


CREATE FUNCTION system_spec.log_exception(p_pg_code text, p_message text, p_constraint_name text, p_detail text, p_http_method text, p_path text, p_http_status integer, p_tenant_id uuid, p_user_id uuid) RETURNS uuid
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
