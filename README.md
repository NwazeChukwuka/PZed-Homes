# P-ZED Homes – Hotel Management App

A production-ready Flutter application for hotel operations and guest experiences. It features role-based dashboards (Owner, Manager, Receptionist, Housekeeper, Kitchen Staff, Bartender, Accountant, HR, Security, Cleaner), guest landing and booking flows, and Supabase-backed auth and data.

## Features
- Role-based navigation (staff) + guest landing pages
- Supabase authentication and profiles
- Dashboards: bookings, attendance, KPIs
- Modules: Housekeeping, Kitchen/Bar, Inventory, Finance, HR, Maintenance, Reporting, POS, Communications
- Responsive layouts for mobile, tablet, and desktop (web)
- Centralized theming, error handling, and app state

## Tech Stack
- Flutter 3.35
- Supabase (`supabase_flutter`)
- Provider (state) + `go_router` (navigation)
- Responsive utilities and custom theme system

## Prerequisites
- Flutter SDK installed (`flutter doctor` should pass)
- Supabase project (URL + anon key)
- Android/iOS tooling if building for mobile

## Setup
1. Configure Supabase in `lib/main.dart`:
   - Replace `url` and `anonKey` with your project values.
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run -d chrome   # web
   flutter run -d windows  # windows
   flutter run -d android  # android
   ```

## Project Structure
- `lib/core/navigation/app_router.dart`: Central router + route guards
- `lib/core/services/auth_service.dart`: Supabase auth + profile-to-role mapping
- `lib/core/state/app_state.dart`: Global app preferences and UX state
- `lib/core/theme/app_theme.dart`: Light/Dark themes and tokens
- `lib/core/theme/responsive.dart`: Responsive widgets (grid, padding, text, builder)
- `lib/core/error/error_handler.dart`: Centralized error UI and mapping
- `lib/presentation/screens/...`: Feature screens (guest, staff modules)
- `lib/presentation/widgets/...`: Reusable UI components

## Environment & Data
- Supabase tables expected (examples):
  - `profiles` (id, full_name, role)
  - `bookings` (guest, room, status, created_at)
  - `attendance_records` (profile_id, clock_in_time, clock_out_time)
  - RPC: `get_dashboard_stats`
- Ensure Row Level Security (RLS) policies allow proper access per role.

## Testing
Run widget tests:
```bash
flutter test
```

## Production Notes
- Configure app icons and splash screens (Android/iOS/Web)
- Verify `go_router` deep-links and web URL strategy
- Set analytics/monitoring as needed
- Ensure secure storage for any sensitive tokens if added later

## Contribution
PRs welcome. Ensure `flutter analyze` passes and add tests for UI logic where practical.
