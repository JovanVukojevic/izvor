-- === Wrappers: Users ===


CREATE FUNCTION api.activate_user(p_user_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.activate_user(p_user_id);
$$;


CREATE FUNCTION api.admin_reset_password(p_user_id uuid, p_password_hash text) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.admin_reset_password(p_user_id, p_password_hash);
$$;


CREATE FUNCTION api.authenticate_user(p_email text) RETURNS SETOF api.user_credentials
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT u.id, u.email, u.password_hash, r.code, u.created_at, u.updated_at
    FROM spec.authenticate_user(p_email) u
    JOIN impl.roles r ON (r.tenant_id, r.id) = (u.tenant_id, u.role_id);
$$;


CREATE FUNCTION api.change_password(p_user_id uuid, p_new_password_hash text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.change_password(p_user_id, p_new_password_hash);
$$;


CREATE FUNCTION api.create_user(p_email text, p_password_hash text, p_role text DEFAULT 'learner'::text) RETURNS uuid
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.create_user(p_email, p_password_hash, p_role);
$$;


CREATE FUNCTION api.deactivate_user(p_user_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.deactivate_user(p_user_id);
$$;


CREATE FUNCTION api.get_current_user() RETURNS SETOF api.user_with_tenant
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT * FROM spec.get_current_user();
$$;


CREATE FUNCTION api.get_user(p_user_id uuid) RETURNS SETOF api."user"
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT * FROM spec.get_user(p_user_id);
$$;


CREATE FUNCTION api.list_users(p_role_filter text, p_active_filter boolean) RETURNS SETOF api."user"
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT * FROM spec.list_users(p_role_filter, p_active_filter);
$$;

-- === Wrappers: Categories ===


CREATE FUNCTION api.create_category(p_name text, p_description text) RETURNS uuid
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.create_category(p_name, p_description);
$$;


CREATE FUNCTION api.delete_category(p_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.delete_category(p_id);
$$;


CREATE FUNCTION api.get_category(p_id uuid) RETURNS SETOF api.category
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT id, name, description, created_at, updated_at
    FROM spec.get_category(p_id);
$$;


CREATE FUNCTION api.list_categories() RETURNS SETOF api.category
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT id, name, description, created_at, updated_at
    FROM spec.list_categories();
$$;


CREATE FUNCTION api.update_category(p_id uuid, p_name text, p_description text) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.update_category(p_id, p_name, p_description);
$$;

-- === Wrappers: Courses ===


CREATE FUNCTION api.activate_course(p_course_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.activate_course(p_course_id);
$$;


CREATE FUNCTION api.create_course(p_title text, p_description text, p_category_ids uuid[], p_first_lesson_title text, p_first_lesson_content text) RETURNS uuid
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.create_course(p_title, p_description, p_category_ids,
                              p_first_lesson_title, p_first_lesson_content);
$$;


CREATE FUNCTION api.deactivate_course(p_course_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.deactivate_course(p_course_id);
$$;


CREATE FUNCTION api.delete_course(p_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.delete_course(p_id);
$$;


CREATE FUNCTION api.get_course(p_id uuid) RETURNS SETOF api.course
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT * FROM spec.get_course(p_id);
$$;


CREATE FUNCTION api.get_course_completion_stats(p_course_id uuid) RETURNS api.course_completion_stats
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.get_course_completion_stats(p_course_id);
$$;


CREATE FUNCTION api.list_courses(p_category_filter uuid DEFAULT NULL::uuid, p_active_filter boolean DEFAULT NULL::boolean) RETURNS SETOF api.course
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT * FROM spec.list_courses(p_category_filter, p_active_filter);
$$;


CREATE FUNCTION api.update_course(p_id uuid, p_title text, p_description text, p_category_ids uuid[]) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.update_course(p_id, p_title, p_description, p_category_ids);
$$;

-- === Wrappers: Lessons ===


CREATE FUNCTION api.create_lesson(p_course_id uuid, p_title text, p_content text) RETURNS uuid
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.create_lesson(p_course_id, p_title, p_content);
$$;


CREATE FUNCTION api.delete_lesson(p_lesson_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.delete_lesson(p_lesson_id);
$$;


CREATE FUNCTION api.get_lesson(p_lesson_id uuid) RETURNS SETOF api.lesson
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
BEGIN
    RETURN QUERY
        SELECT id, course_id, title, content, position, created_at, updated_at
        FROM spec.get_lesson(p_lesson_id);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lesson_not_found';
    END IF;
END;
$$;


CREATE FUNCTION api.list_lessons_by_course(p_course_id uuid) RETURNS SETOF api.lesson
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT id, course_id, title, content, position, created_at, updated_at
    FROM spec.list_lessons_by_course(p_course_id);
$$;


CREATE FUNCTION api.reorder_lesson(p_lesson_id uuid, p_new_position integer) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.reorder_lesson(p_lesson_id, p_new_position);
$$;


CREATE FUNCTION api.update_lesson(p_lesson_id uuid, p_title text, p_content text) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.update_lesson(p_lesson_id, p_title, p_content);
$$;

-- === Wrappers: Enrollments ===


CREATE FUNCTION api.cancel_enrollment(p_enrollment_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.cancel_enrollment(p_enrollment_id);
$$;


CREATE FUNCTION api.enroll_user(p_user_id uuid, p_course_id uuid) RETURNS uuid
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.enroll_user(p_user_id, p_course_id);
$$;


CREATE FUNCTION api.get_enrollment(p_enrollment_id uuid) RETURNS SETOF api.enrollment
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
BEGIN
    RETURN QUERY
        SELECT id, course_id, user_id, status,
               enrolled_at, completed_at, cancelled_at,
               created_at, updated_at
        FROM spec.get_enrollment(p_enrollment_id);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'enrollment_not_found';
    END IF;
END;
$$;


CREATE FUNCTION api.list_enrollments_by_course(p_course_id uuid, p_status_filter text) RETURNS SETOF api.enrollment
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT id, course_id, user_id, status,
           enrolled_at, completed_at, cancelled_at,
           created_at, updated_at
    FROM spec.list_enrollments_by_course(p_course_id, p_status_filter);
$$;


CREATE FUNCTION api.list_enrollments_by_user(p_user_id uuid, p_status_filter text) RETURNS SETOF api.enrollment
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT id, course_id, user_id, status,
           enrolled_at, completed_at, cancelled_at,
           created_at, updated_at
    FROM spec.list_enrollments_by_user(p_user_id, p_status_filter);
$$;

-- === Wrappers: Lesson Progress ===


CREATE FUNCTION api.get_lesson_progress_by_enrollment(p_enrollment_id uuid) RETURNS SETOF api.lesson_progress
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT * FROM spec.get_lesson_progress_by_enrollment(p_enrollment_id);
$$;


CREATE FUNCTION api.mark_lesson_complete(p_lesson_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.mark_lesson_complete(p_lesson_id);
$$;

-- === Wrappers: Refresh Tokens ===


CREATE FUNCTION api.create_refresh_token(p_lifetime_days integer) RETURNS api.refresh_token
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.create_refresh_token(p_lifetime_days);
$$;


CREATE FUNCTION api.revoke_all_user_refresh_tokens(p_user_id uuid) RETURNS integer
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.revoke_all_user_refresh_tokens(p_user_id);
$$;


CREATE FUNCTION api.revoke_refresh_token(p_token text) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.revoke_refresh_token(p_token);
$$;


CREATE FUNCTION api.rotate_refresh_token(p_token text, p_lifetime_days integer) RETURNS api.refresh_token
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'api', 'spec', 'impl', 'app', 'pg_temp'
    AS $$
    SELECT spec.rotate_refresh_token(p_token, p_lifetime_days);
$$;
