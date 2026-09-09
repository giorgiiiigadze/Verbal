-- The project grants new public-schema functions to API roles by default, so
-- revoke the anonymous role explicitly as well as PUBLIC.
revoke execute on function public.create_quote_with_client_details(
  text, text, text[], text, numeric, numeric, text, text, text, jsonb, text
) from public, anon;

grant execute on function public.create_quote_with_client_details(
  text, text, text[], text, numeric, numeric, text, text, text, jsonb, text
) to authenticated;
