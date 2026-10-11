DROP FUNCTION IF EXISTS public.get_progress_map_points(integer);
CREATE FUNCTION public.get_progress_map_points(p_days integer DEFAULT 30)
RETURNS TABLE(location_lat numeric, location_lng numeric, place_label text, moment_count bigint)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $function$
  SELECT
    round(pm.location_lat::numeric, 2) AS location_lat,
    round(pm.location_lng::numeric, 2) AS location_lng,
    max(pm.place_label)::text AS place_label,
    count(*)::bigint AS moment_count
  FROM public.progress_moments AS pm
  WHERE pm.privacy = 'public'
    AND pm.status = 'published'
    AND pm.location_consent IS TRUE
    AND pm.location_lat IS NOT NULL
    AND pm.location_lng IS NOT NULL
    AND pm.created_at >= now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 30)))
  GROUP BY round(pm.location_lat::numeric, 2), round(pm.location_lng::numeric, 2);
$function$;
REVOKE ALL ON FUNCTION public.get_progress_map_points(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_progress_map_points(integer) TO anon, authenticated, service_role;

DROP FUNCTION IF EXISTS public.get_public_achievement_cards(integer);
CREATE FUNCTION public.get_public_achievement_cards(p_limit integer DEFAULT 12)
RETURNS TABLE(title text, story text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT ac.title::text, ac.story::text
  FROM public.achievement_cards AS ac
  WHERE ac.status = 'published'
    AND ac.visibility = 'public'
  ORDER BY ac.published_at DESC
  LIMIT least(greatest(coalesce(p_limit, 12), 1), 100);
$function$;
REVOKE ALL ON FUNCTION public.get_public_achievement_cards(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_achievement_cards(integer) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.suggest_journey_for_moment(p_progress_moment_id uuid)
RETURNS TABLE(journey_title text, journey_id uuid, confidence numeric)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required';
  END IF;

  RETURN QUERY
  SELECT
    j.title::text AS journey_title,
    j.id AS journey_id,
    CASE
      WHEN position(lower(j.title) IN lower(coalesce(m.body, ''))) > 0 THEN 0.90::numeric
      WHEN nullif(trim(j.category), '') IS NOT NULL
        AND position(lower(j.category) IN lower(coalesce(m.body, ''))) > 0 THEN 0.70::numeric
      ELSE 0.50::numeric
    END AS confidence
  FROM public.progress_moments AS m
  JOIN public.journeys AS j
    ON j.user_id = auth.uid()
   AND j.status = 'active'
  WHERE m.id = p_progress_moment_id
    AND m.user_id = auth.uid()
    AND nullif(trim(coalesce(m.body, '')), '') IS NOT NULL
    AND (
      position(lower(j.title) IN lower(coalesce(m.body, ''))) > 0
      OR (
        nullif(trim(j.category), '') IS NOT NULL
        AND position(lower(j.category) IN lower(coalesce(m.body, ''))) > 0
      )
      OR EXISTS (
        SELECT 1
        FROM regexp_split_to_table(concat_ws(' ', j.title, j.category), '[^[:alnum:]]+') AS token(value)
        WHERE length(token.value) >= 4
          AND position(lower(token.value) IN lower(coalesce(m.body, ''))) > 0
      )
    )
  ORDER BY confidence DESC, j.created_at DESC
  LIMIT 3;
END;
$function$;
REVOKE ALL ON FUNCTION public.suggest_journey_for_moment(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.suggest_journey_for_moment(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.accept_journey_suggestion(
  p_progress_moment_id uuid,
  p_journey_id uuid
)
RETURNS public.progress_moments
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $function$
DECLARE
  v_moment public.progress_moments;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required';
  END IF;

  UPDATE public.progress_moments AS m
  SET journey_id = p_journey_id
  WHERE m.id = p_progress_moment_id
    AND m.user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.journeys AS j
      WHERE j.id = p_journey_id
        AND j.user_id = auth.uid()
        AND j.status = 'active'
    )
  RETURNING m.* INTO v_moment;

  IF v_moment.id IS NULL THEN
    RAISE EXCEPTION 'progress moment or active journey not found for this user';
  END IF;

  RETURN v_moment;
END;
$function$;
REVOKE ALL ON FUNCTION public.accept_journey_suggestion(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_journey_suggestion(uuid, uuid) TO authenticated, service_role;
