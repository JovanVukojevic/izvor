-- ЗАВРШЕТАК ЛЕКЦИЈЕ identity refactor. The relational model treats a completion
-- as the triple (enrollment, course, lesson); the physical table carried only
-- (enrollment, lesson) and derived course by join. Promote course_id into the
-- completion identity and make course-consistency structural via composite FKs.
--
-- impl.lessons keeps its surrogate PK (tenant_id, id) for uniform addressing; the
-- weak-entity composite is realized as a separate FK-targetable candidate key
-- UNIQUE (tenant_id, course_id, id). impl.enrollments gains a redundant superset
-- UNIQUE (tenant_id, id, course_id) purely as the bonus-FK target.
--
-- FK validation runs through RLS (migration 020), so the two completion FKs are
-- added under a NO FORCE / FORCE toggle; UNIQUE/CHECK/PK validation does not
-- (migration 029) and SET NOT NULL does not (migration 025); the backfill uses
-- the per-tenant set_config loop from migrations 023/031.

ALTER TABLE impl.lessons
    ADD CONSTRAINT lessons_course_lesson_unique UNIQUE (tenant_id, course_id, id);

ALTER TABLE impl.lessons
    ADD CONSTRAINT lessons_position_check CHECK (position > 0);

ALTER TABLE impl.enrollments
    ADD CONSTRAINT enrollments_id_course_unique UNIQUE (tenant_id, id, course_id);


ALTER TABLE impl.lesson_completion ADD COLUMN course_id UUID;

DO $$
DECLARE
    t_id UUID;
BEGIN
    FOR t_id IN SELECT id FROM system_impl.tenants LOOP
        PERFORM set_config('app.current_tenant', t_id::TEXT, true);
        UPDATE impl.lesson_completion c
           SET course_id = l.course_id
          FROM impl.lessons l
         WHERE l.tenant_id = c.tenant_id
           AND l.id        = c.lesson_id;
    END LOOP;
END $$;

ALTER TABLE impl.lesson_completion ALTER COLUMN course_id SET NOT NULL;


ALTER TABLE impl.lesson_completion DROP CONSTRAINT lesson_completion_pkey;

ALTER TABLE impl.lesson_completion
    ADD CONSTRAINT lesson_completion_pkey
    PRIMARY KEY (tenant_id, enrollment_id, course_id, lesson_id);


-- FK validation runs through RLS (migration 020), so toggle FORCE off on the
-- referencing and referenced tables for the duration of the ADD, then restore.
-- If either ADD raises foreign_key_violation, existing data violates the new
-- structural rule (a completion whose course_id disagrees with its lesson's or
-- enrollment's course) -- that is a real integrity signal, not a thing to patch.
ALTER TABLE impl.lesson_completion NO FORCE ROW LEVEL SECURITY;
ALTER TABLE impl.lessons           NO FORCE ROW LEVEL SECURITY;
ALTER TABLE impl.enrollments       NO FORCE ROW LEVEL SECURITY;

ALTER TABLE impl.lesson_completion
    DROP CONSTRAINT lesson_completion_tenant_id_lesson_id_fkey,
    ADD  CONSTRAINT lesson_completion_tenant_id_course_id_lesson_id_fkey
         FOREIGN KEY (tenant_id, course_id, lesson_id)
         REFERENCES impl.lessons (tenant_id, course_id, id) ON DELETE RESTRICT;

ALTER TABLE impl.lesson_completion
    DROP CONSTRAINT lesson_completion_tenant_id_enrollment_id_fkey,
    ADD  CONSTRAINT lesson_completion_tenant_id_enrollment_id_course_id_fkey
         FOREIGN KEY (tenant_id, enrollment_id, course_id)
         REFERENCES impl.enrollments (tenant_id, id, course_id) ON DELETE RESTRICT;

ALTER TABLE impl.enrollments       FORCE ROW LEVEL SECURITY;
ALTER TABLE impl.lessons           FORCE ROW LEVEL SECURITY;
ALTER TABLE impl.lesson_completion FORCE ROW LEVEL SECURITY;


CREATE OR REPLACE FUNCTION spec.mark_lesson_complete(p_lesson_id uuid)
RETURNS boolean
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

    INSERT INTO impl.lesson_completion (tenant_id, enrollment_id, course_id, lesson_id)
    VALUES (app.current_tenant(), v_enrollment_id, v_course_id, p_lesson_id)
    ON CONFLICT (tenant_id, enrollment_id, course_id, lesson_id) DO NOTHING;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    RETURN true;
END;
$$;
