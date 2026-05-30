-- Esegui solo se hai già creato le tabelle e vuoi codici master univoci tra associazioni
-- (evita che due sedi usino lo stesso codice di recupero)

alter table public.organizzazioni
  drop constraint if exists organizzazioni_master_code_unique;

alter table public.organizzazioni
  add constraint organizzazioni_master_code_unique unique (master_code);
