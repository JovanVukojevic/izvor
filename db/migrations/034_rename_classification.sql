ALTER TABLE impl.course_categories RENAME TO classification;

ALTER TABLE impl.classification RENAME CONSTRAINT course_categories_pkey TO classification_pkey;
ALTER TABLE impl.classification RENAME CONSTRAINT course_categories_tenant_id_category_id_fkey TO classification_tenant_id_category_id_fkey;
ALTER TABLE impl.classification RENAME CONSTRAINT course_categories_tenant_id_course_id_fkey TO classification_tenant_id_course_id_fkey;
ALTER INDEX impl.course_categories_tenant_category_idx RENAME TO classification_tenant_category_idx;

CREATE OR REPLACE FUNCTION spec.create_course(p_title text, p_description text, p_category_ids uuid[], p_first_lesson_title text, p_first_lesson_content text)
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

    IF p_first_lesson_title IS NULL OR length(trim(p_first_lesson_title)) = 0 THEN
        RAISE EXCEPTION 'First lesson title is required';
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
    VALUES (app.current_tenant(), v_id,
            trim(p_first_lesson_title), COALESCE(p_first_lesson_content, ''), 1);

    RETURN QUERY SELECT * FROM spec.get_course(v_id);
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid course data: %', SQLERRM;
END;
$function$;

CREATE OR REPLACE FUNCTION spec.update_course(p_id uuid, p_title text, p_description text, p_category_ids uuid[])
 RETURNS SETOF api.course
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_cur_title  TEXT;
    v_cur_desc   TEXT;
    v_cur_cats   UUID[];
    v_distinct   UUID[];
    v_found_cnt  INT;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_id);

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    IF p_category_ids IS NULL OR array_length(p_category_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'category_required';
    END IF;

    SELECT array_agg(DISTINCT cat ORDER BY cat) INTO v_distinct
      FROM unnest(p_category_ids) AS cat;

    SELECT COUNT(*) INTO v_found_cnt
      FROM impl.categories
     WHERE id = ANY(v_distinct);

    IF v_found_cnt <> array_length(v_distinct, 1) THEN
        RAISE EXCEPTION 'category_not_found';
    END IF;

    SELECT title, description
      INTO v_cur_title, v_cur_desc
      FROM impl.courses
     WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found';
    END IF;

    SELECT COALESCE(array_agg(category_id ORDER BY category_id), ARRAY[]::UUID[])
      INTO v_cur_cats
      FROM impl.classification
     WHERE course_id = p_id;

    IF v_cur_title    = trim(p_title)
       AND v_cur_desc IS NOT DISTINCT FROM p_description
       AND v_cur_cats = v_distinct THEN
        -- No-op short-circuit: skips the DELETE+INSERT that would otherwise
        -- churn the classification join table on an unchanged update.
        RETURN QUERY SELECT * FROM spec.get_course(p_id);
        RETURN;
    END IF;

    UPDATE impl.courses
       SET title       = trim(p_title),
           description = p_description
     WHERE id = p_id;

    DELETE FROM impl.classification
     WHERE course_id = p_id
       AND category_id <> ALL (v_distinct);

    INSERT INTO impl.classification (tenant_id, course_id, category_id)
    SELECT app.current_tenant(), p_id, cat
      FROM unnest(v_distinct) AS cat
    ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM spec.get_course(p_id);
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid course data: %', SQLERRM;
END;
$function$;

CREATE OR REPLACE FUNCTION spec.delete_category(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM spec.assert_role('admin');

    IF EXISTS (
        SELECT 1 FROM impl.classification
         WHERE category_id = p_id
    ) THEN
        RAISE EXCEPTION 'category_in_use';
    END IF;

    DELETE FROM impl.categories
    WHERE id = p_id;

    RETURN FOUND;
END;
$function$;

CREATE OR REPLACE FUNCTION spec.get_course(p_id uuid)
 RETURNS SETOF api.course
 LANGUAGE sql
 STABLE
AS $function$
    SELECT c.id,
           COALESCE(
               (SELECT array_agg(cc.category_id ORDER BY cc.category_id)
                  FROM impl.classification cc
                 WHERE cc.tenant_id = c.tenant_id AND cc.course_id = c.id),
               ARRAY[]::UUID[]
           ) AS category_ids,
           c.author_id, c.title, c.description,
           c.created_at, c.updated_at, c.is_active
      FROM impl.courses c
     WHERE c.id = p_id;
$function$;

CREATE OR REPLACE FUNCTION spec.list_courses(p_category_filter uuid DEFAULT NULL::uuid, p_active_filter boolean DEFAULT NULL::boolean)
 RETURNS SETOF api.course
 LANGUAGE sql
 STABLE
AS $function$
    SELECT c.id,
           COALESCE(
               (SELECT array_agg(cc.category_id ORDER BY cc.category_id)
                  FROM impl.classification cc
                 WHERE cc.tenant_id = c.tenant_id AND cc.course_id = c.id),
               ARRAY[]::UUID[]
           ) AS category_ids,
           c.author_id, c.title, c.description,
           c.created_at, c.updated_at, c.is_active
      FROM impl.courses c
     WHERE (p_category_filter IS NULL OR EXISTS (
               SELECT 1 FROM impl.classification cc
                WHERE cc.tenant_id   = c.tenant_id
                  AND cc.course_id   = c.id
                  AND cc.category_id = p_category_filter))
       AND (p_active_filter IS NULL OR c.is_active = p_active_filter)
     ORDER BY c.created_at DESC;
$function$;

CREATE OR REPLACE FUNCTION impl.assert_course_has_category()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'impl', 'app', 'pg_temp'
AS $function$
BEGIN
    IF EXISTS (
        SELECT 1 FROM impl.courses
         WHERE tenant_id = OLD.tenant_id AND id = OLD.course_id
    )
    AND NOT EXISTS (
        SELECT 1 FROM impl.classification
         WHERE tenant_id = OLD.tenant_id AND course_id = OLD.course_id
    ) THEN
        RAISE EXCEPTION 'course_must_have_categories';
    END IF;
    RETURN NULL;
END;
$function$;
