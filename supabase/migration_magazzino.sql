-- Creazione tabella magazzino per gestione attrezzature
-- Esegui questo script in Supabase → SQL Editor

CREATE TABLE IF NOT EXISTS public.magazzino (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id UUID NOT NULL REFERENCES public.organizzazioni(id) ON DELETE CASCADE,
  descrizione TEXT NOT NULL,
  quantita INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Abilita RLS
ALTER TABLE public.magazzino ENABLE ROW LEVEL SECURITY;

-- Politica RLS per permettere lettura a tutti gli utenti autenticati
CREATE POLICY "Permetti lettura magazzino" ON public.magazzino
  FOR SELECT USING (auth.role() = 'authenticated');

-- Politica RLS per permettere inserimento a tutti gli utenti autenticati
CREATE POLICY "Permetti inserimento magazzino" ON public.magazzino
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Politica RLS per permettere aggiornamento a tutti gli utenti autenticati
CREATE POLICY "Permetti aggiornamento magazzino" ON public.magazzino
  FOR UPDATE USING (auth.role() = 'authenticated');

-- Politica RLS per permettere cancellazione a tutti gli utenti autenticati
CREATE POLICY "Permetti cancellazione magazzino" ON public.magazzino
  FOR DELETE USING (auth.role() = 'authenticated');
