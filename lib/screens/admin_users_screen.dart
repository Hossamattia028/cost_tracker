import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_strings.dart';
import '../models/app_user.dart';
import '../services/app_provider.dart';
import '../widgets/user_form_dialog.dart';

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final users = provider.users;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const UserFormDialog(),
                  ),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text(AppStrings.newUser),
                ),
              ),
            ),
            Expanded(
              child: users.isEmpty
                  ? const Center(child: Text(AppStrings.noUsers))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _UserTile(user: users[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  final AppUser user;
  const _UserTile({required this.user});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppProvider>();
    final accountNames = user.allowedAccountIds
        .map((id) => provider.accountsById[id]?.name ?? id)
        .join('، ');

    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(user.name.characters.first)),
        title: Text(user.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.email),
            if (accountNames.isNotEmpty)
              Text(
                '${AppStrings.allowedAccounts}: $accountNames',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text(AppStrings.delete),
                content: Text('حذف المستخدم ${user.name}؟'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(AppStrings.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(AppStrings.delete),
                  ),
                ],
              ),
            );
            if (confirm == true && context.mounted) {
              await provider.deleteUser(user.uid);
            }
          },
        ),
      ),
    );
  }
}
