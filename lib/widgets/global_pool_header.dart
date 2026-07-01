import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/app_provider.dart';

class GlobalPoolHeader extends StatelessWidget {
  const GlobalPoolHeader({super.key});

  Future<void> _addToPool(BuildContext context) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة للرصيد الكلي العام'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'المبلغ',
              prefixIcon: Icon(Icons.add_circle_outline),
            ),
            validator: (value) {
              final amount =
                  double.tryParse((value ?? '').replaceAll(',', ''));
              if (amount == null || amount <= 0) return 'أدخل مبلغاً صحيحاً';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final amount = double.parse(controller.text.replaceAll(',', ''));
    controller.dispose();
    try {
      await context.read<AppProvider>().addToGlobalPool(amount);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إضافة المبلغ للرصيد الكلي')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('d MMM yyyy  h:mm a', 'ar');
    final recent = provider.poolTransfers.take(5).toList();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: cs.primaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance, color: cs.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'الرصيد الكلي العام',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  provider.globalPoolBalance.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'أي تحويل لأي حساب يُخصم من هذا الرصيد فقط',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _addToPool(context),
              icon: const Icon(Icons.add),
              label: const Text('إضافة رصيد كلي'),
            ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'آخر السحوبات',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              ...recent.map(
                (t) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${t.amount.toStringAsFixed(2)} → ${t.accountName}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        fmt.format(t.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
