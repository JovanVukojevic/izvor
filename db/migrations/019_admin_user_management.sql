ALTER TYPE api.user ADD ATTRIBUTE is_active BOOLEAN;


CREATE FUNCTION spec.list_users(
    p_role_filter   TEXT DEFAULT NULL,
    p_active_filter BOOLEAN DEFAULT NULL
)
RETURNS SETOF api.user
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    PERFORM spec.assert_role('admin');

    RETURN QUERY
    SELECT id, email, role::TEXT, created_at, updated_at, is_active
    FROM impl.users
    WHERE (p_role_filter IS NULL OR role = p_role_filter::impl.user_role)
      AND (p_active_filter IS NULL OR is_active = p_active_filter)
    ORDER BY created_at DESC;
END;
$$;

ALTER FUNCTION spec.list_users(TEXT, BOOLEAN) OWNER TO izvor_admin;


CREATE FUNCTION spec.get_user(p_user_id UUID)
RETURNS SETOF api.user
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    PERFORM spec.assert_role('admin');

    RETURN QUERY
    SELECT id, email, role::TEXT, created_at, updated_at, is_active
    FROM impl.users
    WHERE id = p_user_id;
END;
$$;

ALTER FUNCTION spec.get_user(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.admin_reset_password(
    p_user_id       UUID,
    p_password_hash TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_changed BOOLEAN;
BEGIN
    PERFORM spec.assert_role('admin');

    UPDATE impl.users
    SET password_hash = p_password_hash
    WHERE id = p_user_id AND is_active = true
    RETURNING true INTO v_changed;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'user_not_found'
            USING ERRCODE = 'no_data_found';
    END IF;

    PERFORM spec.revoke_all_user_refresh_tokens(p_user_id);

    RETURN COALESCE(v_changed, false);
END;
$$;

ALTER FUNCTION spec.admin_reset_password(UUID, TEXT) OWNER TO izvor_admin;


CREATE OR REPLACE FUNCTION spec.deactivate_user(p_user_id UUID)
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

    PERFORM 1 FROM impl.users
    WHERE id = p_user_id AND is_active = true;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    UPDATE impl.users
    SET is_active = false
    WHERE id = p_user_id AND is_active = true
    RETURNING true INTO v_changed;

    PERFORM spec.revoke_all_user_refresh_tokens(p_user_id);

    RETURN COALESCE(v_changed, false);
END;
$$;


CREATE FUNCTION api.list_users(
    p_role_filter   TEXT,
    p_active_filter BOOLEAN
)
RETURNS SETOF api.user
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.list_users(p_role_filter, p_active_filter);
$$;

ALTER FUNCTION api.list_users(TEXT, BOOLEAN) OWNER TO izvor_admin;


CREATE FUNCTION api.get_user(p_user_id UUID)
RETURNS SETOF api.user
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.get_user(p_user_id);
$$;

ALTER FUNCTION api.get_user(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.admin_reset_password(
    p_user_id       UUID,
    p_password_hash TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.admin_reset_password(p_user_id, p_password_hash);
$$;

ALTER FUNCTION api.admin_reset_password(UUID, TEXT) OWNER TO izvor_admin;
