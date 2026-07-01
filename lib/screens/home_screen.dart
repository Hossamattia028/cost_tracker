import 'dart:io';
import 'package:cost_tracker/widgets/app_logo.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_strings.dart';
import '../services/app_provider.dart';
import '../widgets/account_form_dialog.dart';
import '../widgets/app_logo_title.dart';
import '../widgets/confirm_logout_dialog.dart';
import 'accounts_screen.dart';
import 'add_record_screen.dart';
import 'admin_users_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  AppProvider? _provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider = context.read<AppProvider>();
      _provider!.addListener(_onProviderUpdate);
      _openSharedImagesIfAny();
    });
  }

  @override
  void dispose() {
    _provider?.removeListener(_onProviderUpdate);
    super.dispose();
  }

  void _onProviderUpdate() {
    if (_provider?.pendingSharedImages.isNotEmpty ?? false) {
      _openSharedImagesIfAny();
    }
  }

  void _openSharedImagesIfAny() {
    final provider = context.read<AppProvider>();
    if (provider.pendingSharedImages.isEmpty) return;
    final images = List<File>.from(provider.pendingSharedImages);
    provider.clearPendingSharedImages();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddRecordScreen(sharedImages: images),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isAdmin = provider.isAdmin;

    final tabs = <Widget>[
      const AccountsScreen(),
      const ReportsScreen(),
      if (isAdmin) const AdminUsersScreen(),
    ];

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.account_balance_wallet_outlined),
        selectedIcon: Icon(Icons.account_balance_wallet),
        label: AppStrings.accounts,
      ),
      const NavigationDestination(
        icon: Icon(Icons.bar_chart_outlined),
        selectedIcon: Icon(Icons.bar_chart),
        label: AppStrings.reports,
      ),
      if (isAdmin)
        const NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: AppStrings.users,
        ),
    ];

    if (_tab >= tabs.length) _tab = 0;

    return Scaffold(
      appBar: AppBar(
        leading: const AppLogo(size: AppBranding.logoSize),
        actions: [
          if (isAdmin && _tab == 0)
            IconButton(
              tooltip: AppStrings.newAccount,
              icon: const Icon(Icons.add_card_outlined),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const AccountFormDialog(),
              ),
            ),
          IconButton(
            tooltip: 'الإعدادات',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            tooltip: AppStrings.logout,
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirm = await showLogoutDialog(context);
              if (confirm && context.mounted) {
                provider.signOut();
              }
            },
          ),
        ],
      ),
      body: tabs[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: destinations,
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddRecordScreen()),
              ),
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.addRecord),
            )
          : null,
    );
  }

  String _tabTitle(int tab, bool isAdmin) {
    if (tab == 0) return AppStrings.accounts;
    if (tab == 1) return AppStrings.reports;
    if (isAdmin && tab == 2) return AppStrings.users;
    return AppStrings.appName;
  }
}
