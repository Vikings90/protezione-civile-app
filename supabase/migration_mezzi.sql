-- Aggiornamento tabella mezzi per aggiungere org_id
-- Esegui questo script in Supabase → SQL Editor

-- Rimuovi policy RLS esistenti
DROP POLICY IF EXISTS "Permetti lettura mezzi" ON public.mezzi;
DROP POLICY IF EXISTS "Permetti inserimento mezzi" ON public.mezzi;
DROP POLICY IF EXISTS "Permetti aggiornamento mezzi" ON public.mezzi;
DROP POLICY IF EXISTS "Permetti cancellazione mezzi" ON public.mezzi;

-- Aggiungi colonna org_id se non esiste (inizia come nullable)
ALTER TABLE public.mezzi
ADD COLUMN IF NOT EXISTS org_id UUID REFERENCES public.organizzazioni(id) ON DELETE CASCADE;

-- Aggiorna i mezzi esistenti senza org_id con il primo org_id disponibile
UPDATE public.mezzi m
SET org_id = o.id
FROM public.organizzazioni o
WHERE m.org_id IS NULL
AND o.id = (SELECT id FROM public.organizzazioni LIMIT 1);

-- Rendi org_id NOT NULL (solo se tutti i mezzi hanno un org_id)
ALTER TABLE public.mezzi
ALTER COLUMN org_id SET NOT NULL;

-- Ricrea le policy RLS
CREATE POLICY "Permetti lettura mezzi" ON public.mezzi
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Permetti inserimento mezzi" ON public.mezzi
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Permetti aggiornamento mezzi" ON public.mezzi
  FOR UPDATE USING (auth.role() = 'authenticated');

CREATE POLICY "Permetti cancellazione mezzi" ON public.mezzi
  FOR DELETE USING (auth.role() = 'authenticated');
