# Experience Lab GPS Tracker (Flutter)

A cross-platform (Android + iOS) rebuild of the BUas Experience Lab GPS
tracking client. It collects GPS and accelerometer data during research
sessions and uploads it to the existing FastAPI server every 60 seconds.
The server, database, and Streamlit dashboard are unchanged — this app speaks
the exact same API the old Android (OwnTracks fork) app did.

Bluetooth beacon scanning has been intentionally left out of this version.

---

## 1. What this app does

- Lists projects from the server and lets you pick one.
- Downloads that project's configuration and geofence.
- Validates and locks a participant ID (P001, P002, ...).
- Records GPS at the configured frequency and accelerometer (if enabled).
- Tags every data point with the geofence zone it was recorded in.
- Runs ENTER/EXIT geofence actions (start/stop logging, toggle accelerometer).
- Uploads batches every 60 seconds; retries on failure without losing data.
- Auto-stops after the project's maximum duration.
- Keeps running in the background (Android foreground service; iOS location mode).

---

## 2. Prerequisites

- Flutter SDK 3.4 or newer. Verify with `flutter doctor` — every line that
  matters (Android toolchain, Xcode if building iOS) should be a checkmark.
- For Android: Android Studio + an Android device or emulator (API 26+).
- For iOS: a Mac with Xcode, and an Apple Developer account for device builds
  (background location requires a real device; the simulator can fake GPS but
  not background behaviour).

---

## 3. First-time setup

These files in this folder are the ones I wrote. They drop into a standard
Flutter project. The cleanest way to assemble the project:

1. Create a fresh Flutter project (this generates the Android/iOS scaffolding,
   Gradle files, AppDelegate, etc.):

   ```bash
   flutter create --org nl.buas.experiencelab --project-name experience_lab_tracker experience_lab_tracker
   cd experience_lab_tracker
   ```

2. Copy the files from this folder over the generated project, replacing where
   they overlap:
   - `pubspec.yaml`            -> project root (overwrite)
   - `lib/`                    -> project root (overwrite the generated lib/)
   - `android/app/src/main/AndroidManifest.xml` -> overwrite
   - `ios/Runner/Info.plist`   -> overwrite

3. Install dependencies:

   ```bash
   flutter pub get
   ```

   If any package version fails to resolve, run `flutter pub upgrade` to pull
   the latest compatible versions. The pinned versions here are known-good as
   of early 2026 but pub will happily move them forward.

4. Set the server URL. Open `lib/config/constants.dart` and confirm:

   ```dart
   static const String serverBaseUrl = 'https://gpstracker.buas.nl';
   ```

   Point it at a local machine while testing if you want (e.g.
   `http://192.168.1.50:8001`). Note: plain http works on Android with the
   manifest as-is, and on iOS because `NSAllowsArbitraryLoads` is set.

---

## 4. Android-specific setup

Most of it is already in the provided `AndroidManifest.xml`. Two things to verify
in the generated Gradle files:

- `android/app/build.gradle`:
  - `minSdkVersion` must be **26 or higher** (Android 8). The foreground service
    type APIs and modern background rules assume this.
  - `compileSdkVersion` / `targetSdkVersion` should be **34** so the typed
    foreground services (Android 14) behave.

- The manifest uses `tools:replace` on the background service's
  `foregroundServiceType`. The `xmlns:tools` namespace is already declared at
  the top of the provided manifest, so the merge will succeed.

Run it:

```bash
flutter run            # on a connected Android device
# or build a release APK:
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

### Battery optimization (important for long sessions)

Samsung, Xiaomi, Huawei and others aggressively kill background services.
On the research phones, manually exclude the app from battery optimization:
Settings -> Apps -> Experience Lab Tracker -> Battery -> Unrestricted.
Without this, Android may kill the foreground service after the screen has been
off for a while on those manufacturers.

---

## 5. iOS-specific setup

The provided `Info.plist` already declares the usage strings and background
modes. After copying it in:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select the Runner target -> Signing & Capabilities.
3. Add the **Background Modes** capability and tick:
   - Location updates
   - Background fetch
   - Background processing
   (These mirror the `UIBackgroundModes` array in Info.plist; Xcode wants them
   set in the capability UI too.)
4. Set your development team for signing.
5. Run on a **real device** (background location does not work on the simulator):

   ```bash
   flutter run --release
   ```

### iOS background reality check

- GPS in the background works reliably thanks to the location background mode
  plus the "Always" location permission. The blue status bar indicator will show.
- The accelerometer may pause when the app is fully backgrounded and the screen
  is locked — iOS restricts continuous motion sampling more than Android. For
  studies that need continuous accelerometer in-pocket on iOS, keep the screen
  on or test carefully. GPS-only studies are unaffected.

---

## 6. How the code is organized

```
lib/
  config/constants.dart          Server URL, intervals, all tunables
  models/
    project.dart                 GET /projects item
    project_config.dart          Parsed config_json + geofence rules
    sensor_points.dart           GpsPoint / AccelPoint (exact server JSON keys)
    batch_upload.dart            The /upload payload (matches server Pydantic)
  utils/
    geofence.dart                GeoJSON parser + ray-casting point-in-polygon
    timestamp.dart               UTC "yyyy-MM-dd HH:mm:ss.SSS" formatter
  services/
    api_service.dart             All 6 server calls
    device_service.dart          Persistent phone UUID + device model
    permission_service.dart      Location/background/notification flow
    location_service.dart        geolocator stream (per-platform settings)
    accelerometer_service.dart   sensors_plus stream
    geofence_service.dart        Zone state machine + 60s exit grace
    background_service.dart      THE ISOLATE: owns buffers + 60s upload loop
  providers/
    project_provider.dart        Project list / selection / config (UI state)
    recording_provider.dart      Bridges UI <-> background service
  screens/
    project_selection_screen.dart
    recording_screen.dart        ID input, start/stop, live status panel
  main.dart                      Entry point, providers, service init
```

### The one mental model to keep

`background_service.dart` runs in a **separate isolate**. It cannot see your
widgets or providers. The UI and the isolate talk only through messages:

- UI -> isolate: `FlutterBackgroundService().invoke('startRecording', {...})`
- isolate -> UI: `service.invoke('status', {...})`, which `RecordingProvider`
  listens to and republishes to the screens.

If you add a new piece of data to collect, you change it in three places: the
isolate (buffer + collection), the `BatchUpload` model (JSON field), and the
status message if you want it on screen.

---

## 7. The exact server contract (do not drift from this)

Upload payload (`POST /upload/ingest` and `/upload/register_session`):

```json
{
  "project_id": 1,
  "participant_id": "P001",
  "phone_uuid": "uuid-v4-string",
  "device_model": "moto g 5G",
  "gps_data":   [ {"lat":..,"lon":..,"acc":..,"zone":"Zone_1","time":"..","battery":87} ],
  "accel_data": [ {"x":..,"y":..,"z":..,"zone":"Zone_1","time":".."} ],
  "beacon_data": []
}
```

- `zone` is the geofence zone name, or the literal string `"None"` when outside
  all zones. The server converts `"None"` to SQL NULL.
- `time` is UTC, formatted `yyyy-MM-dd HH:mm:ss.SSS`.
- `beacon_data` is always an empty array in this client.

If you ever rename a field here, the server's Pydantic model will reject the
payload and uploads will silently fail. Keep these names exact.

---

## 8. Testing without walking around

- Android emulator: Extended controls (`...`) -> Location -> set coordinates or
  play a GPX route to simulate movement.
- iOS simulator: Features -> Location -> Freeway Drive (but background won't
  behave like a device).
- Watch the live status panel: GPS buffered count should climb, and every 60s
  it should reset to ~0 with a fresh "Last upload" timestamp.
- Confirm on the server side: the Streamlit dashboard's live map should show the
  participant within a few minutes, and the `devices` table should have a row.

---

## 9. Common problems

- **"Could not load projects"** — wrong `serverBaseUrl`, server down, or the
  device has no network. Check the URL and that the phone can reach the server.
- **Uploads never succeed** — usually a field-name mismatch (see section 7) or
  the server rejecting the payload. Check the FastAPI log on the server.
- **Recording dies after screen-off (Android)** — battery optimization; see
  section 4.
- **No background GPS on iOS** — the "Always" permission wasn't granted, or the
  Background Modes capability isn't set in Xcode (section 5).
- **Participant ID always "taken"** — a previous `register_session` left an
  orphan in the `devices` table. Delete that row in SSMS to free the ID (this is
  the same behaviour as the old app).

---

## 10. What was deliberately left out vs. the old app

- Bluetooth beacons (per your request).
- The in-app map (researchers use the dashboard's live map; this removes the
  Google Maps API key dependency). To add it back, drop in `google_maps_flutter`,
  add an API key per platform, and render the current position from the status
  stream.
- The OwnTracks MQTT/contacts/waypoints machinery (never used in research mode).
