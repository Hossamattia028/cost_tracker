import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../core/constants.dart';
import 'amount_ai_client.dart';

/// Recognizes the receipt total amount using OpenAI (vision for images, chat
/// for text). Returns a clean numeric string (e.g. "1000" or "1000.50") or null.
class AiAmountService implements AmountAiClient {
  AiAmountService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _systemPrompt =
      'You read Egyptian mobile-wallet transfer receipts/messages (Vodafone '
      'Cash, Etisalat, Orange, WE) and return ONLY the transferred money '
      'amount (the value of the transaction).\n'
      'The amount you want is the number that appears:\n'
      '- on the «إجمالي» / «الإجمالي» / «اجمالي» line (the value on the other '
      'side of that line), or\n'
      '- after phrases like «تم تحويل» / «قيمة العملية» / «المبلغ المحول» / '
      '«مبلغ», and is usually followed by the currency «ج.م» / «جنيه».\n'
      'STRICTLY IGNORE every other number, including: phone/wallet numbers '
      '(e.g. starting 010/011/012/015, «الرقم المحول منه/إليه»), transaction '
      'or reference IDs, «رقم العميل», «رقم المجموعة», dates, times, and any '
      'remaining balance.\n'
      'Respond with ONLY the numeric amount — no currency, no words, no '
      'thousands separators, dot for decimals. If there is no clear transfer '
      'amount, respond with exactly: null';

  static const _multiSystemPrompt =
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

  @override
  Future<String?> fromText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return _complete([
      {'role': 'system', 'content': _systemPrompt},
      {
        'role': 'user',
        'content': 'Extract the total (إجمالي) amount from this text:\n$trimmed',
      },
    ]);
  }

  /// Extracts every transaction amount from a (possibly long) text block.
  @override
  Future<List<String>> amountsFromText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];
    final content = await _completeRaw([
      {'role': 'system', 'content': _multiSystemPrompt},
      {
        'role': 'user',
        'content':
            'Extract all transfer amounts from this text:\n$trimmed',
      },
    ], maxTokens: 800);
    return _parseAmountList(content);
  }

  @override
  Future<String?> fromImage(File file) async {
    final dataUrl = await _imageToDataUrl(file);
    if (dataUrl == null) return null;
    return _complete([
      {'role': 'system', 'content': _systemPrompt},
      {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': 'Read this receipt and return the total (إجمالي) amount.',
          },
          {
            'type': 'image_url',
            'image_url': {'url': dataUrl},
          },
        ],
      },
    ]);
  }

  Future<String?> _complete(List<Map<String, dynamic>> messages) async {
    final content = await _completeRaw(messages, maxTokens: 20);
    return _parseAmount(content);
  }

  Future<String> _completeRaw(
    List<Map<String, dynamic>> messages, {
    required int maxTokens,
  }) async {
    if (AppConstants.openAiApiKey.isEmpty) {
      throw Exception('OpenAI API key is not configured');
    }

    debugPrint('[AI] → POST ${AppConstants.openAiBaseUrl} '
        'model=${AppConstants.openAiModel}');
    final response = await _client
        .post(
          Uri.parse(AppConstants.openAiBaseUrl),
          headers: {
            'Authorization': 'Bearer ${AppConstants.openAiApiKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': AppConstants.openAiModel,
            'temperature': 0,
            'max_tokens': maxTokens,
            'messages': messages,
          }),
        )
        .timeout(const Duration(seconds: 90));

    final body = utf8.decode(response.bodyBytes);
    debugPrint('[AI] ← status=${response.statusCode}');
    debugPrint('[AI] ← body=$body');

    if (response.statusCode != 200) {
      throw Exception(
        'OpenAI request failed (${response.statusCode}): $body',
      );
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return '';
    final content =
        (choices.first['message']?['content'] as String?)?.trim() ?? '';
    debugPrint('[AI] parsed content: "$content"');
    return content;
  }

  List<String> _parseAmountList(String content) {
    final normalized = _normalizeNumerals(content);
    // Isolate the JSON array if the model added any wrapping text/fences.
    final start = normalized.indexOf('[');
    final end = normalized.lastIndexOf(']');
    final slice = (start != -1 && end > start)
        ? normalized.substring(start, end + 1)
        : normalized;

    final results = <String>[];

    List<dynamic>? parsed;
    try {
      final decoded = jsonDecode(slice);
      if (decoded is List) parsed = decoded;
    } catch (_) {}

    if (parsed != null) {
      for (final item in parsed) {
        final cleaned = _cleanNumber(item.toString());
        if (cleaned != null) results.add(cleaned);
      }
      return results;
    }

    // Fallback: pull every number-like token from the response.
    for (final m in RegExp(r'\d[\d,]*(?:\.\d+)?').allMatches(slice)) {
      final cleaned = _cleanNumber(m.group(0)!);
      if (cleaned != null) results.add(cleaned);
    }
    return results;
  }

  String? _cleanNumber(String raw) {
    final cleaned = raw.replaceAll(',', '').trim();
    final value = double.tryParse(cleaned);
    if (value == null || value <= 0) return null;
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  String? _parseAmount(String content) {
    final lower = content.toLowerCase();
    final normalized = _normalizeNumerals(content);
    final match = RegExp(r'\d[\d,]*(?:\.\d+)?').firstMatch(normalized);
    if (match == null) {
      if (lower.contains('null')) return null;
      return null;
    }
    final cleaned = match.group(0)!.replaceAll(',', '');
    final value = double.tryParse(cleaned);
    if (value == null || value <= 0) return null;
    // Drop a trailing ".0" so whole numbers look clean in the field.
    if (value == value.roundToDouble()) return value.toInt().toString();
    return cleaned;
  }

  /// Decodes, fixes orientation, downscales and re-encodes as JPEG so the
  /// payload is small while the total stays legible to the vision model.
  Future<String?> _imageToDataUrl(File file) async {
    try {
      final bytes = await file.readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      decoded = img.bakeOrientation(decoded);

      const maxDimension = 1600;
      final longest = math.max(decoded.width, decoded.height);
      if (longest > maxDimension) {
        final scale = maxDimension / longest;
        decoded = img.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
          interpolation: img.Interpolation.cubic,
        );
      }

      final jpeg = img.encodeJpg(decoded, quality: 90);
      return 'data:image/jpeg;base64,${base64Encode(jpeg)}';
    } catch (_) {
      return null;
    }
  }

  String _normalizeNumerals(String text) {
    final buf = StringBuffer();
    for (final ch in text.runes) {
      if (ch >= 0x0660 && ch <= 0x0669) {
        buf.writeCharCode(ch - 0x0660 + 0x30);
      } else if (ch >= 0x06F0 && ch <= 0x06F9) {
        buf.writeCharCode(ch - 0x06F0 + 0x30);
      } else {
        buf.writeCharCode(ch);
      }
    }
    return buf.toString();
  }

  @override
  void dispose() => _client.close();
}
