#!/usr/bin/env bash
# Runs only against a local Supabase stack. The explicit opt-in prevents an
# accidental `db reset` from wiping a developer's local data.
set -euo pipefail

if [[ "${VERBAL_ALLOW_LOCAL_RESET:-}" != "1" ]]; then
  echo "Refusing to reset the local database. Re-run with VERBAL_ALLOW_LOCAL_RESET=1."
  exit 1
fi

node supabase/functions/app-store-notifications/notification-state.test.mjs

(
  cd supabase/functions/verify-subscription
  npm install --no-save --package-lock=false @apple/app-store-server-library@3.1.0
  node entitlement.test.mjs
)

supabase db start
supabase db reset
supabase test db supabase/tests/quota_and_integrity.sql --local
