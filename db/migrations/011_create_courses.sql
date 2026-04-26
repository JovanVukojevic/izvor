CREATE TYPE impl.course_status AS ENUM ('draft', 'published', 'archived');

ALTER TYPE impl.course_status OWNER TO izvor_admin;


CREATE TABLE impl.courses (
    id           UUID NOT NULL DEFAULT gen_random_uuid(),
    tenant_id    UUID NOT NULL,

    category_id  UUID,
    author_id    UUID NOT NULL,

    title        TEXT NOT NULL
                     CHECK (length(trim(title)) BETWEEN 1 AND 300),

    description  TEXT,

    status       impl.course_status NOT NULL DEFAULT 'draft',

    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (tenant_id, id),

    FOREIGN KEY (tenant_id, category_id)
        REFERENCES impl.categories (tenant_id, id)
        ON DELETE RESTRICT,

    FOREIGN KEY (tenant_id, author_id)
        REFERENCES impl.users (tenant_id, id)
);

ALTER TABLE impl.courses OWNER TO izvor_admin;


CREATE INDEX courses_tenant_status_idx
    ON impl.courses (tenant_id, status);

CREATE INDEX courses_tenant_category_idx
    ON impl.courses (tenant_id, category_id)
    WHERE category_id IS NOT NULL;

CREATE INDEX courses_tenant_author_idx
    ON impl.courses (tenant_id, author_id);


CREATE TRIGGER courses_set_updated_at
    BEFORE UPDATE ON impl.courses
    FOR EACH ROW
    EXECUTE FUNCTION app.set_updated_at();


ALTER TABLE impl.courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE impl.courses FORCE  ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON impl.courses
    USING       (tenant_id = app.current_tenant())
    WITH CHECK  (tenant_id = app.current_tenant());


CREATE TYPE api.course AS (
    id           UUID,
    category_id  UUID,
    author_id    UUID,
    title        TEXT,
    description  TEXT,
    status       TEXT,
    created_at   TIMESTAMPTZ,
    updated_at   TIMESTAMPTZ
);

ALTER TYPE api.course OWNER TO izvor_admin;


CREATE FUNCTION spec.assert_course_owner_or_admin(p_course_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_author UUID;
BEGIN
    IF spec.get_current_role() = 'admin' THEN
        RETURN;
    END IF;

    SELECT author_id INTO v_author
    FROM impl.courses
    WHERE id = p_course_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF v_author <> app.current_user_id() THEN
        RAISE EXCEPTION 'not_course_owner'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
END;
$$;

ALTER FUNCTION spec.assert_course_owner_or_admin(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.create_course(
    p_title       TEXT,
    p_description TEXT,
    p_category_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id UUID;
BEGIN
    PERFORM spec.assert_role('author');

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    INSERT INTO impl.courses (tenant_id, category_id, author_id, title, description)
    VALUES (app.current_tenant(), p_category_id, app.current_user_id(), trim(p_title), p_description)
    RETURNING id INTO v_id;

    RETURN v_id;
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'category_not_found';
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid course data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.create_course(TEXT, TEXT, UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.update_course(
    p_id          UUID,
    p_title       TEXT,
    p_description TEXT,
    p_category_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_id);

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    IF EXISTS (
        SELECT 1 FROM impl.courses
        WHERE id = p_id AND status = 'archived'
    ) THEN
        RAISE EXCEPTION 'course_is_archived';
    END IF;

    UPDATE impl.courses
    SET title       = trim(p_title),
        description = p_description,
        category_id = p_category_id
    WHERE id = p_id;

    RETURN FOUND;
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'category_not_found';
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid course data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.update_course(UUID, TEXT, TEXT, UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.delete_course(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_changed BOOLEAN;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_id);

    UPDATE impl.courses
    SET status = 'archived'
    WHERE id = p_id AND status <> 'archived'
    RETURNING true INTO v_changed;

    RETURN COALESCE(v_changed, false);
END;
$$;

ALTER FUNCTION spec.delete_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.get_course(p_id UUID)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
AS $$
    SELECT id, category_id, author_id, title, description, status::text,
           created_at, updated_at
    FROM impl.courses
    WHERE id = p_id;
$$;

ALTER FUNCTION spec.get_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.list_courses(
    p_category_filter UUID,
    p_status_filter   impl.course_status
)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
AS $$
    SELECT id, category_id, author_id, title, description, status::text,
           created_at, updated_at
    FROM impl.courses
    WHERE status = COALESCE(p_status_filter, 'published')
      AND (p_category_filter IS NULL OR category_id = p_category_filter)
    ORDER BY created_at DESC;
$$;

ALTER FUNCTION spec.list_courses(UUID, impl.course_status) OWNER TO izvor_admin;


CREATE FUNCTION api.create_course(
    p_title       TEXT,
    p_description TEXT,
    p_category_id UUID
)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.create_course(p_title, p_description, p_category_id);
$$;

ALTER FUNCTION api.create_course(TEXT, TEXT, UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.update_course(
    p_id          UUID,
    p_title       TEXT,
    p_description TEXT,
    p_category_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.update_course(p_id, p_title, p_description, p_category_id);
$$;

ALTER FUNCTION api.update_course(UUID, TEXT, TEXT, UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.delete_course(p_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.delete_course(p_id);
$$;

ALTER FUNCTION api.delete_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.get_course(p_id UUID)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, category_id, author_id, title, description, status,
           created_at, updated_at
    FROM spec.get_course(p_id);
$$;

ALTER FUNCTION api.get_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.list_courses(
    p_category_filter UUID,
    p_status_filter   TEXT
)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, category_id, author_id, title, description, status,
           created_at, updated_at
    FROM spec.list_courses(p_category_filter, p_status_filter::impl.course_status);
$$;

ALTER FUNCTION api.list_courses(UUID, TEXT) OWNER TO izvor_admin;
