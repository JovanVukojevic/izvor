CREATE FUNCTION spec.get_current_user()
RETURNS SETOF impl.users
LANGUAGE sql
STABLE
AS $$
    SELECT * FROM impl.users WHERE id = app.current_user_id();
$$;

ALTER FUNCTION spec.get_current_user() OWNER TO izvor_admin;


CREATE FUNCTION api.get_current_user()
RETURNS SETOF api.user
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, email, role::text, created_at, updated_at
    FROM spec.get_current_user();
$$;

ALTER FUNCTION api.get_current_user() OWNER TO izvor_admin;
