# GharGharMatrimony — mobile app (Flutter)

Same features and logins as the web app, for Android (Google Play) and iOS.

| Who | How they sign in | What they see |
|---|---|---|
| Members | Mobile number + OTP | Matches, Interests, Messages, Profile, Help chat (photos, voice notes, translation) |
| Staff (moderators / admins) | "Staff sign in" link on the login screen → email + password + authenticator code | Dashboard, Profiles, Photos, Reports, Support inbox; admins also get Audit log, App logs, Staff |

Package name: **`com.ghargharmatrimony.app`** — change it in `android/app/build.gradle.kts`
(`applicationId` and `namespace`) **before your first Play Store upload**; it can never change afterwards.

## 1. One-time setup (Windows)

1. Install [Flutter](https://docs.flutter.dev/get-started/install/windows/mobile) (3.50 or newer — the app needs Dart 3.14) and Android Studio.
2. In Android Studio → **More Actions → SDK Manager**, install the latest Android SDK, *Command-line Tools* and *Build-Tools*.
3. Check everything is green:

```bash
flutter doctor --android-licenses
```

```bash
flutter doctor
```

## 2. Run it against your laptop backend

Start the backend so phones can reach it (note `--host 0.0.0.0`):

```bash
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Then, from `matrimony-app\mobile`:

```bash
flutter pub get
```

**Android emulator** (talks to your laptop as `10.0.2.2` — the default):

```bash
flutter run
```

**Real phone over USB** (phone and laptop on the same Wi-Fi; find your laptop IP with `ipconfig`, e.g. 192.168.1.20):

```bash
flutter run --dart-define=API_URL=http://192.168.1.20:8000/api/v1
```

Allow port 8000 in Windows Firewall if the phone can't connect. Dev OTP is `123456`.

Plain `http://` only works in debug builds. Release builds require `https://`.

## 3. Build for the Play Store

### a) Create your upload key (once — keep it safe and backed up!)

```bash
keytool -genkey -v -keystore %USERPROFILE%\ghargharmatrimony-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### b) Create `android\key.properties` (it is git-ignored — never commit it)

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=C:\\Users\\YOU\\ghargharmatrimony-upload.jks
```

### c) Build the app bundle pointing at your live HTTPS API

```bash
flutter build appbundle --release --dart-define=API_URL=https://api.yourdomain.in/api/v1
```

The file to upload is `build\app\outputs\bundle\release\app-release.aab`.

Each new upload needs a higher version: bump `version: 1.0.0+1` in `pubspec.yaml`
(the number after `+` is the Play version code).

## 4. Google Play Console checklist

1. Create a developer account at play.google.com/console (one-time fee).
2. **Create app** → name *GharGharMatrimony*, App, Free.
3. **Store listing**: upload `store/play-icon-512.png` (app icon) and `store/feature-graphic-1024x500.png`;
   add at least 2 phone screenshots (take them from the emulator), short + full description.
4. **App content**:
   - Privacy policy URL (required — host it on your website).
   - Data safety: collects phone number, name, date of birth, photos, religion/community, messages, voice recordings (help chat); encrypted in transit; users can request deletion.
   - Target audience: 18+ only. Content rating questionnaire: dating/matrimony, user-to-user communication.
   - Permissions: microphone (voice notes to the help team), camera/photos (profile photos).
5. **Testing → Internal testing** → create release → upload the `.aab` → add your testers' emails. Test first, then promote to Production.
6. Let Google manage the app signing key (default "Play App Signing") — your `.jks` is the *upload* key.

## 5. Project layout

```
lib/
  main.dart                 router + who-can-go-where rules
  core/                     api client (member + staff sessions), app state, realtime socket, theme, labels, translation
  widgets/                  shared UI (buttons, cards, avatars, OTP field, voice recorder/player, translate button)
  screens/member/           login, register wizard, matches, profile view, interests, messages, my profile, help chat
  screens/admin/            staff login (2-step), dashboard, profiles, photos, reports, support, audit, logs, staff
store/                      Play Store graphics
assets/icon/                launcher icon source (regenerate: dart run flutter_launcher_icons)
```

Checks:

```bash
flutter analyze
```

```bash
flutter test
```
