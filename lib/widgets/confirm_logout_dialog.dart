import 'package:flutter/material.dart';
import '../core/app_strings.dart';

Future<bool> showLogoutDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.logout, color: cs.primary, size: 32),
        title: const Text(AppStrings.logout),
        content: const Text(AppStrings.logoutConfirm),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(AppStrings.yesLogout),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
