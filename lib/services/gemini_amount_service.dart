import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../core/constants.dart';
import 'amount_ai_client.dart';

/// Recognizes the transfer amount using Google Gemini (free tier available).
/// Mirrors [AiAmountService] so the two backends are interchangeable.
class GeminiAmountService implements AmountAiClient {
  GeminiAmountService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Uri get _endpoint => Uri.parse(
        '${AppConstants.geminiBaseUrl}/${AppConstants.geminiModel}'
        ':generateContent?key=${AppConstants.geminiApiKey}',
      );

  @override
  Future<String?> fromText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final content = await _generate(
      system: kAmountSystemPrompt,
      parts: [
        {'text': 'Extract the total (إجمالي) amount from this text:\n$trimmed'}
      ],
      maxTokens: 64,
    );
    return _parseAmount(content);
  }

  @override
  Future<List<String>> amountsFromText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];
    final content = await _generate(
      system: kAmountMultiSystemPrompt,
      parts: [
        {'text': 'Extract all transfer amounts from this text:\n$trimmed'}
      ],
      maxTokens: 1024,
    );
    return _parseAmountList(content);
  }

  @override
  Future<String?> fromImage(File file) async {
    final base64Data = await _imageToBase64(file);
    if (base64Data == null) return null;
    final content = await _generate(
      system: kAmountSystemPrompt,
      parts: [
        {'text': 'Read this receipt and return the total (إجمالي) amount.'},
        {
          'inline_data': {'mime_type': 'image/jpeg', 'data': base64Data},
        },
      ],
      maxTokens: 64,
    );
    return _parseAmount(content);
  }

  Future<String> _generate({
    required String system,
    required List<Map<String, dynamic>> parts,
    required int maxTokens,
  }) async {
    if (AppConstants.geminiApiKey.isEmpty) {
      throw Exception('Gemini API key is not configured');
    }

    debugPrint('[AI/Gemini] → ${AppConstants.geminiModel}');
    final response = await _client
        .post(
          _endpoint,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'system_instruction': {
              'parts': [
                {'text': system}
              ]
            },
            'contents': [
              {'role': 'user', 'parts': parts}
            ],
            'generationConfig': {
              'temperature': 0,
              'maxOutputTokens': maxTokens,
              // Gemini 2.5 models "think" by default and spend the output
              // budget on hidden reasoning, truncating the answer. We only
              // need a number, so disable thinking for speed + reliability.
              'thinkingConfig': {'thinkingBudget': 0},
            },
          }),
        )
        .timeout(const Duration(seconds: 90));

    final body = utf8.decode(response.bodyBytes);
    debugPrint('[AI/Gemini] ← status=${response.statusCode}');
    debugPrint('[AI/Gemini] ← body=$body');

    if (response.statusCode != 200) {
      throw Exception(
        'Gemini request failed (${response.statusCode}): $body',
      );
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return '';
    final contentParts = (candidates.first['content']?['parts'] as List?) ?? [];
    final text = contentParts
        .map((p) => (p as Map)['text']?.toString() ?? '')
        .join()
        .trim();
    debugPrint('[AI/Gemini] parsed content: "$text"');
    return text;
  }

  // --- Parsing (same rules as the OpenAI backend) ---------------------------

  String? _parseAmount(String content) {
    final normalized = _normalizeNumerals(content);
    final match = RegExp(r'\d[\d,]*(?:\.\d+)?').firstMatch(normalized);
    if (match == null) return null;
    return _cleanNumber(match.group(0)!);
  }

  List<String> _parseAmountList(String content) {
    final normalized = _normalizeNumerals(content);
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

  Future<String?> _imageToBase64(File file) async {
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
      return base64Encode(img.encodeJpg(decoded, quality: 90));
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
