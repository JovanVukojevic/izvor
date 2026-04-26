-- completed_at distinct from created_at: completed_at is the learner act
-- (mark_lesson_complete call time), created_at is DB row creation. Will
-- usually match, but kept distinct so a future migration may diverge them
-- (e.g., backfilled progress with original completion timestamps).
CREATE TABLE impl.lesson_progress (
    id             UUID NOT NULL DEFAULT gen_random_uuid(),
    tenant_id      UUID NOT NULL,

    enrollment_id  UUID NOT NULL,
    lesson_id      UUID NOT NULL,

    completed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (tenant_id, id),

    FOREIGN KEY (tenant_id, enrollment_id)
        REFERENCES impl.enrollments (tenant_id, id)
        ON DELETE RESTRICT,

    FOREIGN KEY (tenant_id, lesson_id)
        REFERENCES impl.lessons (tenant_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT lesson_progress_unique
        UNIQUE (tenant_id, enrollment_id, lesson_id)
);

ALTER TABLE impl.lesson_progress OWNER TO izvor_admin;

-- The UNIQUE on (tenant_id, enrollment_id, lesson_id) is the only btree
-- on this table. It supports prefix lookups on (tenant_id, enrollment_id)
-- for the enrollment-scoped reads in get_lesson_progress_by_enrollment
-- and get_course_completion_stats. The ORDER BY lessons.position in the
-- former requires a sort step after the JOIN regardless of indexing on
-- lesson_progress; an additional (tenant_id, enrollment_id) index would
-- not eliminate it. Add only if EXPLAIN ANALYZE shows it warranted.

COMMENT ON COLUMN impl.lesson_progress.completed_at IS
    'When the learner marked the lesson complete (the act); distinct from created_at (DB row creation) for audit clarity if a future migration backfills.';


CREATE TRIGGER lesson_progress_set_updated_at
    BEFORE UPDATE ON impl.lesson_progress
    FOR EACH ROW
    EXECUTE FUNCTION app.set_updated_at();


ALTER TABLE impl.lesson_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE impl.lesson_progress FORCE  ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON impl.lesson_progress
    USING       (tenant_id = app.current_tenant())
    WITH CHECK  (tenant_id = app.current_tenant());


CREATE TYPE api.lesson_progress AS (
    id             UUID,
    enrollment_id  UUID,
    lesson_id      UUID,
    completed_at   TIMESTAMPTZ,
    created_at     TIMESTAMPTZ,
    updated_at     TIMESTAMPTZ
);

ALTER TYPE api.lesson_progress OWNER TO izvor_admin;


CREATE TYPE api.course_completion_stats AS (
    course_id             UUID,
    total_enrollments     INT,
    active_count          INT,
    completed_count       INT,
    cancelled_count       INT,
    average_progress_pct  NUMERIC(5,2)
);

ALTER TYPE api.course_completion_stats OWNER TO izvor_admin;


-- Self-only authorization: marking a lesson complete is a learning act,
-- not a management action. Admin has no special privilege here (contrast
-- enroll_user / cancel_enrollment which branch on caller-vs-target).
--
-- Sequential gating is read-time: toggling course.sequential on a
-- published course only affects future calls. (a) sequential always true:
-- enforced per-call. (b) false-then-true with gaps: gaps surface as
-- prerequisite_lesson_incomplete on the next gated call. (c) true-then-
-- false: previously-gated learners unblock immediately. No special-casing.
--
-- Idempotent silent INSERT: second call returns false (create-record
-- semantics — the row should exist, and does). Contrast cancel_enrollment
-- which raises on second call (state-transition semantics).
--
-- Auto-flip skipped for completed enrollments (already terminal); INSERT
-- still proceeds as audit trail for lessons added post-completion.
--
-- Course archived during learning: ALLOWED. Archive is a content-mgmt
-- decision; learners with active enrollments can finish what they started.
CREATE FUNCTION spec.mark_lesson_complete(p_lesson_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id          UUID;
    v_course_status      impl.course_status;
    v_sequential         BOOLEAN;
    v_enrollment_id      UUID;
    v_enrollment_status  impl.enrollment_status;
    v_target_pos         INT;
    v_progress_count     INT;
    v_lesson_count       INT;
BEGIN
    SELECT course_id INTO v_course_id
    FROM impl.lessons
    WHERE id = p_lesson_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lesson_not_found';
    END IF;

    SELECT status, sequential INTO v_course_status, v_sequential
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

    IF v_course_status = 'published'
       AND v_sequential = true
       AND v_enrollment_status = 'active' THEN
        SELECT position INTO v_target_pos
        FROM impl.lessons
        WHERE id = p_lesson_id;

        IF EXISTS (
            SELECT 1 FROM impl.lessons L
            WHERE L.course_id = v_course_id
              AND L.position  < v_target_pos
              AND NOT EXISTS (
                  SELECT 1 FROM impl.lesson_progress P
                  WHERE P.enrollment_id = v_enrollment_id
                    AND P.lesson_id     = L.id
              )
        ) THEN
            RAISE EXCEPTION 'prerequisite_lesson_incomplete';
        END IF;
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

ALTER FUNCTION spec.mark_lesson_complete(UUID) OWNER TO izvor_admin;

COMMENT ON FUNCTION spec.mark_lesson_complete(UUID) IS
    'Records lesson completion for the calling user; idempotent (returns false on duplicate). Enforces sequential gating when course.sequential=true. Auto-flips enrollment to completed when all lessons done.';


-- Authorization: enrollment owner, course author, or admin. Author path
-- mirrors list_enrollments_by_course (7.3a) — instructors see learner
-- progress on their own courses.
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
        SELECT P.id, P.enrollment_id, P.lesson_id,
               P.completed_at, P.created_at, P.updated_at
        FROM impl.lesson_progress P
        JOIN impl.lessons L ON L.id = P.lesson_id
        WHERE P.enrollment_id = p_enrollment_id
        ORDER BY L.position ASC;
END;
$$;

ALTER FUNCTION spec.get_lesson_progress_by_enrollment(UUID) OWNER TO izvor_admin;

COMMENT ON FUNCTION spec.get_lesson_progress_by_enrollment(UUID) IS
    'Lists progress rows for an enrollment, ordered by lesson position. Authorized for: the enrollment owner, the course author, or admin.';


-- Data-centric aggregation: counts and average computed in SQL, returned
-- as a single composite. One round trip, MVCC-consistent snapshot. Moves
-- the calculation to where the data lives (invariant 7).
--
-- average_progress_pct is the mean over ACTIVE enrollments only. Including
-- completed (always 100%) would inflate the metric; the intended reading
-- is "where are my in-flight learners?", not "how complete is the cohort".
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
            COUNT(p.id) AS progress_count
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


CREATE FUNCTION api.mark_lesson_complete(p_lesson_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.mark_lesson_complete(p_lesson_id);
$$;

ALTER FUNCTION api.mark_lesson_complete(UUID) OWNER TO izvor_admin;

COMMENT ON FUNCTION api.mark_lesson_complete(UUID) IS
    'Public wrapper for spec.mark_lesson_complete; self-only authorization (caller''s own enrollment).';


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


CREATE FUNCTION api.get_course_completion_stats(p_course_id UUID)
RETURNS api.course_completion_stats
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.get_course_completion_stats(p_course_id);
$$;

ALTER FUNCTION api.get_course_completion_stats(UUID) OWNER TO izvor_admin;

COMMENT ON FUNCTION api.get_course_completion_stats(UUID) IS
    'Public wrapper for spec.get_course_completion_stats.';
