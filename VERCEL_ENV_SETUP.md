# Vercel Environment Variables Setup Guide

## ⚠️ IMPORTANT: Never commit API keys to GitHub!

All sensitive keys must be set as **Environment Variables** in Vercel Dashboard.

---

## 📋 Required Environment Variables

### 1. Supabase Configuration

| Variable Name | Description | Where to Find |
|--------------|-------------|---------------|
| `SUPABASE_URL` | Your Supabase project URL | Supabase Dashboard → Settings → API → Project URL |
| `SUPABASE_ANON_KEY` | Your Supabase anonymous/public key | Supabase Dashboard → Settings → API → Project API keys → `anon` `public` |

**Note:** The `anon` key is safe to use in client-side code. It's designed to be public and is protected by Row Level Security (RLS) policies.

---

### 2. Paystack Configuration (When you integrate)

| Variable Name | Description | Where to Find |
|--------------|-------------|---------------|
| `PAYSTACK_PUBLIC_KEY` | Your Paystack public key | Paystack Dashboard → Settings → API Keys & Webhooks → Public Key |
| `PAYSTACK_SECRET_KEY` | Your Paystack secret key (for server-side only) | Paystack Dashboard → Settings → API Keys & Webhooks → Secret Key |

**⚠️ Important:** 
- `PAYSTACK_PUBLIC_KEY` can be used in client-side code
- `PAYSTACK_SECRET_KEY` should **NEVER** be exposed in client-side code. Use it only in server-side functions (Supabase Edge Functions or a backend API)

---

## 🚀 How to Set Environment Variables in Vercel

### Step 1: Go to Vercel Dashboard
1. Log in to [Vercel Dashboard](https://vercel.com/dashboard)
2. Select your project

### Step 2: Navigate to Environment Variables
1. Click **Settings** (gear icon)
2. Click **Environment Variables** in the left sidebar

### Step 3: Add Variables
1. Click **Add New**
2. Enter the **Key** (e.g., `SUPABASE_URL`)
3. Enter the **Value** (your actual key/URL)
4. Select **Environments**:
   - ✅ **Production** (for live site)
   - ✅ **Preview** (for preview deployments)
   - ✅ **Development** (optional, for local dev)

### Step 4: Save and Redeploy
1. Click **Save**
2. Go to **Deployments** tab
3. Click **...** on the latest deployment
4. Click **Redeploy** to apply the new environment variables

---

## 📝 Example Setup

### Supabase Variables:
```
SUPABASE_URL = https://your-project-id.supabase.co
SUPABASE_ANON_KEY = eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### Paystack Variables (when ready):
```
PAYSTACK_PUBLIC_KEY = pk_test_xxxxxxxxxxxxx (for test mode)
PAYSTACK_PUBLIC_KEY = pk_live_xxxxxxxxxxxxx (for production)
```

---

## 🔒 Security Best Practices

1. ✅ **DO:** Set environment variables in Vercel Dashboard
2. ✅ **DO:** Use different keys for test and production
3. ✅ **DO:** Rotate keys if they're accidentally exposed
4. ❌ **DON'T:** Commit keys to GitHub
5. ❌ **DON'T:** Hardcode keys in your code
6. ❌ **DON'T:** Share keys in screenshots or documentation

---

## 🧪 Testing Locally

For local development, you can create a `.env` file (make sure it's in `.gitignore`):

```bash
# .env (DO NOT COMMIT THIS FILE)
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
PAYSTACK_PUBLIC_KEY=your-paystack-public-key
```

Then run:
```bash
flutter run -d chrome --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
```

Or use a package like `flutter_dotenv` to load from `.env` file.

---

## ✅ Verification

After setting environment variables and redeploying:

1. Check Vercel build logs to ensure variables are loaded
2. Test your app to ensure Supabase connection works
3. Check browser console for any authentication errors

---

## 🆘 Troubleshooting

**Problem:** "Missing required environment variables" error
- **Solution:** Ensure variables are set in Vercel Dashboard and you've redeployed

**Problem:** Supabase connection fails
- **Solution:** Verify the URL and key are correct (no extra spaces, correct format)

**Problem:** Variables work locally but not on Vercel
- **Solution:** Make sure you selected the correct environment (Production/Preview) when adding variables

---

## 📚 Additional Resources

- [Vercel Environment Variables Docs](https://vercel.com/docs/concepts/projects/environment-variables)
- [Supabase API Keys Guide](https://supabase.com/docs/guides/api/api-keys)
- [Paystack API Documentation](https://paystack.com/docs/api/)

