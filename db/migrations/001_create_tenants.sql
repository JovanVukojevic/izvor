CREATE OR REPLACE FUNCTION app.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

ALTER FUNCTION app.set_updated_at() OWNER TO izvor_admin;


CREATE TYPE system_impl.tenant_status AS ENUM ('active', 'suspended');

ALTER TYPE system_impl.tenant_status OWNER TO izvor_admin;


CREATE TABLE system_impl.tenants (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name        TEXT NOT NULL
                    CHECK (length(trim(name)) > 0),

    code        TEXT NOT NULL UNIQUE
                    CHECK (code ~ '^[A-Z][A-Z0-9_]{1,31}$'),

    subdomain   TEXT NOT NULL UNIQUE
                    CHECK (subdomain ~ '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$')
                    CHECK (subdomain NOT IN ('www', 'admin', 'api', 'app',
                                             'mail', 'static', 'assets', 'cdn',
                                             'support', 'help', 'blog', 'docs')),

    status      system_impl.tenant_status NOT NULL DEFAULT 'active',

    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE system_impl.tenants OWNER TO izvor_admin;


CREATE TRIGGER tenants_set_updated_at
    BEFORE UPDATE ON system_impl.tenants
    FOR EACH ROW
    EXECUTE FUNCTION app.set_updated_at();
