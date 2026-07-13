-- Interventi di protezione civile
create table if not exists public.interventi (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizzazioni (id) on delete cascade,
  titolo text not null,
  descrizione text default '',
  segnalato_da text default '',
  inizio text not null,
  fine text,
  foto text,
  mezzi text[] default '{}',
  volontari_impegnati text[] default '{}',
  stato text not null default 'sala_radio' check (stato in ('sala_radio', 'archiviato')),
  created_at timestamptz not null default now()
);

alter table public.interventi enable row level security;

-- INTERVENTI
create policy "interventi_all_org"
on public.interventi for all to authenticated
using (org_id = public.current_org_id())
with check (org_id = public.current_org_id());
