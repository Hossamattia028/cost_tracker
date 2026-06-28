import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../core/constants.dart';
import '../models/app_user.dart';
import 'firestore_helper.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentFirebaseUser => _auth.currentUser;

  Future<AppUser?> getCurrentAppUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await withFirestoreRetry(
      () => _db.collection('users').doc(user.uid).get(),
    );
    if (!doc.exists) return null;
    return AppUser.fromMap(userDocData(doc.data(), doc.id));
  }

  Future<void> ensureAdminExists() async {
    try {
      final admins = await withFirestoreRetry(
        () => _db
            .collection('users')
            .where('role', isEqualTo: UserRole.admin.firestoreValue)
            .limit(1)
            .get(),
      );
      if (admins.docs.isNotEmpty) return;

      await _createAdminAuthAndProfile();
    } catch (_) {
      return;
    }
  }

  Future<void> _createAdminAuthAndProfile() async {
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'admin-bootstrap-${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      UserCredential credential;
      try {
        credential = await secondaryAuth.createUserWithEmailAndPassword(
          email: AppConstants.adminEmail,
          password: AppConstants.adminPassword,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code != 'email-already-in-use') rethrow;
        credential = await secondaryAuth.signInWithEmailAndPassword(
          email: AppConstants.adminEmail,
          password: AppConstants.adminPassword,
        );
      }

      final uid = credential.user!.uid;
      await _ensureUserProfile(
        uid: uid,
        name: 'المدير',
        email: AppConstants.adminEmail,
        role: UserRole.admin,
      );
      await secondaryAuth.signOut();
    } finally {
      if (secondaryApp != null) {
        await secondaryApp.delete();
      }
    }
  }

  Future<void> _ensureUserProfile({
    required String uid,
    required String name,
    required String email,
    required UserRole role,
    List<String> allowedAccountIds = const [],
  }) async {
    final ref = _db.collection('users').doc(uid);
    final existing = await withFirestoreRetry(() => ref.get());
    if (existing.exists) return;

    await withFirestoreRetry(
      () => ref.set(
        AppUser(
          uid: uid,
          name: name,
          email: email,
          role: role,
          allowedAccountIds: allowedAccountIds,
          createdAt: DateTime.now(),
        ).toMap(),
      ),
    );
  }

  Future<AppUser> signIn(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = credential.user!.uid;
    final normalizedEmail = email.trim().toLowerCase();

    try {
      final doc = await withFirestoreRetry(
        () => _db.collection('users').doc(uid).get(),
      );

      if (!doc.exists) {
        if (normalizedEmail == AppConstants.adminEmail.toLowerCase()) {
          final admin = AppUser(
            uid: uid,
            name: 'المدير',
            email: AppConstants.adminEmail,
            role: UserRole.admin,
            createdAt: DateTime.now(),
          );
          await withFirestoreRetry(
            () => _db.collection('users').doc(uid).set(admin.toMap()),
          );
          return admin;
        }
        await _auth.signOut();
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'المستخدم غير مسجل في النظام',
        );
      }

      return AppUser.fromMap(userDocData(doc.data(), doc.id));
    } on FirebaseException {
      await _auth.signOut();
      rethrow;
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> createUser({
    required String name,
    required String email,
    required String password,
    required List<String> allowedAccountIds,
  }) async {
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'user-create-${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = credential.user!.uid;
      await _ensureUserProfile(
        uid: uid,
        name: name.trim(),
        email: email.trim(),
        role: UserRole.user,
        allowedAccountIds: allowedAccountIds,
      );
      await secondaryAuth.signOut();
    } finally {
      if (secondaryApp != null) {
        await secondaryApp.delete();
      }
    }
  }

  Future<void> deleteUser(String uid) async {
    await withFirestoreRetry(() => _db.collection('users').doc(uid).delete());
  }
}
