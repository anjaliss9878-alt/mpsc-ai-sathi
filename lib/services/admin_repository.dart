import 'package:cloud_firestore/cloud_firestore.dart';

/// Checks Admin Panel access against the Firestore allow-list.
///
/// Accepts either `admin/{uid}` (singular — current production) or
/// `admins/{uid}` (plural — older docs/rules) so login and security rules
/// stay in sync regardless of which collection the project owner created.
///
/// These collections are intentionally NOT writable by any client (see
/// `firestore.rules`) — an admin must be added manually from the Firebase
/// Console by the project owner.
class AdminRepository {
  AdminRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'admin';
  static const String legacyCollection = 'admins';

  Future<bool> isAdmin(String uid) async {
    final primary = await _firestore.collection(collection).doc(uid).get();
    if (primary.exists) return true;
    final legacy = await _firestore.collection(legacyCollection).doc(uid).get();
    return legacy.exists;
  }

  /// Reads the optional `role` field off the admin's allow-list document
  /// (checks singular `admin` first, then plural `admins`). Defaults to
  /// `admin` (full access) when the field is missing.
  Future<String> getRole(String uid) async {
    final primary = await _firestore.collection(collection).doc(uid).get();
    if (primary.exists) {
      return primary.data()?['role'] as String? ?? 'admin';
    }
    final legacy = await _firestore.collection(legacyCollection).doc(uid).get();
    return legacy.data()?['role'] as String? ?? 'admin';
  }

  /// A small number of especially sensitive modules (Student block/unblock,
  /// Notifications) are restricted to `admin`/`superadmin` — an `editor`
  /// role can manage day-to-day content but not student accounts or mass
  /// notifications.
  bool roleCanManageStudents(String role) => role != 'editor';
  bool roleCanSendNotifications(String role) => role != 'editor';
}

/// Shared instance used by the Admin Panel's login gate.
final AdminRepository adminRepository = AdminRepository();
