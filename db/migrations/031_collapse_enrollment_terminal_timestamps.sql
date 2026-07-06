-- impl.enrollments carried two terminal-state timestamps, completed_at and
-- cancelled_at, each with its own biconditional CHECK. A terminal enrollment
-- is either completed or cancelled, never both, so the two columns are never
-- populated at once: collapse them into a single finished_at with one CHECK
-- covering both terminal statuses. status already disambiguates which terminal
-- state was reached, so dropping cancelled_at loses no information.
--
-- DROP ATTRIBUTE on the api.enrollment composite type cannot run while
-- functions depend on it, so the six SETOF api.enrollment functions are
-- dropped first and recreated after the type change (pattern from migrations
-- 015 and 018). The terminal-timestamp trigger lives in impl since migration
-- 026; only its body changes, the trigger wiring is untouched.

ALTER TABLE impl.enrollments
    DROP CONSTRAINT enrollments_completed_at_check,
    DROP CONSTRAINT enrollments_cancelled_at_check;

ALTER TABLE impl.enrollments RENAME COLUMN completed_at TO finished_at;

-- 3. Fold cancelled_at into finished_at for already-cancelled rows so the new
-- biconditional CHECK holds for existing data before it is installed. Per-tenant
-- loop because impl.enrollments has FORCE ROW LEVEL SECURITY (pattern from 023).
DO $$
DECLARE
    t_id UUID;
BEGIN
    FOR t_id IN SELECT id FROM system_impl.tenants LOOP
        PERFORM set_config('app.current_tenant', t_id::TEXT, true);
        UPDATE impl.enrollments
           SET finished_at = cancelled_at
         WHERE status = 'cancelled' AND finished_at IS NULL;
    END LOOP;
END $$;

ALTER TABLE impl.enrollments DROP COLUMN cancelled_at;

ALTER TABLE impl.enrollments
    ADD CONSTRAINT enrollments_finished_at_check
    CHECK ((status IN ('completed', 'cancelled')) = (finished_at IS NOT NULL));


-- 6. Trigger body: stamp the one column on either terminal transition,
-- only when not already supplied (never overwrite an explicit value).
CREATE OR REPLACE FUNCTION impl.stamp_enrollment_terminal_timestamp()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status IN ('completed', 'cancelled') AND NEW.finished_at IS NULL THEN
        NEW.finished_at := NOW();
    END IF;

    RETURN NEW;
END;
$$;


-- 7. cancel_enrollment writes the unified column (defense in depth alongside
-- the trigger above).
CREATE OR REPLACE FUNCTION spec.cancel_enrollment(p_enrollment_id uuid)
RETURNS boolean
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

    RETURN true;
END;
$$;


-- 8. Reshape the api.enrollment composite type. Drop the six dependent
-- functions, rename completed_at -> finished_at in place (keeps its slot),
-- drop cancelled_at, recreate spec.* then api.*.
DROP FUNCTION api.get_enrollment(uuid);
DROP FUNCTION api.list_enrollments_by_user(uuid, text);
DROP FUNCTION api.list_enrollments_by_course(uuid, text);
DROP FUNCTION spec.get_enrollment(uuid);
DROP FUNCTION spec.list_enrollments_by_user(uuid, text);
DROP FUNCTION spec.list_enrollments_by_course(uuid, text);

ALTER TYPE api.enrollment RENAME ATTRIBUTE completed_at TO finished_at;
ALTER TYPE api.enrollment DROP ATTRIBUTE cancelled_at;


CREATE FUNCTION spec.get_enrollment(p_enrollment_id uuid)
RETURNS SETOF api.enrollment
LANGUAGE sql
STABLE
AS $$
    SELECT id, course_id, user_id, status::text,
           enrolled_at, finished_at,
           created_at, updated_at
    FROM impl.enrollments
    WHERE id = p_enrollment_id;
$$;

ALTER FUNCTION spec.get_enrollment(uuid) OWNER TO izvor_admin;


CREATE FUNCTION spec.list_enrollments_by_user(p_user_id uuid, p_status_filter text)
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
               enrolled_at, finished_at,
               created_at, updated_at
        FROM impl.enrollments
        WHERE user_id = p_user_id
          AND (p_status_filter IS NULL
               OR status = p_status_filter::impl.enrollment_status)
        ORDER BY enrolled_at DESC;
END;
$$;

ALTER FUNCTION spec.list_enrollments_by_user(uuid, text) OWNER TO izvor_admin;


CREATE FUNCTION spec.list_enrollments_by_course(p_course_id uuid, p_status_filter text)
RETURNS SETOF api.enrollment
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_course_id);

    RETURN QUERY
        SELECT id, course_id, user_id, status::text,
               enrolled_at, finished_at,
               created_at, updated_at
        FROM impl.enrollments
        WHERE course_id = p_course_id
          AND (p_status_filter IS NULL
               OR status = p_status_filter::impl.enrollment_status)
        ORDER BY enrolled_at DESC;
END;
$$;

ALTER FUNCTION spec.list_enrollments_by_course(uuid, text) OWNER TO izvor_admin;


CREATE FUNCTION api.get_enrollment(p_enrollment_id uuid)
RETURNS SETOF api.enrollment
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
BEGIN
    RETURN QUERY
        SELECT id, course_id, user_id, status,
               enrolled_at, finished_at,
               created_at, updated_at
        FROM spec.get_enrollment(p_enrollment_id);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'enrollment_not_found';
    END IF;
END;
$$;

ALTER FUNCTION api.get_enrollment(uuid) OWNER TO izvor_admin;


CREATE FUNCTION api.list_enrollments_by_user(p_user_id uuid, p_status_filter text)
RETURNS SETOF api.enrollment
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, course_id, user_id, status,
           enrolled_at, finished_at,
           created_at, updated_at
    FROM spec.list_enrollments_by_user(p_user_id, p_status_filter);
$$;

ALTER FUNCTION api.list_enrollments_by_user(uuid, text) OWNER TO izvor_admin;


CREATE FUNCTION api.list_enrollments_by_course(p_course_id uuid, p_status_filter text)
RETURNS SETOF api.enrollment
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, course_id, user_id, status,
           enrolled_at, finished_at,
           created_at, updated_at
    FROM spec.list_enrollments_by_course(p_course_id, p_status_filter);
$$;

ALTER FUNCTION api.list_enrollments_by_course(uuid, text) OWNER TO izvor_admin;
