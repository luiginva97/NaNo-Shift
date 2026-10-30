alter table public.shifts
  add column if not exists template_id uuid null
  references public.shift_templates(id) on delete set null;
create index if not exists shifts_template_id_idx on public.shifts(template_id);
