/// Financial snapshot for one account over a date range.
class AccountDaySummary {
  final String accountId;
  final String accountName;
  final String currency;
  final double opening;
  final double withdrawn;
  final double remaining;

  const AccountDaySummary({
    required this.accountId,
    required this.accountName,
    required this.currency,
    required this.opening,
    required this.withdrawn,
    required this.remaining,
  });
}
