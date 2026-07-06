-- Surface the author's / enrolled user's email on api.course and api.enrollment
-- so the frontend can render a human-readable identity instead of a bare UUID
-- (impl.users has no name column — email is the identity).
--
-- Email is added as a tenant-scoped correlated subquery against impl.users,
-- mirroring how get_course already assembles category_ids. A subquery (not a
-- JOIN) keeps a hard-deleted author/user from ever dropping the parent row and
-- avoids aliasing every existing column list. The subquery reads impl.users
-- (FORCE RLS, tenant_isolation) under the api SECURITY DEFINER wrapper with
-- app.current_tenant set; the author/user is same-tenant, so RLS admits the row.
--
-- ADD ATTRIBUTE forces every function that names the composite type in its
-- signature to be dropped first and recreated after. Drop order: api wrappers
-- (SQL-language, hard-depend on spec) before spec; recreate spec (get_* first,
-- since siblings delegate to it) before api.

DROP FUNCTION api.get_course(uuid);
DROP FUNCTION api.list_courses(uuid, boolean);
DROP FUNCTION api.create_course(text, text, uuid[], jsonb);
DROP FUNCTION api.update_course(uuid, text, text, uuid[]);
DROP FUNCTION api.activate_course(uuid);
DROP FUNCTION api.deactivate_course(uuid);

DROP FUNCTION api.get_enrollment(uuid);
DROP FUNCTION api.list_enrollments_by_course(uuid, text);
DROP FUNCTION api.list_enrollments_by_user(uuid, text);
DROP FUNCTION api.enroll_user(uuid, uuid);
DROP FUNCTION api.cancel_enrollment(uuid);

DROP FUNCTION spec.get_course(uuid);
DROP FUNCTION spec.list_courses(uuid, boolean);
DROP FUNCTION spec.create_course(text, text, uuid[], jsonb);
DROP FUNCTION spec.update_course(uuid, text, text, uuid[]);
DROP FUNCTION spec.activate_course(uuid);
DROP FUNCTION spec.deactivate_course(uuid);

DROP FUNCTION spec.get_enrollment(uuid);
DROP FUNCTION spec.list_enrollments_by_course(uuid, text);
DROP FUNCTION spec.list_enrollments_by_user(uuid, text);
DROP FUNCTION spec.enroll_user(uuid, uuid);
DROP FUNCTION spec.cancel_enrollment(uuid);

ALTER TYPE api.course ADD ATTRIBUTE author_email text;
ALTER TYPE api.enrollment ADD ATTRIBUTE user_email text;

CREATE FUNCTION spec.get_course(p_id uuid) RETURNS SETOF api.course
    LANGUAGE sql STABLE
    AS $$
    SELECT c.id,
           COALESCE(
               (SELECT array_agg(cc.category_id ORDER BY cc.category_id)
                  FROM impl.classification cc
                 WHERE cc.tenant_id = c.tenant_id AND cc.course_id = c.id),
               ARRAY[]::UUID[]
           ) AS category_ids,
           c.author_id, c.title, c.description,
           c.created_at, c.updated_at, c.is_active,
           (SELECT u.email FROM impl.users u
             WHERE u.tenant_id = c.tenant_id AND u.id = c.author_id) AS author_email
      FROM impl.courses c
     WHERE c.id = p_id;
$$;


CREATE FUNCTION spec.list_courses(p_category_filter uuid DEFAULT NULL::uuid, p_active_filter boolean DEFAULT NULL::boolean) RETURNS SETOF api.course
    LANGUAGE sql STABLE
    AS $$
    SELECT c.id,
           COALESCE(
               (SELECT array_agg(cc.category_id ORDER BY cc.category_id)
                  FROM impl.classification cc
                 WHERE cc.tenant_id = c.tenant_id AND cc.course_id = c.id),
               ARRAY[]::UUID[]
           ) AS category_ids,
           c.author_id, c.title, c.description,
           c.created_at, c.updated_at, c.is_active,
           (SELECT u.email FROM impl.users u
             WHERE u.tenant_id = c.tenant_id AND u.id = c.author_id) AS author_email
      FROM impl.courses c
     WHERE (p_category_filter IS NULL OR EXISTS (
               SELECT 1 FROM impl.classification cc
                WHERE cc.tenant_id   = c.tenant_id
                  AND cc.course_id   = c.id
                  AND cc.category_id = p_category_filter))
       AND (p_active_filter IS NULL OR c.is_active = p_active_filter)
     ORDER BY c.created_at DESC;
$$;


CREATE FUNCTION spec.create_course(p_title text, p_description text, p_category_ids uuid[], p_lessons jsonb) RETURNS SETOF api.course
    LANGUAGE plpgsql
    AS $$
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
$$;


CREATE FUNCTION spec.update_course(p_id uuid, p_title text, p_description text, p_category_ids uuid[]) RETURNS SETOF api.course
    LANGUAGE plpgsql
    AS $$
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
$$;


CREATE FUNCTION spec.activate_course(p_course_id uuid) RETURNS SETOF api.course
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_active BOOLEAN;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_course_id);

    SELECT is_active INTO v_active
    FROM impl.courses
    WHERE id = p_course_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found';
    END IF;

    IF v_active THEN
        RETURN QUERY SELECT * FROM spec.get_course(p_course_id);
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM impl.lessons
         WHERE tenant_id = app.current_tenant()
           AND course_id = p_course_id
    ) THEN
        RAISE EXCEPTION 'course_has_no_lessons';
    END IF;

    UPDATE impl.courses SET is_active = true WHERE id = p_course_id;
    RETURN QUERY SELECT * FROM spec.get_course(p_course_id);
END;
$$;


CREATE FUNCTION spec.deactivate_course(p_course_id uuid) RETURNS SETOF api.course
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_active BOOLEAN;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_course_id);

    SELECT is_active INTO v_active
    FROM impl.courses
    WHERE id = p_course_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found';
    END IF;

    IF NOT v_active THEN
        RETURN QUERY SELECT * FROM spec.get_course(p_course_id);
        RETURN;
    END IF;

    UPDATE impl.courses SET is_active = false WHERE id = p_course_id;
    RETURN QUERY SELECT * FROM spec.get_course(p_course_id);
END;
$$;

CREATE FUNCTION spec.get_enrollment(p_enrollment_id uuid) RETURNS SETOF api.enrollment
    LANGUAGE sql STABLE
    AS $$
    SELECT e.id, e.course_id, e.user_id, e.status::text,
           e.enrolled_at, e.finished_at,
           e.created_at, e.updated_at,
           (SELECT u.email FROM impl.users u
             WHERE u.tenant_id = e.tenant_id AND u.id = e.user_id) AS user_email
    FROM impl.enrollments e
    WHERE e.id = p_enrollment_id;
$$;


CREATE FUNCTION spec.list_enrollments_by_course(p_course_id uuid, p_status_filter text) RETURNS SETOF api.enrollment
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_course_id);

    RETURN QUERY
        SELECT e.id, e.course_id, e.user_id, e.status::text,
               e.enrolled_at, e.finished_at,
               e.created_at, e.updated_at,
               (SELECT u.email FROM impl.users u
                 WHERE u.tenant_id = e.tenant_id AND u.id = e.user_id) AS user_email
        FROM impl.enrollments e
        WHERE e.course_id = p_course_id
          AND (p_status_filter IS NULL
               OR e.status = p_status_filter::impl.enrollment_status)
        ORDER BY e.enrolled_at DESC;
END;
$$;


CREATE FUNCTION spec.list_enrollments_by_user(p_user_id uuid, p_status_filter text) RETURNS SETOF api.enrollment
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    IF p_user_id <> app.current_user_id()
       AND spec.get_current_role() <> 'admin' THEN
        RAISE EXCEPTION 'not_authorized';
    END IF;

    PERFORM 1 FROM impl.users WHERE id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'user_not_found';
    END IF;

    RETURN QUERY
        SELECT e.id, e.course_id, e.user_id, e.status::text,
               e.enrolled_at, e.finished_at,
               e.created_at, e.updated_at,
               (SELECT u.email FROM impl.users u
                 WHERE u.tenant_id = e.tenant_id AND u.id = e.user_id) AS user_email
        FROM impl.enrollments e
        WHERE e.user_id = p_user_id
          AND (p_status_filter IS NULL
               OR e.status = p_status_filter::impl.enrollment_status)
        ORDER BY e.enrolled_at DESC;
END;
$$;


CREATE FUNCTION spec.enroll_user(p_user_id uuid, p_course_id uuid) RETURNS SETOF api.enrollment
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_active        BOOLEAN;
    v_user_active   BOOLEAN;
    v_id            UUID;
BEGIN
    SELECT is_active INTO v_active
    FROM impl.courses
    WHERE id = p_course_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found';
    END IF;

    IF NOT v_active THEN
        RAISE EXCEPTION 'course_inactive';
    END IF;

    IF p_user_id <> app.current_user_id() THEN
        PERFORM spec.assert_role('admin');
    END IF;

    SELECT is_active INTO v_user_active
    FROM impl.users
    WHERE id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'user_not_found';
    END IF;

    IF NOT v_user_active THEN
        RAISE EXCEPTION 'user_inactive';
    END IF;

    IF EXISTS (
        SELECT 1 FROM impl.enrollments
        WHERE course_id = p_course_id
          AND user_id   = p_user_id
          AND status    = 'active'
    ) THEN
        RAISE EXCEPTION 'enrollment_already_active';
    END IF;

    INSERT INTO impl.enrollments (tenant_id, course_id, user_id)
    VALUES (app.current_tenant(), p_course_id, p_user_id)
    RETURNING id INTO v_id;

    RETURN QUERY SELECT * FROM spec.get_enrollment(v_id);
END;
$$;


CREATE FUNCTION spec.cancel_enrollment(p_enrollment_id uuid) RETURNS SETOF api.enrollment
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_user_id UUID;
    v_status  impl.enrollment_status;
BEGIN
    SELECT user_id, status INTO v_user_id, v_status
    FROM impl.enrollments
    WHERE id = p_enrollment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'enrollment_not_found';
    END IF;

    IF v_user_id <> app.current_user_id() THEN
        PERFORM spec.assert_role('admin');
    END IF;

    IF v_status <> 'active' THEN
        RAISE EXCEPTION 'enrollment_not_active';
    END IF;

    UPDATE impl.enrollments
    SET status      = 'cancelled',
        finished_at = NOW()
    WHERE id = p_enrollment_id;

    RETURN QUERY SELECT * FROM spec.get_enrollment(p_enrollment_id);
END;
$$;

CREATE FUNCTION api.get_course(p_id uuid) RETURNS SETOF api.course
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path = api, spec, impl, app, pg_temp
    AS $$
    SELECT * FROM spec.get_course(p_id);
$$;


CREATE FUNCTION api.list_courses(p_category_filter uuid DEFAULT NULL::uuid, p_active_filter boolean DEFAULT NULL::boolean) RETURNS SETOF api.course
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path = api, spec, impl, app, pg_temp
    AS $$
    SELECT * FROM spec.list_courses(p_category_filter, p_active_filter);
$$;


CREATE FUNCTION api.create_course(p_title text, p_description text, p_category_ids uuid[], p_lessons jsonb) RETURNS SETOF api.course
    LANGUAGE sql SECURITY DEFINER
    SET search_path = api, spec, impl, app, pg_temp
    AS $$
    SELECT * FROM spec.create_course(p_title, p_description, p_category_ids, p_lessons);
$$;


CREATE FUNCTION api.update_course(p_id uuid, p_title text, p_description text, p_category_ids uuid[]) RETURNS SETOF api.course
    LANGUAGE sql SECURITY DEFINER
    SET search_path = api, spec, impl, app, pg_temp
    AS $$
    SELECT * FROM spec.update_course(p_id, p_title, p_description, p_category_ids);
$$;


CREATE FUNCTION api.activate_course(p_course_id uuid) RETURNS SETOF api.course
    LANGUAGE sql SECURITY DEFINER
    SET search_path = api, spec, impl, app, pg_temp
    AS $$
    SELECT * FROM spec.activate_course(p_course_id);
$$;


CREATE FUNCTION api.deactivate_course(p_course_id uuid) RETURNS SETOF api.course
    LANGUAGE sql SECURITY DEFINER
    SET search_path = api, spec, impl, app, pg_temp
    AS $$
    SELECT * FROM spec.deactivate_course(p_course_id);
$$;

-- === Recreate api wrappers: enrollments ===
-- get_enrollment / list_* enumerate columns explicitly (get_enrollment adds a
-- not-found raise; the lists are plain projections) — the new user_email column
-- must be appended to each so the projection matches the extended composite type.
-- enroll_user / cancel_enrollment are thin SELECT * and stay as-is.

CREATE FUNCTION api.get_enrollment(p_enrollment_id uuid) RETURNS SETOF api.enrollment
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path = api, spec, impl, app, pg_temp
    AS $$
BEGIN
    RETURN QUERY
        SELECT id, course_id, user_id, status,
               enrolled_at, finished_at,
               created_at, updated_at, user_email
        FROM spec.get_enrollment(p_enrollment_id);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'enrollment_not_found';
    END IF;
END;
$$;


CREATE FUNCTION api.list_enrollments_by_course(p_course_id uuid, p_status_filter text) RETURNS SETOF api.enrollment
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path = api, spec, impl, app, pg_temp
    AS $$
    SELECT id, course_id, user_id, status,
           enrolled_at, finished_at,
           created_at, updated_at, user_email
    FROM spec.list_enrollments_by_course(p_course_id, p_status_filter);
$$;


CREATE FUNCTION api.list_enrollments_by_user(p_user_id uuid, p_status_filter text) RETURNS SETOF api.enrollment
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path = api, spec, impl, app, pg_temp
    AS $$
    SELECT id, course_id, user_id, status,
           enrolled_at, finished_at,
           created_at, updated_at, user_email
    FROM spec.list_enrollments_by_user(p_user_id, p_status_filter);
$$;


CREATE FUNCTION api.enroll_user(p_user_id uuid, p_course_id uuid) RETURNS SETOF api.enrollment
    LANGUAGE sql SECURITY DEFINER
    SET search_path = api, spec, impl, app, pg_temp
    AS $$
    SELECT * FROM spec.enroll_user(p_user_id, p_course_id);
$$;


CREATE FUNCTION api.cancel_enrollment(p_enrollment_id uuid) RETURNS SETOF api.enrollment
    LANGUAGE sql SECURITY DEFINER
    SET search_path = api, spec, impl, app, pg_temp
    AS $$
    SELECT * FROM spec.cancel_enrollment(p_enrollment_id);
$$;
