/**
 * Firestore emulator companion for P1-3.
 * Run: firebase emulators:exec --only firestore "node --test tool/firestore_rules_test.mjs"
 * Skips when @firebase/rules-unit-testing is missing or the emulator is down.
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import test from 'node:test';
import assert from 'node:assert/strict';

const toolDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(toolDir, '..');
const require = createRequire(resolve(toolDir, 'package.json'));

let rulesUnit;
try {
  rulesUnit = require('@firebase/rules-unit-testing');
} catch {
  rulesUnit = null;
}

const rules = readFileSync(resolve(root, 'firestore.rules'), 'utf8');

function skipWithoutEmulator() {
  if (!rulesUnit) {
    test('emulator rules tests skipped: @firebase/rules-unit-testing not installed', () => {
      assert.ok(true);
    });
    return true;
  }
  return false;
}

if (skipWithoutEmulator()) {
  // Static assertions still run below via the Dart suite; this file is the
  // emulator companion.
} else {
  const { assertFails, assertSucceeds, initializeTestEnvironment } = rulesUnit;

  async function withEnv(run) {
    const testEnv = await initializeTestEnvironment({
      projectId: 'mpsc-rag-rules',
      firestore: { rules },
    });
    try {
      await testEnv.clearFirestore();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await db.doc('admin/admin1').set({ role: 'admin' });
        await db.doc('ragSources/live').set({
          title: 'Article 14',
          published: true,
          status: 'Ready',
          contentStatus: 'published',
        });
        await db.doc('ragChunks/live_0').set({
          sourceId: 'live',
          published: true,
          text: 'equality before law',
        });
        await db.doc('ragSources/draft').set({
          title: 'Draft',
          published: false,
          status: 'Uploading',
          contentStatus: 'draft',
        });
        await db.doc('ragChunks/draft_0').set({
          sourceId: 'draft',
          published: false,
          text: 'hidden draft',
        });
        await db.doc('ragSources/review').set({
          title: 'Review',
          published: false,
          status: 'Ready',
          contentStatus: 'underReview',
        });
        await db.doc('ragChunks/review_0').set({
          sourceId: 'review',
          published: false,
          text: 'under review',
        });
        await db.doc('ragSources/processing').set({
          title: 'Processing',
          published: true,
          status: 'Processing',
        });
        await db.doc('ragChunks/processing_0').set({
          sourceId: 'processing',
          published: false,
          text: 'still processing',
        });
        await db.doc('ragSources/failed').set({
          title: 'Failed',
          published: true,
          status: 'Failed',
        });
        await db.doc('ragChunks/failed_0').set({
          sourceId: 'failed',
          published: false,
          text: 'failed index',
        });
        await db.doc('ragSources/unpublished').set({
          title: 'Unpublished',
          published: false,
          status: 'Ready',
          contentStatus: 'unpublished',
        });
        await db.doc('ragChunks/unpublished_0').set({
          sourceId: 'unpublished',
          published: false,
          text: 'unpublished',
        });
        await db.doc('students/alice/testAttempts/a1').set({ score: 40 });
        await db.doc('students/bob/testAttempts/b1').set({ score: 90 });
      });
      await run(testEnv);
    } finally {
      await testEnv.cleanup();
    }
  }

  function studentDb(testEnv) {
    return testEnv.authenticatedContext('alice').firestore();
  }

  function adminDb(testEnv) {
    return testEnv.authenticatedContext('admin1').firestore();
  }

  test('Draft → inaccessible to student, readable by admin', async () => {
    await withEnv(async (env) => {
      const student = studentDb(env);
      const admin = adminDb(env);
      await assertFails(student.doc('ragSources/draft').get());
      await assertFails(student.doc('ragChunks/draft_0').get());
      await assertSucceeds(admin.doc('ragSources/draft').get());
      await assertSucceeds(admin.doc('ragChunks/draft_0').get());
    });
  });

  test('Under Review → inaccessible to student', async () => {
    await withEnv(async (env) => {
      const student = studentDb(env);
      await assertFails(student.doc('ragSources/review').get());
      await assertFails(student.doc('ragChunks/review_0').get());
    });
  });

  test('Processing → inaccessible to student', async () => {
    await withEnv(async (env) => {
      const student = studentDb(env);
      await assertFails(student.doc('ragSources/processing').get());
      await assertFails(student.doc('ragChunks/processing_0').get());
    });
  });

  test('Failed → inaccessible to student', async () => {
    await withEnv(async (env) => {
      const student = studentDb(env);
      await assertFails(student.doc('ragSources/failed').get());
      await assertFails(student.doc('ragChunks/failed_0').get());
    });
  });

  test('Unpublished → inaccessible to student', async () => {
    await withEnv(async (env) => {
      const student = studentDb(env);
      await assertFails(student.doc('ragSources/unpublished').get());
      await assertFails(student.doc('ragChunks/unpublished_0').get());
    });
  });

  test('Published + Ready → accessible to student; student cannot write', async () => {
    await withEnv(async (env) => {
      const student = studentDb(env);
      await assertSucceeds(student.doc('ragSources/live').get());
      await assertSucceeds(student.doc('ragChunks/live_0').get());
      await assertFails(student.doc('ragSources/live').update({ title: 'hack' }));
      await assertFails(student.doc('ragChunks/live_0').delete());
      await assertFails(
        student.collection('ragSources').add({ published: true, status: 'Ready' }),
      );
    });
  });

  test('student published+Ready query does not return other statuses', async () => {
    await withEnv(async (env) => {
      const student = studentDb(env);
      const snap = await assertSucceeds(
        student
          .collection('ragSources')
          .where('published', '==', true)
          .where('status', '==', 'Ready')
          .get(),
      );
      assert.equal(snap.docs.length, 1);
      assert.equal(snap.docs[0].id, 'live');
    });
  });

  test('student published chunk query only returns live Ready chunks', async () => {
    await withEnv(async (env) => {
      const student = studentDb(env);
      const snap = await assertSucceeds(
        student.collection('ragChunks').where('published', '==', true).get(),
      );
      assert.equal(snap.docs.length, 1);
      assert.equal(snap.docs[0].id, 'live_0');
    });
  });
    await withEnv(async (env) => {
      const admin = adminDb(env);
      const all = await assertSucceeds(admin.collection('ragSources').get());
      assert.equal(all.docs.length, 6);
      await assertSucceeds(
        admin.doc('ragSources/draft').update({ title: 'admin edit' }),
      );
    });
  });

  test('student cannot read another student testAttempts', async () => {
    await withEnv(async (env) => {
      const alice = studentDb(env);
      await assertSucceeds(alice.doc('students/alice/testAttempts/a1').get());
      await assertFails(alice.doc('students/bob/testAttempts/b1').get());
      const admin = adminDb(env);
      await assertSucceeds(admin.doc('students/bob/testAttempts/b1').get());
    });
  });
}
