-- Migration 026: relocate three business-rule trigger functions from app to impl.
--
-- Classification rule: trigger functions whose body references specific tables
-- or columns of a single entity belong in that entity's home schema. The three
-- functions added in migration 024 (auto_complete_enrollment,
-- stamp_enrollment_terminal_timestamp, normalize_email) each reference only
-- impl.* tables; they belong in impl, not in app. The genuinely cross-cutting
-- helpers (current_tenant, current_user_id, set_updated_at — the last shared
-- across impl.* and system_impl.tenants) stay in app.
--
-- Function bodies are byte-identical to the current state; only the schema
-- qualifier changes. Wrapped in an explicit BEGIN/COMMIT because ON_ERROR_STOP
-- aborts but does not group statements into one transaction — and the three
-- trigger pointer flips plus three function drops form one logical operation
-- that must apply atomically.

BEGIN;

CREATE OR REPLACE FUNCTION impl.auto_complete_enrollment() RETURNS trigger
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

CREATE OR REPLACE FUNCTION impl.stamp_enrollment_terminal_timestamp() RETURNS trigger
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

CREATE OR REPLACE FUNCTION impl.normalize_email() RETURNS trigger
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

DROP TRIGGER IF EXISTS users_normalize_email ON impl.users;
CREATE TRIGGER users_normalize_email
    BEFORE INSERT OR UPDATE ON impl.users
    FOR EACH ROW EXECUTE FUNCTION impl.normalize_email();

DROP TRIGGER IF EXISTS enrollments_stamp_terminal_timestamp ON impl.enrollments;
CREATE TRIGGER enrollments_stamp_terminal_timestamp
    BEFORE INSERT OR UPDATE ON impl.enrollments
    FOR EACH ROW EXECUTE FUNCTION impl.stamp_enrollment_terminal_timestamp();

DROP TRIGGER IF EXISTS lesson_progress_auto_complete_enrollment ON impl.lesson_progress;
CREATE TRIGGER lesson_progress_auto_complete_enrollment
    AFTER INSERT ON impl.lesson_progress
    FOR EACH ROW EXECUTE FUNCTION impl.auto_complete_enrollment();

DROP FUNCTION IF EXISTS app.auto_complete_enrollment();
DROP FUNCTION IF EXISTS app.stamp_enrollment_terminal_timestamp();
DROP FUNCTION IF EXISTS app.normalize_email();

COMMIT;
