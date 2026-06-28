import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/app_strings.dart';
import '../models/account.dart';
import '../services/app_provider.dart';

class AccountFormDialog extends StatefulWidget {
  final Account? account;
  const AccountFormDialog({super.key, this.account});

  @override
  State<AccountFormDialog> createState() => _AccountFormDialogState();
}

class _AccountFormDialogState extends State<AccountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _commissionCtrl;
  late String _currency;

  static const _currencies = ['EGP', 'USD', 'EUR', 'SAR', 'AED'];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.account?.name ?? '');
    _descCtrl =
        TextEditingController(text: widget.account?.description ?? '');
    _commissionCtrl = TextEditingController(
      text: widget.account?.commissionPercent.toString() ?? '0',
    );
    _currency = widget.account?.currency ?? 'EGP';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _commissionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<AppProvider>();
    final commission =
        double.tryParse(_commissionCtrl.text.replaceAll(',', '')) ?? 0;

    if (widget.account == null) {
      await provider.addAccount(Account(
        id: '',
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        currency: _currency,
        commissionPercent: commission,
        createdAt: DateTime.now(),
      ));
    } else {
      await provider.updateAccount(widget.account!.copyWith(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        currency: _currency,
        commissionPercent: commission,
      ));
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.account != null;

    return AlertDialog(
      title: Text(isEdit ? AppStrings.editAccount : AppStrings.newAccount),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: AppStrings.accountName,
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? AppStrings.nameRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: AppStrings.description,
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _commissionCtrl,
                decoration: const InputDecoration(
                  labelText: AppStrings.commission,
                  prefixIcon: Icon(Icons.percent),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _currency,
                decoration: const InputDecoration(
                  labelText: AppStrings.currency,
                  prefixIcon: Icon(Icons.monetization_on_outlined),
                ),
                items: _currencies
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _currency = v!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEdit ? AppStrings.save : AppStrings.create),
        ),
      ],
    );
  }
}
