ALTER TABLE impl.courses
    ADD COLUMN sequential BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN impl.courses.sequential IS
    'When true, lessons must be completed in position order. Read by 7.3b mark_lesson_complete; toggling on a published course only affects future completions.';


DROP FUNCTION api.list_courses(UUID, TEXT);
DROP FUNCTION api.get_course(UUID);
DROP FUNCTION api.update_course(UUID, TEXT, TEXT, UUID);
DROP FUNCTION spec.list_courses(UUID, impl.course_status);
DROP FUNCTION spec.get_course(UUID);
DROP FUNCTION spec.update_course(UUID, TEXT, TEXT, UUID);

ALTER TYPE api.course ADD ATTRIBUTE sequential BOOLEAN;


-- Toggling sequential on a published course is read-time at completion,
-- not write-time on existing LessonProgress: false -> true gates only
-- future mark_lesson_complete calls; true -> false instantly unblocks
-- any user previously gated. Returns false on no-op (suppresses
-- updated_at bump); returns true if any of the four fields changed.
CREATE FUNCTION spec.update_course(
    p_id          UUID,
    p_title       TEXT,
    p_description TEXT,
    p_category_id UUID,
    p_sequential  BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_status     impl.course_status;
    v_cur_title  TEXT;
    v_cur_desc   TEXT;
    v_cur_cat    UUID;
    v_cur_seq    BOOLEAN;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_id);

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    IF p_sequential IS NULL THEN
        RAISE EXCEPTION 'Sequential is required';
    END IF;

    SELECT status, title, description, category_id, sequential
    INTO   v_status, v_cur_title, v_cur_desc, v_cur_cat, v_cur_seq
    FROM   impl.courses
    WHERE  id = p_id;

    IF v_status = 'archived' THEN
        RAISE EXCEPTION 'course_is_archived';
    END IF;

    IF v_cur_title    = trim(p_title)
       AND v_cur_desc IS NOT DISTINCT FROM p_description
       AND v_cur_cat  IS NOT DISTINCT FROM p_category_id
       AND v_cur_seq  = p_sequential THEN
        RETURN false;
    END IF;

    UPDATE impl.courses
    SET title       = trim(p_title),
        description = p_description,
        category_id = p_category_id,
        sequential  = p_sequential
    WHERE id = p_id;

    RETURN true;
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'category_not_found';
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid course data: %', SQLERRM;
END;
$$;

ALTER FUNCTION spec.update_course(UUID, TEXT, TEXT, UUID, BOOLEAN) OWNER TO izvor_admin;

COMMENT ON FUNCTION spec.update_course(UUID, TEXT, TEXT, UUID, BOOLEAN) IS
    'Updates a course (title/description/category/sequential). Returns false on no-op (no field changed); true otherwise. Rejected on archived courses.';


CREATE FUNCTION api.update_course(
    p_id          UUID,
    p_title       TEXT,
    p_description TEXT,
    p_category_id UUID,
    p_sequential  BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.update_course(p_id, p_title, p_description, p_category_id, p_sequential);
$$;

ALTER FUNCTION api.update_course(UUID, TEXT, TEXT, UUID, BOOLEAN) OWNER TO izvor_admin;

COMMENT ON FUNCTION api.update_course(UUID, TEXT, TEXT, UUID, BOOLEAN) IS
    'Public wrapper for spec.update_course; appended p_sequential parameter in 7.3a.';


CREATE FUNCTION spec.get_course(p_id UUID)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
AS $$
    SELECT id, category_id, author_id, title, description, status::text,
           created_at, updated_at, sequential
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
           created_at, updated_at, sequential
    FROM impl.courses
    WHERE status = COALESCE(p_status_filter, 'published')
      AND (p_category_filter IS NULL OR category_id = p_category_filter)
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
           created_at, updated_at, sequential
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
           created_at, updated_at, sequential
    FROM spec.list_courses(p_category_filter, p_status_filter::impl.course_status);
$$;

ALTER FUNCTION api.list_courses(UUID, TEXT) OWNER TO izvor_admin;


-- 'completed' is reserved for 7.3b transitions: mark_lesson_complete
-- on the final lesson moves an enrollment from active -> completed.
-- Declared up front because ALTER TYPE ADD VALUE cannot run in the
-- same transaction that uses the new value (would force a 2-step
-- migration). No procedure in 7.3a writes 'completed'; the CHECK
-- constraint on completed_at stays inert until 7.3b populates it.
CREATE TYPE impl.enrollment_status AS ENUM ('active', 'completed', 'cancelled');

ALTER TYPE impl.enrollment_status OWNER TO izvor_admin;

COMMENT ON TYPE impl.enrollment_status IS
    'Enrollment lifecycle: active (default), cancelled (7.3a), completed (reserved for 7.3b mark_lesson_complete).';


CREATE TABLE impl.enrollments (
    id            UUID NOT NULL DEFAULT gen_random_uuid(),
    tenant_id     UUID NOT NULL,

    course_id     UUID NOT NULL,
    user_id       UUID NOT NULL,

    status        impl.enrollment_status NOT NULL DEFAULT 'active',

    enrolled_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at  TIMESTAMPTZ,
    cancelled_at  TIMESTAMPTZ,

    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (tenant_id, id),

    FOREIGN KEY (tenant_id, course_id)
        REFERENCES impl.courses (tenant_id, id)
        ON DELETE RESTRICT,

    FOREIGN KEY (tenant_id, user_id)
        REFERENCES impl.users (tenant_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT enrollments_cancelled_at_check
        CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL)),

    CONSTRAINT enrollments_completed_at_check
        CHECK ((status = 'completed') = (completed_at IS NOT NULL))
);

ALTER TABLE impl.enrollments OWNER TO izvor_admin;

COMMENT ON CONSTRAINT enrollments_cancelled_at_check ON impl.enrollments IS
    'Status and cancelled_at must agree: defense-in-depth against drift between state and timestamp.';

COMMENT ON CONSTRAINT enrollments_completed_at_check ON impl.enrollments IS
    'Status and completed_at must agree: inert in 7.3a, ready for 7.3b mark_lesson_complete.';


CREATE INDEX enrollments_tenant_user_status_idx
    ON impl.enrollments (tenant_id, user_id, status);

CREATE INDEX enrollments_tenant_course_status_idx
    ON impl.enrollments (tenant_id, course_id, status);

CREATE UNIQUE INDEX enrollments_active_unique
    ON impl.enrollments (tenant_id, course_id, user_id)
    WHERE status = 'active';

COMMENT ON INDEX impl.enrollments_active_unique IS
    'One active enrollment per (course, user); cancelled and completed rows are not indexed, allowing re-enrollment with audit history preserved.';


CREATE TRIGGER enrollments_set_updated_at
    BEFORE UPDATE ON impl.enrollments
    FOR EACH ROW
    EXECUTE FUNCTION app.set_updated_at();


ALTER TABLE impl.enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE impl.enrollments FORCE  ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON impl.enrollments
    USING       (tenant_id = app.current_tenant())
    WITH CHECK  (tenant_id = app.current_tenant());


CREATE TYPE api.enrollment AS (
    id            UUID,
    course_id     UUID,
    user_id       UUID,
    status        TEXT,
    enrolled_at   TIMESTAMPTZ,
    completed_at  TIMESTAMPTZ,
    cancelled_at  TIMESTAMPTZ,
    created_at    TIMESTAMPTZ,
    updated_at    TIMESTAMPTZ
);

ALTER TYPE api.enrollment OWNER TO izvor_admin;


CREATE FUNCTION spec.enroll_user(
    p_user_id   UUID,
    p_course_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_status impl.course_status;
    v_active BOOLEAN;
    v_id     UUID;
BEGIN
    SELECT status INTO v_status
    FROM impl.courses
    WHERE id = p_course_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found';
    END IF;

    IF v_status = 'archived' THEN
        RAISE EXCEPTION 'course_is_archived';
    ELSIF v_status = 'draft' THEN
        RAISE EXCEPTION 'course_not_published';
    END IF;

    IF p_user_id <> app.current_user_id() THEN
        PERFORM spec.assert_role('admin');
    END IF;

    SELECT is_active INTO v_active
    FROM impl.users
    WHERE id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'user_not_found';
    END IF;

    IF NOT v_active THEN
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


CREATE FUNCTION spec.cancel_enrollment(p_enrollment_id UUID)
RETURNS BOOLEAN
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
    SET status       = 'cancelled',
        cancelled_at = NOW()
    WHERE id = p_enrollment_id;

    RETURN true;
END;
$$;

ALTER FUNCTION spec.cancel_enrollment(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.get_enrollment(p_enrollment_id UUID)
RETURNS SETOF api.enrollment
LANGUAGE sql
STABLE
AS $$
    SELECT id, course_id, user_id, status::text,
           enrolled_at, completed_at, cancelled_at,
           created_at, updated_at
    FROM impl.enrollments
    WHERE id = p_enrollment_id;
$$;

ALTER FUNCTION spec.get_enrollment(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.list_enrollments_by_user(
    p_user_id       UUID,
    p_status_filter TEXT
)
RETURNS SETOF api.enrollment
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF p_user_id <> app.current_user_id()
       AND spec.get_current_role() <> 'admin' THEN
        RAISE EXCEPTION 'not_authorized';
    END IF;

    PERFORM 1 FROM impl.users WHERE id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'user_not_found';
    END IF;

    RETURN QUERY
        SELECT id, course_id, user_id, status::text,
               enrolled_at, completed_at, cancelled_at,
               created_at, updated_at
        FROM impl.enrollments
        WHERE user_id = p_user_id
          AND (p_status_filter IS NULL
               OR status = p_status_filter::impl.enrollment_status)
        ORDER BY enrolled_at DESC;
END;
$$;

ALTER FUNCTION spec.list_enrollments_by_user(UUID, TEXT) OWNER TO izvor_admin;


CREATE FUNCTION spec.list_enrollments_by_course(
    p_course_id     UUID,
    p_status_filter TEXT
)
RETURNS SETOF api.enrollment
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_course_id);

    RETURN QUERY
        SELECT id, course_id, user_id, status::text,
               enrolled_at, completed_at, cancelled_at,
               created_at, updated_at
        FROM impl.enrollments
        WHERE course_id = p_course_id
          AND (p_status_filter IS NULL
               OR status = p_status_filter::impl.enrollment_status)
        ORDER BY enrolled_at DESC;
END;
$$;

ALTER FUNCTION spec.list_enrollments_by_course(UUID, TEXT) OWNER TO izvor_admin;


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


CREATE FUNCTION api.cancel_enrollment(p_enrollment_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.cancel_enrollment(p_enrollment_id);
$$;

ALTER FUNCTION api.cancel_enrollment(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.get_enrollment(p_enrollment_id UUID)
RETURNS SETOF api.enrollment
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
BEGIN
    RETURN QUERY
        SELECT id, course_id, user_id, status,
               enrolled_at, completed_at, cancelled_at,
               created_at, updated_at
        FROM spec.get_enrollment(p_enrollment_id);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'enrollment_not_found';
    END IF;
END;
$$;

ALTER FUNCTION api.get_enrollment(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.list_enrollments_by_user(
    p_user_id       UUID,
    p_status_filter TEXT
)
RETURNS SETOF api.enrollment
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, course_id, user_id, status,
           enrolled_at, completed_at, cancelled_at,
           created_at, updated_at
    FROM spec.list_enrollments_by_user(p_user_id, p_status_filter);
$$;

ALTER FUNCTION api.list_enrollments_by_user(UUID, TEXT) OWNER TO izvor_admin;


CREATE FUNCTION api.list_enrollments_by_course(
    p_course_id     UUID,
    p_status_filter TEXT
)
RETURNS SETOF api.enrollment
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, course_id, user_id, status,
           enrolled_at, completed_at, cancelled_at,
           created_at, updated_at
    FROM spec.list_enrollments_by_course(p_course_id, p_status_filter);
$$;

ALTER FUNCTION api.list_enrollments_by_course(UUID, TEXT) OWNER TO izvor_admin;
