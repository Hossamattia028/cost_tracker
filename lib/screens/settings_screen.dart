import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_provider.dart';
import '../widgets/account_pin_dialogs.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'المظهر',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                        label: Text('تلقائي'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('فاتح'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('داكن'),
                      ),
                    ],
                    selected: {provider.themeMode},
                    onSelectionChanged: (value) {
                      provider.setThemeMode(value.first);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: const Text('رمز الحماية للحسابات'),
                  subtitle: Text(
                    provider.hasAccountPin
                        ? 'مفعل - سيتم طلب الرمز عند فتح أو تعديل أي حساب'
                        : 'غير مفعل',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showChangePinDialog(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
