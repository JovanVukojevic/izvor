CREATE TABLE impl.roles (
    tenant_id    UUID NOT NULL,
    id           UUID NOT NULL DEFAULT gen_random_uuid(),
    code         TEXT NOT NULL,
    name         TEXT NOT NULL,
    description  TEXT,
    rank         INTEGER NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tenant_id, id),
    CONSTRAINT roles_code_check CHECK (code IN ('admin', 'author', 'learner')),
    CONSTRAINT roles_rank_check CHECK (rank > 0)
);

CREATE UNIQUE INDEX roles_code_unique_idx ON impl.roles (tenant_id, code);
CREATE UNIQUE INDEX roles_rank_unique_idx ON impl.roles (tenant_id, rank);

ALTER TABLE impl.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE impl.roles FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON impl.roles
    USING (tenant_id = app.current_tenant())
    WITH CHECK (tenant_id = app.current_tenant());

CREATE TRIGGER roles_set_updated_at
    BEFORE UPDATE ON impl.roles
    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

ALTER TABLE impl.roles OWNER TO izvor_admin;


ALTER TABLE impl.users ADD COLUMN role_id UUID;

DO $$
DECLARE t_id UUID;
BEGIN
    FOR t_id IN SELECT id FROM system_impl.tenants LOOP
        PERFORM set_config('app.current_tenant', t_id::TEXT, true);
        INSERT INTO impl.roles (tenant_id, code, name, description, rank) VALUES
            (t_id, 'admin',   'Administrator', 'Full administrative access within the organization', 100),
            (t_id, 'author',  'Author',        'Can create and manage course content',                50),
            (t_id, 'learner', 'Learner',       'Can browse and complete courses',                     10);
    END LOOP;
END $$;

DO $$
DECLARE
    t_id          UUID;
    v_unconverted INTEGER;
    v_total       INTEGER := 0;
BEGIN
    FOR t_id IN SELECT id FROM system_impl.tenants LOOP
        PERFORM set_config('app.current_tenant', t_id::TEXT, true);
        UPDATE impl.users u
        SET role_id = r.id
        FROM impl.roles r
        WHERE r.tenant_id = u.tenant_id
          AND r.code = u.role::TEXT
          AND u.tenant_id = t_id;

        SELECT count(*)::int INTO v_unconverted
        FROM impl.users WHERE role_id IS NULL AND tenant_id = t_id;
        v_total := v_total + v_unconverted;
    END LOOP;

    IF v_total > 0 THEN
        RAISE EXCEPTION 'migration_020_failed: % users with NULL role_id', v_total;
    END IF;
END $$;

ALTER TABLE impl.roles NO FORCE ROW LEVEL SECURITY;
ALTER TABLE impl.users NO FORCE ROW LEVEL SECURITY;

ALTER TABLE impl.users
    ALTER COLUMN role_id SET NOT NULL,
    ADD CONSTRAINT users_role_fk FOREIGN KEY (tenant_id, role_id)
        REFERENCES impl.roles(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE impl.users FORCE ROW LEVEL SECURITY;
ALTER TABLE impl.roles FORCE ROW LEVEL SECURITY;


DROP FUNCTION spec.assert_role(impl.user_role);

CREATE FUNCTION spec.assert_role(p_min_role TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_code  TEXT;
    v_current_rank  INTEGER;
    v_required_rank INTEGER;
BEGIN
    SELECT r.code, r.rank
    INTO v_current_code, v_current_rank
    FROM impl.users u
    JOIN impl.roles r ON (r.tenant_id, r.id) = (u.tenant_id, u.role_id)
    WHERE u.id = app.current_user_id() AND u.is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'no_active_user_in_session'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT rank INTO v_required_rank
    FROM impl.roles WHERE code = p_min_role;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'invalid_role: %', p_min_role
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF v_current_rank >= v_required_rank THEN
        RETURN;
    END IF;

    RAISE EXCEPTION 'role % required, caller has %', p_min_role, v_current_code
        USING ERRCODE = 'insufficient_privilege';
END;
$$;

ALTER FUNCTION spec.assert_role(TEXT) OWNER TO izvor_admin;


DROP FUNCTION spec.get_current_role();

CREATE FUNCTION spec.get_current_role()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_code TEXT;
BEGIN
    SELECT r.code INTO v_code
    FROM impl.users u
    JOIN impl.roles r ON (r.tenant_id, r.id) = (u.tenant_id, u.role_id)
    WHERE u.id = app.current_user_id() AND u.is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'no_active_user_in_session'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    RETURN v_code;
END;
$$;

ALTER FUNCTION spec.get_current_role() OWNER TO izvor_admin;


DROP FUNCTION spec.create_user(TEXT, TEXT, impl.user_role);

CREATE FUNCTION spec.create_user(
    p_email         TEXT,
    p_password_hash TEXT,
    p_role          TEXT DEFAULT 'learner'
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id      UUID;
    v_role_id UUID;
BEGIN
    PERFORM spec.assert_role('admin');

    IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
        RAISE EXCEPTION 'Email is required';
    END IF;
    IF p_password_hash IS NULL OR length(p_password_hash) = 0 THEN
        RAISE EXCEPTION 'Password hash is required';
    END IF;

    SELECT id INTO v_role_id FROM impl.roles WHERE code = p_role;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'invalid_role: %', p_role
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    INSERT INTO impl.users (tenant_id, email, password_hash, role_id)
    VALUES (app.current_tenant(), trim(p_email), p_password_hash, v_role_id)
    RETURNING id INTO v_id;

    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'User with email % already exists in this tenant', p_email;
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid user data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.create_user(TEXT, TEXT, TEXT) OWNER TO izvor_admin;


DROP FUNCTION spec.create_user_internal(TEXT, TEXT, impl.user_role);

CREATE FUNCTION spec.create_user_internal(
    p_email         TEXT,
    p_password_hash TEXT,
    p_role          TEXT DEFAULT 'learner'
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id      UUID;
    v_role_id UUID;
BEGIN
    IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
        RAISE EXCEPTION 'Email is required';
    END IF;
    IF p_password_hash IS NULL OR length(p_password_hash) = 0 THEN
        RAISE EXCEPTION 'Password hash is required';
    END IF;

    SELECT id INTO v_role_id FROM impl.roles WHERE code = p_role;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'invalid_role: %', p_role
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    INSERT INTO impl.users (tenant_id, email, password_hash, role_id)
    VALUES (app.current_tenant(), trim(p_email), p_password_hash, v_role_id)
    RETURNING id INTO v_id;

    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'User with email % already exists in this tenant', p_email;
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid user data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.create_user_internal(TEXT, TEXT, TEXT) OWNER TO izvor_admin;


CREATE OR REPLACE FUNCTION api.create_user(
    p_email         TEXT,
    p_password_hash TEXT,
    p_role          TEXT DEFAULT 'learner'
)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.create_user(p_email, p_password_hash, p_role);
$$;


CREATE OR REPLACE FUNCTION api.authenticate_user(p_email TEXT)
RETURNS SETOF api.user_credentials
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT u.id, u.email, u.password_hash, r.code, u.created_at, u.updated_at
    FROM spec.authenticate_user(p_email) u
    JOIN impl.roles r ON (r.tenant_id, r.id) = (u.tenant_id, u.role_id);
$$;


CREATE OR REPLACE FUNCTION spec.get_current_user()
RETURNS SETOF api.user_with_tenant
LANGUAGE sql
STABLE
AS $$
    SELECT
        u.id,
        u.email,
        r.code,
        u.created_at,
        u.updated_at,
        t.id,
        t.name,
        t.subdomain
    FROM impl.users u
    JOIN impl.roles r ON (r.tenant_id, r.id) = (u.tenant_id, u.role_id)
    JOIN system_impl.tenants t ON t.id = u.tenant_id
    WHERE u.id = app.current_user_id() AND u.is_active = true;
$$;


CREATE OR REPLACE FUNCTION spec.list_users(
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
    SELECT u.id, u.email, r.code, u.created_at, u.updated_at, u.is_active
    FROM impl.users u
    JOIN impl.roles r ON (r.tenant_id, r.id) = (u.tenant_id, u.role_id)
    WHERE (p_role_filter IS NULL OR r.code = p_role_filter)
      AND (p_active_filter IS NULL OR u.is_active = p_active_filter)
    ORDER BY u.created_at DESC;
END;
$$;


CREATE OR REPLACE FUNCTION spec.get_user(p_user_id UUID)
RETURNS SETOF api.user
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    PERFORM spec.assert_role('admin');

    RETURN QUERY
    SELECT u.id, u.email, r.code, u.created_at, u.updated_at, u.is_active
    FROM impl.users u
    JOIN impl.roles r ON (r.tenant_id, r.id) = (u.tenant_id, u.role_id)
    WHERE u.id = p_user_id;
END;
$$;


CREATE OR REPLACE FUNCTION system_api.create_tenant_with_admin(
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

    INSERT INTO impl.roles (tenant_id, code, name, description, rank) VALUES
        (v_tenant_id, 'admin',   'Administrator', 'Full administrative access within the organization', 100),
        (v_tenant_id, 'author',  'Author',        'Can create and manage course content',                50),
        (v_tenant_id, 'learner', 'Learner',       'Can browse and complete courses',                     10);

    v_admin_id := spec.create_user_internal(p_admin_email, p_admin_password_hash, 'admin');

    v_result := (v_tenant_id, p_tenant_code, p_subdomain, v_admin_id, p_admin_email);
    RETURN v_result;
END;
$$;


ALTER TABLE impl.users DROP COLUMN role;
DROP TYPE impl.user_role;
