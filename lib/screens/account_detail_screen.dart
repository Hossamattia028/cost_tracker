import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/app_strings.dart';
import '../models/account.dart';
import '../models/cost_record.dart';
import '../services/app_provider.dart';
import '../widgets/confirm_delete_record_dialog.dart';
import '../widgets/full_screen_image_dialog.dart';
import '../widgets/record_image.dart';
import 'add_record_screen.dart';

class AccountDetailScreen extends StatefulWidget {
  final Account account;
  const AccountDetailScreen({super.key, required this.account});

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _searching = false;
  bool _selectionMode = false;
  final Set<String> _selected = {};

  Account get account => widget.account;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CostRecord> _filtered(List<CostRecord> all) {
    final records =
        all.where((r) => r.accountId == account.id).toList();
    if (_query.trim().isEmpty) return records;
    final q = _query.trim().toLowerCase();
    return records.where((r) {
      final amount = r.amount.toStringAsFixed(2);
      final note = (r.note ?? '').toLowerCase();
      return amount.contains(q) ||
          r.amount.toString().contains(q) ||
          note.contains(q);
    }).toList();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchCtrl.clear();
        _query = '';
      }
    });
  }

  void _enterSelection(String id) {
    setState(() {
      _selectionMode = true;
      _selected.add(id);
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        _selected.add(id);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _selectAll(List<CostRecord> records) {
    setState(() {
      _selected
        ..clear()
        ..addAll(records.map((r) => r.id));
      _selectionMode = _selected.isNotEmpty;
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    if (count == 0) return;
    final confirm = await showConfirmDeleteDialog(
      context,
      title: AppStrings.deleteSelected,
      message: AppStrings.deleteSelectedConfirm(count),
    );
    if (!confirm || !mounted) return;
    final ids = _selected.toList();
    _exitSelection();
    await context.read<AppProvider>().deleteRecords(ids);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.recordsDeleted)),
      );
    }
  }

  Future<void> _deleteAll() async {
    final confirm = await showConfirmDeleteDialog(
      context,
      title: AppStrings.deleteAllRecords,
      message: AppStrings.deleteAllRecordsConfirm,
    );
    if (!confirm || !mounted) return;
    await context.read<AppProvider>().deleteAllRecordsForAccount(account.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.recordsDeleted)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _buildAppBar(cs),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final filtered = _filtered(provider.records);
          final allForAccount = provider.records
              .where((r) => r.accountId == account.id)
              .toList();
          final total =
              allForAccount.fold<double>(0, (s, r) => s + r.amount);
          final commissionTotal = allForAccount.fold<double>(
              0, (s, r) => s + account.commissionFor(r.amount));

          // Drop selections for records that no longer exist.
          _selected.removeWhere(
            (id) => !allForAccount.any((r) => r.id == id),
          );

          return Column(
            children: [
              _summaryCard(cs, total, commissionTotal, allForAccount.length),
              Expanded(
                child: allForAccount.isEmpty
                    ? _emptyState()
                    : filtered.isEmpty
                        ? const Center(child: Text(AppStrings.noSearchResults))
                        : ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final record = filtered[i];
                              return _RecordCard(
                                record: record,
                                account: account,
                                selectionMode: _selectionMode,
                                selected: _selected.contains(record.id),
                                onTapImage: () => FullScreenImageDialog.show(
                                    context, record.imageUrl),
                                onLongPress: () => _enterSelection(record.id),
                                onToggleSelected: () =>
                                    _toggleSelected(record.id),
                                onDelete: () async {
                                  final confirm =
                                      await showDeleteRecordDialog(context);
                                  if (confirm && context.mounted) {
                                    context
                                        .read<AppProvider>()
                                        .deleteRecord(record.id);
                                  }
                                },
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _goToAdd,
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.addRecord),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme cs) {
    if (_selectionMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: AppStrings.clearSelection,
          onPressed: _exitSelection,
        ),
        title: Text(AppStrings.selectedCount(_selected.length)),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: AppStrings.selectAll,
            onPressed: () {
              final records = context
                  .read<AppProvider>()
                  .records
                  .where((r) => r.accountId == account.id)
                  .toList();
              _selectAll(records);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: cs.error,
            tooltip: AppStrings.deleteSelected,
            onPressed: _selected.isEmpty ? null : _deleteSelected,
          ),
        ],
      );
    }

    if (_searching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _toggleSearch,
        ),
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: AppStrings.searchRecordsHint,
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _query = '');
              },
            ),
        ],
      );
    }

    return AppBar(
      title: Text(account.name),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: AppStrings.search,
          onPressed: _toggleSearch,
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'select') {
              setState(() => _selectionMode = true);
            } else if (value == 'delete_all') {
              _deleteAll();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'select',
              child: ListTile(
                leading: Icon(Icons.checklist),
                title: Text(AppStrings.selectRecords),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'delete_all',
              child: ListTile(
                leading: Icon(Icons.delete_sweep_outlined),
                title: Text(AppStrings.deleteAllRecords),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard(
    ColorScheme cs,
    double total,
    double commissionTotal,
    int count,
  ) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [cs.primary, cs.primaryContainer]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppStrings.totalAmount,
                        style: TextStyle(
                            color: cs.onPrimary.withValues(alpha: 0.85))),
                    Text(
                      '${total.toStringAsFixed(2)} ${account.currency}',
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$count ${AppStrings.records}',
                style:
                    TextStyle(color: cs.onPrimary.withValues(alpha: 0.85)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${AppStrings.commission} (${account.commissionPercent}%): ',
                style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.85)),
              ),
              Text(
                '${commissionTotal.toStringAsFixed(2)} ${account.currency}',
                style: TextStyle(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(AppStrings.noRecords),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _goToAdd,
            icon: const Icon(Icons.add),
            label: const Text(AppStrings.addFirstRecord),
          ),
        ],
      ),
    );
  }

  void _goToAdd() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddRecordScreen(preselectedAccount: account),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final CostRecord record;
  final Account account;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTapImage;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelected;
  final VoidCallback onDelete;

  const _RecordCard({
    required this.record,
    required this.account,
    required this.selectionMode,
    required this.selected,
    required this.onTapImage,
    required this.onLongPress,
    required this.onToggleSelected,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('d MMM yyyy  h:mm a', 'ar');

    return Card(
      color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: selectionMode ? onToggleSelected : null,
        onLongPress: selectionMode ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectionMode)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 24),
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? cs.primary : cs.outline,
                  ),
                ),
              GestureDetector(
                onTap: selectionMode ? onToggleSelected : onTapImage,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: RecordImage(
                    imageUrl: record.imageUrl,
                    enableFullScreen: false,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${record.amount.toStringAsFixed(2)} ${account.currency}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: cs.primary,
                      ),
                    ),
                    Text(
                      '${AppStrings.commissionAmount}: ${account.commissionFor(record.amount).toStringAsFixed(2)} ${account.currency}',
                      style: TextStyle(color: cs.secondary, fontSize: 12),
                    ),
                    if (record.note != null) ...[
                      const SizedBox(height: 4),
                      Text(record.note!,
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 4),
                    Text(fmt.format(record.createdAt),
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
              if (!selectionMode)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: cs.error,
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
