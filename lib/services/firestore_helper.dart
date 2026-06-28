import 'package:cloud_firestore/cloud_firestore.dart';

DateTime parseFirestoreDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.parse(value);
  return DateTime.now();
}

Future<T> withFirestoreRetry<T>(
  Future<T> Function() action, {
  int maxAttempts = 5,
}) async {
  var delay = const Duration(milliseconds: 800);
  FirebaseException? lastException;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await FirebaseFirestore.instance.enableNetwork();
      return await action().timeout(const Duration(seconds: 15));
    } on FirebaseException catch (e) {
      lastException = e;
      final retryable = e.code == 'unavailable' ||
          e.code == 'deadline-exceeded' ||
          e.code == 'internal';
      if (retryable && attempt < maxAttempts) {
        await Future.delayed(delay);
        delay *= 2;
        continue;
      }
      rethrow;
    }
  }

  throw lastException ??
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'Firestore unavailable',
      );
}

String firestoreErrorMessage(FirebaseException e) {
  switch (e.code) {
    case 'unavailable':
      return 'خدمة قاعدة البيانات غير متاحة. تأكد من تفعيل Firestore في Firebase Console والاتصال بالإنترنت.';
    case 'permission-denied':
      return 'ليس لديك صلاحية للوصول. راجع قواعد أمان Firestore.';
    case 'deadline-exceeded':
      return 'انتهت مهلة الاتصال. حاول مرة أخرى.';
    case 'user-not-found':
      return 'المستخدم غير مسجل في النظام. تواصل مع المدير.';
    default:
      return e.message ?? e.code;
  }
}

Map<String, dynamic> userDocData(Map<String, dynamic>? data, String docId) {
  return {
    ...?data,
    'uid': data?['uid'] ?? docId,
  };
}
