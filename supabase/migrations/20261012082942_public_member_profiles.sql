create or replace function public.get_public_profile(
  p_user_id uuid,
  p_limit integer default 60
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select jsonb_build_object(
    'profile', jsonb_build_object(
      'display_name', identity.display_name,
      'username', identity.username,
      'avatar_path', identity.avatar_path,
      'moment_count', (
        select count(*)::integer
        from public.progress_moments as moment
        where moment.user_id = identity.user_id
          and moment.privacy = 'public'
          and moment.status = 'published'
      ),
      'achievement_count', (
        select count(*)::integer
        from public.achievement_cards as card
        where card.user_id = identity.user_id
          and card.visibility = 'public'
          and card.status = 'published'
      )
    ),
    'moments', coalesce((
      select jsonb_agg(to_jsonb(shared_moment) order by shared_moment.created_at desc)
      from (
        select
          moment.id,
          moment.created_at,
          moment.progress_type,
          moment.body,
          moment.media_url,
          moment.media_type,
          moment.place_label,
          moment.verification_state
        from public.progress_moments as moment
        where moment.user_id = identity.user_id
          and moment.privacy = 'public'
          and moment.status = 'published'
        order by moment.created_at desc
        limit least(greatest(coalesce(p_limit, 60), 1), 60)
      ) as shared_moment
    ), '[]'::jsonb),
    'achievements', coalesce((
      select jsonb_agg(to_jsonb(shared_achievement) order by shared_achievement.published_at desc nulls last)
      from (
        select card.title, card.story, card.published_at
        from public.achievement_cards as card
        where card.user_id = identity.user_id
          and card.visibility = 'public'
          and card.status = 'published'
        order by card.published_at desc nulls last
        limit 30
      ) as shared_achievement
    ), '[]'::jsonb)
  )
  from public.public_profile_identities as identity
  where identity.user_id = p_user_id;
$function$;

revoke all on function public.get_public_profile(uuid, integer) from public, anon, authenticated;
grant execute on function public.get_public_profile(uuid, integer) to anon, authenticated;
