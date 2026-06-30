import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_provider.dart';

Future<bool> showVerifyPinDialog(BuildContext context) async {
  final provider = context.read<AppProvider>();
  if (!provider.hasAccountPin) return true;

  final controller = TextEditingController();
  String? errorText;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('أدخل رمز الحماية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('هذا الإجراء يتطلب إدخال رمز الحماية.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                labelText: 'رمز الحماية',
                errorText: errorText,
              ),
              onSubmitted: (_) {
                if (provider.verifyAccountPin(controller.text)) {
                  Navigator.pop(dialogContext, true);
                } else {
                  setState(() => errorText = 'رمز الحماية غير صحيح');
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (provider.verifyAccountPin(controller.text)) {
                Navigator.pop(dialogContext, true);
              } else {
                setState(() => errorText = 'رمز الحماية غير صحيح');
              }
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return ok ?? false;
}

Future<void> showChangePinDialog(BuildContext context) async {
  final provider = context.read<AppProvider>();
  final currentCtrl = TextEditingController();
  final newCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(provider.hasAccountPin ? 'تغيير رمز الحماية' : 'إنشاء رمز حماية'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: currentCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'الرمز الحالي',
                helperText: 'الرمز الحالي الافتراضي الآن: 123',
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) return 'أدخل الرمز الحالي';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: newCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'الرمز الجديد',
                helperText: 'من 4 إلى 6 أرقام',
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return 'أدخل الرمز الجديد';
                if (text.length < 4 || text.length > 6) {
                  return 'رمز الحماية يجب أن يكون من 4 إلى 6 أرقام';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: confirmCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'تأكيد الرمز الجديد'),
              validator: (value) {
                if ((value ?? '').trim() != newCtrl.text.trim()) {
                  return 'تأكيد الرمز غير مطابق';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        if (provider.hasAccountPin)
          TextButton(
            onPressed: () async {
              await provider.setAccountPin('');
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم إيقاف رمز الحماية')),
                );
              }
            },
            child: const Text('إزالة الرمز'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () async {
            if (!formKey.currentState!.validate()) return;
            final ok = await provider.changeAccountPin(
              currentPin: currentCtrl.text,
              newPin: newCtrl.text,
            );
            if (!ok) {
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('الرمز الحالي غير صحيح')),
                );
              }
              return;
            }
            if (dialogContext.mounted) {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حفظ رمز الحماية')),
              );
            }
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );

  currentCtrl.dispose();
  newCtrl.dispose();
  confirmCtrl.dispose();
}
