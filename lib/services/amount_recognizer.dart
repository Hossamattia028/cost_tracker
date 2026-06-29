import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import 'ai_amount_service.dart';
import 'amount_ai_client.dart';
import 'gemini_amount_service.dart';
import 'ocr_service.dart';

/// Single entry point for amount recognition.
///
/// Chooses the engine via [AppConstants.amountEngine]:
///   * [AmountEngine.ai] — AI ([AppConstants.aiProvider] = OpenAI or Gemini).
///   * [AmountEngine.localOcr] — the original on-device ML Kit OCR.
class AmountRecognizer {
  AmountRecognizer({OcrService? ocr, AmountAiClient? ai})
      : _ocr = ocr ?? OcrService(),
        _ai = ai ?? _defaultAiClient();

  final OcrService _ocr;
  final AmountAiClient _ai;

  static AmountAiClient _defaultAiClient() {
    switch (AppConstants.aiProvider) {
      case AiProvider.openAi:
        return AiAmountService();
      case AiProvider.gemini:
        return GeminiAmountService();
    }
  }

  Future<String?> fromImage(File file) async {
    final results = await amountsFromImages([file]);
    return results.isEmpty ? null : results.first;
  }

  Future<List<String?>> amountsFromImages(List<File> files) async {
    if (files.isEmpty) return const [];
    if (AppConstants.amountEngine == AmountEngine.localOcr) {
      final results = <String?>[];
      for (final file in files) {
        results.add(await _ocr.extractAmount(file));
      }
      return results;
    }
    if (AppConstants.aiStrictNoFallback) {
      return _ai.amountsFromImages(files);
    }
    try {
      return await _ai.amountsFromImages(files);
    } catch (e) {
      debugPrint('AI batch image recognition failed, falling back to OCR: $e');
    }
    final results = <String?>[];
    for (final file in files) {
      results.add(await _ocr.extractAmount(file));
    }
    return results;
  }

  /// Text-only recognition is AI-only (local OCR cannot read free text).
  Future<String?> fromText(String text) => _ai.fromText(text);

  /// Extracts every transfer amount from a long text/chat block (AI-only).
  Future<List<String>> amountsFromText(String text) =>
      _ai.amountsFromText(text);

  void dispose() => _ai.dispose();
}
