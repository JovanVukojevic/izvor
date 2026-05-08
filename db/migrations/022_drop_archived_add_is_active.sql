-- Migration 022: drop 'archived' from course_status; introduce courses.is_active.
--
-- Conflated axes split:
--   * status     → pure lifecycle (draft | published)
--   * is_active  → pure tombstone (parallel to users.is_active from mig 009)
--
-- delete_course branches: hard delete when no enrollments exist (lessons
-- explicitly cleaned up first, since the FK is ON DELETE RESTRICT), soft
-- delete (is_active = false) when any enrollment of any status exists.
-- restore_course undoes the soft path.
--
-- Order is forced by PostgreSQL: DROP TYPE refuses while functions
-- reference the type; ALTER TYPE ADD ATTRIBUTE on api.course is safest
-- once the dependent function bodies are gone.


ALTER TABLE impl.courses
  ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT true;


DROP INDEX impl.courses_tenant_status_idx;


DROP FUNCTION api.list_courses(UUID, TEXT);
DROP FUNCTION api.get_course(UUID);
DROP FUNCTION api.update_course(UUID, TEXT, TEXT, UUID);
DROP FUNCTION api.delete_course(UUID);
DROP FUNCTION api.create_course(TEXT, TEXT, UUID);
DROP FUNCTION api.publish_course(UUID);
DROP FUNCTION api.enroll_user(UUID, UUID);
DROP FUNCTION api.create_lesson(UUID, TEXT, TEXT);
DROP FUNCTION api.update_lesson(UUID, TEXT, TEXT);
DROP FUNCTION api.reorder_lesson(UUID, INT);
DROP FUNCTION api.delete_lesson(UUID);

DROP FUNCTION spec.list_courses(UUID, impl.course_status);
DROP FUNCTION spec.get_course(UUID);
DROP FUNCTION spec.update_course(UUID, TEXT, TEXT, UUID);
DROP FUNCTION spec.delete_course(UUID);
DROP FUNCTION spec.create_course(TEXT, TEXT, UUID);
DROP FUNCTION spec.publish_course(UUID);
DROP FUNCTION spec.enroll_user(UUID, UUID);
DROP FUNCTION spec.create_lesson(UUID, TEXT, TEXT);
DROP FUNCTION spec.update_lesson(UUID, TEXT, TEXT);
DROP FUNCTION spec.reorder_lesson(UUID, INT);
DROP FUNCTION spec.delete_lesson(UUID);


-- spec.mark_lesson_complete declares v_course_status impl.course_status,
-- which would block DROP TYPE below. CREATE OR REPLACE to switch the
-- variable to TEXT — semantics unchanged.
CREATE OR REPLACE FUNCTION spec.mark_lesson_complete(p_lesson_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id          UUID;
    v_course_status      TEXT;
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

    SELECT status::text INTO v_course_status
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


-- Per-tenant data migration. izvor_admin is subject to FORCE RLS on
-- impl.courses; set_config + DML must live in the same transactional
-- unit (matches mig 020 pattern). For archived courses with no
-- enrollments: hard delete (lessons first, since FK is ON DELETE
-- RESTRICT — same explicit cascade the new spec.delete_course will
-- use). For archived courses with enrollments: remap to (published,
-- is_active=false), preserving the audit history.
DO $$
DECLARE
    t_id UUID;
BEGIN
    FOR t_id IN SELECT id FROM system_impl.tenants LOOP
        PERFORM set_config('app.current_tenant', t_id::TEXT, true);

        DELETE FROM impl.lessons l
         WHERE EXISTS (
             SELECT 1 FROM impl.courses c
              WHERE c.tenant_id = l.tenant_id
                AND c.id        = l.course_id
                AND c.status    = 'archived'
                AND NOT EXISTS (
                  SELECT 1 FROM impl.enrollments e
                   WHERE e.tenant_id = c.tenant_id AND e.course_id = c.id
                )
         );

        DELETE FROM impl.courses c
         WHERE c.status = 'archived'
           AND NOT EXISTS (
             SELECT 1 FROM impl.enrollments e
              WHERE e.tenant_id = c.tenant_id AND e.course_id = c.id
           );

        UPDATE impl.courses
           SET status = 'published', is_active = false
         WHERE status = 'archived';
    END LOOP;
END $$;


ALTER TABLE impl.courses ALTER COLUMN status DROP DEFAULT;

CREATE TYPE impl.course_status_new AS ENUM ('draft', 'published');
ALTER TYPE impl.course_status_new OWNER TO izvor_admin;

ALTER TABLE impl.courses
    ALTER COLUMN status TYPE impl.course_status_new
    USING status::text::impl.course_status_new;

DROP TYPE impl.course_status;
ALTER TYPE impl.course_status_new RENAME TO course_status;

ALTER TABLE impl.courses ALTER COLUMN status SET DEFAULT 'draft';


ALTER TYPE api.course ADD ATTRIBUTE is_active BOOLEAN;


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
    VALUES (app.current_tenant(), p_category_id, app.current_user_id(), trim(p_title), p_description, true)
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


CREATE FUNCTION spec.delete_course(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_active   BOOLEAN;
    v_has_enr  BOOLEAN;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_id);

    SELECT is_active INTO v_active
    FROM impl.courses
    WHERE id = p_id
    FOR UPDATE;

    IF NOT v_active THEN
        RETURN false;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM impl.enrollments WHERE course_id = p_id
    ) INTO v_has_enr;

    IF NOT v_has_enr THEN
        -- Hard branch: no enrollments → wipe lessons (FK is ON DELETE
        -- RESTRICT, so the implicit cascade must be explicit here) then
        -- delete the course row itself.
        DELETE FROM impl.lessons
         WHERE tenant_id = app.current_tenant()
           AND course_id = p_id;

        DELETE FROM impl.courses WHERE id = p_id;
        RETURN true;
    END IF;

    UPDATE impl.courses
    SET is_active = false
    WHERE id = p_id;

    RETURN true;
END;
$$;

ALTER FUNCTION spec.delete_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.restore_course(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_active BOOLEAN;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_id);

    SELECT is_active INTO v_active
    FROM impl.courses
    WHERE id = p_id
    FOR UPDATE;

    IF v_active THEN
        RETURN false;
    END IF;

    UPDATE impl.courses
    SET is_active = true
    WHERE id = p_id;

    RETURN true;
END;
$$;

ALTER FUNCTION spec.restore_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.get_course(p_id UUID)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
AS $$
    SELECT id, category_id, author_id, title, description, status::text,
           created_at, updated_at, is_active
    FROM impl.courses
    WHERE id = p_id;
$$;

ALTER FUNCTION spec.get_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.list_courses(
    p_category_filter UUID DEFAULT NULL,
    p_status_filter   impl.course_status DEFAULT NULL,
    p_active_filter   BOOLEAN DEFAULT NULL
)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
AS $$
    SELECT id, category_id, author_id, title, description, status::text,
           created_at, updated_at, is_active
    FROM impl.courses
    WHERE (p_category_filter IS NULL OR category_id = p_category_filter)
      AND (p_status_filter   IS NULL OR status      = p_status_filter)
      AND (p_active_filter   IS NULL OR is_active   = p_active_filter)
    ORDER BY created_at DESC;
$$;

ALTER FUNCTION spec.list_courses(UUID, impl.course_status, BOOLEAN) OWNER TO izvor_admin;


CREATE FUNCTION spec.publish_course(p_course_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_status       TEXT;
    v_lesson_count INT;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_course_id);

    SELECT status::text INTO v_status FROM impl.courses WHERE id = p_course_id;

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


CREATE FUNCTION spec.enroll_user(
    p_user_id   UUID,
    p_course_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_active        BOOLEAN;
    v_status        TEXT;
    v_user_active   BOOLEAN;
    v_id            UUID;
BEGIN
    SELECT is_active, status::text INTO v_active, v_status
    FROM impl.courses
    WHERE id = p_course_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found';
    END IF;

    IF NOT v_active THEN
        RAISE EXCEPTION 'course_inactive';
    END IF;

    IF v_status <> 'published' THEN
        RAISE EXCEPTION 'course_not_published';
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
    v_status    TEXT;
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

    SELECT status::text INTO v_status FROM impl.courses WHERE id = v_course_id;

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


CREATE FUNCTION api.restore_course(p_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.restore_course(p_id);
$$;

ALTER FUNCTION api.restore_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.get_course(p_id UUID)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, category_id, author_id, title, description, status,
           created_at, updated_at, is_active
    FROM spec.get_course(p_id);
$$;

ALTER FUNCTION api.get_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.list_courses(
    p_category_filter UUID    DEFAULT NULL,
    p_status_filter   TEXT    DEFAULT NULL,
    p_active_filter   BOOLEAN DEFAULT NULL
)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, category_id, author_id, title, description, status,
           created_at, updated_at, is_active
    FROM spec.list_courses(
        p_category_filter,
        p_status_filter::impl.course_status,
        p_active_filter
    );
$$;

ALTER FUNCTION api.list_courses(UUID, TEXT, BOOLEAN) OWNER TO izvor_admin;


CREATE FUNCTION api.publish_course(p_course_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.publish_course(p_course_id);
$$;

ALTER FUNCTION api.publish_course(UUID) OWNER TO izvor_admin;


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


CREATE FUNCTION api.delete_lesson(p_lesson_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.delete_lesson(p_lesson_id);
$$;

ALTER FUNCTION api.delete_lesson(UUID) OWNER TO izvor_admin;


CREATE INDEX courses_tenant_active_status_idx
    ON impl.courses (tenant_id, status)
    WHERE is_active = true;
