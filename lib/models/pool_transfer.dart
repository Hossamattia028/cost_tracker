import '../services/firestore_helper.dart';

/// A withdrawal from the global pool to fund a transfer on an account.
class PoolTransfer {
  final String id;
  final double amount;
  final String accountId;
  final String accountName;
  final DateTime createdAt;
  final String createdBy;
  final String? recordId;

  const PoolTransfer({
    required this.id,
    required this.amount,
    required this.accountId,
    required this.accountName,
    required this.createdAt,
    required this.createdBy,
    this.recordId,
  });

  Map<String, dynamic> toMap() => {
        'amount': amount,
        'accountId': accountId,
        'accountName': accountName,
        'createdAt': createdAt.toIso8601String(),
        'createdBy': createdBy,
        if (recordId != null) 'recordId': recordId,
      };

  factory PoolTransfer.fromMap(String id, Map<String, dynamic> map) =>
      PoolTransfer(
        id: id,
        amount: (map['amount'] as num).toDouble(),
        accountId: map['accountId'] as String,
        accountName: map['accountName'] as String? ?? '',
        createdAt: parseFirestoreDate(map['createdAt']),
        createdBy: map['createdBy'] as String,
        recordId: map['recordId'] as String?,
      );
}
