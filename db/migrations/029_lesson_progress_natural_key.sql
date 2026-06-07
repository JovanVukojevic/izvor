-- НАПРЕДАК_ЛЕКЦИЈЕ is a weak entity: its identity is (enrollment, lesson)
-- within a tenant, not an independent surrogate. Conceptual ДЕР and the
-- relational model in db/relacioni-model.md both treat (tenant_id,
-- enrollment_id, lesson_id) as the primary key; the physical table was
-- carrying a surrogate (tenant_id, id) PK with the natural key enforced
-- as UNIQUE. This migration aligns the physical schema: drop the
-- surrogate, promote the natural key to PRIMARY KEY. All three model
-- levels now agree (conceptual / relational / physical).
--
-- spec.mark_lesson_complete needs no edit. Its ON CONFLICT clause
-- targets the column tuple (tenant_id, enrollment_id, lesson_id), not
-- the constraint name lesson_progress_unique. PG accepts ON CONFLICT
-- on any unique constraint matching the tuple — so once that same tuple
-- becomes the PRIMARY KEY, the conflict resolution still fires and
-- idempotent semantics are preserved.
--
-- Order is forced by PostgreSQL: cannot DROP ATTRIBUTE from api.lesson_progress
-- while functions returning SETOF api.lesson_progress exist. Same dance as
-- migrations 015 and 018: drop dependent functions → alter type → recreate
-- functions. spec.get_course_completion_stats is dropped+recreated alongside
-- because its body references p.id (cosmetic COUNT(p.id) → COUNT(*)); easier
-- to recreate than to chase CREATE OR REPLACE drift across migrations.

DROP FUNCTION api.get_lesson_progress_by_enrollment(UUID);
DROP FUNCTION spec.get_lesson_progress_by_enrollment(UUID);
DROP FUNCTION spec.get_course_completion_stats(UUID);

ALTER TYPE api.lesson_progress DROP ATTRIBUTE id;

ALTER TABLE impl.lesson_progress DROP CONSTRAINT lesson_progress_pkey;
ALTER TABLE impl.lesson_progress DROP CONSTRAINT lesson_progress_unique;
ALTER TABLE impl.lesson_progress DROP COLUMN id;

ALTER TABLE impl.lesson_progress
    ADD CONSTRAINT lesson_progress_pkey
    PRIMARY KEY (tenant_id, enrollment_id, lesson_id);


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
        SELECT P.enrollment_id, P.lesson_id, P.completed_at
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


CREATE FUNCTION spec.get_course_completion_stats(p_course_id UUID)
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
        LEFT JOIN impl.lesson_progress p ON p.enrollment_id = e.id
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

ALTER FUNCTION spec.get_course_completion_stats(UUID) OWNER TO izvor_admin;

COMMENT ON FUNCTION spec.get_course_completion_stats(UUID) IS
    'Aggregates per-course enrollment counts (total/active/completed/cancelled) and average percent progress (active enrollments only). Course owner or admin.';
