-- Migration 023: collapse course status ENUM into the is_active boolean.
--
-- After mig 022 the meaningful states were (draft, is_active=true),
-- (published, is_active=true), (published, is_active=false). Folding the
-- "draft" state into is_active=false leaves a single axis:
--   * is_active=false → not available to learners (former "draft" or
--                       former soft-delete)
--   * is_active=true  → available to learners (former "published")
--
-- Procedure surface follows: publish_course + restore_course collapse
-- into activate_course (gated by course_has_no_lessons, idempotent on
-- already-active); deactivate_course is the inverse. delete_course
-- becomes hard-only and raises course_has_enrollments when any
-- enrollment row exists (the soft branch is now deactivate_course's
-- job). delete_lesson is allowed regardless of course state, gated by
-- lesson_has_progress.
--
-- The new reader-writer lock pattern: mark_lesson_complete acquires
-- FOR SHARE on the parent course before progress INSERT;
-- delete_lesson holds FOR UPDATE on the same row. Parallel
-- mark_lesson_complete callers share the lock, but a concurrent
-- delete_lesson blocks until they commit.


-- 1. Per-tenant data migration. Folds (draft, is_active=true) into
-- is_active=false. (draft, is_active=false) is unreachable in
-- production, but the explicit AND clause documents intent.
DO $$
DECLARE
    t_id UUID;
BEGIN
    FOR t_id IN SELECT id FROM system_impl.tenants LOOP
        PERFORM set_config('app.current_tenant', t_id::TEXT, true);
        UPDATE impl.courses
           SET is_active = false
         WHERE status = 'draft'
           AND is_active = true;
    END LOOP;
END $$;


-- 2. Drop dependent functions (api wrappers first, then spec).
DROP FUNCTION api.list_courses(UUID, TEXT, BOOLEAN);
DROP FUNCTION api.get_course(UUID);
DROP FUNCTION api.update_course(UUID, TEXT, TEXT, UUID);
DROP FUNCTION api.delete_course(UUID);
DROP FUNCTION api.create_course(TEXT, TEXT, UUID);
DROP FUNCTION api.publish_course(UUID);
DROP FUNCTION api.restore_course(UUID);
DROP FUNCTION api.enroll_user(UUID, UUID);
DROP FUNCTION api.delete_lesson(UUID);

DROP FUNCTION spec.list_courses(UUID, impl.course_status, BOOLEAN);
DROP FUNCTION spec.get_course(UUID);
DROP FUNCTION spec.update_course(UUID, TEXT, TEXT, UUID);
DROP FUNCTION spec.delete_course(UUID);
DROP FUNCTION spec.create_course(TEXT, TEXT, UUID);
DROP FUNCTION spec.publish_course(UUID);
DROP FUNCTION spec.restore_course(UUID);
DROP FUNCTION spec.enroll_user(UUID, UUID);
DROP FUNCTION spec.delete_lesson(UUID);


-- 3. mark_lesson_complete declared v_course_status TEXT only to host an
-- IS NULL existence probe. Replace with a FOR SHARE row-existence
-- probe so the function pairs with delete_lesson's FOR UPDATE on the
-- same row, and so we can drop the type entirely below.
CREATE OR REPLACE FUNCTION spec.mark_lesson_complete(p_lesson_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id          UUID;
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

    PERFORM 1 FROM impl.courses WHERE id = v_course_id FOR SHARE;

    IF NOT FOUND THEN
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


DROP INDEX impl.courses_tenant_active_status_idx;

ALTER TYPE api.course DROP ATTRIBUTE status;

-- Flip the column default before dropping it so any concurrent INSERT
-- on the live system would inherit the safe value. spec.create_course
-- below also sets is_active = false explicitly (defense in depth).
ALTER TABLE impl.courses ALTER COLUMN is_active SET DEFAULT false;

ALTER TABLE impl.courses DROP COLUMN status;
DROP TYPE impl.course_status;


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

    INSERT INTO impl.courses (tenant_id, category_id, author_id, title, description, is_active)
    VALUES (app.current_tenant(), p_category_id, app.current_user_id(), trim(p_title), p_description, false)
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
DECLARE
    v_cur_title  TEXT;
    v_cur_desc   TEXT;
    v_cur_cat    UUID;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_id);

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    SELECT title, description, category_id
    INTO   v_cur_title, v_cur_desc, v_cur_cat
    FROM   impl.courses
    WHERE  id = p_id;

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


-- delete_course is hard-only post-023. The soft branch from mig 022 is
-- now spec.deactivate_course's job. assert_course_owner_or_admin
-- raises course_not_found on missing, so a second call on an
-- already-deleted course consistently raises rather than returning
-- false silently (the row is gone — there is nothing to be idempotent
-- about).
CREATE FUNCTION spec.delete_course(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_id);

    PERFORM 1 FROM impl.courses WHERE id = p_id FOR UPDATE;

    IF EXISTS (SELECT 1 FROM impl.enrollments WHERE course_id = p_id) THEN
        RAISE EXCEPTION 'course_has_enrollments';
    END IF;

    DELETE FROM impl.lessons
     WHERE tenant_id = app.current_tenant()
       AND course_id = p_id;

    DELETE FROM impl.courses WHERE id = p_id;

    RETURN true;
END;
$$;

ALTER FUNCTION spec.delete_course(UUID) OWNER TO izvor_admin;


-- activate_course replaces both publish_course (first-time activation,
-- gated by course_has_no_lessons) and restore_course (reactivation of
-- a previously deactivated course). Idempotent: returns false when
-- already active.
CREATE FUNCTION spec.activate_course(p_course_id UUID)
RETURNS BOOLEAN
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

    IF v_active THEN
        RETURN false;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM impl.lessons
         WHERE tenant_id = app.current_tenant()
           AND course_id = p_course_id
    ) THEN
        RAISE EXCEPTION 'course_has_no_lessons';
    END IF;

    UPDATE impl.courses SET is_active = true WHERE id = p_course_id;
    RETURN true;
END;
$$;

ALTER FUNCTION spec.activate_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.deactivate_course(p_course_id UUID)
RETURNS BOOLEAN
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

    IF NOT v_active THEN
        RETURN false;
    END IF;

    UPDATE impl.courses SET is_active = false WHERE id = p_course_id;
    RETURN true;
END;
$$;

ALTER FUNCTION spec.deactivate_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.get_course(p_id UUID)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
AS $$
    SELECT id, category_id, author_id, title, description,
           created_at, updated_at, is_active
    FROM impl.courses
    WHERE id = p_id;
$$;

ALTER FUNCTION spec.get_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.list_courses(
    p_category_filter UUID    DEFAULT NULL,
    p_active_filter   BOOLEAN DEFAULT NULL
)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
AS $$
    SELECT id, category_id, author_id, title, description,
           created_at, updated_at, is_active
    FROM impl.courses
    WHERE (p_category_filter IS NULL OR category_id = p_category_filter)
      AND (p_active_filter   IS NULL OR is_active   = p_active_filter)
    ORDER BY created_at DESC;
$$;

ALTER FUNCTION spec.list_courses(UUID, BOOLEAN) OWNER TO izvor_admin;


CREATE FUNCTION spec.enroll_user(
    p_user_id   UUID,
    p_course_id UUID
)
RETURNS UUID
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

    RETURN v_id;
END;
$$;

ALTER FUNCTION spec.enroll_user(UUID, UUID) OWNER TO izvor_admin;


-- delete_lesson loses the course_not_draft gate (no more "draft" to
-- check); gains a lesson_has_progress gate so committed learner
-- progress is not silently destroyed by lesson removal. The
-- parent-course FOR UPDATE pairs with mark_lesson_complete's FOR
-- SHARE.
CREATE FUNCTION spec.delete_lesson(p_lesson_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id UUID;
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

    IF EXISTS (
        SELECT 1 FROM impl.lesson_progress WHERE lesson_id = p_lesson_id
    ) THEN
        RAISE EXCEPTION 'lesson_has_progress';
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


CREATE FUNCTION api.activate_course(p_course_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.activate_course(p_course_id);
$$;

ALTER FUNCTION api.activate_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.deactivate_course(p_course_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.deactivate_course(p_course_id);
$$;

ALTER FUNCTION api.deactivate_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.get_course(p_id UUID)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, category_id, author_id, title, description,
           created_at, updated_at, is_active
    FROM spec.get_course(p_id);
$$;

ALTER FUNCTION api.get_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.list_courses(
    p_category_filter UUID    DEFAULT NULL,
    p_active_filter   BOOLEAN DEFAULT NULL
)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, category_id, author_id, title, description,
           created_at, updated_at, is_active
    FROM spec.list_courses(p_category_filter, p_active_filter);
$$;

ALTER FUNCTION api.list_courses(UUID, BOOLEAN) OWNER TO izvor_admin;


CREATE FUNCTION api.enroll_user(
    p_user_id   UUID,
    p_course_id UUID
)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.enroll_user(p_user_id, p_course_id);
$$;

ALTER FUNCTION api.enroll_user(UUID, UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.delete_lesson(p_lesson_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.delete_lesson(p_lesson_id);
$$;

ALTER FUNCTION api.delete_lesson(UUID) OWNER TO izvor_admin;


-- 7. Replacement index. Optimized for the learner-browsing hot path
-- (active courses only); the prior index also keyed on status which
-- no longer exists.
CREATE INDEX courses_tenant_active_idx
    ON impl.courses (tenant_id)
    WHERE is_active = true;
