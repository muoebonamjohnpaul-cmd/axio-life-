-- Let Explore create temporary signed URLs for media attached to published public moments.
-- The bucket remains private; existing owner-only read access is preserved.
DROP POLICY IF EXISTS progress_media_read_public_posts ON storage.objects;

CREATE POLICY progress_media_read_public_posts
ON storage.objects
FOR SELECT
TO anon, authenticated
USING (
  bucket_id = 'progress-media'
  AND EXISTS (
    SELECT 1
    FROM public.progress_moments AS pm
    WHERE pm.media_url = name
      AND pm.privacy = 'public'
      AND pm.status = 'published'
      AND pm.media_type IN ('photo', 'video')
  )
);
