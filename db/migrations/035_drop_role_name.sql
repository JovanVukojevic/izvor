CREATE OR REPLACE FUNCTION system_api.create_tenant_with_admin(p_tenant_name text, p_tenant_code text, p_subdomain text, p_admin_email text, p_admin_password_hash text)
 RETURNS system_api.tenant_with_admin
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'system_api', 'system_spec', 'system_impl', 'spec', 'impl', 'app', 'pg_temp'
AS $function$
DECLARE
    v_tenant_id UUID;
    v_admin_id  UUID;
    v_result    system_api.tenant_with_admin;
BEGIN
    v_tenant_id := system_spec.create_tenant(p_tenant_name, p_tenant_code, p_subdomain);

    PERFORM set_config('app.current_tenant', v_tenant_id::text, true);

    INSERT INTO impl.roles (tenant_id, code, description, rank) VALUES
        (v_tenant_id, 'admin',   'Full administrative access within the organization', 100),
        (v_tenant_id, 'author',  'Can create and manage course content',                50),
        (v_tenant_id, 'learner', 'Can browse and complete courses',                     10);

    v_admin_id := spec.create_user_internal(p_admin_email, p_admin_password_hash, 'admin');

    v_result := (v_tenant_id, p_tenant_code, p_subdomain, v_admin_id, p_admin_email);
    RETURN v_result;
END;
$function$;

ALTER TABLE impl.roles DROP COLUMN name;
