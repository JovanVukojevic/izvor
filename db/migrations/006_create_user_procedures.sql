CREATE FUNCTION spec.create_user(
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

ALTER FUNCTION spec.create_user(TEXT, TEXT, impl.user_role) OWNER TO izvor_admin;


CREATE FUNCTION spec.authenticate_user(p_email TEXT)
RETURNS SETOF impl.users
LANGUAGE sql
STABLE
AS $$
    SELECT * FROM impl.users
    WHERE lower(trim(email)) = lower(trim(p_email));
$$;

ALTER FUNCTION spec.authenticate_user(TEXT) OWNER TO izvor_admin;


CREATE FUNCTION spec.change_password(
    p_user_id           UUID,
    p_new_password_hash TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_new_password_hash IS NULL OR length(p_new_password_hash) = 0 THEN
        RAISE EXCEPTION 'Password hash is required';
    END IF;

    UPDATE impl.users
    SET password_hash = p_new_password_hash
    WHERE id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % not found in current tenant', p_user_id;
    END IF;
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid password hash: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.change_password(UUID, TEXT) OWNER TO izvor_admin;
