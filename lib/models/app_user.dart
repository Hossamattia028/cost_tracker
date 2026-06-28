import '../core/constants.dart';
import '../services/firestore_helper.dart';

class AppUser {
  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final List<String> allowedAccountIds;
  final DateTime createdAt;

  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.allowedAccountIds = const [],
    required this.createdAt,
  });

  bool get isAdmin => role == UserRole.admin;

  bool canAccessAccount(String accountId) {
    if (isAdmin) return true;
    return allowedAccountIds.contains(accountId);
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'email': email,
        'role': role.firestoreValue,
        'allowedAccountIds': allowedAccountIds,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        uid: map['uid'] as String,
        name: map['name'] as String,
        email: map['email'] as String,
        role: UserRoleX.fromString(map['role'] as String?),
        allowedAccountIds: (map['allowedAccountIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        createdAt: parseFirestoreDate(map['createdAt']),
      );

  AppUser copyWith({
    String? name,
    UserRole? role,
    List<String>? allowedAccountIds,
  }) =>
      AppUser(
        uid: uid,
        name: name ?? this.name,
        email: email,
        role: role ?? this.role,
        allowedAccountIds: allowedAccountIds ?? this.allowedAccountIds,
        createdAt: createdAt,
      );
}
