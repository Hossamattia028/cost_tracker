import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/account.dart';
import '../models/app_user.dart';
import '../models/cost_record.dart';
import 'firestore_helper.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<Account>> watchAccounts() {
    return _db
        .collection('accounts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Account.fromMap(d.id, d.data()))
            .toList());
  }

  Stream<List<CostRecord>> watchRecords({String? accountId}) {
    Query<Map<String, dynamic>> query =
        _db.collection('records').orderBy('createdAt', descending: true);
    if (accountId != null) {
      query = query.where('accountId', isEqualTo: accountId);
    }
    return query.snapshots().map(
          (snap) => snap.docs
              .map((d) => CostRecord.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Stream<List<AppUser>> watchUsers() {
    return _db
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => AppUser.fromMap(userDocData(d.data(), d.id)))
              .toList(),
        );
  }

  Future<String> addAccount(Account account) async {
    final ref = await withFirestoreRetry(
      () => _db.collection('accounts').add(account.toMap()),
    );
    return ref.id;
  }

  Future<void> updateAccount(Account account) async {
    await withFirestoreRetry(
      () => _db.collection('accounts').doc(account.id).update(account.toMap()),
    );
  }

  Future<void> deleteAccount(String id) async {
    await withFirestoreRetry(() async {
      final batch = _db.batch();
      final records = await _db
          .collection('records')
          .where('accountId', isEqualTo: id)
          .get();
      for (final doc in records.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_db.collection('accounts').doc(id));
      await batch.commit();
    });
  }

  Future<List<String>> addRecords(List<CostRecord> records) async {
    final ids = <String>[];
    await withFirestoreRetry(() async {
      final batch = _db.batch();
      for (final record in records) {
        final docRef = _db.collection('records').doc();
        ids.add(docRef.id);
        batch.set(docRef, record.toMap());
      }
      await batch.commit();
    });
    return ids;
  }

  Future<void> updateRecord(String id, Map<String, dynamic> fields) async {
    await withFirestoreRetry(
      () => _db.collection('records').doc(id).set(
            fields,
            SetOptions(merge: true),
          ),
    );
  }

  Future<void> linkRecordImage({
    required String recordId,
    required int receiptImageId,
    required String imageUrl,
  }) =>
      updateRecord(recordId, {
        'receiptImageId': receiptImageId,
        'imageUrl': imageUrl,
      });

  Future<void> deleteRecord(String id) async {
    await withFirestoreRetry(() => _db.collection('records').doc(id).delete());
  }

  Future<void> deleteRecords(List<String> ids) async {
    if (ids.isEmpty) return;
    // Firestore batches allow up to 500 writes; chunk to stay safe.
    for (var i = 0; i < ids.length; i += 450) {
      final chunk = ids.sublist(i, (i + 450).clamp(0, ids.length));
      await withFirestoreRetry(() async {
        final batch = _db.batch();
        for (final id in chunk) {
          batch.delete(_db.collection('records').doc(id));
        }
        await batch.commit();
      });
    }
  }

  Future<double> getTotalForAccount(String accountId) async {
    final snap = await withFirestoreRetry(
      () => _db
          .collection('records')
          .where('accountId', isEqualTo: accountId)
          .get(),
    );
    return snap.docs.fold<double>(
      0,
      (total, doc) =>
          total + ((doc.data()['amount'] as num?)?.toDouble() ?? 0),
    );
  }
}
