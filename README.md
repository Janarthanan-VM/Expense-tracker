# Expense Tracker (Flutter) — Step 1: Foundation

This step gives you a working app with:

- Encrypted on-device database (SQLCipher, key kept in Android Keystore)
- 19 default categories (expense, income, transfer) + create / rename / hide your own
- Add, edit and delete transactions manually
- **Categorize every payment**: category picker, "To categorize" list, "Always use this for <payee>" rule that also fixes earlier payments
- Home: this month's spending and income, spending by category, recent payments
- Transactions list grouped by day with search
- Long-press any transaction to change its category quickly
- **Cash and other payments**: every entry records how you paid (Cash, UPI,
  Card, Bank, Other). Manual entries default to Cash. Filter the list by
  method, and see this month's cash vs UPI spending on the home screen
- **Automatic UPI detection (Android)**: payments are read from bank SMS
  notifications and from Google Pay, PhonePe, Paytm, BHIM, CRED, Amazon Pay
  and MobiKwik notifications. Each payment is saved and a notification offers
  one-tap category buttons. Duplicates (app + SMS for the same payment) are
  merged. Set it up in Settings > Detect UPI payments automatically.

### Android code

`native/android/` holds the Kotlin code (notification listener, parser,
notification buttons) and `tool/patch_android.py` adds the permissions and
components to the generated Android project. The GitHub workflow copies both
in and runs the parser's unit tests (`native/android/test/`).

Coming next: backup & restore, Scan & Pay, automatic detection from UPI notifications.

---

## 1. Create the Flutter project

```bash
flutter create --org com.yourname --platforms android expense_tracker
cd expense_tracker
```

The project name must be `expense_tracker` (the test file imports `package:expense_tracker/...`).

## 2. Add the packages

```bash
flutter pub add flutter_riverpod:^2.6.1 sqflite_sqlcipher path flutter_secure_storage uuid intl
```

Riverpod is pinned to 2.x on purpose; the code uses the 2.x API.
Do **not** also add `sqflite`; it conflicts with `sqflite_sqlcipher`.

## 3. Copy the code

- Delete the generated `lib/main.dart` and `test/widget_test.dart`.
- Copy this `lib/` folder and `test/` folder into the project.

## 4. Android settings

In `android/app/build.gradle.kts` (or `build.gradle`), inside `defaultConfig`:

```kotlin
minSdk = 23
```

In `android/app/src/main/AndroidManifest.xml`, on the `<application>` tag, add:

```xml
android:allowBackup="false"
android:fullBackupContent="false"
```

Why: Android's automatic backup would restore the database file without its
encryption key (Keystore keys are never backed up), so the app could not open it.
The app's own encrypted backup (next step) replaces this.

## 5. Run

```bash
flutter test          # unit tests for money parsing and payee matching
flutter run           # on a phone or emulator
```

---

## Project structure

```
lib/
├── main.dart                         opens the encrypted DB, starts the app
├── app.dart                          MaterialApp + theme
├── core/
│   ├── db/app_database.dart          schema v1, migrations, default category seed
│   ├── db/db_key_store.dart          creates / reads the DB encryption key
│   ├── providers.dart                Riverpod providers + refreshAll()
│   ├── theme/app_theme.dart
│   └── utils/formatters.dart         ₹ formatting (paise), dates
└── features/
    ├── categories/                   model, defaults, repository, picker, screen
    ├── transactions/                 model, repository, add/edit, list, to-categorize
    ├── home/                         bottom navigation shell, home dashboard
    └── settings/                     settings (placeholders for next steps)
```

## Key design choices

- **Money is stored as integer paise** (₹250.50 = 25050) to avoid rounding errors.
- **Every transaction has a category or appears in "To categorize"**. Suggested
  categories are marked "(suggested)" until the user confirms them.
- **Payee rules**: choosing "Always use this for <payee>" saves a rule keyed by
  UPI ID (or name if there is no UPI ID). New payments from that payee are
  categorized automatically, and older uncategorized ones are updated.
- **Duplicates**: a unique UPI reference prevents the same payment being saved
  twice when it arrives from Scan & Pay, a notification and an SMS. Deleted
  payments keep their reference so they are not captured again.
- **Transfers** between your own accounts are excluded from spending and income.
