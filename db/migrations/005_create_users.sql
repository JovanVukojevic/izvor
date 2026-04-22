CREATE TYPE impl.user_role AS ENUM ('admin', 'author', 'learner');

ALTER TYPE impl.user_role OWNER TO izvor_admin;


CREATE TABLE impl.users (
    id             UUID NOT NULL DEFAULT gen_random_uuid(),
    tenant_id      UUID NOT NULL,

    email          TEXT NOT NULL
                       CHECK (email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),

    password_hash  TEXT NOT NULL
                       CHECK (length(password_hash) = 60),

    role           impl.user_role NOT NULL DEFAULT 'learner',

    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (tenant_id, id)
);

ALTER TABLE impl.users OWNER TO izvor_admin;


CREATE UNIQUE INDEX users_tenant_email_key
    ON impl.users (tenant_id, lower(trim(email)));


CREATE TRIGGER users_set_updated_at
    BEFORE UPDATE ON impl.users
    FOR EACH ROW
    EXECUTE FUNCTION app.set_updated_at();


ALTER TABLE impl.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE impl.users FORCE  ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON impl.users
    USING       (tenant_id = app.current_tenant())
    WITH CHECK  (tenant_id = app.current_tenant());
