-- The entity records a single point-in-time completion event: only
-- completed_at, no surrogate key after migration 029 promoted the natural
-- (tenant_id, enrollment_id, lesson_id) tuple to PRIMARY KEY, and the
-- table is append-only via mark_lesson_complete with ON CONFLICT DO
-- NOTHING. "progress" wrongly suggested a mutable percentage; "completion"
-- names the act. Thesis-side this aligns with ЗАВРШЕТАК ЛЕКЦИЈЕ replacing
-- НАПРЕДАК ЛЕКЦИЈЕ in the verbal model.
--
-- Pure name surgery: no data migration, no constraint relaxation, no
-- CHECK changes, no signature changes. Composite type rename works in
-- place because PG resolves return types by OID — functions returning
-- SETOF api.lesson_progress remain valid after the type rename (unlike
-- DROP ATTRIBUTE in migrations 015/018/029, which DOES require dropping
-- dependents).
--
-- Action verbs stay: spec.mark_lesson_complete, impl.auto_complete_enrollment.
-- Only entity-named identifiers change.

-- 1. Rename table.
ALTER TABLE impl.lesson_progress RENAME TO lesson_completion;

-- 2. Rename composite type (does NOT require dropping returning functions).
ALTER TYPE api.lesson_progress RENAME TO lesson_completion;

-- 3. Rename constraints + trigger for cosmetic consistency.
ALTER TABLE impl.lesson_completion
    RENAME CONSTRAINT lesson_progress_pkey TO lesson_completion_pkey;

ALTER TABLE impl.lesson_completion
    RENAME CONSTRAINT lesson_progress_tenant_id_enrollment_id_fkey
                   TO lesson_completion_tenant_id_enrollment_id_fkey;

ALTER TABLE impl.lesson_completion
    RENAME CONSTRAINT lesson_progress_tenant_id_lesson_id_fkey
                   TO lesson_completion_tenant_id_lesson_id_fkey;

ALTER TRIGGER lesson_progress_auto_complete_enrollment
    ON impl.lesson_completion
    RENAME TO lesson_completion_auto_complete_enrollment;

-- 4. Rename the entity-named read functions.
ALTER FUNCTION spec.get_lesson_progress_by_enrollment(UUID)
    RENAME TO get_lesson_completion_by_enrollment;

ALTER FUNCTION api.get_lesson_progress_by_enrollment(UUID)
    RENAME TO get_lesson_completion_by_enrollment;

-- 5. Recreate function bodies that string-reference the old table name.

CREATE OR REPLACE FUNCTION spec.get_lesson_completion_by_enrollment(p_enrollment_id UUID)
RETURNS SETOF api.lesson_completion
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
        SELECT C.enrollment_id, C.lesson_id, C.completed_at
        FROM impl.lesson_completion C
        JOIN impl.lessons L ON L.id = C.lesson_id
        WHERE C.enrollment_id = p_enrollment_id
        ORDER BY L.position ASC;
END;
$$;

ALTER FUNCTION spec.get_lesson_completion_by_enrollment(UUID) OWNER TO izvor_admin;

COMMENT ON FUNCTION spec.get_lesson_completion_by_enrollment(UUID) IS
    'Lists completion rows for an enrollment, ordered by lesson position. Authorized for: the enrollment owner, the course author, or admin.';


CREATE OR REPLACE FUNCTION api.get_lesson_completion_by_enrollment(p_enrollment_id UUID)
RETURNS SETOF api.lesson_completion
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.get_lesson_completion_by_enrollment(p_enrollment_id);
$$;

ALTER FUNCTION api.get_lesson_completion_by_enrollment(UUID) OWNER TO izvor_admin;

COMMENT ON FUNCTION api.get_lesson_completion_by_enrollment(UUID) IS
    'Public wrapper for spec.get_lesson_completion_by_enrollment.';


CREATE OR REPLACE FUNCTION spec.mark_lesson_complete(p_lesson_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id          UUID;
    v_enrollment_id      UUID;
    v_enrollment_status  impl.enrollment_status;
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

    INSERT INTO impl.lesson_completion (tenant_id, enrollment_id, lesson_id)
    VALUES (app.current_tenant(), v_enrollment_id, p_lesson_id)
    ON CONFLICT (tenant_id, enrollment_id, lesson_id) DO NOTHING;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    RETURN true;
END;
$$;


-- spec.delete_lesson: same body as migration 027, with two edits — table
-- reference updated and the EXISTS-guard raise renamed from
-- lesson_has_progress to lesson_has_completions (the error code's full
-- meaning is "this lesson has rows in the completion table"; "progress"
-- becomes dead vocabulary after this migration).
CREATE OR REPLACE FUNCTION spec.delete_lesson(p_lesson_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id     UUID;
    v_old_pos       INT;
    v_lesson_count  INT;
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
        SELECT 1 FROM impl.lesson_completion WHERE lesson_id = p_lesson_id
    ) THEN
        RAISE EXCEPTION 'lesson_has_completions';
    END IF;

    SELECT COUNT(*) INTO v_lesson_count
    FROM impl.lessons
    WHERE course_id = v_course_id;

    IF v_lesson_count <= 1 THEN
        RAISE EXCEPTION 'course_must_have_lessons';
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


CREATE OR REPLACE FUNCTION spec.get_course_completion_stats(p_course_id UUID)
RETURNS api.course_completion_stats
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result api.course_completion_stats;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_course_id);

    WITH enrollment_counts AS (
        SELECT
            COUNT(*)                                              AS total,
            COUNT(*) FILTER (WHERE status = 'active')             AS active,
            COUNT(*) FILTER (WHERE status = 'completed')          AS completed,
            COUNT(*) FILTER (WHERE status = 'cancelled')          AS cancelled
        FROM impl.enrollments
        WHERE course_id = p_course_id
    ),
    lesson_total AS (
        SELECT COUNT(*) AS n FROM impl.lessons WHERE course_id = p_course_id
    ),
    active_progress AS (
        SELECT
            e.id AS enrollment_id,
            COUNT(*) AS progress_count
        FROM impl.enrollments e
        LEFT JOIN impl.lesson_completion c ON c.enrollment_id = e.id
        WHERE e.course_id = p_course_id AND e.status = 'active'
        GROUP BY e.id
    ),
    avg_pct AS (
        SELECT
            CASE
                WHEN (SELECT n FROM lesson_total) = 0 THEN 0.00
                WHEN COUNT(*) = 0                     THEN 0.00
                ELSE ROUND(
                    AVG(progress_count * 100.0 / (SELECT n FROM lesson_total))::NUMERIC,
                    2
                )
            END AS pct
        FROM active_progress
    )
    SELECT
        p_course_id,
        ec.total::INT,
        ec.active::INT,
        ec.completed::INT,
        ec.cancelled::INT,
        ap.pct
    INTO v_result
    FROM enrollment_counts ec, avg_pct ap;

    RETURN v_result;
END;
$$;


CREATE OR REPLACE FUNCTION impl.auto_complete_enrollment()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_enrollment_id   UUID;
    v_course_id       UUID;
    v_lesson_count    INT;
    v_completion_count  INT;
BEGIN
    v_enrollment_id := NEW.enrollment_id;

    SELECT course_id INTO v_course_id
    FROM impl.enrollments
    WHERE id = v_enrollment_id;

    SELECT COUNT(*) INTO v_lesson_count
    FROM impl.lessons
    WHERE course_id = v_course_id;

    SELECT COUNT(*) INTO v_completion_count
    FROM impl.lesson_completion
    WHERE enrollment_id = v_enrollment_id;

    IF v_completion_count = v_lesson_count AND v_lesson_count > 0 THEN
        UPDATE impl.enrollments
        SET status = 'completed'
        WHERE id = v_enrollment_id
          AND status = 'active';
    END IF;

    RETURN NULL;
END;
$$;
