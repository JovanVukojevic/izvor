-- Demo seed for consultation walkthrough.
-- Two tenants (Intellya, FON), three users each (admin/learner/author), no domain data.
-- All accounts share password 'demo123' (dev-only, dev DB only).
--
-- Idempotent: re-running produces the same end state.
-- Apply as izvor_admin:
--   docker exec -i izvor-postgres psql -U izvor_admin -d izvor < db/seeds/demo.sql

-- Custom GUC carries the hash through both top-level statements and DO blocks
-- (psql \set substitution doesn't reach inside $$-quoted bodies).
SET demo.password_hash = '$2a$10$aH8P2ER.hbSgONDOOtUNNOrO5PF2mXCCHGu.dZqZRB4KTzja2TNr.';

DO $$
DECLARE t_id UUID;
BEGIN
    FOR t_id IN SELECT id FROM system_impl.tenants LOOP
        PERFORM set_config('app.current_tenant', t_id::TEXT, true);
        DELETE FROM impl.lesson_progress;
        DELETE FROM impl.enrollments;
        DELETE FROM impl.lessons;
        DELETE FROM impl.courses;
        DELETE FROM impl.refresh_tokens;
        DELETE FROM impl.categories;
        DELETE FROM impl.users;
        DELETE FROM impl.roles;
    END LOOP;
END $$;

DELETE FROM system_impl.tenants;

SELECT system_api.create_tenant_with_admin('Intellya', 'INTELLYA', 'intellya', 'admin@intellya.com', current_setting('demo.password_hash'));
SELECT system_api.create_tenant_with_admin('FON',      'FON',      'fon',      'admin@fon.com',      current_setting('demo.password_hash'));

DO $$
DECLARE
    rec RECORD;
    v_hash TEXT := current_setting('demo.password_hash');
BEGIN
    FOR rec IN SELECT id, subdomain FROM system_impl.tenants ORDER BY subdomain LOOP
        PERFORM set_config('app.current_tenant', rec.id::TEXT, true);
        PERFORM spec.create_user_internal('jovan@'    || rec.subdomain || '.com', v_hash, 'learner');
        PERFORM spec.create_user_internal('natalija@' || rec.subdomain || '.com', v_hash, 'author');
    END LOOP;
END $$;

DO $$
DECLARE
    rec RECORD;
    v_user_count INT := 0;
    v_partial INT;
BEGIN
    FOR rec IN SELECT id FROM system_impl.tenants LOOP
        PERFORM set_config('app.current_tenant', rec.id::TEXT, true);
        SELECT COUNT(*) INTO v_partial FROM impl.users;
        v_user_count := v_user_count + v_partial;
    END LOOP;
    RAISE NOTICE 'tenants=%, users (all tenants)=%',
        (SELECT COUNT(*) FROM system_impl.tenants), v_user_count;
END $$;
