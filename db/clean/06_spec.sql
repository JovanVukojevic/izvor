-- === API Composite Types ===


CREATE TYPE api."user" AS (
	id uuid,
	email text,
	role text,
	created_at timestamp with time zone,
	updated_at timestamp with time zone,
	is_active boolean
);


CREATE TYPE api.user_credentials AS (
	id uuid,
	email text,
	password_hash text,
	role text,
	created_at timestamp with time zone,
	updated_at timestamp with time zone
);


CREATE TYPE api.user_with_tenant AS (
	id uuid,
	email text,
	role text,
	created_at timestamp with time zone,
	updated_at timestamp with time zone,
	tenant_id uuid,
	tenant_name text,
	tenant_subdomain text
);


CREATE TYPE api.category AS (
	id uuid,
	name text,
	description text,
	created_at timestamp with time zone,
	updated_at timestamp with time zone
);


CREATE TYPE api.course AS (
	id uuid,
	category_ids uuid[],
	author_id uuid,
	title text,
	description text,
	created_at timestamp with time zone,
	updated_at timestamp with time zone,
	is_active boolean
);


CREATE TYPE api.lesson AS (
	id uuid,
	course_id uuid,
	title text,
	content text,
	"position" integer,
	created_at timestamp with time zone,
	updated_at timestamp with time zone
);


CREATE TYPE api.enrollment AS (
	id uuid,
	course_id uuid,
	user_id uuid,
	status text,
	enrolled_at timestamp with time zone,
	completed_at timestamp with time zone,
	cancelled_at timestamp with time zone,
	created_at timestamp with time zone,
	updated_at timestamp with time zone
);


CREATE TYPE api.lesson_completion AS (
	enrollment_id uuid,
	lesson_id uuid,
	completed_at timestamp with time zone
);


CREATE TYPE api.course_completion_stats AS (
	course_id uuid,
	total_enrollments integer,
	active_count integer,
	completed_count integer,
	cancelled_count integer,
	average_progress_pct numeric(5,2)
);


CREATE TYPE api.refresh_token AS (
	id uuid,
	user_id uuid,
	token text,
	issued_at timestamp with time zone,
	expires_at timestamp with time zone
);

-- === Assertions ===


CREATE FUNCTION spec.assert_course_owner_or_admin(p_course_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_author UUID;
BEGIN
    IF spec.get_current_role() = 'admin' THEN
        RETURN;
    END IF;

    SELECT author_id INTO v_author
    FROM impl.courses
    WHERE id = p_course_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF v_author <> app.current_user_id() THEN
        RAISE EXCEPTION 'not_course_owner'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
END;
$$;


CREATE FUNCTION spec.assert_role(p_min_role text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_current_code  TEXT;
    v_current_rank  INTEGER;
    v_required_rank INTEGER;
BEGIN
    SELECT r.code, r.rank
    INTO v_current_code, v_current_rank
    FROM impl.users u
    JOIN impl.roles r ON (r.tenant_id, r.id) = (u.tenant_id, u.role_id)
    WHERE u.id = app.current_user_id() AND u.is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'no_active_user_in_session'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT rank INTO v_required_rank
    FROM impl.roles WHERE code = p_min_role;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'invalid_role: %', p_min_role
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF v_current_rank >= v_required_rank THEN
        RETURN;
    END IF;

    RAISE EXCEPTION 'role % required, caller has %', p_min_role, v_current_code
        USING ERRCODE = 'insufficient_privilege';
END;
$$;


CREATE FUNCTION spec.get_current_role() RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_code TEXT;
BEGIN
    SELECT r.code INTO v_code
    FROM impl.users u
    JOIN impl.roles r ON (r.tenant_id, r.id) = (u.tenant_id, u.role_id)
    WHERE u.id = app.current_user_id() AND u.is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'no_active_user_in_session'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    RETURN v_code;
END;
$$;

-- === Procedures: Users ===


CREATE FUNCTION spec.activate_user(p_user_id uuid) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_changed BOOLEAN;
BEGIN
    PERFORM spec.assert_role('admin');

    UPDATE impl.users
    SET is_active = true
    WHERE id = p_user_id AND is_active = false
    RETURNING true INTO v_changed;

    RETURN COALESCE(v_changed, false);
END;
$$;


CREATE FUNCTION spec.admin_reset_password(p_user_id uuid, p_password_hash text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_changed BOOLEAN;
BEGIN
    PERFORM spec.assert_role('admin');

    UPDATE impl.users
    SET password_hash = p_password_hash
    WHERE id = p_user_id AND is_active = true
    RETURNING true INTO v_changed;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'user_not_found'
            USING ERRCODE = 'no_data_found';
    END IF;

    PERFORM spec.revoke_all_user_refresh_tokens(p_user_id);

    RETURN COALESCE(v_changed, false);
END;
$$;


CREATE FUNCTION spec.authenticate_user(p_email text) RETURNS SETOF impl.users
    LANGUAGE sql STABLE
    AS $$
    SELECT * FROM impl.users
    WHERE lower(trim(email)) = lower(trim(p_email))
      AND is_active = true;
$$;


CREATE FUNCTION spec.change_password(p_user_id uuid, p_new_password_hash text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF p_new_password_hash IS NULL OR length(p_new_password_hash) = 0 THEN
        RAISE EXCEPTION 'Password hash is required';
    END IF;

    UPDATE impl.users
    SET password_hash = p_new_password_hash
    WHERE id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % not found in current tenant', p_user_id;
    END IF;
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid password hash: %', SQLERRM;
END;
$$;


CREATE FUNCTION spec.create_user(p_email text, p_password_hash text, p_role text DEFAULT 'learner'::text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id      UUID;
    v_role_id UUID;
BEGIN
    PERFORM spec.assert_role('admin');

    IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
        RAISE EXCEPTION 'Email is required';
    END IF;
    IF p_password_hash IS NULL OR length(p_password_hash) = 0 THEN
        RAISE EXCEPTION 'Password hash is required';
    END IF;

    SELECT id INTO v_role_id FROM impl.roles WHERE code = p_role;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'invalid_role: %', p_role
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    INSERT INTO impl.users (tenant_id, email, password_hash, role_id)
    VALUES (app.current_tenant(), trim(p_email), p_password_hash, v_role_id)
    RETURNING id INTO v_id;

    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'User with email % already exists in this tenant', p_email;
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid user data: %', SQLERRM;
END;
$$;


CREATE FUNCTION spec.create_user_internal(p_email text, p_password_hash text, p_role text DEFAULT 'learner'::text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id      UUID;
    v_role_id UUID;
BEGIN
    IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
        RAISE EXCEPTION 'Email is required';
    END IF;
    IF p_password_hash IS NULL OR length(p_password_hash) = 0 THEN
        RAISE EXCEPTION 'Password hash is required';
    END IF;

    SELECT id INTO v_role_id FROM impl.roles WHERE code = p_role;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'invalid_role: %', p_role
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    INSERT INTO impl.users (tenant_id, email, password_hash, role_id)
    VALUES (app.current_tenant(), trim(p_email), p_password_hash, v_role_id)
    RETURNING id INTO v_id;

    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'User with email % already exists in this tenant', p_email;
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid user data: %', SQLERRM;
END;
$$;


CREATE FUNCTION spec.deactivate_user(p_user_id uuid) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_changed BOOLEAN;
BEGIN
    PERFORM spec.assert_role('admin');

    IF p_user_id = app.current_user_id() THEN
        RAISE EXCEPTION 'cannot_deactivate_self'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    PERFORM 1 FROM impl.users
    WHERE id = p_user_id AND is_active = true;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    UPDATE impl.users
    SET is_active = false
    WHERE id = p_user_id AND is_active = true
    RETURNING true INTO v_changed;

    PERFORM spec.revoke_all_user_refresh_tokens(p_user_id);

    RETURN COALESCE(v_changed, false);
END;
$$;


CREATE FUNCTION spec.get_current_user() RETURNS SETOF api.user_with_tenant
    LANGUAGE sql STABLE
    AS $$
    SELECT
        u.id,
        u.email,
        r.code,
        u.created_at,
        u.updated_at,
        t.id,
        t.name,
        t.subdomain
    FROM impl.users u
    JOIN impl.roles r ON (r.tenant_id, r.id) = (u.tenant_id, u.role_id)
    JOIN system_impl.tenants t ON t.id = u.tenant_id
    WHERE u.id = app.current_user_id() AND u.is_active = true;
$$;


CREATE FUNCTION spec.get_user(p_user_id uuid) RETURNS SETOF api."user"
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    PERFORM spec.assert_role('admin');

    RETURN QUERY
    SELECT u.id, u.email, r.code, u.created_at, u.updated_at, u.is_active
    FROM impl.users u
    JOIN impl.roles r ON (r.tenant_id, r.id) = (u.tenant_id, u.role_id)
    WHERE u.id = p_user_id;
END;
$$;


CREATE FUNCTION spec.list_users(p_role_filter text DEFAULT NULL::text, p_active_filter boolean DEFAULT NULL::boolean) RETURNS SETOF api."user"
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    PERFORM spec.assert_role('admin');

    RETURN QUERY
    SELECT u.id, u.email, r.code, u.created_at, u.updated_at, u.is_active
    FROM impl.users u
    JOIN impl.roles r ON (r.tenant_id, r.id) = (u.tenant_id, u.role_id)
    WHERE (p_role_filter IS NULL OR r.code = p_role_filter)
      AND (p_active_filter IS NULL OR u.is_active = p_active_filter)
    ORDER BY u.created_at DESC;
END;
$$;

-- === Procedures: Categories ===


CREATE FUNCTION spec.create_category(p_name text, p_description text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id UUID;
BEGIN
    PERFORM spec.assert_role('admin');

    IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
        RAISE EXCEPTION 'Name is required';
    END IF;

    INSERT INTO impl.categories (tenant_id, name, description)
    VALUES (app.current_tenant(), trim(p_name), p_description)
    RETURNING id INTO v_id;

    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Category with name % already exists in this tenant', p_name;
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid category data: %', SQLERRM;
END;
$$;


CREATE FUNCTION spec.delete_category(p_id uuid) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM spec.assert_role('admin');

    IF EXISTS (
        SELECT 1 FROM impl.course_categories
         WHERE category_id = p_id
    ) THEN
        RAISE EXCEPTION 'category_in_use';
    END IF;

    DELETE FROM impl.categories
    WHERE id = p_id;

    RETURN FOUND;
END;
$$;


CREATE FUNCTION spec.get_category(p_id uuid) RETURNS SETOF api.category
    LANGUAGE sql STABLE
    AS $$
    SELECT id, name, description, created_at, updated_at
    FROM impl.categories
    WHERE id = p_id;
$$;


CREATE FUNCTION spec.list_categories() RETURNS SETOF api.category
    LANGUAGE sql STABLE
    AS $$
    SELECT id, name, description, created_at, updated_at
    FROM impl.categories
    ORDER BY name;
$$;


CREATE FUNCTION spec.update_category(p_id uuid, p_name text, p_description text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM spec.assert_role('admin');

    IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
        RAISE EXCEPTION 'Name is required';
    END IF;

    UPDATE impl.categories
    SET name        = trim(p_name),
        description = p_description
    WHERE id = p_id;

    RETURN FOUND;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Category with name % already exists in this tenant', p_name;
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid category data: %', SQLERRM;
END;
$$;

-- === Procedures: Courses ===


CREATE FUNCTION spec.activate_course(p_course_id uuid) RETURNS boolean
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

    IF v_active THEN
        RETURN false;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM impl.lessons
         WHERE tenant_id = app.current_tenant()
           AND course_id = p_course_id
    ) THEN
        RAISE EXCEPTION 'course_has_no_lessons';
    END IF;

    UPDATE impl.courses SET is_active = true WHERE id = p_course_id;
    RETURN true;
END;
$$;


CREATE FUNCTION spec.create_course(p_title text, p_description text, p_category_ids uuid[], p_first_lesson_title text, p_first_lesson_content text) RETURNS uuid
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

    INSERT INTO impl.course_categories (tenant_id, course_id, category_id)
    SELECT app.current_tenant(), v_id, cat
      FROM unnest(v_distinct) AS cat;

    INSERT INTO impl.lessons (tenant_id, course_id, title, content, position)
    VALUES (app.current_tenant(), v_id,
            trim(p_first_lesson_title), COALESCE(p_first_lesson_content, ''), 1);

    RETURN v_id;
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid course data: %', SQLERRM;
END;
$$;


CREATE FUNCTION spec.deactivate_course(p_course_id uuid) RETURNS boolean
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

    IF NOT v_active THEN
        RETURN false;
    END IF;

    UPDATE impl.courses SET is_active = false WHERE id = p_course_id;
    RETURN true;
END;
$$;


CREATE FUNCTION spec.delete_course(p_id uuid) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_id);

    PERFORM 1 FROM impl.courses WHERE id = p_id FOR UPDATE;

    IF EXISTS (SELECT 1 FROM impl.enrollments WHERE course_id = p_id) THEN
        RAISE EXCEPTION 'course_has_enrollments';
    END IF;

    DELETE FROM impl.lessons
     WHERE tenant_id = app.current_tenant()
       AND course_id = p_id;

    DELETE FROM impl.courses WHERE id = p_id;

    RETURN true;
END;
$$;


CREATE FUNCTION spec.get_course(p_id uuid) RETURNS SETOF api.course
    LANGUAGE sql STABLE
    AS $$
    SELECT c.id,
           COALESCE(
               (SELECT array_agg(cc.category_id ORDER BY cc.category_id)
                  FROM impl.course_categories cc
                 WHERE cc.tenant_id = c.tenant_id AND cc.course_id = c.id),
               ARRAY[]::UUID[]
           ) AS category_ids,
           c.author_id, c.title, c.description,
           c.created_at, c.updated_at, c.is_active
      FROM impl.courses c
     WHERE c.id = p_id;
$$;


CREATE FUNCTION spec.get_course_completion_stats(p_course_id uuid) RETURNS api.course_completion_stats
    LANGUAGE plpgsql STABLE
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


CREATE FUNCTION spec.list_courses(p_category_filter uuid DEFAULT NULL::uuid, p_active_filter boolean DEFAULT NULL::boolean) RETURNS SETOF api.course
    LANGUAGE sql STABLE
    AS $$
    SELECT c.id,
           COALESCE(
               (SELECT array_agg(cc.category_id ORDER BY cc.category_id)
                  FROM impl.course_categories cc
                 WHERE cc.tenant_id = c.tenant_id AND cc.course_id = c.id),
               ARRAY[]::UUID[]
           ) AS category_ids,
           c.author_id, c.title, c.description,
           c.created_at, c.updated_at, c.is_active
      FROM impl.courses c
     WHERE (p_category_filter IS NULL OR EXISTS (
               SELECT 1 FROM impl.course_categories cc
                WHERE cc.tenant_id   = c.tenant_id
                  AND cc.course_id   = c.id
                  AND cc.category_id = p_category_filter))
       AND (p_active_filter IS NULL OR c.is_active = p_active_filter)
     ORDER BY c.created_at DESC;
$$;


CREATE FUNCTION spec.update_course(p_id uuid, p_title text, p_description text, p_category_ids uuid[]) RETURNS boolean
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

    SELECT COALESCE(array_agg(category_id ORDER BY category_id), ARRAY[]::UUID[])
      INTO v_cur_cats
      FROM impl.course_categories
     WHERE course_id = p_id;

    IF v_cur_title    = trim(p_title)
       AND v_cur_desc IS NOT DISTINCT FROM p_description
       AND v_cur_cats = v_distinct THEN
        RETURN false;
    END IF;

    UPDATE impl.courses
       SET title       = trim(p_title),
           description = p_description
     WHERE id = p_id;

    DELETE FROM impl.course_categories
     WHERE course_id = p_id
       AND category_id <> ALL (v_distinct);

    INSERT INTO impl.course_categories (tenant_id, course_id, category_id)
    SELECT app.current_tenant(), p_id, cat
      FROM unnest(v_distinct) AS cat
    ON CONFLICT DO NOTHING;

    RETURN true;
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid course data: %', SQLERRM;
END;
$$;

-- === Procedures: Lessons ===


CREATE FUNCTION spec.create_lesson(p_course_id uuid, p_title text, p_content text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id       UUID;
    v_position INT;
BEGIN
    PERFORM 1 FROM impl.courses WHERE id = p_course_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    PERFORM spec.assert_course_owner_or_admin(p_course_id);

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    SELECT COALESCE(MAX(position), 0) + 1 INTO v_position
    FROM impl.lessons
    WHERE course_id = p_course_id;

    INSERT INTO impl.lessons (tenant_id, course_id, title, content, position)
    VALUES (app.current_tenant(), p_course_id, trim(p_title),
            COALESCE(p_content, ''), v_position)
    RETURNING id INTO v_id;

    RETURN v_id;
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid lesson data: %', SQLERRM;
END;
$$;


CREATE FUNCTION spec.delete_lesson(p_lesson_id uuid) RETURNS boolean
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


CREATE FUNCTION spec.get_lesson(p_lesson_id uuid) RETURNS SETOF api.lesson
    LANGUAGE sql STABLE
    AS $$
    SELECT id, course_id, title, content, position, created_at, updated_at
    FROM impl.lessons
    WHERE id = p_lesson_id;
$$;


CREATE FUNCTION spec.list_lessons_by_course(p_course_id uuid) RETURNS SETOF api.lesson
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    PERFORM 1 FROM impl.courses WHERE id = p_course_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'course_not_found';
    END IF;

    RETURN QUERY
        SELECT id, course_id, title, content, position, created_at, updated_at
        FROM impl.lessons
        WHERE course_id = p_course_id
        ORDER BY position ASC;
END;
$$;


CREATE FUNCTION spec.reorder_lesson(p_lesson_id uuid, p_new_position integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_course_id UUID;
    v_old_pos   INT;
    v_count     INT;
BEGIN
    SELECT course_id INTO v_course_id
    FROM impl.lessons
    WHERE id = p_lesson_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lesson_not_found';
    END IF;

    PERFORM 1 FROM impl.courses WHERE id = v_course_id FOR UPDATE;

    SELECT position INTO v_old_pos
    FROM impl.lessons
    WHERE id = p_lesson_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lesson_not_found';
    END IF;

    PERFORM spec.assert_course_owner_or_admin(v_course_id);

    SELECT COUNT(*) INTO v_count
    FROM impl.lessons
    WHERE course_id = v_course_id;

    IF p_new_position < 1 OR p_new_position > v_count THEN
        RAISE EXCEPTION 'position_out_of_range';
    END IF;

    IF p_new_position = v_old_pos THEN
        RETURN false;
    END IF;

    SET CONSTRAINTS lessons_position_unique DEFERRED;

    UPDATE impl.lessons
    SET position = CASE
        WHEN id = p_lesson_id THEN p_new_position
        WHEN p_new_position < v_old_pos
             AND position BETWEEN p_new_position AND v_old_pos - 1
                                          THEN position + 1
        WHEN p_new_position > v_old_pos
             AND position BETWEEN v_old_pos + 1 AND p_new_position
                                          THEN position - 1
        ELSE position
    END
    WHERE course_id = v_course_id;

    RETURN true;
END;
$$;


CREATE FUNCTION spec.update_lesson(p_lesson_id uuid, p_title text, p_content text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_course_id UUID;
BEGIN
    SELECT course_id INTO v_course_id
    FROM impl.lessons
    WHERE id = p_lesson_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lesson_not_found';
    END IF;

    PERFORM spec.assert_course_owner_or_admin(v_course_id);

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    UPDATE impl.lessons
    SET title   = trim(p_title),
        content = COALESCE(p_content, '')
    WHERE id = p_lesson_id;

    RETURN FOUND;
EXCEPTION
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid lesson data: %', SQLERRM;
END;
$$;

-- === Procedures: Enrollments ===


CREATE FUNCTION spec.cancel_enrollment(p_enrollment_id uuid) RETURNS boolean
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
    SET status       = 'cancelled',
        cancelled_at = NOW()
    WHERE id = p_enrollment_id;

    RETURN true;
END;
$$;


CREATE FUNCTION spec.enroll_user(p_user_id uuid, p_course_id uuid) RETURNS uuid
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

    RETURN v_id;
END;
$$;


CREATE FUNCTION spec.get_enrollment(p_enrollment_id uuid) RETURNS SETOF api.enrollment
    LANGUAGE sql STABLE
    AS $$
    SELECT id, course_id, user_id, status::text,
           enrolled_at, completed_at, cancelled_at,
           created_at, updated_at
    FROM impl.enrollments
    WHERE id = p_enrollment_id;
$$;


CREATE FUNCTION spec.list_enrollments_by_course(p_course_id uuid, p_status_filter text) RETURNS SETOF api.enrollment
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_course_id);

    RETURN QUERY
        SELECT id, course_id, user_id, status::text,
               enrolled_at, completed_at, cancelled_at,
               created_at, updated_at
        FROM impl.enrollments
        WHERE course_id = p_course_id
          AND (p_status_filter IS NULL
               OR status = p_status_filter::impl.enrollment_status)
        ORDER BY enrolled_at DESC;
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
        SELECT id, course_id, user_id, status::text,
               enrolled_at, completed_at, cancelled_at,
               created_at, updated_at
        FROM impl.enrollments
        WHERE user_id = p_user_id
          AND (p_status_filter IS NULL
               OR status = p_status_filter::impl.enrollment_status)
        ORDER BY enrolled_at DESC;
END;
$$;

-- === Procedures: Lesson Completions ===


CREATE FUNCTION spec.get_lesson_completion_by_enrollment(p_enrollment_id uuid) RETURNS SETOF api.lesson_completion
    LANGUAGE plpgsql STABLE
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


CREATE FUNCTION spec.mark_lesson_complete(p_lesson_id uuid) RETURNS boolean
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

-- === Procedures: Refresh Tokens ===


CREATE FUNCTION spec.create_refresh_token(p_lifetime_days integer) RETURNS api.refresh_token
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN spec.create_refresh_token_internal(app.current_user_id(), p_lifetime_days);
END;
$$;


CREATE FUNCTION spec.create_refresh_token_internal(p_user_id uuid, p_lifetime_days integer) RETURNS api.refresh_token
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_token       TEXT;
    v_hash        TEXT;
    v_id          UUID;
    v_issued_at   TIMESTAMPTZ;
    v_expires_at  TIMESTAMPTZ;
BEGIN
    -- gen_random_bytes lives in pgcrypto (public schema). Fully-qualified
    -- because api SECURITY DEFINER wrappers exclude public from search_path
    -- (invariant 10). encode and sha256 are in pg_catalog — always reachable.
    v_token := rtrim(
        translate(
            replace(replace(encode(public.gen_random_bytes(32), 'base64'), E'\n', ''), E'\r', ''),
            '+/', '-_'),
        '=');
    v_hash := encode(sha256(v_token::bytea), 'hex');

    INSERT INTO impl.refresh_tokens (tenant_id, user_id, token_hash, expires_at)
    VALUES (
        app.current_tenant(),
        p_user_id,
        v_hash,
        NOW() + (p_lifetime_days || ' days')::INTERVAL)
    RETURNING id, issued_at, expires_at INTO v_id, v_issued_at, v_expires_at;

    RETURN (v_id, p_user_id, v_token, v_issued_at, v_expires_at)::api.refresh_token;
END;
$$;


CREATE FUNCTION spec.revoke_all_user_refresh_tokens(p_user_id uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_count INTEGER;
BEGIN
    IF p_user_id <> app.current_user_id() THEN
        PERFORM spec.assert_role('admin');
    END IF;

    UPDATE impl.refresh_tokens
    SET revoked_at = NOW()
    WHERE user_id = p_user_id AND revoked_at IS NULL;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;


CREATE FUNCTION spec.revoke_refresh_token(p_token text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_changed BOOLEAN;
    v_hash    TEXT;
BEGIN
    v_hash := encode(sha256(p_token::bytea), 'hex');

    UPDATE impl.refresh_tokens
    SET revoked_at = NOW()
    WHERE token_hash = v_hash AND revoked_at IS NULL
    RETURNING true INTO v_changed;

    RETURN COALESCE(v_changed, false);
END;
$$;


CREATE FUNCTION spec.rotate_refresh_token(p_token text, p_lifetime_days integer) RETURNS api.refresh_token
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_user_id UUID;
    v_hash    TEXT;
BEGIN
    v_hash := encode(sha256(p_token::bytea), 'hex');

    SELECT user_id INTO v_user_id
    FROM impl.refresh_tokens
    WHERE token_hash = v_hash
      AND revoked_at IS NULL
      AND expires_at > NOW()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'invalid_refresh_token'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    UPDATE impl.refresh_tokens
    SET revoked_at = NOW()
    WHERE token_hash = v_hash;

    RETURN spec.create_refresh_token_internal(v_user_id, p_lifetime_days);
END;
$$;
