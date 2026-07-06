-- Creazione tabella presenze per il sistema di registrazione presenze
-- Esegui questo script in Supabase → SQL Editor

-- Crea la tabella presenze
CREATE TABLE IF NOT EXISTS public.presenze (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id UUID NOT NULL REFERENCES public.organizzazioni(id) ON DELETE CASCADE,
  volontario_email TEXT NOT NULL,
  volontario_nome TEXT NOT NULL,
  giorno TEXT NOT NULL,
  entrata TEXT NOT NULL,
  uscita TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Abilita RLS
ALTER TABLE public.presenze ENABLE ROW LEVEL SECURITY;

-- Politica RLS: permetti lettura/scrittura solo agli utenti della stessa organizzazione
CREATE POLICY "Utenti possono vedere presenze della loro organizzazione"
  ON public.presenze FOR SELECT
  USING (org_id IN (SELECT org_id FROM public.profili WHERE id = auth.uid()));

CREATE POLICY "Utenti possono inserire presenze nella loro organizzazione"
  ON public.presenze FOR INSERT
  WITH CHECK (org_id IN (SELECT org_id FROM public.profili WHERE id = auth.uid()));

CREATE POLICY "Utenti possono aggiornare presenze della loro organizzazione"
  ON public.presenze FOR UPDATE
  USING (org_id IN (SELECT org_id FROM public.profili WHERE id = auth.uid()));

CREATE POLICY "Utenti possono cancellare presenze della loro organizzazione"
  ON public.presenze FOR DELETE
  USING (org_id IN (SELECT org_id FROM public.profili WHERE id = auth.uid()));

-- Indice per migliorare le performance
CREATE INDEX IF NOT EXISTS idx_presenze_org_id ON public.presenze(org_id);
CREATE INDEX IF NOT EXISTS idx_presenze_volontario_email ON public.presenze(volontario_email);
CREATE INDEX IF NOT EXISTS idx_presenze_entrata ON public.presenze(entrata DESC);
