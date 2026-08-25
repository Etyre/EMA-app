# EMA Sampler

A Flutter app (iOS + Android from one codebase) for signal-contingent experience
sampling / ecological momentary assessment. At random intervals inside your
active hours it fires a notification (sound + vibration); tapping it opens a
short survey whose answers are saved on-device and pushed to a Google Sheet.

## Features

- Random intervals between a **min** and **max** (minutes), only inside a daily
  **active window** (e.g. 08:00–22:00; overnight windows like 22:00–06:00 work too).
- Notification **visibility timeout** (e.g. 15 min). Unanswered prompts are logged
  as `expired` (so you can compute response rates).
- Question editor: single choice, multiple choice (both with optional "Other…"
  text field), free text, and numeric scale/slider. Reorder by drag.
- Partial submissions allowed; blank answers are stored as empty cells.
- Every response records: scheduled/notification time, time the survey was opened,
  time submitted, and time zone.
- Local SQLite storage + retry queue: nothing is lost if you're offline; rows are
  upserted into the sheet by a unique id so retries never duplicate.
- Selectable notification sound (system default or one of six bundled chimes,
  with a preview button). Sounds are synthesized WAVs in `assets/sounds/`; the
  same files live in `android/app/src/main/res/raw/`. On iOS they are copied to
  the app's `Library/Sounds` folder at startup (no Xcode project changes needed).
  Each file starts with ~1.5 s of silence: Bluetooth headphones take up to a
  second to wake their audio link, and a short clip would otherwise finish
  before it becomes audible.
  To add a sound: drop `name.wav` (<30 s, with the same lead-in) in both folders
  and add it to `NotificationSounds` in `lib/models/models.dart`.
- "Send test prompt now" button on the home screen.
- History screen with CSV export (copies to clipboard).

## Google Sheet setup (one time)

1. Create a Google Sheet. **Extensions → Apps Script**, replace the contents with
   `apps_script/Code.gs`, save.
2. **Deploy → New deployment → Web app**. Execute as *Me*; Who has access *Anyone*.
   Authorize when prompted.
3. Copy the URL ending in `/exec` into `.env` (`cp .env.example .env`, then set
   `SHEET_URL=...`). `.env` is git-ignored. It's baked in at build time with
   `--dart-define-from-file=.env` (see below); you can also paste/override it in
   **Settings → Apps Script web app URL** inside the app.
4. New question texts get their own columns automatically. If you ever edit the
   script, redeploy as a *new version* (the URL stays the same).

## Building & installing

Requirements: Flutter (installed), Xcode for iOS, Android Studio + SDK for Android
(not yet installed on this Mac — `flutter doctor` will tell you).

```bash
flutter pub get
flutter run --dart-define-from-file=.env            # on a connected iPhone / Android device
flutter build ios --dart-define-from-file=.env      # then archive via Xcode, or:
flutter build apk --release --dart-define-from-file=.env   # Android APK / appbundle
```

For iOS on a real phone, open `ios/Runner.xcworkspace` once in Xcode, select your
team under *Signing & Capabilities*, then `flutter run -d <device>`.
Personal (free) Apple developer builds expire after 7 days; a paid account
(TestFlight) lasts 90 days per build.

### Note: this folder is iCloud-synced

`~/Documents` is synced by iCloud Drive, which adds Finder/FileProvider
attributes that make iOS codesigning fail ("resource fork, Finder information,
or similar detritus not allowed"). To avoid that, `build/` is a symlink to
`~/Library/Caches/ema-app-build`. If you clone this elsewhere, either keep the
project outside iCloud or recreate the symlink:

```bash
rm -rf build && mkdir -p ~/Library/Caches/ema-app-build && ln -s ~/Library/Caches/ema-app-build build
```

## Testing

`integration_test/app_test.dart` drives the real app on a simulator: enables
sampling, checks prompts are scheduled with the OS inside the window, answers a
test prompt (incl. "Other" text and a slider), submits, and verifies expiry logic.

```bash
flutter test integration_test/app_test.dart -d <simulator-id> --dart-define-from-file=.env   # xcrun simctl list devices
```

## Updating without losing data

- Data lives in the app's private storage (SQLite `ema.db` + SharedPreferences),
  which iOS and Android keep across updates as long as the **bundle id stays the
  same** (`com.elityre.ema_app`). Never uninstall to update — just install the new
  build over the old one (`flutter run`, Xcode, TestFlight, or a new APK).
- Bump `version:` in `pubspec.yaml` for each release (e.g. `1.0.1+2`; the number
  after `+` must increase for Android).
- Schema changes go in `PromptDb._onUpgrade` (SQLite) and
  `SettingsStore.migrateIfNeeded` (settings/questions JSON). Add migrations, never
  drop tables.
- Belt and braces: the History screen's *Copy CSV* button exports everything, and
  the Google Sheet is an off-device copy.

## Platform notes / known limits

- **Auto-dismiss:** Android removes the notification natively after the visibility
  timeout. iOS has no such API for local notifications, so on iOS the stale
  notification is cleared the next time the app comes to the foreground. Either
  way an unanswered prompt is logged as `expired` after the timeout.
- **Scheduling:** notifications are pre-scheduled up to 3 days / 40 prompts ahead
  (iOS caps pending local notifications at 64) and topped up whenever the app is
  opened or a survey is submitted. If you don't open the app for >3 days, prompts
  stop until you do.
- Android 12+ asks for the *exact alarm* permission on first launch so prompts
  fire at precise times; Android 13+ asks for notification permission.
- On iOS, sound + vibration follow the ringer/silent switch and Focus modes.
  Prompts use the *Time Sensitive* interruption level so they can break through Focus if you allow it.

## Code map

```
lib/main.dart                     app entry, notification tap routing, lifecycle housekeeping
lib/app_state.dart                service locator
lib/models/models.dart            Question, AppSettings, PromptRecord
lib/storage/settings_store.dart   settings + questions (versioned JSON)
lib/storage/db.dart               SQLite prompts table with migration hook
lib/services/notification_service.dart   flutter_local_notifications wrapper
lib/services/scheduler.dart       random-interval generation, top-up, expiry
lib/services/uploader.dart        Apps Script POST with retry queue
lib/screens/                      home, survey, settings, questions editor, history
apps_script/Code.gs               Google Sheet receiver
```
