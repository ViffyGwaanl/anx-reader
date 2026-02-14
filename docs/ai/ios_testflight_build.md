# iOS TestFlight Build Notes (Flutter)

This note documents the recommended “stable path” to produce TestFlight builds for this fork.

> TL;DR: use **Xcode Archive → Upload**. Keep build numbers in `pubspec.yaml` and make sure Flutter regenerates `ios/Flutter/Generated.xcconfig`.

---

## 1) One-time setup

### 1.1 Open the correct workspace

Open:

- `ios/Runner.xcworkspace`

Not:

- `ios/Runner.xcodeproj`

Because CocoaPods integration (and many script phases) rely on the workspace.

### 1.2 Signing (Runner + extension)

In Xcode:

- Select target **Runner** → Signing & Capabilities → select your Team
- Select target **shareExtension** (if present) → do the same

Ensure:

- Bundle IDs are unique and match Apple Developer / App Store Connect
- App Groups (if enabled) are consistent across targets

---

## 2) Every release build (repeat)

### 2.1 Bump version/build number

Edit the repo root `pubspec.yaml`:

```yaml
version: 1.12.0+6317
```

- `1.12.0` = marketing version (CFBundleShortVersionString)
- `6317` = build number (CFBundleVersion)

**App Store Connect requires build number to increase on every upload.**

### 2.2 Refresh Flutter iOS generated settings

Flutter writes build metadata into:

- `ios/Flutter/Generated.xcconfig`

Important:

- This file is **generated** and **gitignored**.
- Xcode reads `$(FLUTTER_BUILD_NUMBER)` from this file.

If you only run `flutter pub get`, this file may not refresh.

Recommended command:

```bash
flutter clean
flutter pub get
flutter build ios --release --no-codesign
```

Verify:

```bash
grep '^version:' pubspec.yaml
grep 'FLUTTER_BUILD_NUMBER' ios/Flutter/Generated.xcconfig
```

If Xcode Archive still shows an old build number, this is the first thing to check.

### 2.3 Archive + Upload

In Xcode:

1. Select scheme: **Runner**
2. Select destination: **Any iOS Device (arm64)**
3. Product → **Archive**
4. Organizer → Distribute App → App Store Connect → **Upload**

---

## 3) Known gotchas

### 3.1 “I changed pubspec build number but Archive still shows old value”

Cause:

- `ios/Flutter/Generated.xcconfig` still has the old `FLUTTER_BUILD_NUMBER`.

Fix:

- Run `flutter build ios --release --no-codesign` (or any iOS build that regenerates the config) before archiving.

### 3.2 Xcode build setting `CURRENT_PROJECT_VERSION`

To avoid confusion, this fork aligns Runner’s `CURRENT_PROJECT_VERSION` with Flutter:

- `CURRENT_PROJECT_VERSION = $(FLUTTER_BUILD_NUMBER)`

This makes the Xcode UI consistent with Flutter-driven versioning.

### 3.3 Export compliance (cryptography)

This fork uses `package:cryptography` for encrypted backup (AES-GCM / PBKDF2).

App Store Connect may ask export compliance questions.

- Answer according to your app’s real usage and your distribution region.
- If you get stuck on the questionnaire, capture screenshots and we can decide the correct options.

---

## 附：中文速记

- `pubspec.yaml` 的 `version: x.y.z+BUILD` 里，`BUILD` 就是 TestFlight 的 Build Number。
- Xcode 显示的 build number 实际来自 `ios/Flutter/Generated.xcconfig` 的 `FLUTTER_BUILD_NUMBER`。
- **改了 pubspec 但 Xcode 还显示旧值**：先跑一遍 `flutter build ios --release --no-codesign` 再 Archive。
