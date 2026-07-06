-- Migration 021: drop sequential lesson gating.
--
-- Removes the `sequential` flag from courses (added in 013) and the
-- gating block in spec.mark_lesson_complete (014). All courses now
-- behave as non-sequential — lessons can be completed in any order.
-- The `position` column on impl.lessons is preserved as display
-- ordering for the UI; only the gating semantics tied to sequential
-- are removed.
--
-- Order is forced by PostgreSQL: ALTER TYPE DROP ATTRIBUTE fails
-- while functions reference the type, ALTER TABLE DROP COLUMN fails
-- while function bodies reference the column. Pattern matches 015 / 018.


-- Same signature, so CREATE OR REPLACE works without DROP.
-- api.mark_lesson_complete is unchanged (thin SELECT pass-through).
CREATE OR REPLACE FUNCTION spec.mark_lesson_complete(p_lesson_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id          UUID;
    v_course_status      impl.course_status;
    v_enrollment_id      UUID;
    v_enrollment_status  impl.enrollment_status;
    v_progress_count     INT;
    v_lesson_count       INT;
BEGIN
    SELECT course_id INTO v_course_id
    FROM impl.lessons
    WHERE id = p_lesson_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lesson_not_found';
    END IF;

    SELECT status INTO v_course_status
    FROM impl.courses
    WHERE id = v_course_id;

    IF v_course_status IS NULL THEN
        RAISE EXCEPTION 'course_not_found';
    END IF;

    SELECT id, status INTO v_enrollment_id, v_enrollment_status
    FROM impl.enrollments
    WHERE course_id = v_course_id
      AND user_id   = app.current_user_id()
    ORDER BY enrolled_at DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'not_enrolled';
    END IF;

    IF v_enrollment_status = 'cancelled' THEN
        RAISE EXCEPTION 'enrollment_cancelled';
    END IF;

    PERFORM 1 FROM impl.enrollments WHERE id = v_enrollment_id FOR UPDATE;

    INSERT INTO impl.lesson_progress (tenant_id, enrollment_id, lesson_id)
    VALUES (app.current_tenant(), v_enrollment_id, p_lesson_id)
    ON CONFLICT (tenant_id, enrollment_id, lesson_id) DO NOTHING;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    IF v_enrollment_status = 'active' THEN
        SELECT COUNT(*) INTO v_progress_count
        FROM impl.lesson_progress
        WHERE enrollment_id = v_enrollment_id;

        SELECT COUNT(*) INTO v_lesson_count
        FROM impl.lessons
        WHERE course_id = v_course_id;

        IF v_progress_count = v_lesson_count THEN
            UPDATE impl.enrollments
            SET status       = 'completed',
                completed_at = NOW()
            WHERE id = v_enrollment_id;
        END IF;
    END IF;

    RETURN true;
END;
$$;

COMMENT ON FUNCTION spec.mark_lesson_complete(UUID) IS
    'Records lesson completion for the calling user; idempotent (returns false on duplicate). Auto-flips enrollment to completed when all lessons done.';


-- spec.create_course and api.create_course never took p_sequential
-- (verified against 011) so they are not dropped.
DROP FUNCTION api.list_courses(UUID, TEXT);
DROP FUNCTION api.get_course(UUID);
DROP FUNCTION api.update_course(UUID, TEXT, TEXT, UUID, BOOLEAN);
DROP FUNCTION spec.list_courses(UUID, impl.course_status);
DROP FUNCTION spec.get_course(UUID);
DROP FUNCTION spec.update_course(UUID, TEXT, TEXT, UUID, BOOLEAN);


ALTER TYPE api.course DROP ATTRIBUTE sequential;


ALTER TABLE impl.courses DROP COLUMN sequential;


CREATE FUNCTION spec.update_course(
    p_id          UUID,
    p_title       TEXT,
    p_description TEXT,
    p_category_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_status     impl.course_status;
    v_cur_title  TEXT;
    v_cur_desc   TEXT;
    v_cur_cat    UUID;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_id);

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    SELECT status, title, description, category_id
    INTO   v_status, v_cur_title, v_cur_desc, v_cur_cat
    FROM   impl.courses
    WHERE  id = p_id;

    IF v_status = 'archived' THEN
        RAISE EXCEPTION 'course_is_archived';
    END IF;

    IF v_cur_title    = trim(p_title)
       AND v_cur_desc IS NOT DISTINCT FROM p_description
       AND v_cur_cat  IS NOT DISTINCT FROM p_category_id THEN
        RETURN false;
    END IF;

    UPDATE impl.courses
    SET title       = trim(p_title),
        description = p_description,
        category_id = p_category_id
    WHERE id = p_id;

    RETURN true;
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'category_not_found';
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid course data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.update_course(UUID, TEXT, TEXT, UUID) OWNER TO izvor_admin;

COMMENT ON FUNCTION spec.update_course(UUID, TEXT, TEXT, UUID) IS
    'Updates a course (title/description/category). Returns false on no-op (no field changed); true otherwise. Rejected on archived courses.';


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

COMMENT ON FUNCTION api.update_course(UUID, TEXT, TEXT, UUID) IS
    'Public wrapper for spec.update_course.';


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
    WHERE (p_category_filter IS NULL OR category_id = p_category_filter)
      AND (p_status_filter   IS NULL OR status      = p_status_filter)
    ORDER BY created_at DESC;
$$;

ALTER FUNCTION spec.list_courses(UUID, impl.course_status) OWNER TO izvor_admin;


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
