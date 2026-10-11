CREATE OR REPLACE FUNCTION public.add_progress_moment_reaction(p_moment_id uuid, p_reaction text)
RETURNS public.progress_moment_reactions
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v public.progress_moment_reactions;
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication required';
  END IF;

  IF p_reaction IS NULL OR p_reaction NOT IN ('celebrate', 'support', 'inspire') THEN
    RAISE EXCEPTION 'invalid reaction';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.progress_moments
    WHERE id = p_moment_id
      AND status = 'published'
      AND privacy = 'public'
  ) THEN
    RAISE EXCEPTION 'progress moment not available';
  END IF;

  INSERT INTO public.progress_moment_reactions(moment_id, user_id, reaction)
  VALUES (p_moment_id, v_user_id, p_reaction)
  ON CONFLICT (moment_id, user_id, reaction) DO NOTHING
  RETURNING * INTO v;

  IF NOT FOUND THEN
    SELECT *
    INTO v
    FROM public.progress_moment_reactions
    WHERE moment_id = p_moment_id
      AND user_id = v_user_id
      AND reaction = p_reaction;
  END IF;

  RETURN v;
END;
$function$;
