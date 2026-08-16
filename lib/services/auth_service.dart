import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Thrown by [AuthService] with a message that is safe to show directly to
/// the student (already translated into a friendly Marathi/English string).
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

const String _genericAuthError =
    'काहीतरी चुकले. कृपया पुन्हा प्रयत्न करा.\n'
    '(Something went wrong. Please try again.)';

/// Thin wrapper around [FirebaseAuth] used by the Login/Signup/Profile
/// screens. Kept as a single seam so the app's auth backend could be
/// swapped later without touching the UI.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// Emits the current [User] (or `null` when signed out) — drives
  /// [AuthGate]'s logged-in/logged-out routing.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<User> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthException(
          'खाते तयार करता आले नाही. कृपया पुन्हा प्रयत्न करा.\n'
          '(Could not create the account. Please try again.)',
        );
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(_genericAuthError);
    }
  }

  Future<User> signIn({
    required String email,
    required String password,
  }) async {
    // TEMPORARY DEBUG INSTRUMENTATION — remove once auth/invalid-credential
    // is root-caused. Prints to the browser console / `flutter run` terminal
    // (DWDS mirrors dart:core print() to both for `flutter run -d chrome`).
    // ignore: avoid_print
    print(
      '[AUTH DEBUG] projectId=${Firebase.app().options.projectId} '
      'apiKey=${Firebase.app().options.apiKey} '
      'authDomain=${Firebase.app().options.authDomain} '
      'emailTrimmed="${email.trim()}" emailLength=${email.trim().length} '
      'passwordLength=${password.length}',
    );
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthException(
          'लॉगिन करता आले नाही. कृपया पुन्हा प्रयत्न करा.\n'
          '(Could not log in. Please try again.)',
        );
      }
      // ignore: avoid_print
      print('[AUTH DEBUG] signIn SUCCESS uid=${user.uid}');
      return user;
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print('[AUTH DEBUG] FirebaseAuthException code="${e.code}" message="${e.message}"');
      throw AuthException(_messageFor(e));
    } on AuthException {
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print('[AUTH DEBUG] Unexpected error: $e');
      throw const AuthException(_genericAuthError);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    } catch (_) {
      throw const AuthException(_genericAuthError);
    }
  }

  Future<void> signOut() => _auth.signOut();

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'हा ईमेल आधीच नोंदणीकृत आहे. कृपया लॉगिन करा.\n'
            '(This email is already registered. Please log in.)';
      case 'invalid-email':
        return 'कृपया वैध ईमेल पत्ता टाका.\n'
            '(Please enter a valid email address.)';
      case 'weak-password':
        return 'पासवर्ड खूप कमजोर आहे. किमान 6 अक्षरे वापरा.\n'
            '(Password is too weak. Use at least 6 characters.)';
      case 'user-not-found':
        return 'या ईमेलसाठी कोणतेही खाते सापडले नाही.\n'
            '(No account found for this email.)';
      case 'wrong-password':
      case 'invalid-credential':
        return 'चुकीचा ईमेल किंवा पासवर्ड.\n'
            '(Incorrect email or password.)';
      case 'user-disabled':
        return 'हे खाते निष्क्रिय करण्यात आले आहे.\n'
            '(This account has been disabled.)';
      case 'too-many-requests':
        return 'खूप प्रयत्न झाले. कृपया थोड्या वेळाने पुन्हा प्रयत्न करा.\n'
            '(Too many attempts. Please try again later.)';
      case 'network-request-failed':
        return 'इंटरनेट कनेक्शन तपासा आणि पुन्हा प्रयत्न करा.\n'
            '(Please check your internet connection and retry.)';
      case 'invalid-api-key':
      case 'api-key-not-valid':
      case 'configuration-not-found':
        return 'Firebase सेटअप अपूर्ण आहे. कृपया प्रशासकाशी संपर्क करा.\n'
            '(Firebase is not fully configured yet for this app.)';
      default:
        return e.message ?? e.code;
    }
  }
}

/// Shared instance used by the auth screens. Swap this single line if the
/// auth backend implementation ever changes.
final AuthService authService = AuthService();
