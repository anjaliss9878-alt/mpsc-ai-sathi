import 'package:cloud_firestore/cloud_firestore.dart';

/// Checks Admin Panel access against the `admins/{uid}` allow-list in
/// Firestore.
///
/// Mirrors the server-side check in `firestore.rules` exactly: a user is an
/// admin only if their `admins/{uid}` document exists AND its `role` field
/// equals `"admin"` — so an admin can be demoted just by changing that
/// field, without deleting the document.
///
/// Documents in `admins` are intentionally NOT writable by any client (see
/// `firestore.rules`) — an admin must be added manually from the Firebase
/// Console by the project owner. This keeps privilege escalation impossible
/// from within the app itself.
class AdminRepository {
  AdminRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'admins';

  Future<bool> isAdmin(String uid) async {
    final doc = await _firestore.collection(collection).doc(uid).get();
    if (!doc.exists) return false;
    return doc.data()?['role'] == 'admin';
  }
}

/// Shared instance used by the Admin Panel's login gate.
final AdminRepository adminRepository = AdminRepository();
