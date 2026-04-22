CREATE TYPE api.user AS (
    id           UUID,
    email        TEXT,
    role         TEXT,
    created_at   TIMESTAMPTZ,
    updated_at   TIMESTAMPTZ
);

ALTER TYPE api.user OWNER TO izvor_admin;


CREATE TYPE api.user_credentials AS (
    id             UUID,
    email          TEXT,
    password_hash  TEXT,
    role           TEXT,
    created_at     TIMESTAMPTZ,
    updated_at     TIMESTAMPTZ
);

ALTER TYPE api.user_credentials OWNER TO izvor_admin;


CREATE FUNCTION api.create_user(
    p_email         TEXT,
    p_password_hash TEXT,
    p_role          TEXT DEFAULT 'learner'
)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.create_user(p_email, p_password_hash, p_role::impl.user_role);
$$;

ALTER FUNCTION api.create_user(TEXT, TEXT, TEXT) OWNER TO izvor_admin;


CREATE FUNCTION api.authenticate_user(p_email TEXT)
RETURNS SETOF api.user_credentials
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, email, password_hash, role::text, created_at, updated_at
    FROM spec.authenticate_user(p_email);
$$;

ALTER FUNCTION api.authenticate_user(TEXT) OWNER TO izvor_admin;


CREATE FUNCTION api.change_password(
    p_user_id           UUID,
    p_new_password_hash TEXT
)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.change_password(p_user_id, p_new_password_hash);
$$;

ALTER FUNCTION api.change_password(UUID, TEXT) OWNER TO izvor_admin;
