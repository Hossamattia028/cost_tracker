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

  Uri _endpointFor(String model) => Uri.parse(
        '${AppConstants.geminiBaseUrl}/$model:generateContent',
      );

  Map<String, String> _headers(String apiKey) => {
        'Content-Type': 'application/json',
        'X-goog-api-key': apiKey,
      };

  @override
  Future<String?> fromText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final content = await _generate(
      system: kAmountSystemPrompt,
      parts: [
        {'text': 'Extract the total (إجمالي) amount from this text:\n$trimmed'}
      ],
      maxTokens: 256,
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
    final results = await amountsFromImages([file]);
    return results.isEmpty ? null : results.first;
  }

  @override
  Future<List<String?>> amountsFromImages(List<File> files) async {
    if (files.isEmpty) return const [];

    final parts = <Map<String, dynamic>>[
      {
        'text':
            'Read each receipt image below and return the total (إجمالي) '
            'transfer amount for each image, in order. '
            '${files.length} image(s) provided.',
      },
    ];
    for (final file in files) {
      final base64Data = await _imageToBase64(file);
      if (base64Data == null) continue;
      parts.add({
        'inline_data': {'mime_type': 'image/jpeg', 'data': base64Data},
      });
    }
    if (parts.length == 1) {
      return List<String?>.filled(files.length, null);
    }

    final content = await _generate(
      system: kAmountMultiImageSystemPrompt,
      parts: parts,
      maxTokens: math.max(256, files.length * 64),
    );
    return _parseNullableAmountList(content, expectedLength: files.length);
  }

  Future<String> _generate({
    required String system,
    required List<Map<String, dynamic>> parts,
    required int maxTokens,
  }) async {
    final keys = AppConstants.geminiApiKeys.where((k) => k.isNotEmpty).toList();
    if (keys.isEmpty) {
      throw Exception('Gemini API key is not configured');
    }

    Exception? lastError;
    for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
      final apiKey = keys[keyIndex];
      final keyLabel = 'key${keyIndex + 1}';

      for (final model in AppConstants.geminiModels) {
        debugPrint('[AI/Gemini] → $model ($keyLabel)');
        final response = await _client
            .post(
              _endpointFor(model),
              headers: _headers(apiKey),
              body: jsonEncode({
                'system_instruction': {
                  'parts': [
                    {'text': system}
                  ]
                },
                'contents': [
                  {'role': 'user', 'parts': parts}
                ],
                'generationConfig': _generationConfig(model, maxTokens),
              }),
            )
            .timeout(const Duration(seconds: 90));

        final body = utf8.decode(response.bodyBytes);
        debugPrint('[AI/Gemini] ← status=${response.statusCode} ($model, $keyLabel)');
        debugPrint('[AI/Gemini] ← body=$body');

        if (response.statusCode == 429 ||
            response.statusCode == 503 ||
            response.statusCode == 403) {
          lastError = Exception(
            'Gemini unavailable ($model, $keyLabel, ${response.statusCode}): $body',
          );
          debugPrint(
            '[AI/Gemini] ${response.statusCode} on $model ($keyLabel), trying next...',
          );
          continue;
        }
        if (response.statusCode == 404) {
          lastError = Exception('Gemini model not found ($model): $body');
          debugPrint('[AI/Gemini] $model unavailable, trying next model...');
          continue;
        }
        if (response.statusCode != 200) {
          throw Exception(
            'Gemini request failed (${response.statusCode}): $body',
          );
        }

        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final candidates = decoded['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) {
          lastError = Exception('Gemini returned no candidates ($model, $keyLabel)');
          debugPrint('[AI/Gemini] empty candidates on $model ($keyLabel), trying next...');
          continue;
        }
        final contentParts =
            (candidates.first['content']?['parts'] as List?) ?? [];
        final text = contentParts
            .map((p) => (p as Map)['text']?.toString() ?? '')
            .join()
            .trim();
        if (text.isEmpty) {
          lastError = Exception('Gemini returned empty text ($model, $keyLabel)');
          debugPrint('[AI/Gemini] empty response on $model ($keyLabel), trying next...');
          continue;
        }
        debugPrint('[AI/Gemini] parsed content ($model, $keyLabel): "$text"');
        return text;
      }

      if (keyIndex < keys.length - 1) {
        debugPrint('[AI/Gemini] all models rate-limited on $keyLabel, switching key...');
      }
    }

    throw lastError ??
        Exception(
          'All Gemini keys and models are rate-limited. Try again later.',
        );
  }

  Map<String, dynamic> _generationConfig(String model, int maxTokens) {
    return {
      'temperature': 0,
      'maxOutputTokens': maxTokens,
      // Gemini 2.5+ and 3.x models "think" by default and spend the output
      // budget on hidden reasoning (e.g. gemini-flash-latest → 3.5-flash).
      // Without this, text extraction returns truncated garbage like "[".
      'thinkingConfig': {'thinkingBudget': 0},
    };
  }

  // --- Parsing (same rules as the OpenAI backend) ---------------------------

  String? _parseAmount(String content) {
    final normalized = _normalizeNumerals(content);
    final match = RegExp(r'\d[\d,]*(?:\.\d+)?').firstMatch(normalized);
    if (match == null) return null;
    return _cleanNumber(match.group(0)!);
  }

  List<String> _parseAmountList(String content) {
    return _parseNullableAmountList(content)
        .whereType<String>()
        .toList(growable: false);
  }

  List<String?> _parseNullableAmountList(
    String content, {
    int? expectedLength,
  }) {
    final normalized = _normalizeNumerals(content);
    final start = normalized.indexOf('[');
    final end = normalized.lastIndexOf(']');
    final slice = (start != -1 && end > start)
        ? normalized.substring(start, end + 1)
        : normalized;

    final results = <String?>[];
    List<dynamic>? parsed;
    try {
      final decoded = jsonDecode(slice);
      if (decoded is List) parsed = decoded;
    } catch (_) {}

    if (parsed != null) {
      for (final item in parsed) {
        if (item == null) {
          results.add(null);
          continue;
        }
        results.add(_cleanNumber(item.toString()));
      }
    } else {
      for (final m in RegExp(r'\d[\d,]*(?:\.\d+)?').allMatches(slice)) {
        results.add(_cleanNumber(m.group(0)!));
      }
    }

    if (expectedLength == null) return results;
    while (results.length < expectedLength) {
      results.add(null);
    }
    if (results.length > expectedLength) {
      return results.sublist(0, expectedLength);
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
