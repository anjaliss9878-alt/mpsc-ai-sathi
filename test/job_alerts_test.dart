import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/job_alert.dart';
import 'package:mpsc_combine_ai/services/job_alerts_repository.dart';

void main() {
  final now = DateTime(2026, 8, 26);

  test('lifecycle is New / Active / Closing Soon / Closed from real dates', () {
    JobAlert alert({
      required bool published,
      String lastDate = '',
      DateTime? createdAt,
    }) {
      return JobAlert(
        id: 'x',
        examName: 'MPSC Combine Group B',
        organization: 'MPSC',
        post: 'PSI',
        eligibility: 'Graduate',
        description: 'Official notice',
        applicationUrl: 'https://mpsc.gov.in',
        published: published,
        lastDate: lastDate,
        createdAt: createdAt,
      );
    }

    expect(alert(published: false).lifecycle(now), JobAlertLifecycle.draft);
    expect(
      alert(published: true, lastDate: '2026-08-01').lifecycle(now),
      JobAlertLifecycle.closed,
    );
    expect(
      alert(published: true, lastDate: '2026-08-30').lifecycle(now),
      JobAlertLifecycle.closingSoon,
    );
    expect(
      alert(
        published: true,
        lastDate: '2026-12-01',
        createdAt: DateTime(2026, 8, 24),
      ).lifecycle(now),
      JobAlertLifecycle.newlyPosted,
    );
    expect(
      alert(
        published: true,
        lastDate: '2026-12-01',
        createdAt: DateTime(2026, 6, 1),
      ).lifecycle(now),
      JobAlertLifecycle.active,
    );
  });

  test('students only receive published alerts; unpublished stay admin-only',
      () async {
    final db = FakeFirebaseFirestore();
    final repo = JobAlertsRepository(firestore: db);
    await repo.add(
      const JobAlert(
        id: '',
        examName: 'Published PSI',
        organization: 'MPSC',
        post: 'PSI',
        eligibility: 'Graduate',
        description: 'Live',
        applicationUrl: 'https://mpsc.gov.in/psi',
        published: true,
        lastDate: '2026-09-30',
      ),
    );
    await repo.add(
      const JobAlert(
        id: '',
        examName: 'Draft STI',
        organization: 'MPSC',
        post: 'STI',
        eligibility: 'Graduate',
        description: 'Hidden',
        applicationUrl: '',
        published: false,
      ),
    );

    final published = await repo.getPublished();
    expect(published.map((e) => e.examName), ['Published PSI']);
    expect(published.every((e) => e.published), isTrue);

    final all = await repo.watchAll().first;
    expect(all.map((e) => e.examName), containsAll(['Published PSI', 'Draft STI']));
  });

  test('admin update and delete change the shared collection', () async {
    final db = FakeFirebaseFirestore();
    final repo = JobAlertsRepository(firestore: db);
    final id = await repo.add(
      const JobAlert(
        id: '',
        examName: 'Group C',
        organization: 'MPSC',
        post: 'Clerk',
        eligibility: '12th',
        description: 'Open',
        applicationUrl: 'https://mpsc.gov.in/c',
        published: true,
        lastDate: '2026-10-01',
      ),
    );
    await repo.update(
      JobAlert(
        id: id,
        examName: 'Group C',
        organization: 'MPSC',
        post: 'Clerk',
        eligibility: '12th',
        description: 'Closing',
        applicationUrl: 'https://mpsc.gov.in/c',
        published: true,
        lastDate: '2026-08-20',
      ),
    );
    final listed = await repo.getPublished();
    expect(listed.single.lastDate, '2026-08-20');
    expect(listed.single.lifecycle(now), JobAlertLifecycle.closed);

    await repo.delete(id);
    expect(await repo.getPublished(), isEmpty);
  });
}
