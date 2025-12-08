# Environment Variables Setup

This app requires Supabase and Paystack credentials to function properly.

## Quick Setup

1. **Create a `.env` file** in the root directory of your project (same folder as `pubspec.yaml`)

2. **Copy and paste the following template** into your `.env` file:

```env
# Supabase Configuration
SUPABASE_URL=your_supabase_url_here
SUPABASE_ANON_KEY=your_supabase_anon_key_here

# Paystack Configuration
PAYSTACK_PUBLIC_KEY=your_paystack_public_key_here
```

3. **Replace the placeholder values** with your actual credentials:
   - **SUPABASE_URL**: Your Supabase project URL (e.g., `https://xxxxx.supabase.co`)
   - **SUPABASE_ANON_KEY**: Your Supabase anonymous/public key
   - **PAYSTACK_PUBLIC_KEY**: Your Paystack public key

## Where to Find Your Keys

### Supabase Keys
1. Go to your [Supabase Dashboard](https://app.supabase.com)
2. Select your project
3. Go to **Settings** → **API**
4. Copy:
   - **Project URL** → Use as `SUPABASE_URL`
   - **anon/public key** → Use as `SUPABASE_ANON_KEY`

### Paystack Keys
1. Go to your [Paystack Dashboard](https://dashboard.paystack.com)
2. Go to **Settings** → **API Keys & Webhooks**
3. Copy your **Public Key** → Use as `PAYSTACK_PUBLIC_KEY`

## Important Notes

- ⚠️ **NEVER commit the `.env` file to Git!** It's already in `.gitignore`
- The `.env` file is only for **local development**
- For **Vercel deployment**, set these as **Environment Variables** in your Vercel project settings
- The app will show a warning if Supabase is not configured, but will still load with local assets

## Example `.env` File

```env
SUPABASE_URL=https://abcdefghijklmnop.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFiY2RlZmdoaWprbG1ub3AiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTYxNjIzOTAyMiwiZXhwIjoxOTMxODE1MDIyfQ.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
PAYSTACK_PUBLIC_KEY=pk_test_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## Troubleshooting

If you see "Supabase not configured" error:
1. Check that your `.env` file is in the root directory
2. Make sure there are **no spaces** around the `=` sign
3. Make sure there are **no quotes** around the values
4. Restart your Flutter app after creating/updating `.env`

