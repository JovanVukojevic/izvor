-- Migration 016: remove magic published-only default from list_courses.
--
-- Previously: NULL p_status_filter meant 'published-only' (via COALESCE(p_status_filter, 'published')).
-- This was a magic default — semantics not expressible in the parameter name or signature.
-- Now: NULL means "no filter" (standard nullable-filter pattern), matching p_category_filter
-- already in the same procedure. Contract change for direct DB callers; only consumer is api.list_courses
-- (NULL passthrough still correct) and the Angular UI which now controls default selection client-side.

CREATE OR REPLACE FUNCTION spec.list_courses(
    p_category_filter UUID,
    p_status_filter   impl.course_status
)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
AS $$
    SELECT id, category_id, author_id, title, description, status::text,
           created_at, updated_at, sequential
    FROM impl.courses
    WHERE (p_category_filter IS NULL OR category_id = p_category_filter)
      AND (p_status_filter   IS NULL OR status      = p_status_filter)
    ORDER BY created_at DESC;
$$;

CREATE OR REPLACE FUNCTION api.list_courses(
    p_category_filter UUID,
    p_status_filter   TEXT
)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT id, category_id, author_id, title, description, status,
           created_at, updated_at, sequential
    FROM spec.list_courses(p_category_filter, p_status_filter::impl.course_status);
$$;
