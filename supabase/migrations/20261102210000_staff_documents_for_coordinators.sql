-- Documenti e dati del personale visibili a chi coordina il reparto.
-- Condivisione attiva di default (la persona può disattivarla da "Documenti professionali").
-- Il Master non ha mai accesso. Idempotente.

alter table public.profiles
  add column if not exists employee_number text,
  add column if not exists id_doc_type text,
  add column if not exists id_doc_number text,
  add column if not exists id_doc_issued_by text,
  add column if not exists id_doc_issued_on date,
  add column if not exists id_doc_expires_on date,
  add column if not exists docs_visible_to_coordinators boolean not null default true;

alter table public.profiles drop constraint if exists profiles_id_doc_type_check;
alter table public.profiles add constraint profiles_id_doc_type_check
  check (id_doc_type is null or id_doc_type in ('carta_identita','passaporto','patente','permesso_soggiorno','altro'));
alter table public.profiles drop constraint if exists profiles_employee_number_check;
alter table public.profiles add constraint profiles_employee_number_check
  check (employee_number is null or char_length(employee_number) <= 30);

alter table public.professional_documents add column if not exists other_label text;
alter table public.professional_documents drop constraint if exists professional_documents_other_label_check;
alter table public.professional_documents add constraint professional_documents_other_label_check
  check (other_label is null or char_length(other_label) <= 60);

alter table public.professional_documents drop constraint if exists professional_documents_document_type_check;
alter table public.professional_documents add constraint professional_documents_document_type_check
  check (document_type = any (array['blsd','order','fire_safety','cv','id_card','tax_code','other']::text[]));
