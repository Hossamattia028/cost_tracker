import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_strings.dart';
import '../models/account.dart';
import '../services/app_provider.dart';
import '../widgets/account_form_dialog.dart';
import 'account_detail_screen.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        if (provider.loading && provider.accounts.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.accounts.isEmpty) {
          return _EmptyAccounts(
            onAdd: () => showDialog(
              context: context,
              builder: (_) => const AccountFormDialog(),
            ),
            isAdmin: provider.isAdmin,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: provider.accounts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _AccountCard(
            account: provider.accounts[i],
            isAdmin: provider.isAdmin,
          ),
        );
      },
    );
  }
}

class _AccountCard extends StatefulWidget {
  final Account account;
  final bool isAdmin;
  const _AccountCard({required this.account, required this.isAdmin});

  @override
  State<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<_AccountCard> {
  double _total = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadTotal();
  }

  Future<void> _loadTotal() async {
    final total = await context
        .read<AppProvider>()
        .getTotalForAccount(widget.account.id);
    if (mounted) setState(() { _total = total; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final account = widget.account;

    return Card(
      color: cs.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AccountDetailScreen(account: account),
          ),
        ).then((_) => _loadTotal()),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Text(
                  account.name.characters.first,
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    if (account.description != null) ...[
                      const SizedBox(height: 2),
                      Text(account.description!,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 13)),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${AppStrings.commission}: ${account.commissionPercent.toStringAsFixed(1)}%',
                      style: TextStyle(color: cs.secondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _loaded
                      ? Text(
                          '${_total.toStringAsFixed(2)} ${account.currency}',
                          style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                  Text(AppStrings.total,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 11)),
                ],
              ),
              if (widget.isAdmin) ...[
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      await showDialog(
                        context: context,
                        builder: (_) => AccountFormDialog(account: account),
                      );
                    } else if (v == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text(AppStrings.deleteAccount),
                          content: const Text(AppStrings.deleteAccountConfirm),
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
                        context.read<AppProvider>().deleteAccount(account.id);
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text(AppStrings.edit)),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(AppStrings.delete,
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  final VoidCallback onAdd;
  final bool isAdmin;
  const _EmptyAccounts({required this.onAdd, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              size: 72, color: cs.outline),
          const SizedBox(height: 16),
          const Text(AppStrings.noAccounts,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(AppStrings.createFirstAccount,
              style: TextStyle(color: cs.onSurfaceVariant)),
          if (isAdmin) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.newAccount),
            ),
          ],
        ],
      ),
    );
  }
}
