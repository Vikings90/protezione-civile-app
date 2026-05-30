-- Esegui questo script in Supabase → SQL Editor

-- Organizzazioni (associazioni)
create table if not exists public.organizzazioni (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  nome text not null,
  via text default '',
  indirizzo text default '',
  email text not null unique,
  master_code text not null unique,
  created_at timestamptz not null default now()
);

-- Profili utente (master / volontario)
create table if not exists public.profili (
  id uuid primary key references auth.users (id) on delete cascade,
  org_id uuid not null references public.organizzazioni (id) on delete cascade,
  ruolo text not null check (ruolo in ('master', 'volontario')),
  permessi text not null default 'pieno_accesso' check (permessi in ('solo_lettura', 'pieno_accesso')),
  nome text not null default '',
  cognome text not null default '',
  email text not null,
  created_at timestamptz not null default now()
);

-- Inviti volontari (cartella master)
create table if not exists public.inviti (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizzazioni (id) on delete cascade,
  nome text not null,
  cognome text not null,
  email text not null,
  stato text not null default 'in_attesa' check (stato in ('in_attesa', 'registrato')),
  data_invito timestamptz not null default now(),
  data_registrazione timestamptz,
  user_id uuid references auth.users (id),
  unique (org_id, email)
);

-- Volontari operativi (dashboard)
create table if not exists public.volontari (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizzazioni (id) on delete cascade,
  nome text not null,
  ruolo text not null default 'Volontario',
  patente_c boolean not null default false,
  stato text not null default 'Disponibile',
  in_servizio boolean not null default true,
  email text,
  permessi text not null default 'pieno_accesso' check (permessi in ('solo_lettura', 'pieno_accesso')),
  created_at timestamptz not null default now()
);

alter table public.organizzazioni enable row level security;
alter table public.profili enable row level security;
alter table public.inviti enable row level security;
alter table public.volontari enable row level security;

-- Helper: org dell'utente loggato
create or replace function public.current_org_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select org_id from public.profili where id = auth.uid() limit 1;
$$;

-- ORGANIZZAZIONI
create policy "org_select_authenticated"
on public.organizzazioni for select to authenticated
using (id = public.current_org_id() or owner_id = auth.uid());

create policy "org_select_anon_count"
on public.organizzazioni for select to anon
using (true);

create policy "org_insert_owner"
on public.organizzazioni for insert to authenticated
with check (owner_id = auth.uid());

create policy "org_update_owner"
on public.organizzazioni for update to authenticated
using (owner_id = auth.uid());

-- PROFILI
create policy "profili_select_own_org"
on public.profili for select to authenticated
using (org_id = public.current_org_id() or id = auth.uid());

create policy "profili_insert_self"
on public.profili for insert to authenticated
with check (id = auth.uid());

-- INVITI
create policy "inviti_select_org"
on public.inviti for select to authenticated
using (org_id = public.current_org_id());

create policy "inviti_select_pending_anon"
on public.inviti for select to anon
using (stato = 'in_attesa');

create policy "inviti_insert_master"
on public.inviti for insert to authenticated
with check (org_id = public.current_org_id());

create policy "inviti_update_org"
on public.inviti for update to authenticated
using (org_id = public.current_org_id());

-- Il volontario può completare il proprio invito in registrazione
create policy "inviti_update_self_register"
on public.inviti for update to authenticated
using (
  stato = 'in_attesa'
  and lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
);

create policy "inviti_delete_master"
on public.inviti for delete to authenticated
using (org_id = public.current_org_id());

-- VOLONTARI
create policy "volontari_all_org"
on public.volontari for all to authenticated
using (org_id = public.current_org_id())
with check (org_id = public.current_org_id());
