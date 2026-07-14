-- Sicurezza Guida - Registrazione test sicurezza volontari
create table if not exists public.sicurezza_guida (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizzazioni (id) on delete cascade,
  volontario_nome text not null,
  volontario_email text,
  data_test timestamptz not null default now(),
  stato_servizio text not null check (stato_servizio in ('in_servizio', 'uscito')),
  note text default '',
  created_at timestamptz not null default now()
);

alter table public.sicurezza_guida enable row level security;

-- SICUREZZA GUIDA
create policy "sicurezza_guida_all_org"
on public.sicurezza_guida for all to authenticated
using (org_id = public.current_org_id())
with check (org_id = public.current_org_id());
