-- Three business-rule triggers move data-level invariants from procedures
-- into the table layer:
--
--   1. lesson_progress AFTER INSERT auto-flips parent enrollment to
--      'completed' once progress count covers the course's lessons.
--      Previously hand-rolled inside spec.mark_lesson_complete.
--
--   2. enrollments BEFORE INSERT OR UPDATE stamps completed_at /
--      cancelled_at when status transitions to a terminal state and the
--      timestamp is NULL. Complements the existing CHECK biconditional
--      coupling (status, *_at) from migration 013.
--
--   3. users BEFORE INSERT OR UPDATE normalizes email to LOWER(TRIM(...)).
--      Partial UNIQUE index on lower(trim(email)) from migration 005 stays;
--      its functional form is still correct, now redundant in the value
--      sense.
--
-- These are the project's first non-audit triggers. The thesis claim
-- is that the same rules now enforce themselves regardless of write
-- path: a direct INSERT INTO impl.lesson_progress flips the enrollment
-- just as spec.mark_lesson_complete used to.


CREATE OR REPLACE FUNCTION app.auto_complete_enrollment()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_enrollment_id   UUID;
    v_course_id       UUID;
    v_lesson_count    INT;
    v_progress_count  INT;
BEGIN
    v_enrollment_id := NEW.enrollment_id;

    SELECT course_id INTO v_course_id
    FROM impl.enrollments
    WHERE id = v_enrollment_id;

    SELECT COUNT(*) INTO v_lesson_count
    FROM impl.lessons
    WHERE course_id = v_course_id;

    SELECT COUNT(*) INTO v_progress_count
    FROM impl.lesson_progress
    WHERE enrollment_id = v_enrollment_id;

    IF v_progress_count = v_lesson_count AND v_lesson_count > 0 THEN
        UPDATE impl.enrollments
        SET status = 'completed'
        WHERE id = v_enrollment_id
          AND status = 'active';
    END IF;

    RETURN NULL;
END;
$$;


CREATE OR REPLACE FUNCTION app.stamp_enrollment_terminal_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'completed' AND NEW.completed_at IS NULL THEN
        NEW.completed_at := NOW();
    END IF;

    IF NEW.status = 'cancelled' AND NEW.cancelled_at IS NULL THEN
        NEW.cancelled_at := NOW();
    END IF;

    RETURN NEW;
END;
$$;


CREATE OR REPLACE FUNCTION app.normalize_email()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- IS NOT NULL guard: BEFORE triggers fire before CHECK constraints,
    -- so a NULL email must pass through untouched to let the existing
    -- NOT NULL CHECK from migration 005 reject it cleanly.
    IF NEW.email IS NOT NULL THEN
        NEW.email := LOWER(TRIM(NEW.email));
    END IF;
    RETURN NEW;
END;
$$;


CREATE TRIGGER lesson_progress_auto_complete_enrollment
    AFTER INSERT ON impl.lesson_progress
    FOR EACH ROW
    EXECUTE FUNCTION app.auto_complete_enrollment();

CREATE TRIGGER enrollments_stamp_terminal_timestamp
    BEFORE INSERT OR UPDATE ON impl.enrollments
    FOR EACH ROW
    EXECUTE FUNCTION app.stamp_enrollment_terminal_timestamp();

CREATE TRIGGER users_normalize_email
    BEFORE INSERT OR UPDATE ON impl.users
    FOR EACH ROW
    EXECUTE FUNCTION app.normalize_email();


-- spec.mark_lesson_complete loses its auto-flip block (now in trigger).
-- FOR UPDATE on the parent enrollment is preserved: it still serializes
-- parallel INSERTs across callers on the same enrollment so the AFTER
-- INSERT trigger fires inside that lock, keeping the count-equals-count
-- check race-free.
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

    INSERT INTO impl.lesson_progress (tenant_id, enrollment_id, lesson_id)
    VALUES (app.current_tenant(), v_enrollment_id, p_lesson_id)
    ON CONFLICT (tenant_id, enrollment_id, lesson_id) DO NOTHING;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    RETURN true;
END;
$$;
