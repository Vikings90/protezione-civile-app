-- Aggiornamento constraint permessi volontari per includere valore granulare
-- Esegui questo script in Supabase → SQL Editor

-- Rimuovi il constraint esistente
ALTER TABLE public.volontari 
DROP CONSTRAINT IF EXISTS volontari_permessi_check;

-- Aggiungi il constraint aggiornato con i valori corretti
ALTER TABLE public.volontari 
ADD CONSTRAINT volontari_permessi_check CHECK (permessi in ('pieno_accesso', 'solo_lettura', 'granulare'));
