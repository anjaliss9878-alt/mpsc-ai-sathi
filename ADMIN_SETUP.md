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
  `videos`, `liveClasses`, `faculty`, `liveClassAttendance`.
- **Admin allow-list**: `admin/{uid}` — a Firebase Auth user can open the
  Admin Panel only if a document with their UID exists in this collection.
  This collection is **not writable by any client** (see `firestore.rules`),
  so it must be managed from the Firebase Console only.

  > Both the app (`AdminRepository`) and `firestore.rules` / `storage.rules`
  > accept **either** `admin/{uid}` (singular) **or** `admins/{uid}` (plural).
  > If Notes Save still returns `permission-denied`, the rules file on the
  > Firebase project is stale — redeploy from this repo (step 2).

## 2. Deploy the Firestore rules

`firestore.rules` + `storage.rules`:
- Allows any signed-in user to **read** all content collections.
- Allows **write** only if the signed-in user's UID exists in `admin/{uid}`
  **or** `admins/{uid}`.
- Keeps that allow-list collection itself read-only-to-self and never
  client-writable.
- `faculty`: read for any signed-in user, write admin-only (same pattern as
  every other content collection).
- `liveClassAttendance`: read for any signed-in user (so both the student's
  own "My Attendance" screen and the Admin "Attendance" screen work); a
  student may **create** only their own attendance record (the new
  document's `uid` field must equal their auth UID); update/delete is
  admin-only.

Deploy it via the Firebase Console (Firestore → Rules tab → paste the
contents of `firestore.rules` → Publish), or with the Firebase CLI if you
have it installed:

```bash
firebase deploy --only firestore:rules,storage
```

Until that deploy succeeds, Admin login can work (client checks `admin/{uid}`)
while Notes create/update/delete still fail with Firestore `permission-denied`.

## 3. Create your first Admin user

1. Firebase Console → **Authentication** → **Add user** → enter an email +
   password for the admin (or reuse an existing student account's email).
2. Firebase Console → **Firestore Database** → open the `admin`
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

Sign in with the admin email/password from step 3. On first login, use:

- **"Import MPSC structure"** — seeds all **10 subjects** and **every topic**
  (chapters) idempotently by `slug`. Safe to re-run; does not wipe existing
  PDF/AI summary content on topics that already exist.
- **"Import MPSC structure + samples"** — same curriculum plus starter
  MCQ/Test/CA/Video/PYQ samples for empty collections.

Student empty-state on Notes also offers **MPSC विषय रचना लोड करा**.

## 5. Run the student app (unchanged)

```bash
flutter run -t lib/main.dart
```

Any content added/edited/deleted from the Admin Panel appears in the
student app immediately (no rebuild, no restart) because every screen
subscribes to a live Firestore `Stream`. Students only see documents with
`published == true` (missing field is treated as published for backward
compatibility).

## 6. Content model summary

| Collection | Managed from Admin Panel via | Notes |
|---|---|---|
| `subjects` | Notes → Subjects | `title`/`nameMr`, `nameEn`, `slug`, `order`, `published`, `updatedAt`, optional `imageUrl` |
| `chapters` (topics) | Notes → Subjects → Chapters | `title`/`titleMr`, `slug`, `subjectId`, `published`, `tags`, `thumbnailUrl`, `pdfUrl`, `aiSummary`, `revisionNotes`, `classroomLessonId`, `updatedAt` |
| `notes` | Chapter form + Notes form | PDF attachments (Storage), revision bullets, Markdown, `aiSummary`, `tags`, `published`, linked by `subjectId` + `chapterId` |
| `mcqs` | MCQs | `subjectId` + `chapterId` optional links, `tags`, `published` |
| `pyqs` | PYQs | `subjectId` + `chapterId` optional links, `tags`, `published` |
| `tests` | Tests | Each test document embeds its full question list (Mock Test / CBT) |
| `currentAffairs` | Current Affairs | Title, description, category, date |
| `videos` | Videos | Title + external video link (YouTube/Drive/etc.) — no file upload |
| `liveClasses` | Live Classes (Create/Schedule/Edit/Delete/Recordings) | Title, description, subject, faculty, banner image, schedule (real date/time — powers the student countdown), duration, platform + meeting link, optional recording link, status (`upcoming`/`live`/`completed`). `roomId` is reserved for a future 100ms integration and unused today — see `lib/services/live_class_video_service.dart` |
| `faculty` | Live Classes → Faculty | Name, designation, subject, photo URL, bio — assignable to a live class |
| `liveClassAttendance` | Live Classes → Attendance (read-only view; written by students via the Join screen) | One doc per student-per-class join: `liveClassId`, `uid`, `studentName`, `studentEmail`, `markedAt` |

### Curriculum seed (Firebase paths)

- Seeder: `lib/admin/seed/mpsc_curriculum_seeder.dart`
- Catalog: `lib/data/subject_notes_data.dart` (10 subjects, 144 topics)
- Writes: `subjects/{autoId}` + `chapters/{autoId}` with stable `slug`
- Storage uploads (Admin): `notes/…`, `chapters/thumbnails/…`, `subjects/…`

### How to verify

1. Deploy rules if needed: `firebase deploy --only firestore:rules,storage`
2. Admin → **Import MPSC structure** → snackbar shows `10 विषय` / `144 टॉपिक`
3. Admin → Notes → open **राज्यशास्त्र** → see all polity topics
4. Edit a topic: upload PDF, Generate AI Summary, tags, Publish/Draft, Save
5. Student app → विषयवार नोट्स → same hierarchy; Draft topics hidden
6. Add MCQ/PYQ with `chapterId` pasted from Admin chapter list subtitle

### Live Classes module (student + admin)

- **Student**: Live Classes Home → Upcoming / Live Now / Recorded / My
  Attendance, plus a per-class Join screen with a live countdown (while
  `upcoming`) and one-tap Join (while `live`, opens the meeting link and
  marks attendance) or Watch Recording (once `completed`).
- **Admin**: Live Classes (Create/Schedule/Edit/Delete), Faculty, Attendance
  (pick a class → see who joined), Recordings (quick view of completed
  classes' recording links).
- **No video SDK is integrated yet, by design.** Joining a `live` class
  today just opens `meetingUrl` externally (Zoom/Meet/YouTube Live).
  `lib/services/live_class_video_service.dart` is the single seam where a
  real 100ms-backed provider can be added later — it would resolve
  `LiveClassJoinResult.embeddedRoom` instead of `.externalLink`, and no
  other file (Join screen, cards, admin forms) would need to change.

## 7. Adding more admins later

Repeat step 3 for each additional admin — there is intentionally no
in-app way to grant admin access, to keep privilege escalation impossible
from within either app.
