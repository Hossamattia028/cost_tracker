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
    if (AppConstants.amountEngine == AmountEngine.localOcr) {
      return _ocr.extractAmount(file);
    }
    // Strict mode: AI only. Errors propagate so the UI can flag the item
    // instead of silently saving a wrong number from a heuristic fallback.
    if (AppConstants.aiStrictNoFallback) {
      return _ai.fromImage(file);
    }
    try {
      final result = await _ai.fromImage(file);
      if (result != null) return result;
    } catch (e) {
      debugPrint('AI image recognition failed, falling back to OCR: $e');
    }
    return _ocr.extractAmount(file);
  }

  /// Text-only recognition is AI-only (local OCR cannot read free text).
  Future<String?> fromText(String text) => _ai.fromText(text);

  /// Extracts every transfer amount from a long text/chat block (AI-only).
  Future<List<String>> amountsFromText(String text) =>
      _ai.amountsFromText(text);

  void dispose() => _ai.dispose();
}
