import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/account.dart';
import '../models/cost_record.dart';

class ExportService {
  Future<void> exportRecordsCsv({
    required List<CostRecord> records,
    required Map<String, Account> accountsById,
    required String periodLabel,
  }) async {
    final buffer = StringBuffer()
      ..writeln('الحساب,المبلغ,العملة,نسبة العمولة,قيمة العمولة,التاريخ,ملاحظة');

    for (final record in records) {
      final account = accountsById[record.accountId];
      final name = account?.name ?? record.accountId;
      final currency = account?.currency ?? '';
      final commissionPercent = account?.commissionPercent ?? 0;
      final commissionValue = account?.commissionFor(record.amount) ?? 0;
      final date = record.createdAt.toIso8601String();
      final note = (record.note ?? '').replaceAll(',', ' ');
      buffer.writeln(
        '$name,${record.amount},$currency,$commissionPercent,$commissionValue,$date,$note',
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/cost_report_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'تقرير $periodLabel',
      text: 'تقرير العمليات - $periodLabel',
    );
  }
}
