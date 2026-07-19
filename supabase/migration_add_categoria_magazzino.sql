-- Aggiunge colonna categoria alla tabella magazzino
ALTER TABLE public.magazzino ADD COLUMN IF NOT EXISTS categoria TEXT DEFAULT 'elettricità';
