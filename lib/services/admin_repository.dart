import 'package:cloud_firestore/cloud_firestore.dart';

/// Checks Admin Panel access against the `admin/{uid}` allow-list in
/// Firestore.
///
/// Documents in `admin` are intentionally NOT writable by any client (see
/// `firestore.rules`) — an admin must be added manually from the Firebase
/// Console by the project owner. This keeps privilege escalation impossible
/// from within the app itself.
class AdminRepository {
  AdminRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'admin';

  Future<bool> isAdmin(String uid) async {
    final doc = await _firestore.collection(collection).doc(uid).get();
    return doc.exists;
  }
}

/// Shared instance used by the Admin Panel's login gate.
final AdminRepository adminRepository = AdminRepository();
