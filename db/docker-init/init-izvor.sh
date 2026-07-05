#!/bin/sh
set -e
CLEAN=/opt/izvor/db-clean
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -f "$CLEAN/00_init.sql" \
  -c 'SET SESSION AUTHORIZATION izvor_admin' \
  -f "$CLEAN/01_app.sql" \
  -f "$CLEAN/02_system_impl.sql" \
  -f "$CLEAN/03_system_spec.sql" \
  -f "$CLEAN/04_system_api.sql" \
  -f "$CLEAN/05_impl.sql" \
  -f "$CLEAN/06_spec.sql" \
  -f "$CLEAN/07_api.sql" \
  -f "$CLEAN/08_seed_demo.sql"
