import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/app_strings.dart';
import '../core/constants.dart';
import '../models/account.dart';
import '../models/cost_record.dart';
import '../services/app_provider.dart';
import '../widgets/full_screen_image_dialog.dart';
import '../widgets/record_image.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.day;
  String? _accountId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final accounts = provider.accounts;
    final records = provider.getFilteredRecords(
      period: _period,
      accountId: _accountId,
    );

    final total = records.fold<double>(0, (s, r) => s + r.amount);
    final commission = records.fold<double>(0, (s, r) {
      final account = provider.accountsById[r.accountId];
      return s + (account?.commissionFor(r.amount) ?? 0);
    });
    final showDailyByAccount =
        _period == ReportPeriod.day && _accountId == null && records.isNotEmpty;
    final dailyAccountTotals = showDailyByAccount
        ? _totalsByAccount(records)
        : const <String, double>{};

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SegmentedButton<ReportPeriod>(
                segments: ReportPeriod.values
                    .map((p) => ButtonSegment(
                          value: p,
                          label: Text(p.labelAr),
                        ))
                    .toList(),
                selected: {_period},
                onSelectionChanged: (s) =>
                    setState(() => _period = s.first),
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
              if (showDailyByAccount) ...[
                const SizedBox(height: 12),
                _DailyAccountTotals(
                  totals: dailyAccountTotals,
                  accountsById: provider.accountsById,
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
                            periodLabel: _period.labelAr,
                          ),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text(AppStrings.exportCsv),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: records.isEmpty
              ? const Center(child: Text(AppStrings.noRecords))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _ReportRecordTile(
                    record: records[i],
                    account: provider.accountsById[records[i].accountId],
                  ),
                ),
        ),
      ],
    );
  }

  Map<String, double> _totalsByAccount(List<CostRecord> records) {
    final totals = <String, double>{};
    for (final record in records) {
      totals[record.accountId] = (totals[record.accountId] ?? 0) + record.amount;
    }
    return totals;
  }
}

class _DailyAccountTotals extends StatelessWidget {
  final Map<String, double> totals;
  final Map<String, Account> accountsById;

  const _DailyAccountTotals({
    required this.totals,
    required this.accountsById,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = totals.entries.toList()
      ..sort((a, b) {
        final nameA = accountsById[a.key]?.name ?? a.key;
        final nameB = accountsById[b.key]?.name ?? b.key;
        return nameA.compareTo(nameB);
      });

    return Card(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppStrings.dailyAccountSummary,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ...entries.map((entry) {
              final account = accountsById[entry.key];
              final name = account?.name ?? entry.key;
              final amount = entry.value;
              final currency = account?.currency ?? '';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    Text(
                      currency.isEmpty
                          ? amount.toStringAsFixed(0)
                          : '${amount.toStringAsFixed(0)} $currency',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
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

  const _ReportRecordTile({required this.record, this.account});

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
        trailing: account == null
            ? null
            : Text(
                account!.commissionFor(record.amount).toStringAsFixed(2),
                style: TextStyle(color: cs.secondary, fontSize: 12),
              ),
      ),
    );
  }
}
