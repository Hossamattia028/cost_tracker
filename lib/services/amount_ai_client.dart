import 'dart:io';

/// Common interface for AI amount-recognition backends (OpenAI, Gemini, ...).
abstract class AmountAiClient {
  /// Recognizes the single transfer amount from a receipt image.
  Future<String?> fromImage(File file);

  /// Recognizes one transfer amount per receipt image, in the same order.
  /// Returns `null` for any image where no amount could be read.
  Future<List<String?>> amountsFromImages(List<File> files);

  /// Recognizes the single transfer amount from a text block.
  Future<String?> fromText(String text);

  /// Recognizes every transfer amount from a (possibly long) text block.
  Future<List<String>> amountsFromText(String text);

  void dispose();
}

/// Shared extraction instructions so every backend behaves identically.
const String kAmountSystemPrompt =
    'You read Egyptian mobile-wallet transfer receipts/messages (Vodafone '
    'Cash, Etisalat, Orange, WE) and return ONLY the transferred money amount '
    '(the value of the transaction).\n'
    'The amount you want is the number that appears:\n'
    '- on the «إجمالي» / «الإجمالي» / «اجمالي» line (the value on the other '
    'side of that line), or\n'
    '- after phrases like «تم تحويل» / «قيمة العملية» / «المبلغ المحول» / '
    '«مبلغ», and is usually followed by the currency «ج.م» / «جنيه».\n'
    'STRICTLY IGNORE every other number, including: phone/wallet numbers '
    '(e.g. starting 010/011/012/015, «الرقم المحول منه/إليه»), transaction or '
    'reference IDs, «رقم العميل», «رقم المجموعة», dates, times, and any '
    'remaining balance.\n'
    'Respond with ONLY the numeric amount — no currency, no words, no '
    'thousands separators, dot for decimals. If there is no clear transfer '
    'amount, respond with exactly: null';

const String kAmountMultiSystemPrompt =
    'You read a chat log / summary of Egyptian mobile-wallet money transfers '
    '(may contain many transfers for one customer in a day) and return the '
    'transferred money amount of EACH transfer only.\n'
    'For every transfer, the amount is the number that appears:\n'
    '- on the «إجمالي» / «الإجمالي» / «اجمالي» line, or\n'
    '- after phrases like «تم تحويل» / «قيمة العملية» / «المبلغ المحول» / '
    '«مبلغ», usually followed by the currency «ج.م» / «جنيه».\n'
    'STRICTLY IGNORE every other number: phone/wallet numbers (010/011/012/'
    '015..., «الرقم المحول منه/إليه»), transaction or reference IDs, «رقم '
    'العميل», «رقم المجموعة», dates, times, and any remaining balance.\n'
    'Return ONLY a compact JSON array of the transfer amounts as numbers, in '
    'order, e.g. [1000, 250.5, 2000]. No currency, no thousands separators, '
    'dot for decimals, no extra text. If there are no transfers, return [].';

const String kAmountMultiImageSystemPrompt =
    'You read Egyptian mobile-wallet transfer receipt images (Vodafone Cash, '
    'Etisalat, Orange, WE) and return the transferred money amount of EACH '
    'receipt only.\n'
    'For every image, the amount is the number that appears:\n'
    '- on the «إجمالي» / «الإجمالي» / «اجمالي» line, or\n'
    '- after phrases like «تم تحويل» / «قيمة العملية» / «المبلغ المحول» / '
    '«مبلغ», usually followed by the currency «ج.م» / «جنيه».\n'
    'STRICTLY IGNORE every other number: phone/wallet numbers (010/011/012/'
    '015..., «الرقم المحول منه/إليه»), transaction or reference IDs, «رقم '
    'العميل», «رقم المجموعة», dates, times, and any remaining balance.\n'
    'If an image is a duplicate of an earlier image in the same batch, return '
    'null for that duplicate entry.\n'
    'The user sends multiple receipt images in order. Return ONLY a compact '
    'JSON array with one entry per image, in the same order, e.g. '
    '[1000, null, 250.5]. Use null when an image has no clear transfer amount. '
    'No currency, no thousands separators, dot for decimals, no extra text.';
