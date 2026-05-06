-- impl.lesson_progress is an append-only completion-event table:
-- mark_lesson_complete inserts via ON CONFLICT DO NOTHING and rows are
-- never updated. created_at and updated_at always equal completed_at;
-- they are pure redundancy carried over from tables where state evolves.
-- Drop them, drop the updated_at trigger, trim the api composite type.
-- Order is forced by PostgreSQL: cannot drop type attributes while a
-- function depends on the type. Pattern matches migration 015.

DROP FUNCTION api.get_lesson_progress_by_enrollment(UUID);
DROP FUNCTION spec.get_lesson_progress_by_enrollment(UUID);

ALTER TYPE api.lesson_progress DROP ATTRIBUTE created_at;
ALTER TYPE api.lesson_progress DROP ATTRIBUTE updated_at;


CREATE FUNCTION spec.get_lesson_progress_by_enrollment(p_enrollment_id UUID)
RETURNS SETOF api.lesson_progress
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_user_id   UUID;
    v_course_id UUID;
    v_author_id UUID;
BEGIN
    SELECT user_id, course_id INTO v_user_id, v_course_id
    FROM impl.enrollments
    WHERE id = p_enrollment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'enrollment_not_found';
    END IF;

    IF v_user_id <> app.current_user_id()
       AND spec.get_current_role() <> 'admin' THEN
        SELECT author_id INTO v_author_id
        FROM impl.courses
        WHERE id = v_course_id;

        IF v_author_id IS DISTINCT FROM app.current_user_id() THEN
            RAISE EXCEPTION 'not_authorized';
        END IF;
    END IF;

    RETURN QUERY
        SELECT P.id, P.enrollment_id, P.lesson_id, P.completed_at
        FROM impl.lesson_progress P
        JOIN impl.lessons L ON L.id = P.lesson_id
        WHERE P.enrollment_id = p_enrollment_id
        ORDER BY L.position ASC;
END;
$$;

ALTER FUNCTION spec.get_lesson_progress_by_enrollment(UUID) OWNER TO izvor_admin;

COMMENT ON FUNCTION spec.get_lesson_progress_by_enrollment(UUID) IS
    'Lists progress rows for an enrollment, ordered by lesson position. Authorized for: the enrollment owner, the course author, or admin.';


CREATE FUNCTION api.get_lesson_progress_by_enrollment(p_enrollment_id UUID)
RETURNS SETOF api.lesson_progress
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.get_lesson_progress_by_enrollment(p_enrollment_id);
$$;

ALTER FUNCTION api.get_lesson_progress_by_enrollment(UUID) OWNER TO izvor_admin;

COMMENT ON FUNCTION api.get_lesson_progress_by_enrollment(UUID) IS
    'Public wrapper for spec.get_lesson_progress_by_enrollment.';


DROP TRIGGER lesson_progress_set_updated_at ON impl.lesson_progress;

ALTER TABLE impl.lesson_progress
    DROP COLUMN created_at,
    DROP COLUMN updated_at;
