-- Course ↔ Category becomes M:N. A course belongs to one or more categories,
-- treated as thematic tags. The link carries no attributes; it is a pure
-- association, not an aggregation. The verbal model in §11.3 already named
-- (1, N) cardinality; this migration relaxes "exactly one" to "one or more".
--
-- Decisions folded in:
--   * Join table impl.course_categories with CASCADE on courses, RESTRICT on
--     categories. CASCADE on courses because the link rows carry no domain
--     data and a deleted course must shed its links; RESTRICT on categories
--     because deleting a category that still classifies a course is refused
--     (preserves the policy spec.delete_category has implied since 010).
--   * The ≥1 category invariant is enforced, parallel to the ≥1 lesson
--     invariant from 027: create/update_course reject an empty array, and a
--     DEFERRABLE constraint trigger on impl.course_categories raises
--     course_must_have_categories if a final state would leave any course
--     with zero links. Same defense-in-depth split: column-level (NOT NULL
--     on link members) + procedure-level (raise on empty input) + trigger
--     (catches direct writes and end-of-transaction states).
--   * spec.delete_category gets an explicit category_in_use pre-check that
--     mirrors spec.delete_course's course_has_enrollments check. The FK
--     RESTRICT stays as the structural backstop; the pre-check provides the
--     user-readable named code instead of the raw FK error that would name
--     the join table.
--   * spec.create_course / spec.update_course validate category existence
--     explicitly BEFORE any INSERT (compare COUNT against array length over
--     SELECT DISTINCT unnest), raising category_not_found precisely. No
--     body-wrap EXCEPTION block on foreign_key_violation — that would catch
--     unrelated FK paths (author_id, the lesson's course_id) and mislabel
--     them. The narrowed translation keeps category_not_found honest.
--   * api.course composite type swaps category_id UUID for category_ids
--     UUID[]. get_course / list_courses surface the aggregated array via
--     COALESCE(..., ARRAY[]::UUID[]) so a NULL never reaches .NET; the
--     non-null empty array maps cleanly to Guid[] {} (and is unreachable
--     under the ≥1 invariant — defense-in-depth surface).
--   * list_courses keeps p_category_filter UUID; semantics shift from
--     equality to EXISTS-membership against the join table.
--   * Backfill loops over system_impl.tenants (non-RLS source), per the
--     migration-020/023/025 pattern: set_config of app.current_tenant and
--     the gated DML stay inside the same DO block so SET LOCAL semantics
--     hold across the loop body.
--   * Silent dedup of input arrays via SELECT DISTINCT unnest — duplicate
--     ids in caller input are noise, not a domain violation.
--
-- Order inside this migration is load-bearing:
--   1. Create impl.course_categories with FKs, RLS, FORCE, policy, index.
--   2. Backfill from impl.courses.category_id, per tenant, with row-count
--      sanity check.
--   3. Drop dependent api/spec procedures (api wrappers first).
--   4. Drop impl.courses → impl.categories FK + the now-orphaned index.
--   5. Drop impl.courses.category_id column.
--   6. ALTER TYPE api.course: drop category_id, add category_ids UUID[].
--   7. Install assert_course_has_category constraint trigger AFTER all
--      backfill is in place (otherwise the link-INSERT loop could trip the
--      DELETE-only trigger via mid-transaction states — DEFERRED makes this
--      moot anyway, but ordering keeps the migration readable).
--   8. CREATE OR REPLACE spec.delete_category with category_in_use
--      pre-check (api.delete_category wrapper is untouched — pure
--      delegation).
--   9. Recreate spec/api create_course and update_course with new shapes.
--  10. Recreate spec/api get_course and list_courses against the new type.


-- 1. Join table.

CREATE TABLE impl.course_categories (
    tenant_id   UUID NOT NULL,
    course_id   UUID NOT NULL,
    category_id UUID NOT NULL,
    PRIMARY KEY (tenant_id, course_id, category_id),
    FOREIGN KEY (tenant_id, course_id)
        REFERENCES impl.courses (tenant_id, id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id, category_id)
        REFERENCES impl.categories (tenant_id, id) ON DELETE RESTRICT
);

ALTER TABLE impl.course_categories OWNER TO izvor_admin;
ALTER TABLE impl.course_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE impl.course_categories FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON impl.course_categories
    USING       (tenant_id = app.current_tenant())
    WITH CHECK  (tenant_id = app.current_tenant());

-- Course-side lookups ride the PK; category-side filtering needs its own
-- index for the list_courses EXISTS path.
CREATE INDEX course_categories_tenant_category_idx
    ON impl.course_categories (tenant_id, category_id);


-- 2. Backfill from impl.courses.category_id.
--
-- impl.courses.category_id is NOT NULL since migration 025, so no filter
-- needed. Loop over system_impl.tenants (control plane, no RLS) per the
-- 020/023/025 pattern; the inner INSERT runs under set_config of
-- app.current_tenant so RLS WITH CHECK on impl.course_categories passes.
-- Accumulate the missing count per tenant and assert it stays at zero
-- before exiting the loop.

DO $$
DECLARE
    t_id        UUID;
    t_sub       TEXT;
    v_inserted  INT;
    v_missing   INT;
    v_total_ins INT := 0;
BEGIN
    FOR t_id, t_sub IN SELECT id, subdomain FROM system_impl.tenants LOOP
        PERFORM set_config('app.current_tenant', t_id::TEXT, true);

        INSERT INTO impl.course_categories (tenant_id, course_id, category_id)
        SELECT tenant_id, id, category_id
          FROM impl.courses
         WHERE tenant_id = t_id;

        GET DIAGNOSTICS v_inserted = ROW_COUNT;
        v_total_ins := v_total_ins + v_inserted;

        SELECT COUNT(*) INTO v_missing
          FROM impl.courses c
         WHERE c.tenant_id = t_id
           AND NOT EXISTS (
               SELECT 1 FROM impl.course_categories cc
                WHERE cc.tenant_id = c.tenant_id AND cc.course_id = c.id
           );

        IF v_missing > 0 THEN
            RAISE EXCEPTION
                '028 backfill incomplete: tenant=% has % courses without category links',
                t_sub, v_missing;
        END IF;

        RAISE NOTICE 'tenant=% course_categories inserted: %', t_sub, v_inserted;
    END LOOP;

    RAISE NOTICE '028 backfill total: %', v_total_ins;
END $$;


-- 3. Drop dependent procedures. Api wrappers depend on spec; drop wrappers
-- first within each group. Across groups, drop the readers (get/list) and
-- writers (create/update) — both reference api.course or impl.courses.category_id.

DROP FUNCTION api.list_courses(UUID, BOOLEAN);
DROP FUNCTION api.get_course(UUID);
DROP FUNCTION spec.list_courses(UUID, BOOLEAN);
DROP FUNCTION spec.get_course(UUID);

DROP FUNCTION api.update_course(UUID, TEXT, TEXT, UUID);
DROP FUNCTION spec.update_course(UUID, TEXT, TEXT, UUID);

DROP FUNCTION api.create_course(TEXT, TEXT, UUID, TEXT, TEXT);
DROP FUNCTION spec.create_course(TEXT, TEXT, UUID, TEXT, TEXT);


-- 4. Drop the now-orphaned FK and index on impl.courses. The FK from
-- impl.course_categories → impl.categories carries the integrity guarantee
-- going forward; the column on impl.courses is about to disappear.

ALTER TABLE impl.courses DROP CONSTRAINT courses_tenant_id_category_id_fkey;
DROP INDEX impl.courses_tenant_category_idx;


-- 5. Drop the column.

ALTER TABLE impl.courses DROP COLUMN category_id;


-- 6. Reshape api.course composite type.
--
-- ALTER TYPE ... ADD ATTRIBUTE always appends; there is no positional
-- insert in PostgreSQL. A pair of DROP+ADD would leave category_ids in
-- the last slot and the spec function bodies returning columns in
-- (id, category_ids, author_id, ...) order would fail the positional
-- composite-type binding check (RETURNS SETOF api.course matches by
-- position, not by column name).
--
-- Cleanest fix: DROP TYPE + CREATE TYPE. Safe here because every
-- function returning SETOF api.course (get_course / list_courses and
-- their api wrappers) was dropped in step 3 above; nothing else
-- references the type. Side effect: the tombstone slots left by
-- migration 021 (sequential) and 023 (status) get compacted away —
-- positions are 1..8 with no gaps, which keeps \d api.course readable.

DROP TYPE api.course;
CREATE TYPE api.course AS (
    id           UUID,
    category_ids UUID[],
    author_id    UUID,
    title        TEXT,
    description  TEXT,
    created_at   TIMESTAMPTZ,
    updated_at   TIMESTAMPTZ,
    is_active    BOOLEAN
);
ALTER TYPE api.course OWNER TO izvor_admin;


-- 7. Constraint trigger that fires the ≥1 category invariant.
--
-- impl.assert_course_has_category mirrors impl.assert_course_has_lesson
-- from 027 exactly: AFTER DELETE arm + AFTER UPDATE OF course_id arm,
-- DEFERRABLE INITIALLY DEFERRED so update_course's DELETE+INSERT does not
-- trip the check mid-transaction. SECURITY DEFINER + explicit search_path
-- mirrors invariant 10 — without it the trigger called via constraint
-- machinery from arbitrary callers (including izvor_app) would fail on
-- schema USAGE before it could check anything.
--
-- The UPDATE arm exists for parity with lessons; no current procedure
-- updates course_categories in place (update_course performs DELETE+INSERT),
-- but a direct UPDATE that moves a link between courses could leave the
-- source course with zero links. Defense-in-depth principle from 027.
--
-- The missing-parent short-circuit (EXISTS course row) keeps CASCADE
-- deletion of a course from raising course_must_have_categories — the
-- parent is being deleted, the rule doesn't apply.

CREATE OR REPLACE FUNCTION impl.assert_course_has_category()
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
        SELECT 1 FROM impl.course_categories
         WHERE tenant_id = OLD.tenant_id AND course_id = OLD.course_id
    ) THEN
        RAISE EXCEPTION 'course_must_have_categories';
    END IF;
    RETURN NULL;
END;
$$;

ALTER FUNCTION impl.assert_course_has_category() OWNER TO izvor_admin;

CREATE CONSTRAINT TRIGGER course_categories_has_category_on_delete
    AFTER DELETE ON impl.course_categories
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION impl.assert_course_has_category();

CREATE CONSTRAINT TRIGGER course_categories_has_category_on_update
    AFTER UPDATE OF course_id ON impl.course_categories
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION impl.assert_course_has_category();


-- 8. spec.delete_category gains the category_in_use pre-check.
--
-- Mirrors spec.delete_course's course_has_enrollments pre-check pattern:
-- the explicit RAISE gives the user a named code; the FK RESTRICT below
-- (on impl.course_categories → impl.categories) is the structural
-- backstop that would surface as constraint_violation 409 on a direct
-- write, but the api path now always hits the friendly code first.

CREATE OR REPLACE FUNCTION spec.delete_category(p_id UUID)
RETURNS BOOLEAN
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


-- 9. spec.create_course / api.create_course with array category param.
--
-- p_category_ids UUID[] required and non-empty. Explicit pre-validation
-- of every id against impl.categories (tenant-scoped via RLS) raises
-- category_not_found cleanly — no body-wrap EXCEPTION on
-- foreign_key_violation because that would catch unrelated FK paths
-- (author_id, the lesson's course_id) and mislabel them.

CREATE FUNCTION spec.create_course(
    p_title                TEXT,
    p_description          TEXT,
    p_category_ids         UUID[],
    p_first_lesson_title   TEXT,
    p_first_lesson_content TEXT
)
RETURNS UUID
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

ALTER FUNCTION spec.create_course(TEXT, TEXT, UUID[], TEXT, TEXT) OWNER TO izvor_admin;


CREATE FUNCTION api.create_course(
    p_title                TEXT,
    p_description          TEXT,
    p_category_ids         UUID[],
    p_first_lesson_title   TEXT,
    p_first_lesson_content TEXT
)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.create_course(p_title, p_description, p_category_ids,
                              p_first_lesson_title, p_first_lesson_content);
$$;

ALTER FUNCTION api.create_course(TEXT, TEXT, UUID[], TEXT, TEXT) OWNER TO izvor_admin;


-- spec.update_course / api.update_course — full-replacement of the link set.
--
-- The new contract: p_category_ids is the desired final set. Procedure
-- computes the canonical (distinct, sorted) current and desired sets to
-- decide the no-change short-circuit, then DELETEs links not in the new
-- set and INSERTs the missing ones. ON CONFLICT DO NOTHING covers
-- already-present rows (idempotent).
--
-- The DEFERRED course_must_have_categories trigger fires at end of
-- transaction; mid-update intermediate states (after DELETE but before
-- INSERT) do not trip it.

CREATE FUNCTION spec.update_course(
    p_id           UUID,
    p_title        TEXT,
    p_description  TEXT,
    p_category_ids UUID[]
)
RETURNS BOOLEAN
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

ALTER FUNCTION spec.update_course(UUID, TEXT, TEXT, UUID[]) OWNER TO izvor_admin;


CREATE FUNCTION api.update_course(
    p_id           UUID,
    p_title        TEXT,
    p_description  TEXT,
    p_category_ids UUID[]
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT spec.update_course(p_id, p_title, p_description, p_category_ids);
$$;

ALTER FUNCTION api.update_course(UUID, TEXT, TEXT, UUID[]) OWNER TO izvor_admin;


-- 10. spec/api get_course and list_courses — return the aggregated
-- category_ids array. COALESCE-to-empty-array means .NET never sees NULL;
-- under the ≥1 invariant the array is never empty, but the defensive
-- empty-array surface keeps CourseResponse.CategoryIds non-nullable.
--
-- list_courses filter shifts from equality on a scalar column to EXISTS
-- membership against the join table; p_category_filter stays single-UUID
-- (the common "show all courses tagged X" case). The ORDER BY ... inside
-- the aggregate gives stable category_ids output independent of insert order.

CREATE FUNCTION spec.get_course(p_id UUID)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
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

ALTER FUNCTION spec.get_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION spec.list_courses(
    p_category_filter UUID    DEFAULT NULL,
    p_active_filter   BOOLEAN DEFAULT NULL
)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
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

ALTER FUNCTION spec.list_courses(UUID, BOOLEAN) OWNER TO izvor_admin;


CREATE FUNCTION api.get_course(p_id UUID)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.get_course(p_id);
$$;

ALTER FUNCTION api.get_course(UUID) OWNER TO izvor_admin;


CREATE FUNCTION api.list_courses(
    p_category_filter UUID    DEFAULT NULL,
    p_active_filter   BOOLEAN DEFAULT NULL
)
RETURNS SETOF api.course
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = api, spec, impl, app, pg_temp
AS $$
    SELECT * FROM spec.list_courses(p_category_filter, p_active_filter);
$$;

ALTER FUNCTION api.list_courses(UUID, BOOLEAN) OWNER TO izvor_admin;
