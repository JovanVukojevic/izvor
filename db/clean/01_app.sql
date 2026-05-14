-- === Trigger Functions ===


CREATE FUNCTION app.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;
