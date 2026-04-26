ALTER TABLE impl.users ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT true;


CREATE FUNCTION spec.get_current_role()
RETURNS impl.user_role
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_role impl.user_role;
BEGIN
    SELECT role INTO v_role
    FROM impl.users
    WHERE id = app.current_user_id() AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'no_active_user_in_session'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    RETURN v_role;
END;
$$;

ALTER FUNCTION spec.get_current_role() OWNER TO izvor_admin;


CREATE FUNCTION spec.assert_role(min_role impl.user_role)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_current impl.user_role;
BEGIN
    v_current := spec.get_current_role();

    IF array_position(enum_range(NULL::impl.user_role), v_current)
       <= array_position(enum_range(NULL::impl.user_role), min_role) THEN
        RETURN;
    END IF;

    RAISE EXCEPTION 'role % required, caller has %', min_role, v_current
        USING ERRCODE = 'insufficient_privilege';
END;
$$;

ALTER FUNCTION spec.assert_role(impl.user_role) OWNER TO izvor_admin;


CREATE OR REPLACE FUNCTION spec.create_user(
    p_email         TEXT,
    p_password_hash TEXT,
    p_role          impl.user_role DEFAULT 'learner'
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id UUID;
BEGIN
    PERFORM spec.assert_role('admin');

    IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
        RAISE EXCEPTION 'Email is required';
    END IF;
    IF p_password_hash IS NULL OR length(p_password_hash) = 0 THEN
        RAISE EXCEPTION 'Password hash is required';
    END IF;

    INSERT INTO impl.users (tenant_id, email, password_hash, role)
    VALUES (app.current_tenant(), trim(p_email), p_password_hash, p_role)
    RETURNING id INTO v_id;

    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'User with email % already exists in this tenant', p_email;
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid user data: %', SQLERRM;
END;
$$;


CREATE FUNCTION spec.create_user_internal(
    p_email         TEXT,
    p_password_hash TEXT,
    p_role          impl.user_role DEFAULT 'learner'
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id UUID;
BEGIN
    IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
        RAISE EXCEPTION 'Email is required';
    END IF;
    IF p_password_hash IS NULL OR length(p_password_hash) = 0 THEN
        RAISE EXCEPTION 'Password hash is required';
    END IF;

    INSERT INTO impl.users (tenant_id, email, password_hash, role)
    VALUES (app.current_tenant(), trim(p_email), p_password_hash, p_role)
    RETURNING id INTO v_id;

    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'User with email % already exists in this tenant', p_email;
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid user data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.create_user_internal(TEXT, TEXT, impl.user_role) OWNER TO izvor_admin;


CREATE OR REPLACE FUNCTION spec.authenticate_user(p_email TEXT)
RETURNS SETOF impl.users
LANGUAGE sql
STABLE
AS $$
    SELECT * FROM impl.users
    WHERE lower(trim(email)) = lower(trim(p_email))
      AND is_active = true;
$$;


CREATE OR REPLACE FUNCTION spec.get_current_user()
RETURNS SETOF impl.users
LANGUAGE sql
STABLE
AS $$
    SELECT * FROM impl.users
    WHERE id = app.current_user_id() AND is_active = true;
$$;


CREATE FUNCTION spec.deactivate_user(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_changed BOOLEAN;
BEGIN
    PERFORM spec.assert_role('admin');

    IF p_user_id = app.current_user_id() THEN
        RAISE EXCEPTION 'cannot_deactivate_self'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    UPDATE impl.users
    SET is_active = false
    WHERE id = p_user_id AND is_active = true
    RETURNING true INTO v_changed;

    RETURN COALESCE(v_changed, false);
END;
$$;

ALTER FUNCTION spec.deactivate_user(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.activate_user(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_changed BOOLEAN;
BEGIN
    PERFORM spec.assert_role('admin');

    UPDATE impl.users
    SET is_active = true
    WHERE id = p_user_id AND is_active = false
    RETURNING true INTO v_changed;

    RETURN COALESCE(v_changed, false);
END;
$$;

ALTER FUNCTION spec.activate_user(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.deactivate_user(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.deactivate_user(p_user_id);
$$;

ALTER FUNCTION api.deactivate_user(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.activate_user(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.activate_user(p_user_id);
$$;

ALTER FUNCTION api.activate_user(UUID) OWNER TO izvor_admin;


CREATE TYPE system_api.tenant_with_admin AS (
    tenant_id      UUID,
    tenant_code    TEXT,
    subdomain      TEXT,
    admin_user_id  UUID,
    admin_email    TEXT
);

ALTER TYPE system_api.tenant_with_admin OWNER TO izvor_admin;


CREATE FUNCTION system_api.create_tenant_with_admin(
    p_tenant_name         TEXT,
    p_tenant_code         TEXT,
    p_subdomain           TEXT,
    p_admin_email         TEXT,
    p_admin_password_hash TEXT
)
RETURNS system_api.tenant_with_admin
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = system_api, system_spec, system_impl, spec, impl, app, pg_temp
AS $$
DECLARE
    v_tenant_id UUID;
    v_admin_id  UUID;
    v_result    system_api.tenant_with_admin;
BEGIN
    v_tenant_id := system_spec.create_tenant(p_tenant_name, p_tenant_code, p_subdomain);

    PERFORM set_config('app.current_tenant', v_tenant_id::text, true);

    v_admin_id := spec.create_user_internal(p_admin_email, p_admin_password_hash, 'admin');

    v_result := (v_tenant_id, p_tenant_code, p_subdomain, v_admin_id, p_admin_email);
    RETURN v_result;
END;
$$;

ALTER FUNCTION system_api.create_tenant_with_admin(TEXT, TEXT, TEXT, TEXT, TEXT) OWNER TO izvor_admin;
