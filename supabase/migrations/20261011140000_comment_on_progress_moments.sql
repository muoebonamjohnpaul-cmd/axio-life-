CREATE TABLE IF NOT EXISTS public.progress_moment_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  progress_moment_id uuid NOT NULL REFERENCES public.progress_moments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body text NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 500),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS progress_moment_comments_post_created_idx
  ON public.progress_moment_comments (progress_moment_id, created_at DESC);

ALTER TABLE public.progress_moment_comments ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.progress_moment_comments FROM PUBLIC;
GRANT SELECT ON public.progress_moment_comments TO anon, authenticated;
GRANT INSERT, DELETE ON public.progress_moment_comments TO authenticated;

DROP POLICY IF EXISTS progress_moment_comments_read_public ON public.progress_moment_comments;
CREATE POLICY progress_moment_comments_read_public
  ON public.progress_moment_comments FOR SELECT TO anon, authenticated
  USING (EXISTS (
    SELECT 1 FROM public.progress_moments AS pm
    WHERE pm.id = progress_moment_comments.progress_moment_id
      AND pm.privacy = 'public'
      AND pm.status = 'published'
  ));

DROP POLICY IF EXISTS progress_moment_comments_insert_own ON public.progress_moment_comments;
CREATE POLICY progress_moment_comments_insert_own
  ON public.progress_moment_comments FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.progress_moments AS pm
      WHERE pm.id = progress_moment_comments.progress_moment_id
        AND pm.privacy = 'public'
        AND pm.status = 'published'
    )
  );

DROP POLICY IF EXISTS progress_moment_comments_delete_author_or_post_owner ON public.progress_moment_comments;
CREATE POLICY progress_moment_comments_delete_author_or_post_owner
  ON public.progress_moment_comments FOR DELETE TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.progress_moments AS pm
      WHERE pm.id = progress_moment_comments.progress_moment_id
        AND pm.user_id = (SELECT auth.uid())
    )
  );

CREATE OR REPLACE FUNCTION public.get_public_progress_comment_counts(p_moment_ids uuid[])
RETURNS TABLE (progress_moment_id uuid, comment_count bigint)
LANGUAGE sql
STABLE
SET search_path = ''
AS $function$
  SELECT c.progress_moment_id, count(*)::bigint AS comment_count
  FROM public.progress_moment_comments AS c
  JOIN public.progress_moments AS pm ON pm.id = c.progress_moment_id
  WHERE c.progress_moment_id = ANY(p_moment_ids[1:100])
    AND pm.privacy = 'public'
    AND pm.status = 'published'
  GROUP BY c.progress_moment_id;
$function$;

REVOKE ALL ON FUNCTION public.get_public_progress_comment_counts(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_progress_comment_counts(uuid[]) TO anon, authenticated;
