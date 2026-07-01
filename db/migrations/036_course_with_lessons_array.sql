-- Course creation takes lessons as a jsonb array [{title, content}, ...]; position
-- is derived from array order (1..N), never sent by the caller.
--
-- The "course must have >=1 lesson and >=1 category" rules are made structural at
-- birth: DEFERRABLE INITIALLY DEFERRED AFTER INSERT triggers on impl.courses fire at
-- COMMIT, so any creation path (the procedure or a direct INSERT by another client)
-- that leaves a new course with zero lessons or zero categories is rejected. The
-- pre-existing delete/update constraint triggers guard only removal, not creation.

DROP FUNCTION api.create_course(text, text, uuid[], text, text);
DROP FUNCTION spec.create_course(text, text, uuid[], text, text);

CREATE FUNCTION spec.create_course(
    p_title text,
    p_description text,
    p_category_ids uuid[],
    p_lessons jsonb
)
RETURNS SETOF api.course
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id           UUID;
    v_distinct     UUID[];
    v_found_count  INT;
BEGIN
    PERFORM spec.assert_role('author');

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    IF p_category_ids IS NULL OR array_length(p_category_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'category_required';
    END IF;

    IF p_lessons IS NULL OR jsonb_typeof(p_lessons) <> 'array' OR jsonb_array_length(p_lessons) = 0 THEN
        RAISE EXCEPTION 'lesson_required';
    END IF;

    SELECT array_agg(DISTINCT cat) INTO v_distinct
      FROM unnest(p_category_ids) AS cat;

    SELECT COUNT(*) INTO v_found_count
      FROM impl.categories
     WHERE id = ANY(v_distinct);

    IF v_found_count <> array_length(v_distinct, 1) THEN
        RAISE EXCEPTION 'category_not_found';
    END IF;

    INSERT INTO impl.courses (tenant_id, author_id, title, description, is_active)
    VALUES (app.current_tenant(), app.current_user_id(),
            trim(p_title), p_description, false)
    RETURNING id INTO v_id;

    INSERT INTO impl.classification (tenant_id, course_id, category_id)
    SELECT app.current_tenant(), v_id, cat
      FROM unnest(v_distinct) AS cat;

    INSERT INTO impl.lessons (tenant_id, course_id, title, content, position)
    SELECT app.current_tenant(), v_id, trim(elem->>'title'), COALESCE(elem->>'content', ''), ord
      FROM jsonb_array_elements(p_lessons) WITH ORDINALITY AS t(elem, ord);

    RETURN QUERY SELECT * FROM spec.get_course(v_id);
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid course data: %', SQLERRM;
END;
$function$;

CREATE FUNCTION api.create_course(
    p_title text,
    p_description text,
    p_category_ids uuid[],
    p_lessons jsonb
)
RETURNS SETOF api.course
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
AS $function$
    SELECT * FROM spec.create_course(p_title, p_description, p_category_ids, p_lessons);
$function$;

CREATE FUNCTION impl.assert_new_course_has_lesson()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'impl', 'app', 'pg_temp'
AS $function$
BEGIN
    IF EXISTS (
        SELECT 1 FROM impl.courses
         WHERE tenant_id = NEW.tenant_id AND id = NEW.id
    )
    AND NOT EXISTS (
        SELECT 1 FROM impl.lessons
         WHERE tenant_id = NEW.tenant_id AND course_id = NEW.id
    ) THEN
        RAISE EXCEPTION 'course_must_have_lessons';
    END IF;
    RETURN NULL;
END;
$function$;

CREATE FUNCTION impl.assert_new_course_has_category()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'impl', 'app', 'pg_temp'
AS $function$
BEGIN
    IF EXISTS (
        SELECT 1 FROM impl.courses
         WHERE tenant_id = NEW.tenant_id AND id = NEW.id
    )
    AND NOT EXISTS (
        SELECT 1 FROM impl.classification
         WHERE tenant_id = NEW.tenant_id AND course_id = NEW.id
    ) THEN
        RAISE EXCEPTION 'course_must_have_categories';
    END IF;
    RETURN NULL;
END;
$function$;

CREATE CONSTRAINT TRIGGER courses_has_lesson_on_insert
    AFTER INSERT ON impl.courses
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION impl.assert_new_course_has_lesson();

CREATE CONSTRAINT TRIGGER courses_has_category_on_insert
    AFTER INSERT ON impl.courses
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION impl.assert_new_course_has_category();
