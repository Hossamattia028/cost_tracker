import '../services/firestore_helper.dart';

class Account {
  final String id;
  final String name;
  final String? description;
  final String currency;
  final double commissionPercent;
  final double openingBalance;
  final double totalBalance;
  final DateTime createdAt;

  const Account({
    required this.id,
    required this.name,
    this.description,
    this.currency = 'EGP',
    this.commissionPercent = 0,
    this.openingBalance = 0,
    this.totalBalance = 0,
    required this.createdAt,
  });

  double commissionFor(double amount) => amount * commissionPercent / 100;

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'currency': currency,
        'commissionPercent': commissionPercent,
        'openingBalance': openingBalance,
        'totalBalance': totalBalance,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Account.fromMap(String id, Map<String, dynamic> map) => Account(
        id: id,
        name: map['name'] as String,
        description: map['description'] as String?,
        currency: map['currency'] as String? ?? 'EGP',
        commissionPercent:
            (map['commissionPercent'] as num?)?.toDouble() ?? 0,
        openingBalance: (map['openingBalance'] as num?)?.toDouble() ?? 0,
        totalBalance: (map['totalBalance'] as num?)?.toDouble() ?? 0,
        createdAt: parseFirestoreDate(map['createdAt']),
      );

  Account copyWith({
    String? name,
    String? description,
    String? currency,
    double? commissionPercent,
    double? openingBalance,
    double? totalBalance,
  }) =>
      Account(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        currency: currency ?? this.currency,
        commissionPercent: commissionPercent ?? this.commissionPercent,
        openingBalance: openingBalance ?? this.openingBalance,
        totalBalance: totalBalance ?? this.totalBalance,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Account && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
