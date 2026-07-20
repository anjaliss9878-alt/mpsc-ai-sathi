# Admin Panel — Setup Guide

MPSC COMBINE AI now has a full Firestore-backed content layer plus a
separate **Admin Panel** for managing it. This doc covers the one-time
setup needed to use it.

## 1. Architecture at a glance

- **Firebase project**: `mpsc-3f4ef` (already wired into `lib/firebase_options.dart`).
- **Student app** entry point: `lib/main.dart`.
- **Admin Panel** entry point: `lib/admin_main.dart` — a completely separate
  `MaterialApp` (`AdminApp`) that is never bundled into the student mobile
  build. It shares the same Firestore models/repositories as the student
  app, so any change made there is instantly visible in the student app
  via `.snapshots()` streams — no app update required.
- **Content collections** (all top-level in Firestore):
  `subjects`, `chapters`, `notes`, `mcqs`, `pyqs`, `tests`, `currentAffairs`,
  `videos`, `liveClasses`.
- **Admin allow-list**: `admins/{uid}` — a Firebase Auth user can open the
  Admin Panel only if a document with their UID exists in this collection.
  This collection is **not writable by any client** (see `firestore.rules`),
  so it must be managed from the Firebase Console only.

## 2. Deploy the updated Firestore rules

`firestore.rules` was updated to:
- Allow any signed-in user to **read** all content collections.
- Allow **write** only if the signed-in user's UID exists in `admins/{uid}`.
- Keep `admins/{uid}` itself read-only-to-self and never client-writable.

Deploy it via the Firebase Console (Firestore → Rules tab → paste the
contents of `firestore.rules` → Publish), or with the Firebase CLI if you
have it installed:

```bash
firebase deploy --only firestore:rules
```

## 3. Create your first Admin user

1. Firebase Console → **Authentication** → **Add user** → enter an email +
   password for the admin (or reuse an existing student account's email).
2. Firebase Console → **Firestore Database** → open the `admins`
   collection (create it if it doesn't exist) → **Add document**:
   - Document ID: the new user's **UID** (copy it from the Authentication
     tab, next to the user you just created).
   - Fields: add `email` (string) with their email — used only for your
     own reference, not by the security rules.
3. That's it — this user can now sign in to the Admin Panel.

## 4. Run the Admin Panel

```bash
flutter run -d chrome -t lib/admin_main.dart
```

(Or build it for web hosting: `flutter build web -t lib/admin_main.dart`.)

Sign in with the admin email/password from step 3. On first login, use the
**"Import Sample Content"** button on the dashboard to seed one example
document into every content collection — this gives you something to
immediately edit/delete and stops the student app from looking empty.

## 5. Run the student app (unchanged)

```bash
flutter run -t lib/main.dart
```

Any content added/edited/deleted from the Admin Panel appears in the
student app immediately (no rebuild, no restart) because every screen
subscribes to a live Firestore `Stream`.

## 6. Content model summary

| Collection | Managed from Admin Panel via | Notes |
|---|---|---|
| `subjects` / `chapters` / `notes` | Notes → Subjects → Chapters → tap chapter to edit notes | Notes are two bullet lists (Important Points, Revision Summary) |
| `mcqs` | MCQs | Grouped into practice "sets" client-side by the `setTitle` field |
| `tests` | Tests | Each test document embeds its full question list (Mock Test / CBT) |
| `currentAffairs` | Current Affairs | Title, description, category, date |
| `videos` | Videos | Title + external video link (YouTube/Drive/etc.) — no file upload |
| `liveClasses` | Live Classes | Title + external meeting link (Meet/Zoom/YouTube Live) — no file upload |
| `pyqs` | PYQs | Title/subtitle + optional external link to the paper |

## 7. Adding more admins later

Repeat step 3 for each additional admin — there is intentionally no
in-app way to grant admin access, to keep privilege escalation impossible
from within either app.
