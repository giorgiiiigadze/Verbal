-- Development rollout: allow unlimited quote creation without requiring a
-- StoreKit entitlement. This is the existing operational off-switch and can
-- be reversed without changing quote data by setting the value back to true.
update public.app_settings
   set quota_enforced = false,
       updated_at = now()
 where id;
