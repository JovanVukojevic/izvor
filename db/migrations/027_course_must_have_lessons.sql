-- A course must always have at least one lesson. Previously this rule fired
-- only at activation (spec.activate_course raises course_has_no_lessons); a
-- zero-lesson course could exist indefinitely in the inactive state. The
-- rule is now permanent: a course-with-zero-lessons row should not be able
-- to exist at all.
--
-- Order inside this migration is load-bearing:
--   1. Per-tenant cleanup of pre-existing zero-lesson courses runs BEFORE
--      any procedure or trigger change, so the new structural rule does not
--      fire against legacy data.
--   2. spec.create_course / api.create_course are dropped and recreated
--      with a wider signature that accepts the first lesson inline.
--   3. spec.delete_lesson grows a course_must_have_lessons pre-check.
--   4. The constraint trigger is installed LAST. If it were created before
--      the cleanup DO block, the per-tenant DELETE of zero-lesson courses
--      would itself trip the trigger.


-- 1. Cleanup of any existing zero-lesson courses.
--
-- Loops over system_impl.tenants (control plane, no RLS) for the same
-- reason as migrations 023 and 025: impl.courses is FORCE-RLS, the loop's
-- seed query must come from a non-RLS source, and the SET LOCAL
-- (set_config(..., true)) of app.current_tenant must stay in the same
-- transaction unit (this DO block) as the DML it gates.
--
-- A zero-lesson course with enrollments should not be reachable under the
-- current rules (enroll_user raises course_inactive on inactive courses
-- since mig 022, and activate_course already required ≥1 lesson). It is
-- still checked explicitly: if found, the migration RAISEs naming the
-- tenant + course so the operator can backfill a lesson manually. No
-- content is invented by the migration.

DO $$
DECLARE
    t_id          UUID;
    t_subdomain   TEXT;
    v_course      RECORD;
    v_enrollments INT;
    v_cleaned     INT;
BEGIN
    FOR t_id, t_subdomain IN
        SELECT id, subdomain FROM system_impl.tenants
    LOOP
        PERFORM set_config('app.current_tenant', t_id::TEXT, true);
        v_cleaned := 0;

        FOR v_course IN
            SELECT c.id, c.title
              FROM impl.courses c
             WHERE c.tenant_id = t_id
               AND NOT EXISTS (
                   SELECT 1 FROM impl.lessons l
                    WHERE l.tenant_id = c.tenant_id
                      AND l.course_id = c.id
               )
        LOOP
            SELECT COUNT(*) INTO v_enrollments
              FROM impl.enrollments
             WHERE tenant_id = t_id
               AND course_id = v_course.id;

            IF v_enrollments > 0 THEN
                RAISE EXCEPTION
                    'Cannot apply 027: tenant=% course=% (id=%) has 0 lessons but % enrollments; backfill a lesson manually before reapplying',
                    t_subdomain, v_course.title, v_course.id, v_enrollments;
            END IF;

            DELETE FROM impl.courses WHERE id = v_course.id;
            v_cleaned := v_cleaned + 1;
        END LOOP;

        RAISE NOTICE 'tenant=% zero-lesson courses cleaned: %', t_subdomain, v_cleaned;
    END LOOP;
END $$;


-- 2. spec.create_course / api.create_course gain (p_first_lesson_title,
-- p_first_lesson_content). Signature change forces DROP + CREATE (cannot
-- CREATE OR REPLACE across a signature change). The first lesson is
-- inserted at position = 1. is_active stays false — no auto-activation,
-- the user still has to click Activate. The column-level DEFAULT and the
-- explicit is_active=false in INSERT stay paired as defense-in-depth
-- (per the column-defaults memory + invariant 7).
--
-- api wrapper drops first: it depends on spec.

DROP FUNCTION api.create_course(TEXT, TEXT, UUID);
DROP FUNCTION spec.create_course(TEXT, TEXT, UUID);

CREATE FUNCTION spec.create_course(
    p_title               TEXT,
    p_description         TEXT,
    p_category_id         UUID,
    p_first_lesson_title  TEXT,
    p_first_lesson_content TEXT
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

    IF p_category_id IS NULL THEN
        RAISE EXCEPTION 'category_required';
    END IF;

    IF p_first_lesson_title IS NULL OR length(trim(p_first_lesson_title)) = 0 THEN
        RAISE EXCEPTION 'First lesson title is required';
    END IF;

    INSERT INTO impl.courses (tenant_id, category_id, author_id, title, description, is_active)
    VALUES (app.current_tenant(), p_category_id, app.current_user_id(),
            trim(p_title), p_description, false)
    RETURNING id INTO v_id;

    INSERT INTO impl.lessons (tenant_id, course_id, title, content, position)
    VALUES (app.current_tenant(), v_id,
            trim(p_first_lesson_title), COALESCE(p_first_lesson_content, ''), 1);

    RETURN v_id;
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'category_not_found';
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid course data: %', SQLERRM;
END;
$$;


CREATE FUNCTION api.create_course(
    p_title               TEXT,
    p_description         TEXT,
    p_category_id         UUID,
    p_first_lesson_title  TEXT,
    p_first_lesson_content TEXT
)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.create_course(p_title, p_description, p_category_id,
                              p_first_lesson_title, p_first_lesson_content);
$$;


-- 3. spec.delete_lesson grows a "would leave course with zero lessons"
-- pre-check. Ordered AFTER lesson_has_progress because progress is the
-- more domain-specific reason ("a learner has touched this") — same
-- error-code precedence ordering as the existing chain.
--
-- The trigger installed below is the structural safety net for any write
-- path that bypasses this procedure. Both raise course_must_have_lessons,
-- so the application sees one error code regardless of which layer fired.

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
        SELECT 1 FROM impl.lesson_progress WHERE lesson_id = p_lesson_id
    ) THEN
        RAISE EXCEPTION 'lesson_has_progress';
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


-- 4. Structural enforcement: a constraint trigger on impl.lessons fires at
-- COMMIT and raises course_must_have_lessons if any course still exists
-- with zero lessons.
--
-- DEFERRABLE INITIALLY DEFERRED is essential because spec.delete_course
-- executes "DELETE FROM impl.lessons WHERE course_id = X" followed by
-- "DELETE FROM impl.courses WHERE id = X" inside a single transaction.
-- An immediate trigger would raise after the first DELETE (course still
-- exists, lessons just hit zero). Deferred to commit time, the parent
-- course is already gone — and the trigger function short-circuits when
-- the parent is missing, treating that as the legitimate cascade path to
-- zero-lessons-and-zero-course.
--
-- Reservation: the raise is for the case where a course STILL EXISTS but
-- has been emptied of lessons. The cascade path (delete lessons AND
-- course in the same transaction) must not raise.
--
-- This rule depends on spec.delete_course performing both deletions
-- inside ONE transaction. If that ever changes (e.g. split across two
-- HTTP-driven transactions), the deferred check assumption breaks and
-- the trigger will raise on every course deletion.
--
-- PostgreSQL constraint triggers must be FOR EACH ROW (transition tables
-- are not supported with the CONSTRAINT keyword), so the trigger function
-- uses OLD per-row instead of an OLD TABLE transition table. For a multi-
-- row DELETE the function fires once per row; at COMMIT each invocation
-- runs the same EXISTS/NOT EXISTS check against the same (tenant_id,
-- course_id) — redundant but cheap, and correct.
--
-- Two triggers: one on DELETE (the common path); one on UPDATE OF
-- course_id (a hypothetical write that moves the last lesson to a
-- different course — same shape of emptiness if not caught).
--
-- Lives in impl per invariant 12 — references impl.* tables specifically,
-- so it belongs to the domain layer, not to app's cross-cutting helpers
-- (see migration 026).
--
-- SECURITY DEFINER + explicit search_path: the trigger is DEFERRED, so it
-- fires at COMMIT — by then the api.* SECURITY DEFINER context that did
-- the DELETE has already returned and we are back to the connection's
-- effective role (izvor_app), which has no USAGE on schema impl. Without
-- SECURITY DEFINER on the trigger function, the deferred check would
-- raise permission denied for schema impl instead of the intended
-- course_must_have_lessons. The explicit search_path mirrors every other
-- SECURITY DEFINER function in the project (invariant 10) — no public
-- in the list, to keep the schema-shadowing protection intact.

CREATE OR REPLACE FUNCTION impl.assert_course_has_lesson()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = impl, app, pg_temp
AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM impl.courses
         WHERE tenant_id = OLD.tenant_id AND id = OLD.course_id
    )
    AND NOT EXISTS (
        SELECT 1 FROM impl.lessons
         WHERE tenant_id = OLD.tenant_id AND course_id = OLD.course_id
    ) THEN
        RAISE EXCEPTION 'course_must_have_lessons';
    END IF;
    RETURN NULL;
END;
$$;


CREATE CONSTRAINT TRIGGER lessons_course_has_lesson_on_delete
    AFTER DELETE ON impl.lessons
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION impl.assert_course_has_lesson();

CREATE CONSTRAINT TRIGGER lessons_course_has_lesson_on_update
    AFTER UPDATE OF course_id ON impl.lessons
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION impl.assert_course_has_lesson();
