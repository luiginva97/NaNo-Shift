drop policy if exists push_settings_service_role_select on private.push_settings;
create policy push_settings_service_role_select on private.push_settings
  for select to service_role using (true);
