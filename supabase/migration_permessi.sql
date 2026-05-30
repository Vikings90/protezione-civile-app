-- Migrazione per aggiungere il campo permessi al database esistente
-- Esegui questo script in Supabase → SQL Editor per aggiornare il database

-- Aggiungi campo permessi alla tabella profili
ALTER TABLE public.profili 
ADD COLUMN IF NOT EXISTS permessi text NOT NULL DEFAULT 'pieno_accesso';

-- Aggiungi constraint per validare i valori permessi
ALTER TABLE public.profili 
DROP CONSTRAINT IF EXISTS profili_permessi_check;
ALTER TABLE public.profili 
ADD CONSTRAINT profili_permessi_check CHECK (permessi in ('solo_lettura', 'pieno_accesso'));

-- Aggiungi campo permessi alla tabella volontari
ALTER TABLE public.volontari 
ADD COLUMN IF NOT EXISTS permessi text NOT NULL DEFAULT 'pieno_accesso';

-- Aggiungi constraint per validare i valori permessi
ALTER TABLE public.volontari 
DROP CONSTRAINT IF EXISTS volontari_permessi_check;
ALTER TABLE public.volontari 
ADD CONSTRAINT volontari_permessi_check CHECK (permessi in ('solo_lettura', 'pieno_accesso'));
