-- === Types ===


CREATE TYPE system_impl.tenant_status AS ENUM (
    'active',
    'suspended'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

-- === Tables ===


CREATE TABLE system_impl.tenants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    code text NOT NULL,
    subdomain text NOT NULL,
    status system_impl.tenant_status DEFAULT 'active'::system_impl.tenant_status NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tenants_code_check CHECK ((code ~ '^[A-Z][A-Z0-9_]{1,31}$'::text)),
    CONSTRAINT tenants_name_check CHECK ((length(TRIM(BOTH FROM name)) > 0)),
    CONSTRAINT tenants_subdomain_check CHECK ((subdomain ~ '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$'::text)),
    CONSTRAINT tenants_subdomain_check1 CHECK ((subdomain <> ALL (ARRAY['www'::text, 'admin'::text, 'api'::text, 'app'::text, 'mail'::text, 'static'::text, 'assets'::text, 'cdn'::text, 'support'::text, 'help'::text, 'blog'::text, 'docs'::text])))
);

-- === Constraints ===


ALTER TABLE ONLY system_impl.tenants
    ADD CONSTRAINT tenants_code_key UNIQUE (code);


ALTER TABLE ONLY system_impl.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


ALTER TABLE ONLY system_impl.tenants
    ADD CONSTRAINT tenants_subdomain_key UNIQUE (subdomain);

-- === Triggers ===


CREATE TRIGGER tenants_set_updated_at BEFORE UPDATE ON system_impl.tenants FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();
