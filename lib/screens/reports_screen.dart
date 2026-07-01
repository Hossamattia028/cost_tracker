import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/app_strings.dart';
import '../models/account.dart';
import '../models/account_day_summary.dart';
import '../models/cost_record.dart';
import '../services/app_provider.dart';
import '../widgets/confirm_delete_record_dialog.dart';
import '../widgets/full_screen_image_dialog.dart';
import '../widgets/record_image.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _fromDate;
  late DateTime _toDate;
  String? _accountId;

  @override
  void initState() {
    super.initState();
    final today = _startOfDay(DateTime.now());
    _fromDate = today;
    _toDate = today;
  }

  static DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool get _isTodayOnly {
    final today = _startOfDay(DateTime.now());
    return _startOfDay(_fromDate) == today && _startOfDay(_toDate) == today;
  }

  String get _periodLabel {
    final fmt = DateFormat('d MMM yyyy', 'ar');
    if (_startOfDay(_fromDate) == _startOfDay(_toDate)) {
      return fmt.format(_fromDate);
    }
    return 'من ${fmt.format(_fromDate)} إلى ${fmt.format(_toDate)}';
  }

  void _setTodayOnly() {
    final today = _startOfDay(DateTime.now());
    setState(() {
      _fromDate = today;
      _toDate = today;
    });
  }

  void _setThisWeek() {
    final now = DateTime.now();
    final today = _startOfDay(now);
    final weekStart = today.subtract(Duration(days: now.weekday - 1));
    setState(() {
      _fromDate = weekStart;
      _toDate = today;
    });
  }

  void _setThisMonth() {
    final now = DateTime.now();
    setState(() {
      _fromDate = DateTime(now.year, now.month, 1);
      _toDate = _startOfDay(now);
    });
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 5),
      locale: const Locale('ar'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _fromDate = _startOfDay(picked);
      if (_toDate.isBefore(_fromDate)) _toDate = _fromDate;
    });
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate.isBefore(_fromDate) ? _fromDate : _toDate,
      firstDate: _fromDate,
      lastDate: DateTime(DateTime.now().year + 5),
      locale: const Locale('ar'),
    );
    if (picked == null || !mounted) return;
    setState(() => _toDate = _startOfDay(picked));
  }

  Future<void> _changeRecordDate(CostRecord record) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: record.createdAt,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 5),
      locale: const Locale('ar'),
    );
    if (picked == null || !mounted) return;
    final newDate = DateTime(
      picked.year,
      picked.month,
      picked.day,
      record.createdAt.hour,
      record.createdAt.minute,
    );
    await context.read<AppProvider>().updateRecordDate(record.id, newDate);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.dateUpdated)),
      );
    }
  }

  Future<void> _deleteRecord(CostRecord record) async {
    final confirm = await showDeleteRecordDialog(context);
    if (!confirm || !mounted) return;
    await context.read<AppProvider>().deleteRecord(record.id);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final accounts = provider.accounts;
    final records = provider.getFilteredRecordsByRange(
      from: _fromDate,
      to: _toDate,
      accountId: _accountId,
    );
    final summaries = provider.summariesForDateRange(
      from: _fromDate,
      to: _toDate,
      accountId: _accountId,
    );

    final total = records.fold<double>(0, (s, r) => s + r.amount);
    final commission = records.fold<double>(0, (s, r) {
      final account = provider.accountsById[r.accountId];
      return s + (account?.commissionFor(r.amount) ?? 0);
    });

    final dateFmt = DateFormat('d MMM yyyy', 'ar');

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickFromDate,
                        icon: const Icon(Icons.calendar_today_outlined, size: 18),
                        label: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppStrings.dateFrom,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            Text(
                              dateFmt.format(_fromDate),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickToDate,
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppStrings.dateTo,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            Text(
                              dateFmt.format(_toDate),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text(AppStrings.todayOnly),
                      selected: _isTodayOnly,
                      onSelected: (_) => _setTodayOnly(),
                    ),
                    FilterChip(
                      label: const Text(AppStrings.thisWeek),
                      selected: false,
                      onSelected: (_) => _setThisWeek(),
                    ),
                    FilterChip(
                      label: const Text(AppStrings.thisMonth),
                      selected: false,
                      onSelected: (_) => _setThisMonth(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: _accountId,
                  decoration: const InputDecoration(
                    labelText: AppStrings.filter,
                    prefixIcon: Icon(Icons.filter_list),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text(AppStrings.allAccounts),
                    ),
                    ...accounts.map(
                      (a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(a.name),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _accountId = v),
                ),
                const SizedBox(height: 12),
                _SummaryCard(
                  total: total,
                  commission: commission,
                  count: records.length,
                  currency: _accountId != null
                      ? provider.accountsById[_accountId]?.currency ?? 'EGP'
                      : 'EGP',
                ),
                if (summaries.isNotEmpty && _accountId != null) ...[
                  const SizedBox(height: 12),
                  _FinancialSummaries(
                    summaries: summaries,
                    periodLabel: _periodLabel,
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: records.isEmpty
                        ? null
                        : () => provider.exportFilteredRecords(
                              records: records,
                              periodLabel: _periodLabel,
                            ),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text(AppStrings.exportCsv),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_accountId == null)
          _GroupedRecordsSliver(
            accounts: accounts,
            records: records,
            summariesByAccountId: {
              for (final s in summaries) s.accountId: s,
            },
            onChangeDate: _changeRecordDate,
            onDelete: _deleteRecord,
            accountsById: provider.accountsById,
          )
        else if (records.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(AppStrings.noRecordsInRange)),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverList.separated(
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _ReportRecordTile(
                record: records[i],
                account: provider.accountsById[records[i].accountId],
                onChangeDate: () => _changeRecordDate(records[i]),
                onDelete: () => _deleteRecord(records[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _GroupedRecordsSliver extends StatelessWidget {
  final List<Account> accounts;
  final List<CostRecord> records;
  final Map<String, AccountDaySummary> summariesByAccountId;
  final Map<String, Account> accountsById;
  final Future<void> Function(CostRecord) onChangeDate;
  final Future<void> Function(CostRecord) onDelete;

  const _GroupedRecordsSliver({
    required this.accounts,
    required this.records,
    required this.summariesByAccountId,
    required this.accountsById,
    required this.onChangeDate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text(AppStrings.noRecords)),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final account = accounts[index];
            final accountRecords = records
                .where((r) => r.accountId == account.id)
                .toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            final summary = summariesByAccountId[account.id];

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AccountSectionHeader(
                    account: account,
                    summary: summary,
                    recordCount: accountRecords.length,
                  ),
                  if (accountRecords.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        AppStrings.noRecordsInRange,
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ...accountRecords.map(
                      (record) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _ReportRecordTile(
                          record: record,
                          account: accountsById[record.accountId],
                          onChangeDate: () => onChangeDate(record),
                          onDelete: () => onDelete(record),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
          childCount: accounts.length,
        ),
      ),
    );
  }
}

class _AccountSectionHeader extends StatelessWidget {
  final Account account;
  final AccountDaySummary? summary;
  final int recordCount;

  const _AccountSectionHeader({
    required this.account,
    required this.summary,
    required this.recordCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    account.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '$recordCount عملية',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            if (summary != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _miniStat(
                      'الافتتاحي',
                      summary!.opening,
                      account.currency,
                      cs.primary,
                    ),
                  ),
                  Expanded(
                    child: _miniStat(
                      'المسحوب',
                      summary!.withdrawn,
                      account.currency,
                      cs.error,
                    ),
                  ),
                  Expanded(
                    child: _miniStat(
                      'المتبقي',
                      summary!.remaining,
                      account.currency,
                      cs.tertiary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, double value, String currency, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        Text(
          value.toStringAsFixed(2),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 13,
          ),
        ),
        Text(currency, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}

class _FinancialSummaries extends StatelessWidget {
  final List<AccountDaySummary> summaries;
  final String periodLabel;

  const _FinancialSummaries({
    required this.summaries,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ملخص $periodLabel لكل حساب',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 12),
            ...summaries.map((s) => _summaryRow(cs, s)),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(ColorScheme cs, AccountDaySummary s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: cs.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.accountName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 8),
          _line('الافتتاحي', s.opening, s.currency, cs.primary),
          _line('المسحوب', s.withdrawn, s.currency, cs.error),
          _line('المتبقي', s.remaining, s.currency, cs.tertiary),
        ],
      ),
    );
  }

  Widget _line(String label, double value, String currency, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '${value.toStringAsFixed(2)} $currency',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final double total;
  final double commission;
  final int count;
  final String currency;

  const _SummaryCard({
    required this.total,
    required this.commission,
    required this.count,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _row(AppStrings.totalAmount, '$total $currency', cs.primary),
            const SizedBox(height: 6),
            _row(AppStrings.totalCommission, '$commission $currency', cs.secondary),
            const SizedBox(height: 6),
            _row(AppStrings.recordCount, '$count', cs.onSurface),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, Color color) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      );
}

class _ReportRecordTile extends StatelessWidget {
  final CostRecord record;
  final Account? account;
  final VoidCallback onChangeDate;
  final VoidCallback onDelete;

  const _ReportRecordTile({
    required this.record,
    required this.account,
    required this.onChangeDate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('d MMM yyyy  h:mm a', 'ar');
    final currency = account?.currency ?? '';

    return Card(
      color: cs.surfaceContainerLow,
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: RecordImage(
            imageUrl: record.imageUrl,
            width: 48,
            height: 48,
          ),
        ),
        onTap: () => FullScreenImageDialog.show(context, record.imageUrl),
        title: Text('${record.amount.toStringAsFixed(2)} $currency'),
        subtitle: Text(
          '${account?.name ?? ''} • ${fmt.format(record.createdAt)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: AppStrings.changeDate,
              icon: const Icon(Icons.edit_calendar_outlined, size: 20),
              onPressed: onChangeDate,
            ),
            IconButton(
              tooltip: AppStrings.delete,
              icon: Icon(Icons.delete_outline, size: 20, color: cs.error),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
