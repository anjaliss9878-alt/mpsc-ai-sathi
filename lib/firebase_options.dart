// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase configuration for project `mpsc-3f4ef`.
///
/// [android] was extracted from `android/app/google-services.json` and
/// [web] from the Web app's SDK config in the Firebase console — both are
/// real, connected project values (the same values `flutterfire configure`
/// would have written).
///
/// [ios], [macos] and [windows] are still PLACEHOLDERS: no app has been
/// registered for those platforms in the Firebase console yet. Register an
/// app for a platform at https://console.firebase.google.com for project
/// `mpsc-3f4ef`, then copy its config values into the corresponding block
/// below. Until then, `Firebase.initializeApp()` will fail with a clear,
/// caught error on those platforms instead of crashing the app.
///
/// These values are NOT secret keys — they are public client identifiers —
/// but they must match a real, configured Firebase app to work.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux. '
          'Run `flutterfire configure` to add support for this platform.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDRFjUxTQBmmyykJkXD2fGhl9g_jdBF50A',
    appId: '1:206033195402:web:6e013ee97095fb23a13873',
    messagingSenderId: '206033195402',
    projectId: 'mpsc-3f4ef',
    authDomain: 'mpsc-3f4ef.firebaseapp.com',
    storageBucket: 'mpsc-3f4ef.firebasestorage.app',
    measurementId: 'G-BC59Z18JFQ',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCBP2C9cxhIJeRwFq5QRD73fe4F6gh2tuo',
    appId: '1:206033195402:android:9c759cea0916c07aa13873',
    messagingSenderId: '206033195402',
    projectId: 'mpsc-3f4ef',
    storageBucket: 'mpsc-3f4ef.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REPLACE_WITH_FIREBASE_IOS_API_KEY',
    appId: 'REPLACE_WITH_FIREBASE_IOS_APP_ID',
    messagingSenderId: 'REPLACE_WITH_MESSAGING_SENDER_ID',
    projectId: 'REPLACE_WITH_FIREBASE_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_PROJECT_ID.appspot.com',
    iosBundleId: 'com.example.mpscCombineAi',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'REPLACE_WITH_FIREBASE_MACOS_API_KEY',
    appId: 'REPLACE_WITH_FIREBASE_MACOS_APP_ID',
    messagingSenderId: 'REPLACE_WITH_MESSAGING_SENDER_ID',
    projectId: 'REPLACE_WITH_FIREBASE_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_PROJECT_ID.appspot.com',
    iosBundleId: 'com.example.mpscCombineAi',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'REPLACE_WITH_FIREBASE_WINDOWS_API_KEY',
    appId: 'REPLACE_WITH_FIREBASE_WINDOWS_APP_ID',
    messagingSenderId: 'REPLACE_WITH_MESSAGING_SENDER_ID',
    projectId: 'REPLACE_WITH_FIREBASE_PROJECT_ID',
    authDomain: 'REPLACE_WITH_PROJECT_ID.firebaseapp.com',
    storageBucket: 'REPLACE_WITH_PROJECT_ID.appspot.com',
  );
}
