import '../services/firestore_helper.dart';

class CostRecord {
  final String id;
  final String accountId;
  final double amount;
  final String? note;
  final String imageUrl;
  final int? receiptImageId;
  final DateTime createdAt;
  final String createdBy;

  const CostRecord({
    required this.id,
    required this.accountId,
    required this.amount,
    this.note,
    required this.imageUrl,
    this.receiptImageId,
    required this.createdAt,
    required this.createdBy,
  });

  Map<String, dynamic> toMap() => {
        'accountId': accountId,
        'amount': amount,
        'note': note,
        'imageUrl': imageUrl,
        if (receiptImageId != null) 'receiptImageId': receiptImageId,
        'createdAt': createdAt.toIso8601String(),
        'createdBy': createdBy,
      };

  factory CostRecord.fromMap(String id, Map<String, dynamic> map) =>
      CostRecord(
        id: id,
        accountId: map['accountId'] as String,
        amount: (map['amount'] as num).toDouble(),
        note: map['note'] as String?,
        imageUrl: (map['imageUrl'] as String?) ?? '',
        receiptImageId: (map['receiptImageId'] as num?)?.toInt(),
        createdAt: parseFirestoreDate(map['createdAt']),
        createdBy: map['createdBy'] as String,
      );

  CostRecord copyWith({
    String? id,
    double? amount,
    String? note,
    String? imageUrl,
    int? receiptImageId,
  }) =>
      CostRecord(
        id: id ?? this.id,
        accountId: accountId,
        amount: amount ?? this.amount,
        note: note ?? this.note,
        imageUrl: imageUrl ?? this.imageUrl,
        receiptImageId: receiptImageId ?? this.receiptImageId,
        createdAt: createdAt,
        createdBy: createdBy,
      );
}
