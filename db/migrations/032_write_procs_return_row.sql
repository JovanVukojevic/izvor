-- The 14 tenant-plane write procedures change from returning a scalar
-- (UUID / BOOLEAN) to RETURNS SETOF api.<entity>, projecting their result
-- through the matching read getter (spec.get_<entity>). The HTTP layer can
-- then materialize the response body from the write call alone instead of the
-- write + a separate follow-up api.get_* call.
--
-- The getter is the single source of the projection: each proc ends with
-- RETURN QUERY SELECT * FROM spec.get_<entity>(<id>), never a duplicated
-- SELECT list, so the write response is byte-identical to the corresponding GET.
--
-- spec.get_course/get_lesson/get_enrollment/get_category are sql STABLE and
-- return an empty set (no raise) on a missing/RLS-hidden id, and an admin
-- passes spec.assert_course_owner_or_admin silently for a nonexistent course
-- (the admin short-circuit returns before the existence check). So each
-- converted proc must guard existence itself and raise *_not_found rather than
-- project an empty set. Guards already present in the prior bodies are kept;
-- guards added here are update_category (category_not_found), update_course /
-- activate_course / deactivate_course (course_not_found), and activate_user /
-- deactivate_user (user_not_found).
--
-- Return type changes preclude CREATE OR REPLACE: api is dropped before spec
-- (api depends on spec), then spec is recreated with the new SETOF return and
-- api recreated as a thin pass-through. No GRANTs — PUBLIC EXECUTE is the
-- default and access is gated by the USAGE blockade on spec/impl.


DROP FUNCTION api.create_category(TEXT, TEXT);
DROP FUNCTION spec.create_category(TEXT, TEXT);

CREATE FUNCTION spec.create_category(
    p_name        TEXT,
    p_description TEXT
)
RETURNS SETOF api.category
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

    RETURN QUERY SELECT * FROM spec.get_category(v_id);
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Category with name % already exists in this tenant', p_name;
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid category data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.create_category(TEXT, TEXT) OWNER TO izvor_admin;

CREATE FUNCTION api.create_category(
    p_name        TEXT,
    p_description TEXT
)
RETURNS SETOF api.category
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.create_category(p_name, p_description);
$$;

ALTER FUNCTION api.create_category(TEXT, TEXT) OWNER TO izvor_admin;


DROP FUNCTION api.update_category(UUID, TEXT, TEXT);
DROP FUNCTION spec.update_category(UUID, TEXT, TEXT);

CREATE FUNCTION spec.update_category(
    p_id          UUID,
    p_name        TEXT,
    p_description TEXT
)
RETURNS SETOF api.category
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM spec.assert_role('admin');

    IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
        RAISE EXCEPTION 'Name is required';
    END IF;

    PERFORM 1 FROM impl.categories WHERE id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'category_not_found';
    END IF;

    UPDATE impl.categories
    SET name        = trim(p_name),
        description = p_description
    WHERE id = p_id;

    RETURN QUERY SELECT * FROM spec.get_category(p_id);
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Category with name % already exists in this tenant', p_name;
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid category data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.update_category(UUID, TEXT, TEXT) OWNER TO izvor_admin;

CREATE FUNCTION api.update_category(
    p_id          UUID,
    p_name        TEXT,
    p_description TEXT
)
RETURNS SETOF api.category
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.update_category(p_id, p_name, p_description);
$$;

ALTER FUNCTION api.update_category(UUID, TEXT, TEXT) OWNER TO izvor_admin;


DROP FUNCTION api.create_course(TEXT, TEXT, UUID[], TEXT, TEXT);
DROP FUNCTION spec.create_course(TEXT, TEXT, UUID[], TEXT, TEXT);

CREATE FUNCTION spec.create_course(
    p_title                TEXT,
    p_description          TEXT,
    p_category_ids         UUID[],
    p_first_lesson_title   TEXT,
    p_first_lesson_content TEXT
)
RETURNS SETOF api.course
LANGUAGE plpgsql
AS $$
DECLARE
    v_id           UUID;
    v_distinct     UUID[];
    v_found_count  INT;
BEGIN
    PERFORM spec.assert_role('author');

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    IF p_category_ids IS NULL OR array_length(p_category_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'category_required';
    END IF;

    IF p_first_lesson_title IS NULL OR length(trim(p_first_lesson_title)) = 0 THEN
        RAISE EXCEPTION 'First lesson title is required';
    END IF;

    SELECT array_agg(DISTINCT cat) INTO v_distinct
      FROM unnest(p_category_ids) AS cat;

    SELECT COUNT(*) INTO v_found_count
      FROM impl.categories
     WHERE id = ANY(v_distinct);

    IF v_found_count <> array_length(v_distinct, 1) THEN
        RAISE EXCEPTION 'category_not_found';
    END IF;

    INSERT INTO impl.courses (tenant_id, author_id, title, description, is_active)
    VALUES (app.current_tenant(), app.current_user_id(),
            trim(p_title), p_description, false)
    RETURNING id INTO v_id;

    INSERT INTO impl.course_categories (tenant_id, course_id, category_id)
    SELECT app.current_tenant(), v_id, cat
      FROM unnest(v_distinct) AS cat;

    INSERT INTO impl.lessons (tenant_id, course_id, title, content, position)
    VALUES (app.current_tenant(), v_id,
            trim(p_first_lesson_title), COALESCE(p_first_lesson_content, ''), 1);

    RETURN QUERY SELECT * FROM spec.get_course(v_id);
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid course data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.create_course(TEXT, TEXT, UUID[], TEXT, TEXT) OWNER TO izvor_admin;

CREATE FUNCTION api.create_course(
    p_title                TEXT,
    p_description          TEXT,
    p_category_ids         UUID[],
    p_first_lesson_title   TEXT,
    p_first_lesson_content TEXT
)
RETURNS SETOF api.course
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.create_course(p_title, p_description, p_category_ids,
                                     p_first_lesson_title, p_first_lesson_content);
$$;

ALTER FUNCTION api.create_course(TEXT, TEXT, UUID[], TEXT, TEXT) OWNER TO izvor_admin;


DROP FUNCTION api.update_course(UUID, TEXT, TEXT, UUID[]);
DROP FUNCTION spec.update_course(UUID, TEXT, TEXT, UUID[]);

CREATE FUNCTION spec.update_course(
    p_id           UUID,
    p_title        TEXT,
    p_description  TEXT,
    p_category_ids UUID[]
)
RETURNS SETOF api.course
LANGUAGE plpgsql
AS $$
DECLARE
    v_cur_title  TEXT;
    v_cur_desc   TEXT;
    v_cur_cats   UUID[];
    v_distinct   UUID[];
    v_found_cnt  INT;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_id);

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    IF p_category_ids IS NULL OR array_length(p_category_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'category_required';
    END IF;

    SELECT array_agg(DISTINCT cat ORDER BY cat) INTO v_distinct
      FROM unnest(p_category_ids) AS cat;

    SELECT COUNT(*) INTO v_found_cnt
      FROM impl.categories
     WHERE id = ANY(v_distinct);

    IF v_found_cnt <> array_length(v_distinct, 1) THEN
        RAISE EXCEPTION 'category_not_found';
    END IF;

    SELECT title, description
      INTO v_cur_title, v_cur_desc
      FROM impl.courses
     WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found';
    END IF;

    SELECT COALESCE(array_agg(category_id ORDER BY category_id), ARRAY[]::UUID[])
      INTO v_cur_cats
      FROM impl.course_categories
     WHERE course_id = p_id;

    IF v_cur_title    = trim(p_title)
       AND v_cur_desc IS NOT DISTINCT FROM p_description
       AND v_cur_cats = v_distinct THEN
        -- No-op short-circuit: skips the DELETE+INSERT that would otherwise
        -- churn the course_categories join table on an unchanged update.
        RETURN QUERY SELECT * FROM spec.get_course(p_id);
        RETURN;
    END IF;

    UPDATE impl.courses
       SET title       = trim(p_title),
           description = p_description
     WHERE id = p_id;

    DELETE FROM impl.course_categories
     WHERE course_id = p_id
       AND category_id <> ALL (v_distinct);

    INSERT INTO impl.course_categories (tenant_id, course_id, category_id)
    SELECT app.current_tenant(), p_id, cat
      FROM unnest(v_distinct) AS cat
    ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM spec.get_course(p_id);
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid course data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.update_course(UUID, TEXT, TEXT, UUID[]) OWNER TO izvor_admin;

CREATE FUNCTION api.update_course(
    p_id           UUID,
    p_title        TEXT,
    p_description  TEXT,
    p_category_ids UUID[]
)
RETURNS SETOF api.course
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.update_course(p_id, p_title, p_description, p_category_ids);
$$;

ALTER FUNCTION api.update_course(UUID, TEXT, TEXT, UUID[]) OWNER TO izvor_admin;


DROP FUNCTION api.activate_course(UUID);
DROP FUNCTION spec.activate_course(UUID);

CREATE FUNCTION spec.activate_course(p_course_id UUID)
RETURNS SETOF api.course
LANGUAGE plpgsql
AS $$
DECLARE
    v_active BOOLEAN;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_course_id);

    SELECT is_active INTO v_active
    FROM impl.courses
    WHERE id = p_course_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found';
    END IF;

    IF v_active THEN
        RETURN QUERY SELECT * FROM spec.get_course(p_course_id);
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM impl.lessons
         WHERE tenant_id = app.current_tenant()
           AND course_id = p_course_id
    ) THEN
        RAISE EXCEPTION 'course_has_no_lessons';
    END IF;

    UPDATE impl.courses SET is_active = true WHERE id = p_course_id;
    RETURN QUERY SELECT * FROM spec.get_course(p_course_id);
END;
$$;

ALTER FUNCTION spec.activate_course(UUID) OWNER TO izvor_admin;

CREATE FUNCTION api.activate_course(p_course_id UUID)
RETURNS SETOF api.course
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.activate_course(p_course_id);
$$;

ALTER FUNCTION api.activate_course(UUID) OWNER TO izvor_admin;


DROP FUNCTION api.deactivate_course(UUID);
DROP FUNCTION spec.deactivate_course(UUID);

CREATE FUNCTION spec.deactivate_course(p_course_id UUID)
RETURNS SETOF api.course
LANGUAGE plpgsql
AS $$
DECLARE
    v_active BOOLEAN;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_course_id);

    SELECT is_active INTO v_active
    FROM impl.courses
    WHERE id = p_course_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found';
    END IF;

    IF NOT v_active THEN
        RETURN QUERY SELECT * FROM spec.get_course(p_course_id);
        RETURN;
    END IF;

    UPDATE impl.courses SET is_active = false WHERE id = p_course_id;
    RETURN QUERY SELECT * FROM spec.get_course(p_course_id);
END;
$$;

ALTER FUNCTION spec.deactivate_course(UUID) OWNER TO izvor_admin;

CREATE FUNCTION api.deactivate_course(p_course_id UUID)
RETURNS SETOF api.course
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.deactivate_course(p_course_id);
$$;

ALTER FUNCTION api.deactivate_course(UUID) OWNER TO izvor_admin;


DROP FUNCTION api.create_lesson(UUID, TEXT, TEXT);
DROP FUNCTION spec.create_lesson(UUID, TEXT, TEXT);

CREATE FUNCTION spec.create_lesson(
    p_course_id UUID,
    p_title     TEXT,
    p_content   TEXT
)
RETURNS SETOF api.lesson
LANGUAGE plpgsql
AS $$
DECLARE
    v_id       UUID;
    v_position INT;
BEGIN
    PERFORM 1 FROM impl.courses WHERE id = p_course_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    PERFORM spec.assert_course_owner_or_admin(p_course_id);

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

    RETURN QUERY SELECT * FROM spec.get_lesson(v_id);
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid lesson data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.create_lesson(UUID, TEXT, TEXT) OWNER TO izvor_admin;

CREATE FUNCTION api.create_lesson(
    p_course_id UUID,
    p_title     TEXT,
    p_content   TEXT
)
RETURNS SETOF api.lesson
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.create_lesson(p_course_id, p_title, p_content);
$$;

ALTER FUNCTION api.create_lesson(UUID, TEXT, TEXT) OWNER TO izvor_admin;


DROP FUNCTION api.update_lesson(UUID, TEXT, TEXT);
DROP FUNCTION spec.update_lesson(UUID, TEXT, TEXT);

CREATE FUNCTION spec.update_lesson(
    p_lesson_id UUID,
    p_title     TEXT,
    p_content   TEXT
)
RETURNS SETOF api.lesson
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id UUID;
BEGIN
    SELECT course_id INTO v_course_id
    FROM impl.lessons
    WHERE id = p_lesson_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lesson_not_found';
    END IF;

    PERFORM spec.assert_course_owner_or_admin(v_course_id);

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    UPDATE impl.lessons
    SET title   = trim(p_title),
        content = COALESCE(p_content, '')
    WHERE id = p_lesson_id;

    RETURN QUERY SELECT * FROM spec.get_lesson(p_lesson_id);
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid lesson data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.update_lesson(UUID, TEXT, TEXT) OWNER TO izvor_admin;

CREATE FUNCTION api.update_lesson(
    p_lesson_id UUID,
    p_title     TEXT,
    p_content   TEXT
)
RETURNS SETOF api.lesson
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.update_lesson(p_lesson_id, p_title, p_content);
$$;

ALTER FUNCTION api.update_lesson(UUID, TEXT, TEXT) OWNER TO izvor_admin;


DROP FUNCTION api.reorder_lesson(UUID, INT);
DROP FUNCTION spec.reorder_lesson(UUID, INT);

CREATE FUNCTION spec.reorder_lesson(
    p_lesson_id    UUID,
    p_new_position INT
)
RETURNS SETOF api.lesson
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id UUID;
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

    SELECT COUNT(*) INTO v_count
    FROM impl.lessons
    WHERE course_id = v_course_id;

    IF p_new_position < 1 OR p_new_position > v_count THEN
        RAISE EXCEPTION 'position_out_of_range';
    END IF;

    IF p_new_position = v_old_pos THEN
        RETURN QUERY SELECT * FROM spec.get_lesson(p_lesson_id);
        RETURN;
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

    RETURN QUERY SELECT * FROM spec.get_lesson(p_lesson_id);
END;
$$;

ALTER FUNCTION spec.reorder_lesson(UUID, INT) OWNER TO izvor_admin;

CREATE FUNCTION api.reorder_lesson(
    p_lesson_id    UUID,
    p_new_position INT
)
RETURNS SETOF api.lesson
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.reorder_lesson(p_lesson_id, p_new_position);
$$;

ALTER FUNCTION api.reorder_lesson(UUID, INT) OWNER TO izvor_admin;


DROP FUNCTION api.enroll_user(UUID, UUID);
DROP FUNCTION spec.enroll_user(UUID, UUID);

CREATE FUNCTION spec.enroll_user(
    p_user_id   UUID,
    p_course_id UUID
)
RETURNS SETOF api.enrollment
LANGUAGE plpgsql
AS $$
DECLARE
    v_active        BOOLEAN;
    v_user_active   BOOLEAN;
    v_id            UUID;
BEGIN
    SELECT is_active INTO v_active
    FROM impl.courses
    WHERE id = p_course_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found';
    END IF;

    IF NOT v_active THEN
        RAISE EXCEPTION 'course_inactive';
    END IF;

    IF p_user_id <> app.current_user_id() THEN
        PERFORM spec.assert_role('admin');
    END IF;

    SELECT is_active INTO v_user_active
    FROM impl.users
    WHERE id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'user_not_found';
    END IF;

    IF NOT v_user_active THEN
        RAISE EXCEPTION 'user_inactive';
    END IF;

    IF EXISTS (
        SELECT 1 FROM impl.enrollments
        WHERE course_id = p_course_id
          AND user_id   = p_user_id
          AND status    = 'active'
    ) THEN
        RAISE EXCEPTION 'enrollment_already_active';
    END IF;

    INSERT INTO impl.enrollments (tenant_id, course_id, user_id)
    VALUES (app.current_tenant(), p_course_id, p_user_id)
    RETURNING id INTO v_id;

    RETURN QUERY SELECT * FROM spec.get_enrollment(v_id);
END;
$$;

ALTER FUNCTION spec.enroll_user(UUID, UUID) OWNER TO izvor_admin;

CREATE FUNCTION api.enroll_user(
    p_user_id   UUID,
    p_course_id UUID
)
RETURNS SETOF api.enrollment
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.enroll_user(p_user_id, p_course_id);
$$;

ALTER FUNCTION api.enroll_user(UUID, UUID) OWNER TO izvor_admin;


DROP FUNCTION api.cancel_enrollment(UUID);
DROP FUNCTION spec.cancel_enrollment(UUID);

CREATE FUNCTION spec.cancel_enrollment(p_enrollment_id UUID)
RETURNS SETOF api.enrollment
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id UUID;
    v_status  impl.enrollment_status;
BEGIN
    SELECT user_id, status INTO v_user_id, v_status
    FROM impl.enrollments
    WHERE id = p_enrollment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'enrollment_not_found';
    END IF;

    IF v_user_id <> app.current_user_id() THEN
        PERFORM spec.assert_role('admin');
    END IF;

    IF v_status <> 'active' THEN
        RAISE EXCEPTION 'enrollment_not_active';
    END IF;

    UPDATE impl.enrollments
    SET status      = 'cancelled',
        finished_at = NOW()
    WHERE id = p_enrollment_id;

    RETURN QUERY SELECT * FROM spec.get_enrollment(p_enrollment_id);
END;
$$;

ALTER FUNCTION spec.cancel_enrollment(UUID) OWNER TO izvor_admin;

CREATE FUNCTION api.cancel_enrollment(p_enrollment_id UUID)
RETURNS SETOF api.enrollment
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.cancel_enrollment(p_enrollment_id);
$$;

ALTER FUNCTION api.cancel_enrollment(UUID) OWNER TO izvor_admin;


DROP FUNCTION api.create_user(TEXT, TEXT, TEXT);
DROP FUNCTION spec.create_user(TEXT, TEXT, TEXT);

CREATE FUNCTION spec.create_user(
    p_email         TEXT,
    p_password_hash TEXT,
    p_role          TEXT DEFAULT 'learner'
)
RETURNS SETOF api.user
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

    RETURN QUERY SELECT * FROM spec.get_user(v_id);
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'User with email % already exists in this tenant', p_email;
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid user data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.create_user(TEXT, TEXT, TEXT) OWNER TO izvor_admin;

CREATE FUNCTION api.create_user(
    p_email         TEXT,
    p_password_hash TEXT,
    p_role          TEXT DEFAULT 'learner'
)
RETURNS SETOF api.user
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.create_user(p_email, p_password_hash, p_role);
$$;

ALTER FUNCTION api.create_user(TEXT, TEXT, TEXT) OWNER TO izvor_admin;


DROP FUNCTION api.activate_user(UUID);
DROP FUNCTION spec.activate_user(UUID);

CREATE FUNCTION spec.activate_user(p_user_id UUID)
RETURNS SETOF api.user
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM spec.assert_role('admin');

    PERFORM 1 FROM impl.users WHERE id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'user_not_found';
    END IF;

    UPDATE impl.users
    SET is_active = true
    WHERE id = p_user_id AND is_active = false;

    RETURN QUERY SELECT * FROM spec.get_user(p_user_id);
END;
$$;

ALTER FUNCTION spec.activate_user(UUID) OWNER TO izvor_admin;

CREATE FUNCTION api.activate_user(p_user_id UUID)
RETURNS SETOF api.user
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.activate_user(p_user_id);
$$;

ALTER FUNCTION api.activate_user(UUID) OWNER TO izvor_admin;


DROP FUNCTION api.deactivate_user(UUID);
DROP FUNCTION spec.deactivate_user(UUID);

CREATE FUNCTION spec.deactivate_user(p_user_id UUID)
RETURNS SETOF api.user
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM spec.assert_role('admin');

    IF p_user_id = app.current_user_id() THEN
        RAISE EXCEPTION 'cannot_deactivate_self'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    PERFORM 1 FROM impl.users WHERE id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'user_not_found';
    END IF;

    UPDATE impl.users
    SET is_active = false
    WHERE id = p_user_id AND is_active = true;

    PERFORM spec.revoke_all_user_refresh_tokens(p_user_id);

    RETURN QUERY SELECT * FROM spec.get_user(p_user_id);
END;
$$;

ALTER FUNCTION spec.deactivate_user(UUID) OWNER TO izvor_admin;

CREATE FUNCTION api.deactivate_user(p_user_id UUID)
RETURNS SETOF api.user
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.deactivate_user(p_user_id);
$$;

ALTER FUNCTION api.deactivate_user(UUID) OWNER TO izvor_admin;
