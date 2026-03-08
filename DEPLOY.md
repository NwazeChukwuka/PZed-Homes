# Deploying to Vercel (Path A: build on Vercel)

The app builds on Vercel. The build script `vercel_build.sh` installs Flutter and runs `flutter build web`.

**Vercel Dashboard**

- **Build Command:** `bash ./vercel_build.sh` (or leave default so `vercel.json` is used)
- **Output Directory:** `build/web`
- **Environment variables:** Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` in Project → Settings → Environment Variables.

Push to `main` to trigger a deploy.
