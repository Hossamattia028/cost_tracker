# Cost Tracker — Flutter App (Phase 1)

A clean Flutter app for tracking costs per account with Arabic OCR support to auto-extract **إجمالي** (total) values from receipt images.

---

## Features

| Feature | Details |
|---|---|
| **Accounts CRUD** | Create, view, edit, delete accounts with name, description, currency |
| **Cost Records** | Add records manually or via image OCR |
| **Arabic OCR** | Upload/capture a receipt image → auto-extracts the value next to **إجمالي** |
| **Editable amount** | Extracted value fills a text field — you can edit before saving |
| **Per-account totals** | Running total displayed per account |
| **Offline-first** | SQLite via sqflite — no internet needed |

---

## Project Structure

```
lib/
├── main.dart                     # Entry point, theme, providers
├── models/
│   ├── account.dart              # Account model + DB mapping
│   └── cost_record.dart          # CostRecord model + DB mapping
├── services/
│   ├── database_service.dart     # SQLite CRUD operations
│   ├── ocr_service.dart          # ML Kit OCR + إجمالي extraction
│   └── app_provider.dart         # ChangeNotifier state management
├── screens/
│   ├── home_screen.dart          # Main screen + big FAB
│   ├── accounts_screen.dart      # Account list
│   ├── account_detail_screen.dart # Records list per account
│   └── add_record_screen.dart    # New record form with image OCR
└── widgets/
    └── account_form_dialog.dart  # Create/edit account dialog
```

---

## Setup & Build

### Prerequisites

- Flutter SDK ≥ 3.0 — https://docs.flutter.dev/get-started/install
- Android Studio / VS Code with Flutter plugin
- Android NDK 27 (install via Android Studio SDK Manager → SDK Tools → NDK)
- Java 17+ (bundled with Android Studio)

### 1 — Install Flutter & clone project

```bash
git clone <your-repo>
cd cost_tracker
flutter pub get
```

### 2 — Connect an Android device or start an emulator

```bash
flutter devices           # list connected devices
flutter emulators         # list available emulators
flutter emulators --launch <id>
```

### 3 — Run in debug mode

```bash
flutter run
```

### 4 — Build release APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### 5 — Build release App Bundle (for Play Store)

```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

### Signing the release build

Create `android/key.properties`:

```properties
storePassword=<your-password>
keyPassword=<your-key-password>
keyAlias=<your-alias>
storeFile=<path-to-your.keystore>
```

Then update `android/app/build.gradle` to reference these properties (standard Flutter signing setup).

---

## OCR Logic

The OCR service (`lib/services/ocr_service.dart`) uses **Google ML Kit Text Recognition** (on-device, no internet):

1. Loads the image from disk
2. Runs Latin + Arabic text recognition
3. Searches each recognized line for the keyword `إجمالي` (and common variants)
4. Extracts the first numeric value on that line
5. Normalizes Arabic-Indic numerals (٠١٢٣…) to Western digits
6. Falls back to scanning ±60 characters around the keyword in the full text

If extraction succeeds, the amount field is pre-filled. The user can always edit the value before saving.

---

## Dependencies

| Package | Purpose |
|---|---|
| `provider` | State management |
| `sqflite` + `path` | Local SQLite database |
| `image_picker` | Camera / gallery image selection |
| `google_mlkit_text_recognition` | On-device Arabic OCR |
| `flutter_animate` | UI animations |
| `intl` | Date formatting |

---

## Permissions (Android)

- `CAMERA` — capture receipts directly
- `READ_MEDIA_IMAGES` (Android 13+) / `READ_EXTERNAL_STORAGE` (≤ Android 12) — gallery access

---

## Phase 2 Ideas (future)

- Filter records by date range
- Export to PDF / Excel
- Multiple currencies with conversion
- Push notifications for budget thresholds
- Charts / spending analytics
