CREATE TABLE impl.refresh_tokens (
    tenant_id    UUID NOT NULL,
    id           UUID NOT NULL DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL,
    token_hash   TEXT NOT NULL,
    issued_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at   TIMESTAMPTZ NOT NULL,
    revoked_at   TIMESTAMPTZ,
    PRIMARY KEY (tenant_id, id),
    FOREIGN KEY (tenant_id, user_id) REFERENCES impl.users(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT refresh_tokens_token_hash_check CHECK (length(token_hash) = 64),
    CONSTRAINT refresh_tokens_expires_after_issue CHECK (expires_at > issued_at)
);

CREATE UNIQUE INDEX refresh_tokens_token_hash_idx
    ON impl.refresh_tokens (token_hash);

CREATE INDEX refresh_tokens_user_active_idx
    ON impl.refresh_tokens (tenant_id, user_id)
    WHERE revoked_at IS NULL;

ALTER TABLE impl.refresh_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE impl.refresh_tokens FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON impl.refresh_tokens
    USING (tenant_id = app.current_tenant())
    WITH CHECK (tenant_id = app.current_tenant());


CREATE TYPE api.refresh_token AS (
    id          UUID,
    user_id     UUID,
    token       TEXT,
    issued_at   TIMESTAMPTZ,
    expires_at  TIMESTAMPTZ
);

ALTER TYPE api.refresh_token OWNER TO izvor_admin;


-- Bootstrap-pattern: no auth check (mirrors spec.create_user_internal from 009).
-- Caller is responsible for setting app.current_tenant. The raw token is
-- generated server-side and returned only here; only its SHA-256 hex digest
-- is persisted, so DB compromise yields no usable tokens.
CREATE FUNCTION spec.create_refresh_token_internal(
    p_user_id        UUID,
    p_lifetime_days  INT
)
RETURNS api.refresh_token
LANGUAGE plpgsql
AS $$
DECLARE
    v_token       TEXT;
    v_hash        TEXT;
    v_id          UUID;
    v_issued_at   TIMESTAMPTZ;
    v_expires_at  TIMESTAMPTZ;
BEGIN
    -- gen_random_bytes lives in pgcrypto (public schema). Fully-qualified
    -- because api SECURITY DEFINER wrappers exclude public from search_path
    -- (invariant 10). encode and sha256 are in pg_catalog — always reachable.
    v_token := rtrim(
        translate(
            replace(replace(encode(public.gen_random_bytes(32), 'base64'), E'\n', ''), E'\r', ''),
            '+/', '-_'),
        '=');
    v_hash := encode(sha256(v_token::bytea), 'hex');

    INSERT INTO impl.refresh_tokens (tenant_id, user_id, token_hash, expires_at)
    VALUES (
        app.current_tenant(),
        p_user_id,
        v_hash,
        NOW() + (p_lifetime_days || ' days')::INTERVAL)
    RETURNING id, issued_at, expires_at INTO v_id, v_issued_at, v_expires_at;

    RETURN (v_id, p_user_id, v_token, v_issued_at, v_expires_at)::api.refresh_token;
END;
$$;

ALTER FUNCTION spec.create_refresh_token_internal(UUID, INT) OWNER TO izvor_admin;


CREATE FUNCTION spec.create_refresh_token(p_lifetime_days INT)
RETURNS api.refresh_token
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN spec.create_refresh_token_internal(app.current_user_id(), p_lifetime_days);
END;
$$;

ALTER FUNCTION spec.create_refresh_token(INT) OWNER TO izvor_admin;


-- Rotation: validate, revoke, mint new. FOR UPDATE serializes concurrent
-- rotation of the same token — second caller misses the row and sees
-- invalid_refresh_token, the desired theft-detection signal.
CREATE FUNCTION spec.rotate_refresh_token(
    p_token         TEXT,
    p_lifetime_days INT
)
RETURNS api.refresh_token
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id UUID;
    v_hash    TEXT;
BEGIN
    v_hash := encode(sha256(p_token::bytea), 'hex');

    SELECT user_id INTO v_user_id
    FROM impl.refresh_tokens
    WHERE token_hash = v_hash
      AND revoked_at IS NULL
      AND expires_at > NOW()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'invalid_refresh_token'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    UPDATE impl.refresh_tokens
    SET revoked_at = NOW()
    WHERE token_hash = v_hash;

    RETURN spec.create_refresh_token_internal(v_user_id, p_lifetime_days);
END;
$$;

ALTER FUNCTION spec.rotate_refresh_token(TEXT, INT) OWNER TO izvor_admin;


CREATE FUNCTION spec.revoke_refresh_token(p_token TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_changed BOOLEAN;
    v_hash    TEXT;
BEGIN
    v_hash := encode(sha256(p_token::bytea), 'hex');

    UPDATE impl.refresh_tokens
    SET revoked_at = NOW()
    WHERE token_hash = v_hash AND revoked_at IS NULL
    RETURNING true INTO v_changed;

    RETURN COALESCE(v_changed, false);
END;
$$;

ALTER FUNCTION spec.revoke_refresh_token(TEXT) OWNER TO izvor_admin;


CREATE FUNCTION spec.revoke_all_user_refresh_tokens(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    IF p_user_id <> app.current_user_id() THEN
        PERFORM spec.assert_role('admin');
    END IF;

    UPDATE impl.refresh_tokens
    SET revoked_at = NOW()
    WHERE user_id = p_user_id AND revoked_at IS NULL;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

ALTER FUNCTION spec.revoke_all_user_refresh_tokens(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.create_refresh_token(p_lifetime_days INT)
RETURNS api.refresh_token
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.create_refresh_token(p_lifetime_days);
$$;

ALTER FUNCTION api.create_refresh_token(INT) OWNER TO izvor_admin;


CREATE FUNCTION api.rotate_refresh_token(p_token TEXT, p_lifetime_days INT)
RETURNS api.refresh_token
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.rotate_refresh_token(p_token, p_lifetime_days);
$$;

ALTER FUNCTION api.rotate_refresh_token(TEXT, INT) OWNER TO izvor_admin;


CREATE FUNCTION api.revoke_refresh_token(p_token TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.revoke_refresh_token(p_token);
$$;

ALTER FUNCTION api.revoke_refresh_token(TEXT) OWNER TO izvor_admin;


CREATE FUNCTION api.revoke_all_user_refresh_tokens(p_user_id UUID)
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.revoke_all_user_refresh_tokens(p_user_id);
$$;

ALTER FUNCTION api.revoke_all_user_refresh_tokens(UUID) OWNER TO izvor_admin;
