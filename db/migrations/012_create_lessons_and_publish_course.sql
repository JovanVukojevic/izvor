CREATE TABLE impl.lessons (
    id           UUID NOT NULL DEFAULT gen_random_uuid(),
    tenant_id    UUID NOT NULL,

    course_id    UUID NOT NULL,

    title        TEXT NOT NULL
                     CHECK (length(trim(title)) BETWEEN 1 AND 300),

    content      TEXT NOT NULL DEFAULT '',

    position     INT NOT NULL,

    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (tenant_id, id),

    FOREIGN KEY (tenant_id, course_id)
        REFERENCES impl.courses (tenant_id, id)
        ON DELETE RESTRICT,

    -- DEFERRABLE so spec.delete_lesson (compaction shift) and
    -- spec.reorder_lesson (range shift) can run a single multi-row
    -- UPDATE without tripping on transient duplicates. Those procedures
    -- issue SET CONSTRAINTS lessons_position_unique DEFERRED inside the
    -- request transaction; the deferral resets at COMMIT/ROLLBACK.
    CONSTRAINT lessons_position_unique
        UNIQUE (tenant_id, course_id, position) DEFERRABLE INITIALLY IMMEDIATE
);

ALTER TABLE impl.lessons OWNER TO izvor_admin;


CREATE TRIGGER lessons_set_updated_at
    BEFORE UPDATE ON impl.lessons
    FOR EACH ROW
    EXECUTE FUNCTION app.set_updated_at();


ALTER TABLE impl.lessons ENABLE ROW LEVEL SECURITY;
ALTER TABLE impl.lessons FORCE  ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON impl.lessons
    USING       (tenant_id = app.current_tenant())
    WITH CHECK  (tenant_id = app.current_tenant());


CREATE TYPE api.lesson AS (
    id          UUID,
    course_id   UUID,
    title       TEXT,
    content     TEXT,
    position    INT,
    created_at  TIMESTAMPTZ,
    updated_at  TIMESTAMPTZ
);

ALTER TYPE api.lesson OWNER TO izvor_admin;


CREATE FUNCTION spec.create_lesson(
    p_course_id UUID,
    p_title     TEXT,
    p_content   TEXT
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id       UUID;
    v_status   impl.course_status;
    v_position INT;
BEGIN
    SELECT status INTO v_status
    FROM impl.courses
    WHERE id = p_course_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    PERFORM spec.assert_course_owner_or_admin(p_course_id);

    IF v_status = 'archived' THEN
        RAISE EXCEPTION 'course_is_archived';
    END IF;

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    SELECT COALESCE(MAX(position), 0) + 1 INTO v_position
    FROM impl.lessons
    WHERE course_id = p_course_id;

    INSERT INTO impl.lessons (tenant_id, course_id, title, content, position)
    VALUES (app.current_tenant(), p_course_id, trim(p_title),
            COALESCE(p_content, ''), v_position)
    RETURNING id INTO v_id;

    RETURN v_id;
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid lesson data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.create_lesson(UUID, TEXT, TEXT) OWNER TO izvor_admin;


CREATE FUNCTION spec.update_lesson(
    p_lesson_id UUID,
    p_title     TEXT,
    p_content   TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id UUID;
    v_status    impl.course_status;
BEGIN
    SELECT course_id INTO v_course_id
    FROM impl.lessons
    WHERE id = p_lesson_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lesson_not_found';
    END IF;

    PERFORM spec.assert_course_owner_or_admin(v_course_id);

    SELECT status INTO v_status FROM impl.courses WHERE id = v_course_id;

    IF v_status = 'archived' THEN
        RAISE EXCEPTION 'course_is_archived';
    END IF;

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    UPDATE impl.lessons
    SET title   = trim(p_title),
        content = COALESCE(p_content, '')
    WHERE id = p_lesson_id;

    RETURN FOUND;
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid lesson data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.update_lesson(UUID, TEXT, TEXT) OWNER TO izvor_admin;


CREATE FUNCTION spec.delete_lesson(p_lesson_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id UUID;
    v_status    impl.course_status;
    v_old_pos   INT;
BEGIN
    SELECT course_id INTO v_course_id
    FROM impl.lessons
    WHERE id = p_lesson_id;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    PERFORM 1 FROM impl.courses WHERE id = v_course_id FOR UPDATE;

    PERFORM spec.assert_course_owner_or_admin(v_course_id);

    SELECT status INTO v_status FROM impl.courses WHERE id = v_course_id;

    IF v_status <> 'draft' THEN
        RAISE EXCEPTION 'course_not_draft';
    END IF;

    SET CONSTRAINTS lessons_position_unique DEFERRED;

    DELETE FROM impl.lessons
    WHERE id = p_lesson_id
    RETURNING position INTO v_old_pos;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    UPDATE impl.lessons
    SET position = position - 1
    WHERE course_id = v_course_id
      AND position > v_old_pos;

    RETURN true;
END;
$$;

ALTER FUNCTION spec.delete_lesson(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.reorder_lesson(
    p_lesson_id    UUID,
    p_new_position INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id UUID;
    v_status    impl.course_status;
    v_old_pos   INT;
    v_count     INT;
BEGIN
    SELECT course_id INTO v_course_id
    FROM impl.lessons
    WHERE id = p_lesson_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lesson_not_found';
    END IF;

    PERFORM 1 FROM impl.courses WHERE id = v_course_id FOR UPDATE;

    SELECT position INTO v_old_pos
    FROM impl.lessons
    WHERE id = p_lesson_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lesson_not_found';
    END IF;

    PERFORM spec.assert_course_owner_or_admin(v_course_id);

    SELECT status INTO v_status FROM impl.courses WHERE id = v_course_id;

    IF v_status = 'archived' THEN
        RAISE EXCEPTION 'course_is_archived';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM impl.lessons
    WHERE course_id = v_course_id;

    IF p_new_position < 1 OR p_new_position > v_count THEN
        RAISE EXCEPTION 'position_out_of_range';
    END IF;

    IF p_new_position = v_old_pos THEN
        RETURN false;
    END IF;

    SET CONSTRAINTS lessons_position_unique DEFERRED;

    UPDATE impl.lessons
    SET position = CASE
        WHEN id = p_lesson_id THEN p_new_position
        WHEN p_new_position < v_old_pos
             AND position BETWEEN p_new_position AND v_old_pos - 1
                                          THEN position + 1
        WHEN p_new_position > v_old_pos
             AND position BETWEEN v_old_pos + 1 AND p_new_position
                                          THEN position - 1
        ELSE position
    END
    WHERE course_id = v_course_id;

    RETURN true;
END;
$$;

ALTER FUNCTION spec.reorder_lesson(UUID, INT) OWNER TO izvor_admin;


CREATE FUNCTION spec.get_lesson(p_lesson_id UUID)
RETURNS SETOF api.lesson
LANGUAGE sql
STABLE
AS $$
    SELECT id, course_id, title, content, position, created_at, updated_at
    FROM impl.lessons
    WHERE id = p_lesson_id;
$$;

ALTER FUNCTION spec.get_lesson(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.list_lessons_by_course(p_course_id UUID)
RETURNS SETOF api.lesson
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    PERFORM 1 FROM impl.courses WHERE id = p_course_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found';
    END IF;

    RETURN QUERY
        SELECT id, course_id, title, content, position, created_at, updated_at
        FROM impl.lessons
        WHERE course_id = p_course_id
        ORDER BY position ASC;
END;
$$;

ALTER FUNCTION spec.list_lessons_by_course(UUID) OWNER TO izvor_admin;


-- Forward-only state transition: draft -> published. The reverse
-- (published -> draft) is intentionally not exposed in Phase 7.2.
CREATE FUNCTION spec.publish_course(p_course_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_status       impl.course_status;
    v_lesson_count INT;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_course_id);

    SELECT status INTO v_status FROM impl.courses WHERE id = p_course_id;

    IF v_status <> 'draft' THEN
        RAISE EXCEPTION 'course_not_draft';
    END IF;

    SELECT COUNT(*) INTO v_lesson_count
    FROM impl.lessons
    WHERE course_id = p_course_id;

    IF v_lesson_count = 0 THEN
        RAISE EXCEPTION 'course_has_no_lessons';
    END IF;

    UPDATE impl.courses SET status = 'published' WHERE id = p_course_id;

    RETURN true;
END;
$$;

ALTER FUNCTION spec.publish_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.create_lesson(
    p_course_id UUID,
    p_title     TEXT,
    p_content   TEXT
)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.create_lesson(p_course_id, p_title, p_content);
$$;

ALTER FUNCTION api.create_lesson(UUID, TEXT, TEXT) OWNER TO izvor_admin;


CREATE FUNCTION api.update_lesson(
    p_lesson_id UUID,
    p_title     TEXT,
    p_content   TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.update_lesson(p_lesson_id, p_title, p_content);
$$;

ALTER FUNCTION api.update_lesson(UUID, TEXT, TEXT) OWNER TO izvor_admin;


CREATE FUNCTION api.delete_lesson(p_lesson_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.delete_lesson(p_lesson_id);
$$;

ALTER FUNCTION api.delete_lesson(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.reorder_lesson(
    p_lesson_id    UUID,
    p_new_position INT
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.reorder_lesson(p_lesson_id, p_new_position);
$$;

ALTER FUNCTION api.reorder_lesson(UUID, INT) OWNER TO izvor_admin;


CREATE FUNCTION api.get_lesson(p_lesson_id UUID)
RETURNS SETOF api.lesson
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
BEGIN
    RETURN QUERY
        SELECT id, course_id, title, content, position, created_at, updated_at
        FROM spec.get_lesson(p_lesson_id);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lesson_not_found';
    END IF;
END;
$$;

ALTER FUNCTION api.get_lesson(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.list_lessons_by_course(p_course_id UUID)
RETURNS SETOF api.lesson
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, course_id, title, content, position, created_at, updated_at
    FROM spec.list_lessons_by_course(p_course_id);
$$;

ALTER FUNCTION api.list_lessons_by_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.publish_course(p_course_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.publish_course(p_course_id);
$$;

ALTER FUNCTION api.publish_course(UUID) OWNER TO izvor_admin;
