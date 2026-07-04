-- Creazione tabella permessi_sezione per permessi granulari
-- Esegui questo script in Supabase → SQL Editor

CREATE TABLE IF NOT EXISTS public.permessi_sezione (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  volontario_id UUID NOT NULL REFERENCES public.volontari(id) ON DELETE CASCADE,
  sezione TEXT NOT NULL,
  permesso TEXT NOT NULL DEFAULT 'solo_lettura',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(volontario_id, sezione)
);

-- Aggiungi constraint per validare i valori
ALTER TABLE public.permessi_sezione 
DROP CONSTRAINT IF EXISTS permessi_sezione_permesso_check;
ALTER TABLE public.permessi_sezione 
ADD CONSTRAINT permessi_sezione_permesso_check CHECK (permesso in ('solo_lettura', 'pieno_accesso'));

-- Aggiungi constraint per validare le sezioni
ALTER TABLE public.permessi_sezione 
DROP CONSTRAINT IF EXISTS permessi_sezione_sezione_check;
ALTER TABLE public.permessi_sezione 
ADD CONSTRAINT permessi_sezione_sezione_check CHECK (sezione in ('volontari', 'mezzi', 'magazzino', 'sala_radio', 'archivio', 'segnalazioni'));

-- Abilita RLS
ALTER TABLE public.permessi_sezione ENABLE ROW LEVEL SECURITY;

-- Politica RLS per permettere lettura a tutti gli utenti autenticati
CREATE POLICY "Permetti lettura permessi_sezione" ON public.permessi_sezione
  FOR SELECT USING (auth.role() = 'authenticated');

-- Politica RLS per permettere inserimento a tutti gli utenti autenticati
CREATE POLICY "Permetti inserimento permessi_sezione" ON public.permessi_sezione
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Politica RLS per permettere aggiornamento a tutti gli utenti autenticati
CREATE POLICY "Permetti aggiornamento permessi_sezione" ON public.permessi_sezione
  FOR UPDATE USING (auth.role() = 'authenticated');

-- Politica RLS per permettere cancellazione a tutti gli utenti autenticati
CREATE POLICY "Permetti cancellazione permessi_sezione" ON public.permessi_sezione
  FOR DELETE USING (auth.role() = 'authenticated');
