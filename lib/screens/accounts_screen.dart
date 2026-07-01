import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_strings.dart';
import '../models/account.dart';
import '../services/app_provider.dart';
import '../widgets/account_form_dialog.dart';
import '../widgets/account_pin_dialogs.dart';
import '../widgets/global_pool_header.dart';
import 'account_detail_screen.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  Future<void> _onRefresh(BuildContext context) =>
      context.read<AppProvider>().refreshData();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        if (provider.loading && provider.accounts.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.accounts.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => _onRefresh(context),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const GlobalPoolHeader(),
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.5,
                  child: _EmptyAccounts(
                    onAdd: () => showDialog(
                      context: context,
                      builder: (_) => const AccountFormDialog(),
                    ),
                    isAdmin: provider.isAdmin,
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => _onRefresh(context),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              const GlobalPoolHeader(),
              const SizedBox(height: 10),
              ...provider.accounts.map(
                (account) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _AccountCard(
                    account: account,
                    isAdmin: provider.isAdmin,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AccountCard extends StatelessWidget {
  final Account account;
  final bool isAdmin;
  const _AccountCard({required this.account, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final cs = Theme.of(context).colorScheme;
    final account = this.account;
    final withdrawn = provider.spentForAccount(account.id);
    final remaining = provider.remainingForAccount(account);
    final todayOpening = provider.todayOpeningForAccount(account);
    final todayWithdrawn = provider.todaySpentForAccount(account.id);
    final todayRemaining = provider.todayRemainingForAccount(account);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: cs.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final allowed = await showVerifyPinDialog(context);
          if (!allowed || !context.mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AccountDetailScreen(account: account),
            ),
          );
        },
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
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _BalancePill(
                          label: 'المسحوب',
                          value: withdrawn,
                          currency: account.currency,
                          background: cs.errorContainer,
                          foreground: cs.onErrorContainer,
                        ),
                        _BalancePill(
                          label: 'المتبقي',
                          value: remaining,
                          currency: account.currency,
                          background: cs.tertiaryContainer,
                          foreground: cs.onTertiaryContainer,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'افتتاحي اليوم: ${todayOpening.toStringAsFixed(2)} ${account.currency}',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                    Text(
                      'سحب اليوم: ${todayWithdrawn.toStringAsFixed(2)} ${account.currency}  |  متبقي اليوم: ${todayRemaining.toStringAsFixed(2)} ${account.currency}',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${account.totalBalance.toStringAsFixed(2)} ${account.currency}',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'الرصيد الكلي',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                  ),
                ],
              ),
              if (isAdmin) ...[
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      final allowed = await showVerifyPinDialog(context);
                      if (!allowed || !context.mounted) return;
                      await showDialog(
                        context: context,
                        builder: (_) => AccountFormDialog(account: account),
                      );
                    } else if (v == 'reset') {
                      final allowed = await showVerifyPinDialog(context);
                      if (!allowed || !context.mounted) return;
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('تصفية الحساب'),
                          content: const Text(
                            'سيتم تصفير المسحوب وإضافة المتبقي (موجب أو سالب) '
                            'إلى الرصيد الكلي للحساب. هل تريد المتابعة؟',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text(AppStrings.cancel),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('تصفية'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && context.mounted) {
                        await context.read<AppProvider>().resetAccount(account.id);
                      }
                    } else if (v == 'delete') {
                      final allowed = await showVerifyPinDialog(context);
                      if (!allowed || !context.mounted) return;
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
                      value: 'reset',
                      child: Text('تصفية الحساب'),
                    ),
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

class _BalancePill extends StatelessWidget {
  final String label;
  final double value;
  final String currency;
  final Color background;
  final Color foreground;

  const _BalancePill({
    required this.label,
    required this.value,
    required this.currency,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: ${value.toStringAsFixed(2)} $currency',
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
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
