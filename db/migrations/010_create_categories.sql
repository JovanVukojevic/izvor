CREATE TABLE impl.categories (
    id           UUID NOT NULL DEFAULT gen_random_uuid(),
    tenant_id    UUID NOT NULL,

    name         TEXT NOT NULL
                     CHECK (length(trim(name)) BETWEEN 1 AND 200),

    description  TEXT,

    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (tenant_id, id)
);

ALTER TABLE impl.categories OWNER TO izvor_admin;


CREATE UNIQUE INDEX categories_tenant_name_key
    ON impl.categories (tenant_id, lower(trim(name)));


CREATE TRIGGER categories_set_updated_at
    BEFORE UPDATE ON impl.categories
    FOR EACH ROW
    EXECUTE FUNCTION app.set_updated_at();


ALTER TABLE impl.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE impl.categories FORCE  ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON impl.categories
    USING       (tenant_id = app.current_tenant())
    WITH CHECK  (tenant_id = app.current_tenant());


CREATE TYPE api.category AS (
    id           UUID,
    name         TEXT,
    description  TEXT,
    created_at   TIMESTAMPTZ,
    updated_at   TIMESTAMPTZ
);

ALTER TYPE api.category OWNER TO izvor_admin;


CREATE FUNCTION spec.create_category(
    p_name        TEXT,
    p_description TEXT
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id UUID;
BEGIN
    PERFORM spec.assert_role('admin');

    IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
        RAISE EXCEPTION 'Name is required';
    END IF;

    INSERT INTO impl.categories (tenant_id, name, description)
    VALUES (app.current_tenant(), trim(p_name), p_description)
    RETURNING id INTO v_id;

    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Category with name % already exists in this tenant', p_name;
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid category data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.create_category(TEXT, TEXT) OWNER TO izvor_admin;


CREATE FUNCTION spec.update_category(
    p_id          UUID,
    p_name        TEXT,
    p_description TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM spec.assert_role('admin');

    IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
        RAISE EXCEPTION 'Name is required';
    END IF;

    UPDATE impl.categories
    SET name        = trim(p_name),
        description = p_description
    WHERE id = p_id;

    RETURN FOUND;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Category with name % already exists in this tenant', p_name;
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid category data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.update_category(UUID, TEXT, TEXT) OWNER TO izvor_admin;


CREATE FUNCTION spec.delete_category(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM spec.assert_role('admin');

    DELETE FROM impl.categories
    WHERE id = p_id;

    RETURN FOUND;
END;
$$;

ALTER FUNCTION spec.delete_category(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.get_category(p_id UUID)
RETURNS SETOF api.category
LANGUAGE sql
STABLE
AS $$
    SELECT id, name, description, created_at, updated_at
    FROM impl.categories
    WHERE id = p_id;
$$;

ALTER FUNCTION spec.get_category(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.list_categories()
RETURNS SETOF api.category
LANGUAGE sql
STABLE
AS $$
    SELECT id, name, description, created_at, updated_at
    FROM impl.categories
    ORDER BY name;
$$;

ALTER FUNCTION spec.list_categories() OWNER TO izvor_admin;


CREATE FUNCTION api.create_category(
    p_name        TEXT,
    p_description TEXT
)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.create_category(p_name, p_description);
$$;

ALTER FUNCTION api.create_category(TEXT, TEXT) OWNER TO izvor_admin;


CREATE FUNCTION api.update_category(
    p_id          UUID,
    p_name        TEXT,
    p_description TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.update_category(p_id, p_name, p_description);
$$;

ALTER FUNCTION api.update_category(UUID, TEXT, TEXT) OWNER TO izvor_admin;


CREATE FUNCTION api.delete_category(p_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.delete_category(p_id);
$$;

ALTER FUNCTION api.delete_category(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.get_category(p_id UUID)
RETURNS SETOF api.category
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, name, description, created_at, updated_at
    FROM spec.get_category(p_id);
$$;

ALTER FUNCTION api.get_category(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.list_categories()
RETURNS SETOF api.category
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, name, description, created_at, updated_at
    FROM spec.list_categories();
$$;

ALTER FUNCTION api.list_categories() OWNER TO izvor_admin;
