-- === Types ===


CREATE TYPE impl.enrollment_status AS ENUM (
    'active',
    'completed',
    'cancelled'
);

-- === Tables ===


CREATE TABLE impl.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    email text NOT NULL,
    password_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    role_id uuid NOT NULL,
    CONSTRAINT users_email_check CHECK ((email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'::text)),
    CONSTRAINT users_password_hash_check CHECK ((length(password_hash) = 60))
);

ALTER TABLE ONLY impl.users FORCE ROW LEVEL SECURITY;


CREATE TABLE impl.roles (
    tenant_id uuid NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    description text,
    rank integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT roles_code_check CHECK ((code = ANY (ARRAY['admin'::text, 'author'::text, 'learner'::text]))),
    CONSTRAINT roles_rank_check CHECK ((rank > 0))
);

ALTER TABLE ONLY impl.roles FORCE ROW LEVEL SECURITY;


CREATE TABLE impl.categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT categories_name_check CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 200)))
);

ALTER TABLE ONLY impl.categories FORCE ROW LEVEL SECURITY;


CREATE TABLE impl.courses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    author_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_active boolean DEFAULT false NOT NULL,
    CONSTRAINT courses_title_check CHECK (((length(TRIM(BOTH FROM title)) >= 1) AND (length(TRIM(BOTH FROM title)) <= 300)))
);

ALTER TABLE ONLY impl.courses FORCE ROW LEVEL SECURITY;


CREATE TABLE impl.classification (
    tenant_id uuid NOT NULL,
    course_id uuid NOT NULL,
    category_id uuid NOT NULL
);

ALTER TABLE ONLY impl.classification FORCE ROW LEVEL SECURITY;


CREATE TABLE impl.lessons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    course_id uuid NOT NULL,
    title text NOT NULL,
    content text DEFAULT ''::text NOT NULL,
    "position" integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lessons_position_check CHECK (("position" > 0)),
    CONSTRAINT lessons_title_check CHECK (((length(TRIM(BOTH FROM title)) >= 1) AND (length(TRIM(BOTH FROM title)) <= 300)))
);

ALTER TABLE ONLY impl.lessons FORCE ROW LEVEL SECURITY;


CREATE TABLE impl.enrollments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    course_id uuid NOT NULL,
    user_id uuid NOT NULL,
    status impl.enrollment_status DEFAULT 'active'::impl.enrollment_status NOT NULL,
    enrolled_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT enrollments_finished_at_check CHECK (((status = ANY (ARRAY['completed'::impl.enrollment_status, 'cancelled'::impl.enrollment_status])) = (finished_at IS NOT NULL)))
);

ALTER TABLE ONLY impl.enrollments FORCE ROW LEVEL SECURITY;


CREATE TABLE impl.lesson_completion (
    tenant_id uuid NOT NULL,
    enrollment_id uuid NOT NULL,
    lesson_id uuid NOT NULL,
    completed_at timestamp with time zone DEFAULT now() NOT NULL,
    course_id uuid NOT NULL
);

ALTER TABLE ONLY impl.lesson_completion FORCE ROW LEVEL SECURITY;


CREATE TABLE impl.refresh_tokens (
    tenant_id uuid NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    token_hash text NOT NULL,
    issued_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone,
    CONSTRAINT refresh_tokens_expires_after_issue CHECK ((expires_at > issued_at)),
    CONSTRAINT refresh_tokens_token_hash_check CHECK ((length(token_hash) = 64))
);

ALTER TABLE ONLY impl.refresh_tokens FORCE ROW LEVEL SECURITY;

-- === Constraints ===


ALTER TABLE ONLY impl.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (tenant_id, id);


ALTER TABLE ONLY impl.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (tenant_id, id);


ALTER TABLE ONLY impl.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (tenant_id, id);


ALTER TABLE ONLY impl.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (tenant_id, id);


ALTER TABLE ONLY impl.classification
    ADD CONSTRAINT classification_pkey PRIMARY KEY (tenant_id, course_id, category_id);


ALTER TABLE ONLY impl.lessons
    ADD CONSTRAINT lessons_pkey PRIMARY KEY (tenant_id, id);


ALTER TABLE ONLY impl.lessons
    ADD CONSTRAINT lessons_position_unique UNIQUE (tenant_id, course_id, "position") DEFERRABLE;


ALTER TABLE ONLY impl.lessons
    ADD CONSTRAINT lessons_course_lesson_unique UNIQUE (tenant_id, course_id, id);


ALTER TABLE ONLY impl.enrollments
    ADD CONSTRAINT enrollments_pkey PRIMARY KEY (tenant_id, id);


ALTER TABLE ONLY impl.enrollments
    ADD CONSTRAINT enrollments_id_course_unique UNIQUE (tenant_id, id, course_id);


ALTER TABLE ONLY impl.lesson_completion
    ADD CONSTRAINT lesson_completion_pkey PRIMARY KEY (tenant_id, enrollment_id, course_id, lesson_id);


ALTER TABLE ONLY impl.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (tenant_id, id);


ALTER TABLE ONLY impl.users
    ADD CONSTRAINT users_role_fk FOREIGN KEY (tenant_id, role_id) REFERENCES impl.roles(tenant_id, id) ON DELETE RESTRICT;


ALTER TABLE ONLY impl.courses
    ADD CONSTRAINT courses_tenant_id_author_id_fkey FOREIGN KEY (tenant_id, author_id) REFERENCES impl.users(tenant_id, id);


ALTER TABLE ONLY impl.classification
    ADD CONSTRAINT classification_tenant_id_category_id_fkey FOREIGN KEY (tenant_id, category_id) REFERENCES impl.categories(tenant_id, id) ON DELETE RESTRICT;


ALTER TABLE ONLY impl.classification
    ADD CONSTRAINT classification_tenant_id_course_id_fkey FOREIGN KEY (tenant_id, course_id) REFERENCES impl.courses(tenant_id, id) ON DELETE CASCADE;


ALTER TABLE ONLY impl.lessons
    ADD CONSTRAINT lessons_tenant_id_course_id_fkey FOREIGN KEY (tenant_id, course_id) REFERENCES impl.courses(tenant_id, id) ON DELETE RESTRICT;


ALTER TABLE ONLY impl.enrollments
    ADD CONSTRAINT enrollments_tenant_id_course_id_fkey FOREIGN KEY (tenant_id, course_id) REFERENCES impl.courses(tenant_id, id) ON DELETE RESTRICT;


ALTER TABLE ONLY impl.enrollments
    ADD CONSTRAINT enrollments_tenant_id_user_id_fkey FOREIGN KEY (tenant_id, user_id) REFERENCES impl.users(tenant_id, id) ON DELETE RESTRICT;


ALTER TABLE ONLY impl.lesson_completion
    ADD CONSTRAINT lesson_completion_tenant_id_course_id_lesson_id_fkey FOREIGN KEY (tenant_id, course_id, lesson_id) REFERENCES impl.lessons(tenant_id, course_id, id) ON DELETE RESTRICT;


ALTER TABLE ONLY impl.lesson_completion
    ADD CONSTRAINT lesson_completion_tenant_id_enrollment_id_course_id_fkey FOREIGN KEY (tenant_id, enrollment_id, course_id) REFERENCES impl.enrollments(tenant_id, id, course_id) ON DELETE RESTRICT;


ALTER TABLE ONLY impl.refresh_tokens
    ADD CONSTRAINT refresh_tokens_tenant_id_user_id_fkey FOREIGN KEY (tenant_id, user_id) REFERENCES impl.users(tenant_id, id) ON DELETE RESTRICT;

-- === Indexes ===


CREATE UNIQUE INDEX users_tenant_email_key ON impl.users USING btree (tenant_id, lower(TRIM(BOTH FROM email)));


CREATE UNIQUE INDEX roles_code_unique_idx ON impl.roles USING btree (tenant_id, code);


CREATE UNIQUE INDEX roles_rank_unique_idx ON impl.roles USING btree (tenant_id, rank);


CREATE UNIQUE INDEX categories_tenant_name_key ON impl.categories USING btree (tenant_id, lower(TRIM(BOTH FROM name)));


CREATE INDEX courses_tenant_active_idx ON impl.courses USING btree (tenant_id) WHERE (is_active = true);


CREATE INDEX courses_tenant_author_idx ON impl.courses USING btree (tenant_id, author_id);


CREATE INDEX classification_tenant_category_idx ON impl.classification USING btree (tenant_id, category_id);


CREATE UNIQUE INDEX enrollments_active_unique ON impl.enrollments USING btree (tenant_id, course_id, user_id) WHERE (status = 'active'::impl.enrollment_status);


CREATE INDEX enrollments_tenant_course_status_idx ON impl.enrollments USING btree (tenant_id, course_id, status);


CREATE INDEX enrollments_tenant_user_status_idx ON impl.enrollments USING btree (tenant_id, user_id, status);


CREATE UNIQUE INDEX refresh_tokens_token_hash_idx ON impl.refresh_tokens USING btree (token_hash);


CREATE INDEX refresh_tokens_user_active_idx ON impl.refresh_tokens USING btree (tenant_id, user_id) WHERE (revoked_at IS NULL);

-- === Row Level Security ===


ALTER TABLE impl.users ENABLE ROW LEVEL SECURITY;


CREATE POLICY tenant_isolation ON impl.users USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


ALTER TABLE impl.roles ENABLE ROW LEVEL SECURITY;


CREATE POLICY tenant_isolation ON impl.roles USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


ALTER TABLE impl.categories ENABLE ROW LEVEL SECURITY;


CREATE POLICY tenant_isolation ON impl.categories USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


ALTER TABLE impl.courses ENABLE ROW LEVEL SECURITY;


CREATE POLICY tenant_isolation ON impl.courses USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


ALTER TABLE impl.classification ENABLE ROW LEVEL SECURITY;


CREATE POLICY tenant_isolation ON impl.classification USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


ALTER TABLE impl.lessons ENABLE ROW LEVEL SECURITY;


CREATE POLICY tenant_isolation ON impl.lessons USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


ALTER TABLE impl.enrollments ENABLE ROW LEVEL SECURITY;


CREATE POLICY tenant_isolation ON impl.enrollments USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


ALTER TABLE impl.lesson_completion ENABLE ROW LEVEL SECURITY;


CREATE POLICY tenant_isolation ON impl.lesson_completion USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));


ALTER TABLE impl.refresh_tokens ENABLE ROW LEVEL SECURITY;


CREATE POLICY tenant_isolation ON impl.refresh_tokens USING ((tenant_id = app.current_tenant())) WITH CHECK ((tenant_id = app.current_tenant()));

-- === Trigger Functions ===


CREATE FUNCTION impl.assert_course_has_category() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'impl', 'app', 'pg_temp'
    AS $$
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
$$;


CREATE FUNCTION impl.assert_course_has_lesson() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'impl', 'app', 'pg_temp'
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM impl.courses
         WHERE tenant_id = OLD.tenant_id AND id = OLD.course_id
    )
    AND NOT EXISTS (
        SELECT 1 FROM impl.lessons
         WHERE tenant_id = OLD.tenant_id AND course_id = OLD.course_id
    ) THEN
        RAISE EXCEPTION 'course_must_have_lessons';
    END IF;
    RETURN NULL;
END;
$$;


CREATE FUNCTION impl.auto_complete_enrollment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_enrollment_id   UUID;
    v_course_id       UUID;
    v_lesson_count    INT;
    v_completion_count  INT;
BEGIN
    v_enrollment_id := NEW.enrollment_id;

    SELECT course_id INTO v_course_id
    FROM impl.enrollments
    WHERE id = v_enrollment_id;

    SELECT COUNT(*) INTO v_lesson_count
    FROM impl.lessons
    WHERE course_id = v_course_id;

    SELECT COUNT(*) INTO v_completion_count
    FROM impl.lesson_completion
    WHERE enrollment_id = v_enrollment_id;

    IF v_completion_count = v_lesson_count AND v_lesson_count > 0 THEN
        UPDATE impl.enrollments
        SET status = 'completed'
        WHERE id = v_enrollment_id
          AND status = 'active';
    END IF;

    RETURN NULL;
END;
$$;


CREATE FUNCTION impl.normalize_email() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- IS NOT NULL guard: BEFORE triggers fire before CHECK constraints,
    -- so a NULL email must pass through untouched to let the existing
    -- NOT NULL CHECK from migration 005 reject it cleanly.
    IF NEW.email IS NOT NULL THEN
        NEW.email := LOWER(TRIM(NEW.email));
    END IF;
    RETURN NEW;
END;
$$;


CREATE FUNCTION impl.stamp_enrollment_terminal_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.status IN ('completed', 'cancelled') AND NEW.finished_at IS NULL THEN
        NEW.finished_at := NOW();
    END IF;

    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

-- === Triggers ===


CREATE TRIGGER users_normalize_email BEFORE INSERT OR UPDATE ON impl.users FOR EACH ROW EXECUTE FUNCTION impl.normalize_email();


CREATE TRIGGER users_set_updated_at BEFORE UPDATE ON impl.users FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


CREATE TRIGGER roles_set_updated_at BEFORE UPDATE ON impl.roles FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


CREATE TRIGGER categories_set_updated_at BEFORE UPDATE ON impl.categories FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


CREATE TRIGGER courses_set_updated_at BEFORE UPDATE ON impl.courses FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


CREATE CONSTRAINT TRIGGER course_categories_has_category_on_delete AFTER DELETE ON impl.classification DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION impl.assert_course_has_category();


CREATE CONSTRAINT TRIGGER course_categories_has_category_on_update AFTER UPDATE OF course_id ON impl.classification DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION impl.assert_course_has_category();


CREATE CONSTRAINT TRIGGER lessons_course_has_lesson_on_delete AFTER DELETE ON impl.lessons DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION impl.assert_course_has_lesson();


CREATE CONSTRAINT TRIGGER lessons_course_has_lesson_on_update AFTER UPDATE OF course_id ON impl.lessons DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION impl.assert_course_has_lesson();


CREATE TRIGGER lessons_set_updated_at BEFORE UPDATE ON impl.lessons FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


CREATE TRIGGER enrollments_set_updated_at BEFORE UPDATE ON impl.enrollments FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();


CREATE TRIGGER enrollments_stamp_terminal_timestamp BEFORE INSERT OR UPDATE ON impl.enrollments FOR EACH ROW EXECUTE FUNCTION impl.stamp_enrollment_terminal_timestamp();


CREATE TRIGGER lesson_completion_auto_complete_enrollment AFTER INSERT ON impl.lesson_completion FOR EACH ROW EXECUTE FUNCTION impl.auto_complete_enrollment();
