# UPI Expense Tracker: Roadmap, Use Cases & Tech Stack Analysis

> Goal: When the user pays via PhonePe / Google Pay / Paytm / any UPI app, the expense is recorded in our app automatically (or with one tap), categorized, and shown in budgets and reports.

---

## Decisions Log

| # | Decision | Reason |
|---|----------|--------|
| D-1 | **The app will NOT open itself automatically** after a payment | Android 10+ blocks background activity launches; workarounds (overlay, accessibility, full-screen intent) are restricted or risky on Google Play |
| D-2 | Payments made directly in PhonePe/GPay are **detected in the background, auto-saved, and confirmed via a notification** with quick-category buttons | Works on every Android version, no special permission beyond Notification Access |
| D-3 | **The user can categorize every payment** (auto-captured, scanned or manual), change it any time, and nothing stays hidden as uncategorized | Accurate budgets and reports depend on every payment having the right category |

---

## 1. The Core Problem (Read This First)

PhonePe, Google Pay and Paytm **do not offer a public API** that lets third-party apps read a user's transaction history. So we cannot simply "connect to GPay". Every expense tracker in India (e.g. Walnut/axio, Money View, Jupiter-style apps) uses one or more **indirect capture methods**.

Choosing the capture method is the single most important architecture decision, because it decides the platform (Android vs iOS), the permissions we need, and the Play Store review risk.

### 1.1 Capture Methods Compared

| # | Method | How it works | Android | iOS | Automation | Accuracy | Risk / Effort |
|---|--------|--------------|---------|-----|-----------|----------|---------------|
| A | **Scan & Pay inside our app** | User scans merchant QR in *our* app → we parse the `upi://pay?...` data → we launch PhonePe/GPay via UPI intent → app returns status → we save the expense | ✅ | ⚠️ Limited | One tap per payment | High (we know payee + amount) | Low. But some UPI apps restrict intent payments to certain merchants; status callback is not always reliable |
| B | **Bank SMS parsing** | Read debit SMS ("Rs.250 debited from A/c XX1234 to VPA abc@ybl, UPI Ref 4321...") | ✅ | ❌ | Fully automatic | High for amount/ref, medium for merchant | **Google Play restricts SMS permissions**; needs a declaration and approval. Must handle 100+ bank SMS formats |
| C | **Notification listener** | Read payment notifications from GPay/PhonePe/bank apps via `NotificationListenerService` | ✅ | ❌ | Fully automatic | Medium (notification text varies, can be hidden) | Moderate Play review scrutiny; users must grant special access |
| D | **Share / screenshot OCR** | User shares the payment success screen or screenshot to our app → OCR extracts amount, payee, ref | ✅ | ✅ | Semi-manual | Medium–High | Low. Works on iOS too |
| E | **Account Aggregator (AA)** | RBI's consent-based framework (via providers like Setu, Finvu, OneMoney, Anumati) pulls bank transactions | ✅ | ✅ | Automatic (periodic) | Very high, but merchant names are raw | Needs registration as FIU or via a partner; paperwork and cost |
| F | **Email parsing** | Read bank/UPI alert emails via Gmail API | ✅ | ✅ | Automatic | Medium | Gmail restricted-scope verification (security assessment) is costly |
| G | **Statement import** | Upload bank PDF/CSV statement | ✅ | ✅ | Manual, bulk | High | Low. Good fallback and for backfilling history |
| H | **iOS Shortcuts automation** | iOS "Message" personal automation forwards bank SMS text to our app / API | ❌ | ✅ | Semi-automatic | High | User setup is fiddly; not controllable by us |
| I | **Manual entry** | Quick-add form | ✅ | ✅ | Manual | Depends on user | None. Always needed |

### 1.2 Recommendation

- **MVP:** A (Scan & Pay) + I (Manual) + D (Share/screenshot). No sensitive permissions, fast to ship, matches your exact requirement ("if I scan the payment, update the data").
- **Phase 2:** C (Notifications) as the primary auto-capture, with B (SMS) as a backup, so payments made *directly* in GPay/PhonePe are also caught (see Section 3).
- **Phase 3+:** G (Statement import), E (Account Aggregator) for reconciliation and multi-bank accuracy.

**Deduplication key:** the **UPI Reference Number (RRN / UTR, usually 12 digits)**. The same payment can arrive from Scan & Pay, SMS and notification; merge them using the ref number, falling back to amount + timestamp (±2 min) + payee VPA.

---

## 2. How "Scan & Pay" Works (Method A in detail)

1. User opens our app → taps **Scan & Pay**.
2. Camera scans the merchant QR. A UPI QR contains a URI like:
   ```
   upi://pay?pa=merchant@okaxis&pn=Sri%20Krishna%20Stores&am=250.00&cu=INR&tn=Order123&mc=5411
   ```
   - `pa` = payee VPA, `pn` = payee name, `am` = amount (optional), `mc` = merchant category code, `tn` = note
3. App shows a confirm screen: amount (editable if not in QR), **category** (auto-suggested from `mc` / payee history), note.
4. App fires an Android intent with the UPI URI; user picks PhonePe / GPay / Paytm (or we pass a package name to target one).
5. The UPI app returns a result string, e.g. `txnId=...&responseCode=00&Status=SUCCESS&txnRef=...`.
6. App saves the expense with status `SUCCESS` / `FAILURE` / `PENDING`.
7. If status is unclear (user killed the app, no callback), mark as **"Pending – confirm"** and verify later via SMS/notification match or ask the user.

Caveats to plan for:
- Some UPI apps limit intent-initiated payments (especially P2P or unverified merchants) for fraud prevention. Test each app.
- On iOS, launching UPI apps via URL schemes is possible but returning a result is unreliable, so iOS should treat the transaction as "user-confirmed".
- We never touch money or PINs; the UPI app handles authentication. This keeps us out of payment-regulation scope.

---

## 3. Auto-Detecting Payments Made Directly in UPI Apps

When the user scans a QR **inside PhonePe / GPay** (not inside our app), our app detects the payment in the background. Per decision D-1, the app does **not** open itself; instead it saves the payment and notifies the user.

### 3.1 Flow

```
User pays in PhonePe / GPay / Paytm
          │  (1–5 seconds)
          ▼
Notification Listener reads the UPI app's "Paid ₹250 to ..." notification
   (Bank SMS receiver catches it too, as a backup)
          │
          ▼
On-device parser → amount, payee, VPA, UPI ref, time, UPI app
          │
          ▼
Dedup check (UPI ref / amount + time + payee)
          │
          ▼
Auto-save transaction  (status: needs_review, category: suggested or empty)
          │
          ▼
Our notification:
 ┌──────────────────────────────────────────────┐
 │ ₹250 paid to Sri Krishna Stores (PhonePe)     │
 │ Suggested: Groceries                          │
 │ [ Groceries ]  [ Food ]  [ Other… ]           │
 └──────────────────────────────────────────────┘
          │
   ├─ Tap a category button → saved, marked reviewed (app does not open)
   ├─ Tap "Other…" or the notification → app opens on category picker / edit screen
   └─ Ignore / swipe away → stays in "To categorize" list (see Section 4)
```

### 3.2 Technical Notes (Android)

- **NotificationListenerService**: user grants "Notification access" once during onboarding, with a clear explanation screen. Filter only UPI and bank app package names; ignore everything else and never store raw notification text.
- **SMS backup**: `SMS_RECEIVED` broadcast receiver, only if the Play Store SMS permission is approved; otherwise skip this source.
- **Notification with actions**: Android supports up to 3 action buttons. Use the top 2 suggested categories + "Other…". Actions are handled by a `BroadcastReceiver` so the category is saved without opening the app.
- **Opening the app is only on user tap** (PendingIntent from the notification), which Android always allows.
- **OEM battery killers** (Xiaomi, Oppo, Vivo, Realme, Samsung): the listener can be stopped by aggressive battery settings. Onboarding shows a brand-specific guide to allow auto-start / disable battery optimization for the app, and a health check warns if no notification was received for a long time.
- **Missed payments**: later reconciliation through SMS or statement import (Phase 3) catches anything the listener missed.
- **iOS**: not possible (no access to other apps' notifications or SMS). iOS uses Scan & Pay, screenshot share and manual entry.

---

## 4. Categorizing Every Payment

Per decision D-3, **every payment can be categorized by the user**, whatever its source (Scan & Pay, notification, SMS, screenshot, manual, statement import).

### 4.1 Rules

1. Every transaction has a category, or is explicitly in the **"To categorize"** list. It is never silently dropped from reports.
2. Auto-assigned categories are only *suggestions*: they are marked "Auto" until the user confirms or the payee rule is trusted.
3. The user can change the category of **any** transaction at any time, including old ones. Budgets and reports update instantly.
4. Credits (money received) are categorized too: Salary, Refund, Received from friend, Cashback, etc.
5. Self-transfers between the user's own accounts get a **Transfer** category that is excluded from spending totals.

### 4.2 Where the User Can Categorize

| Place | How |
|-------|-----|
| Payment notification | Tap one of the quick buttons, or "Other…" to open the full picker |
| Scan & Pay confirm screen | Pick the category before paying (pre-selected suggestion) |
| "To categorize" list | Home screen card: "5 payments to categorize" → swipe through them one by one |
| Transaction list | Swipe or long-press → change category; multi-select → bulk categorize |
| Transaction detail | Full edit: category, subcategory, split, tags, note |

### 4.3 Features

- **Smart suggestions**: order categories by likelihood using payee history, merchant category code (MCC) from the QR, user rules, amount and time of day.
- **"Remember for this payee"**: when the user picks a category, offer to apply it automatically to future payments to the same payee/VPA, and optionally to past uncategorized ones.
- **Split one payment across categories**: e.g. ₹1,200 at a supermarket → ₹900 Groceries + ₹300 Household. Split amounts must add up to the total.
- **Custom categories and subcategories**: add, rename, change icon/color, reorder, hide. Deleting or merging a category asks where to move its transactions.
- **Tags** (optional, in addition to category): e.g. `#ooty-trip`, `#office` to group payments across categories.
- **Reminder**: optional daily notification at a user-chosen time: "You have 3 uncategorized payments today."
- **Undo**: a short undo option after quick-categorizing from a notification or bulk action.

---

## 5. Use Case Analysis

### 5.1 Actors
- **User** (primary): individual tracking personal spending.
- **Family / group member** (later): shared budgets.
- **System**: background capture services, categorization engine, notifications.

### 5.2 Core Use Cases (MVP)

| ID | Use case | Description |
|----|----------|-------------|
| UC-01 | Sign up / Login | Phone OTP or Google sign-in; optional app lock (PIN / biometric) |
| UC-02 | Scan & Pay | Scan UPI QR → pay via chosen UPI app → auto-record expense |
| UC-03 | Manual add expense | Amount, category, payee, date, payment mode (UPI/cash/card), note |
| UC-04 | Add from screenshot/share | Share payment receipt to app → OCR → pre-filled expense |
| UC-05 | Edit / delete transaction | Fix category, amount, payee, notes |
| UC-06 | Auto-categorization | Suggest category from payee name, VPA, merchant code, past choices |
| UC-07 | Dashboard | Today / this week / this month spend, top categories, recent list |
| UC-08 | Transaction list & search | Filter by date, category, payee, amount, source app |
| UC-09 | Categories management | Default set (Food, Groceries, Travel, Bills, Rent, Shopping, Health, Entertainment, Transfers) + custom |
| UC-10 | Offline mode | Record even without internet; sync later |
| UC-31 | Categorize every payment | User can set or change the category of any transaction from any source, any time (Section 4) |
| UC-32 | "To categorize" list | All uncategorized / auto-suggested payments in one place, with bulk categorize |
| UC-33 | Split across categories | Divide one payment into multiple categories |
| UC-34 | Remember for this payee | Save the user's choice as a rule for future payments |

### 5.3 Automation Use Cases (Phase 2)

| ID | Use case | Description |
|----|----------|-------------|
| UC-11 | Auto-capture from SMS | Parse bank debit/credit SMS in background |
| UC-12 | Auto-capture from notifications | Parse GPay/PhonePe/bank notifications in the background (primary auto-capture, Section 3) |
| UC-35 | Quick-categorize notification | After auto-capture, show a notification with category buttons; saving works without opening the app |
| UC-36 | Uncategorized reminder | Optional daily reminder for payments still to be categorized |
| UC-13 | Review inbox | Newly captured items appear as "Needs review" until confirmed (merged with the "To categorize" list) |
| UC-14 | Duplicate merge | Merge same transaction from multiple sources |
| UC-15 | Income tracking | Credits (salary, refunds, received money) tracked separately |
| UC-16 | Self-transfer detection | Money moved between own accounts is not counted as expense |
| UC-17 | Merchant learning | "Always categorize `swiggy@...` as Food" rules |

### 5.4 Planning & Insights (Phase 3)

| ID | Use case | Description |
|----|----------|-------------|
| UC-18 | Budgets | Monthly budget overall and per category; alerts at 50/80/100% |
| UC-19 | Reports | Monthly/yearly charts, category trends, top merchants, day-of-week patterns |
| UC-20 | Recurring detection | Detect subscriptions, rent, EMI, recharges; remind before due date |
| UC-21 | Export | CSV / PDF / Excel export |
| UC-22 | Statement import | Upload bank PDF/CSV to backfill and reconcile |
| UC-23 | Multiple accounts | Tag transactions by bank account / card / wallet |

### 5.5 Advanced (Phase 4+)

| ID | Use case | Description |
|----|----------|-------------|
| UC-24 | Split expenses | Split with friends, track who owes whom, send UPI collect/reminder link |
| UC-25 | Shared/family budgets | Multiple users contributing to one budget |
| UC-26 | AI insights | "You spent 30% more on food delivery this month", natural-language queries ("how much on petrol in August?") |
| UC-27 | Account Aggregator sync | Consent-based automatic bank data |
| UC-28 | Receipt/bill attachment | Attach photos of bills to transactions |
| UC-29 | Multi-device & web dashboard | Same data on phone + web |
| UC-30 | Tax / reimbursement tagging | Mark business expenses, export for claims |

### 5.6 Non-Functional Requirements

- **Privacy:** financial data is sensitive. Process SMS/notifications **on-device**; send only parsed transaction fields to the server, never raw SMS.
- **Security:** encrypt local DB (SQLCipher), TLS everywhere, biometric app lock, no storage of UPI PINs or card numbers.
- **Compliance:** India's **Digital Personal Data Protection (DPDP) Act, 2023** and its Rules: clear consent, purpose limitation, data deletion on request. Clear privacy policy for Play Store data-safety form.
- **Performance:** capture-to-record under 2 seconds; background services must be battery-friendly.
- **Reliability:** offline-first; no lost transactions.
- **Localization:** English + Tamil/Hindi later; INR formatting (₹1,00,000).

---

## 6. Tech Stack Options

### 6.1 Mobile App

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **Kotlin + Jetpack Compose (native Android)** | Full access to SMS, NotificationListener, intents, background work; best performance | Android only | ✅ Best if Android-first (most UPI users in India are on Android) |
| **Flutter** | One codebase for Android + iOS, good UI, strong community | SMS/notification features need platform channels (Kotlin code anyway) | ✅ Best if you want both platforms early |
| **React Native (Expo + dev client)** | JS/TS skills reuse, shares code with web dashboard | Native modules needed for SMS/notifications; Expo Go won't support them | 👍 Good if team is JS-heavy |

**Key native libraries (Android):**
- QR scanning: Google **ML Kit Barcode Scanning** or ZXing; CameraX
- OCR for screenshots: **ML Kit Text Recognition** (on-device, free)
- Background work: WorkManager
- Local DB: **Room** (native) / **Drift** or Isar (Flutter) / WatermelonDB or op-sqlite (RN), with SQLCipher encryption
- Charts: Vico / MPAndroidChart (native), fl_chart (Flutter), Victory Native (RN)
- Biometrics: AndroidX Biometric

### 6.2 Backend

| Option | Pros | Cons |
|--------|------|------|
| **Supabase** (Postgres + Auth + Row Level Security + Edge Functions) | Fast MVP, real SQL for reports, built-in auth | Less control at scale |
| **Firebase** (Firestore + Auth + Cloud Functions + FCM) | Very fast MVP, great offline sync | NoSQL makes aggregate reports harder; vendor lock-in |
| **Custom: Node.js (NestJS) or Python (FastAPI) + PostgreSQL** | Full control, best for AA integration & ML later | More work to build auth, sync, infra |

**Recommendation:** Start with **Supabase** (or local-only for a pure MVP), move heavy logic to a **FastAPI** service later when adding ML categorization and Account Aggregator.

Supporting services:
- Push notifications: Firebase Cloud Messaging
- Cache/queues (later): Redis, BullMQ/Celery
- Hosting: Supabase cloud / Railway / Render / AWS (Mumbai region `ap-south-1` for data residency)
- Monitoring: Sentry (crashes), PostHog or Firebase Analytics (product analytics)

### 6.3 Categorization Engine (evolves over phases)

1. **Rules:** keyword + VPA map (`swiggy`, `zomato` → Food; `irctc` → Travel; `bescom`, `tneb` → Bills).
2. **Merchant Category Code (MCC)** from QR `mc` param → category mapping.
3. **User learning:** remember user corrections per payee.
4. **ML:** on-device small text classifier (TensorFlow Lite) or server-side model trained on anonymized, consented data.
5. **LLM (optional):** for unknown merchants and natural-language queries; send only merchant name + amount, never full personal data.

### 6.4 SMS Parsing Engine

- Regex templates per bank (HDFC, SBI, ICICI, Axis, Kotak, Indian Bank, IOB, etc.)
- Extract: `amount`, `type` (debit/credit), `account last 4`, `VPA/payee`, `UPI ref`, `date`, `balance`
- Filter by sender IDs (e.g. `AX-HDFCBK`, `VM-SBIUPI`) to ignore OTPs, promos
- Maintain templates as remotely-updatable config so new formats don't need an app release
- Unit-test with a corpus of real (anonymized) SMS samples

Example:
```
SMS: "Rs.250.00 debited from A/c XX1234 on 27-09-26 to VPA sristores@okaxis. UPI Ref 426512345678. Not you? Call 1800..."
→ { amount: 250.00, type: DEBIT, account: "1234", payee_vpa: "sristores@okaxis",
    upi_ref: "426512345678", date: "2026-09-27", source: "SMS" }
```

### 6.5 Web Dashboard (optional, Phase 4)
- Next.js + Tailwind + shadcn/ui + Recharts, same Supabase/Postgres backend.

### 6.6 Suggested Stacks at a Glance

| Scenario | Stack |
|----------|-------|
| Solo dev, Android-first, fastest to real automation | Kotlin + Compose + Room + ML Kit + Supabase |
| Want Android + iOS from day one | Flutter + Drift + ML Kit plugins + Kotlin platform channels for SMS/notifications + Supabase |
| JS/TS team, plan a web app too | React Native (Expo dev client) + native modules + Supabase/NestJS + Next.js web |

---

## 7. Data Model (initial)

```
users           (id, name, phone, email, created_at, settings_json)
accounts        (id, user_id, name, type[bank|wallet|card|cash], last4, bank_name)
categories      (id, user_id|null, name, icon, color, parent_id, is_default)
payees          (id, user_id, display_name, vpa, mcc, default_category_id)
transactions    (id, user_id, account_id, payee_id,
                 category_id|null,            -- null = in "To categorize" list
                 category_source[auto|rule|user],
                 is_reviewed,                 -- false until user confirms
                 amount, currency, type[debit|credit|transfer],
                 status[success|pending|failed|needs_review],
                 upi_ref, upi_app[phonepe|gpay|paytm|bhim|other],
                 source[scan_pay|sms|notification|ocr|manual|statement|aa],
                 note, txn_time, created_at, updated_at, deleted_at)
transaction_sources (id, transaction_id, source, raw_hash, captured_at)   -- for dedup audit, no raw text
budgets         (id, user_id, category_id|null, period[monthly|weekly], amount, start_date)
rules           (id, user_id, match_field, match_value, category_id)
recurring       (id, user_id, payee_id, amount, frequency, next_due)
transaction_splits (id, transaction_id, category_id, amount, note)   -- sum(amount) = transaction.amount
tags            (id, user_id, name)
transaction_tags (transaction_id, tag_id)
attachments     (id, transaction_id, file_url)
```

Unique index on `(user_id, upi_ref)` where `upi_ref` is not null → prevents duplicates.

---

## 8. Architecture Overview

```
┌──────────────────────── Mobile App ────────────────────────┐
│  Capture layer                                              │
│   ├─ Scan & Pay (CameraX + ML Kit + UPI Intent)             │
│   ├─ SMS Receiver ──┐                                       │
│   ├─ Notification Listener ──┤→ Parser Engine (on-device)   │
│   ├─ Share/Screenshot OCR ──┘        │                      │
│   └─ Manual entry                     ▼                     │
│                          Dedup + Categorizer                │
│                                  ▼                          │
│                    Local encrypted DB (offline-first)       │
│                                  ▼                          │
│   Quick-categorize notification (action buttons)            │
│   UI: Dashboard · To categorize · List · Budgets · Reports  │
└──────────────────────────────┬──────────────────────────────┘
                               │ sync (parsed fields only)
                               ▼
┌──────────────────────── Backend ───────────────────────────┐
│ Auth · Postgres · Sync API · Rules/ML service · FCM push    │
│ (later) Account Aggregator integration · Export service     │
└─────────────────────────────────────────────────────────────┘
```

---

## 9. Roadmap

### Phase 0 — Discovery & Setup (1 week)
- Finalize platform choice (Android-first vs cross-platform)
- Wireframes for 6 core screens: Home, Scan & Pay, Add/Edit, Transactions, Budgets, Settings
- Collect 200+ anonymized bank SMS and notification samples
- Test UPI intent behavior on PhonePe, GPay, Paytm, BHIM with real merchants
- Repo, CI (GitHub Actions), lint, crash reporting

### Phase 1 — MVP (4–6 weeks)
- Auth + app lock
- Scan & Pay with UPI intent and result handling (UC-02)
- Manual entry, edit, delete (UC-03, UC-05)
- Default categories + rule-based categorization (UC-06, UC-09)
- Categorize every payment: picker, "To categorize" list, bulk categorize, split, remember-for-payee (UC-31–UC-34)
- Dashboard + transaction list with filters (UC-07, UC-08)
- Offline-first local DB, optional cloud backup
- **Exit criteria:** you can use it daily for a month and every scanned payment is recorded correctly

### Phase 2 — Auto Capture (4–6 weeks, Android)
- SMS parsing engine for top 15 banks (UC-11)
- Notification listener for GPay / PhonePe / Paytm as primary capture (UC-12)
- Quick-categorize notification with action buttons, no auto-open (UC-35)
- Uncategorized reminder (UC-36)
- OEM battery-optimization onboarding guide + listener health check
- "Needs review" inbox + dedup by UPI ref (UC-13, UC-14)
- Income and self-transfer detection (UC-15, UC-16)
- Merchant learning rules (UC-17)
- Screenshot/share OCR (UC-04)
- Play Store permission declaration + privacy policy + data-safety form
- **Exit criteria:** ≥95% of real UPI debits captured automatically without duplicates, and most are categorized from the notification in one tap

### Phase 3 — Budgets & Insights (3–4 weeks)
- Budgets with alerts (UC-18)
- Reports and charts (UC-19)
- Recurring/subscription detection (UC-20)
- CSV/PDF export, statement import (UC-21, UC-22)
- Multiple accounts (UC-23)

### Phase 4 — Social & Sync (4+ weeks)
- Split expenses, shared budgets (UC-24, UC-25)
- Multi-device sync + web dashboard (UC-29)
- iOS app (Scan & Pay, OCR, Shortcuts guide, manual)

### Phase 5 — Intelligence & Integrations (ongoing)
- ML/LLM categorization, natural-language queries (UC-26)
- Account Aggregator integration through a licensed partner (UC-27)
- Tax/reimbursement tagging (UC-30)

---

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Play Store rejects SMS permission | Auto-capture blocked | Ship MVP without it; use Notification Listener as alternative; prepare a strong permission declaration with demo video; keep SMS as an optional feature |
| UPI apps change notification/SMS text | Parsing breaks | Remote-configurable templates, monitoring of parse-failure rate, fallback to "needs review" |
| UPI intent restrictions / no callback | Scan & Pay status unknown | Pending state + later match with SMS/notification + ask user |
| Duplicate records | Wrong totals | UPI ref unique key + fuzzy match fallback |
| Data breach | Loss of trust, legal liability | On-device parsing, encryption at rest, minimal data on server, DPDP-compliant consent & deletion |
| iOS limitations | Weak iOS experience | Position iOS as companion; rely on scan, OCR, statement import, AA |
| Battery drain from background services | Uninstalls | Event-driven receivers only, no polling |
| OEM battery settings kill the notification listener | Missed payments | Brand-specific onboarding guide, health check, SMS backup, statement reconciliation |
| Users ignore notifications, uncategorized payments pile up | Inaccurate reports | "To categorize" card on home, daily reminder, remember-for-payee rules to reduce manual work |

---

## 11. Open Decisions

Already decided: see the Decisions Log at the top (no auto-open, background capture + notification, user categorizes every payment).

1. **Platform:** Android-only first, or Android + iOS together?
2. **Cloud or local-only** for the MVP (local-only is simpler and more private)?
3. **Personal project or public Play Store launch?** (Public launch brings permission reviews and compliance work.)
4. **Team skills:** Kotlin, Dart, or JavaScript/TypeScript?
5. **Monetization (if any):** free, freemium (budgets/reports premium), or one-time purchase?

---

## 12. Suggested Next Steps

1. Answer the open decisions above.
2. Build a throwaway **Scan & Pay prototype** (QR scan → UPI intent → log result) to validate the core flow on your own phone with PhonePe and GPay.
3. Draft the SMS sample corpus from your own bank messages.
4. Then write the detailed technical design + screen specs for Phase 1.
