-- 1. Per-tenant backfill: every tenant gets visited; tenants with NULL-category
-- courses get an 'Uncategorized' category created on demand, and their affected
-- courses pointed to it. The loop iterates over system_impl.tenants (control
-- plane, no RLS) rather than impl.courses (RLS-blocked at the loop's initial
-- SELECT, since app.current_tenant isn't set yet) — same pattern as mig 023.

DO $$
DECLARE
    t_id   UUID;
    cat_id UUID;
BEGIN
    FOR t_id IN SELECT id FROM system_impl.tenants LOOP
        PERFORM set_config('app.current_tenant', t_id::TEXT, true);

        IF NOT EXISTS (
            SELECT 1 FROM impl.courses
             WHERE tenant_id = t_id AND category_id IS NULL
        ) THEN
            CONTINUE;
        END IF;

        SELECT id INTO cat_id
          FROM impl.categories
         WHERE tenant_id = t_id
           AND LOWER(TRIM(name)) = 'uncategorized';

        IF cat_id IS NULL THEN
            INSERT INTO impl.categories (tenant_id, name, description)
            VALUES (t_id, 'Uncategorized', 'Default category for migrated courses')
            RETURNING id INTO cat_id;
        END IF;

        UPDATE impl.courses
           SET category_id = cat_id
         WHERE tenant_id = t_id AND category_id IS NULL;
    END LOOP;
END $$;


-- 2. Column NOT NULL + index swap. The partial WHERE predicate becomes a
-- tautology once the column is non-nullable, so replace with an unconditional
-- index covering the same access path.

ALTER TABLE impl.courses ALTER COLUMN category_id SET NOT NULL;

DROP INDEX IF EXISTS impl.courses_tenant_category_idx;
CREATE INDEX courses_tenant_category_idx
    ON impl.courses (tenant_id, category_id);


-- 3. Refresh spec.create_course and spec.update_course with an explicit
-- category_required raise. Without it, NULL p_category_id would surface as
-- SQLSTATE 23502 (not_null_violation) and map to a generic 500.

CREATE OR REPLACE FUNCTION spec.create_course(
    p_title       TEXT,
    p_description TEXT,
    p_category_id UUID
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

    INSERT INTO impl.courses (tenant_id, category_id, author_id, title, description, is_active)
    VALUES (app.current_tenant(), p_category_id, app.current_user_id(), trim(p_title), p_description, false)
    RETURNING id INTO v_id;

    RETURN v_id;
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'category_not_found';
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid course data: %', SQLERRM;
END;
$$;


CREATE OR REPLACE FUNCTION spec.update_course(
    p_id          UUID,
    p_title       TEXT,
    p_description TEXT,
    p_category_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_cur_title  TEXT;
    v_cur_desc   TEXT;
    v_cur_cat    UUID;
BEGIN
    PERFORM spec.assert_course_owner_or_admin(p_id);

    IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Title is required';
    END IF;

    IF p_category_id IS NULL THEN
        RAISE EXCEPTION 'category_required';
    END IF;

    SELECT title, description, category_id
    INTO   v_cur_title, v_cur_desc, v_cur_cat
    FROM   impl.courses
    WHERE  id = p_id;

    IF v_cur_title    = trim(p_title)
       AND v_cur_desc IS NOT DISTINCT FROM p_description
       AND v_cur_cat  IS NOT DISTINCT FROM p_category_id THEN
        RETURN false;
    END IF;

    UPDATE impl.courses
    SET title       = trim(p_title),
        description = p_description,
        category_id = p_category_id
    WHERE id = p_id;

    RETURN true;
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'category_not_found';
    WHEN check_violation THEN
        RAISE EXCEPTION 'Invalid course data: %', SQLERRM;
END;
$$;
