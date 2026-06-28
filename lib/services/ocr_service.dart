import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// Extracts the receipt total amount.
///
/// Receipts put the total on a line that (reading from the right in Arabic)
/// starts with a total keyword such as «إجمالي / الإجمالي / اجمالي» and shows
/// the value on the other side, e.g. «2384 .ج.م».
///
/// Accuracy strategy (slower but reliable — runs per image):
///   PASS 1: OCR the full image, locate the total row using:
///       1. a line containing a total keyword,
///       2. else a line containing the currency token (ج.م / جم / EGP / L.E),
///       3. else the number rendered in the largest font.
///   PASS 2 (verification): crop the located row, upscale it ~3x and OCR again.
///       Higher resolution of just that row stops digit loss (e.g. 2000→200).
/// Phone numbers, IDs, dates and times are filtered out.
class OcrService {
  static const _totalKeywords = ['جمال', 'اجمال', 'إجمال'];
  static final _currencyRegExp =
      RegExp(r'ج\s*\.?\s*م|\bجم\b|egp|l\.?\s*e', caseSensitive: false);
  static final _timeRegExp = RegExp(r'\d{1,2}\s*:\s*\d{2}');
  static final _dateRegExp = RegExp(r'\d{2,4}\s*-\s*\d{1,2}\s*-\s*\d{1,4}');
  static final _maskRegExp = RegExp(r'[xX*]{2,}');
  static final _numberRegExp = RegExp(r'\d[\d.,]*');

  Future<String?> extractAmount(File imageFile) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final lines = await _recognizeLines(imageFile, recognizer);
      if (lines.isEmpty) return null;

      final best = _bestTotalLine(lines);
      if (best == null) return null;

      // PASS 2: verify by re-reading an upscaled crop of that row.
      final verified = await _verifyByCrop(imageFile, best.rect, recognizer);

      // Prefer whichever read has more digits (recovers dropped zeros),
      // breaking ties in favour of the higher-resolution crop.
      return _pickMoreReliable(best.value, verified);
    } catch (_) {
      return null;
    } finally {
      await recognizer.close();
    }
  }

  String _pickMoreReliable(String pass1, String? crop) {
    if (crop == null) return pass1;
    final d1 = pass1.replaceAll(RegExp(r'\D'), '').length;
    final d2 = crop.replaceAll(RegExp(r'\D'), '').length;
    if (d2 > d1) return crop;
    if (d1 > d2) return pass1;
    return crop;
  }

  Future<List<_OcrLine>> _recognizeLines(
    File file,
    TextRecognizer recognizer,
  ) async {
    final recognized =
        await recognizer.processImage(InputImage.fromFile(file));
    final lines = <_OcrLine>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;
        lines.add(
          _OcrLine(
            raw: text,
            normalized: _normalizeNumerals(text),
            height: line.boundingBox.height.toDouble(),
            rect: line.boundingBox,
          ),
        );
      }
    }
    return lines;
  }

  /// Locates the total row and returns its value + bounding box.
  ///
  /// The keyword «إجمالي» and the value «1000 .ج.م» are usually detected as two
  /// separate lines on the same row, so we anchor spatially: a number sharing
  /// the keyword's (or currency's) row wins. Otherwise the total is the largest
  /// amount-like number on the receipt (phones/IDs/dates are filtered out).
  _TotalCandidate? _bestTotalLine(List<_OcrLine> lines) {
    final keywordRects = [
      for (final l in lines)
        if (_containsKeyword(l.raw)) l.rect,
    ];
    final currencyRects = [
      for (final l in lines)
        if (_currencyRegExp.hasMatch(l.raw)) l.rect,
    ];

    _TotalCandidate? best;
    double bestScore = -1;
    for (final line in lines) {
      if (_isJunkLine(line.normalized)) continue;
      final value = _bestNumberInLine(line.normalized);
      if (value == null) continue;
      final numeric = double.tryParse(value) ?? 0;
      if (numeric <= 0) continue;

      final onKeywordRow = _containsKeyword(line.raw) ||
          keywordRects.any((r) => _sameRow(r, line.rect));
      final onCurrencyRow = _currencyRegExp.hasMatch(line.raw) ||
          currencyRects.any((r) => _sameRow(r, line.rect));

      // Value dominates among unanchored numbers; row anchoring overrides it.
      var score = numeric;
      if (onKeywordRow) score += 1e12;
      if (onCurrencyRow) score += 1e9;
      if (value.contains('.')) score += 1e3;

      if (score > bestScore) {
        bestScore = score;
        best = _TotalCandidate(value: value, rect: line.rect);
      }
    }
    return best;
  }

  bool _sameRow(Rect a, Rect b) {
    final top = math.max(a.top, b.top);
    final bottom = math.min(a.bottom, b.bottom);
    final overlap = bottom - top;
    if (overlap <= 0) return false;
    final minH = math.min(a.height, b.height);
    return minH > 0 && overlap / minH >= 0.4;
  }

  /// Crops the total row, upscales it, and re-runs OCR for a sharper read.
  Future<String?> _verifyByCrop(
    File file,
    Rect rect,
    TextRecognizer recognizer,
  ) async {
    File? tempFile;
    try {
      final bytes = await file.readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      decoded = img.bakeOrientation(decoded);

      final h = decoded.height;
      final padV = (rect.height * 0.6).round();
      final top = math.max(0, rect.top.round() - padV);
      final bottom = math.min(h, rect.bottom.round() + padV);
      final bandHeight = bottom - top;
      if (bandHeight <= 0) return null;

      // Full-width band keeps every digit of the row.
      var band = img.copyCrop(
        decoded,
        x: 0,
        y: top,
        width: decoded.width,
        height: bandHeight,
      );

      // Upscale ~3x (capped) so small digits become legible to ML Kit.
      final targetWidth = math.min(decoded.width * 3, 2400);
      if (targetWidth > band.width) {
        band = img.copyResize(
          band,
          width: targetWidth,
          interpolation: img.Interpolation.cubic,
        );
      }

      final dir = await getTemporaryDirectory();
      tempFile = File(
        '${dir.path}/ocr_crop_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(img.encodeJpg(band, quality: 100));

      final cropLines = await _recognizeLines(tempFile, recognizer);
      return _bestFromCrop(cropLines);
    } catch (_) {
      return null;
    } finally {
      if (tempFile != null && tempFile.existsSync()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  /// In the cropped row, prefer keyword/currency number; else the number with
  /// the most digits (avoids dropped zeros), breaking ties by larger value.
  String? _bestFromCrop(List<_OcrLine> lines) {
    for (final test in [
      (_OcrLine l) => _containsKeyword(l.raw),
      (_OcrLine l) => _currencyRegExp.hasMatch(l.raw),
    ]) {
      for (final line in lines) {
        if (!test(line)) continue;
        final value = _bestNumberInLine(line.normalized);
        if (value != null) return value;
      }
    }

    String? best;
    int bestDigits = -1;
    double bestValue = -1;
    for (final line in lines) {
      if (_isJunkLine(line.normalized)) continue;
      final value = _bestNumberInLine(line.normalized);
      if (value == null) continue;
      final digits = value.replaceAll(RegExp(r'\D'), '').length;
      final numeric = double.tryParse(value) ?? 0;
      if (digits > bestDigits ||
          (digits == bestDigits && numeric > bestValue)) {
        bestDigits = digits;
        bestValue = numeric;
        best = value;
      }
    }
    return best;
  }

  bool _containsKeyword(String raw) {
    final letters = _normalizeArabic(raw);
    return _totalKeywords.any(letters.contains);
  }

  bool _isJunkLine(String normalized) {
    if (_timeRegExp.hasMatch(normalized)) return true;
    if (_dateRegExp.hasMatch(normalized)) return true;
    if (_maskRegExp.hasMatch(normalized)) return true;
    for (final m in RegExp(r'\d+').allMatches(normalized)) {
      final digits = m.group(0)!;
      if (digits.length >= 8) return true;
      if (digits.length >= 5 && digits.startsWith('0')) return true;
    }
    return false;
  }

  /// Picks the most amount-like number from a single line.
  String? _bestNumberInLine(String normalized) {
    String? best;
    double bestScore = -1;
    for (final match in _numberRegExp.allMatches(normalized)) {
      final raw = match.group(0)!;
      final cleaned = _cleanNumber(raw);
      final value = double.tryParse(cleaned);
      if (value == null || value <= 0) continue;

      final digitsOnly = cleaned.replaceAll('.', '');
      if (digitsOnly.length >= 8) continue;
      if (digitsOnly.length >= 5 && digitsOnly.startsWith('0')) continue;

      var score = value;
      if (raw.contains('.') || raw.contains(',')) score += 100000;
      if (value >= 10) score += 1000;

      if (score > bestScore) {
        bestScore = score;
        best = cleaned;
      }
    }
    return best;
  }

  /// Treats commas/dots as thousands separators unless they look decimal.
  String _cleanNumber(String raw) {
    var s = raw;
    final decimal = RegExp(r'[.,](\d{1,2})$').firstMatch(s);
    String? fraction;
    if (decimal != null) {
      fraction = decimal.group(1);
      s = s.substring(0, decimal.start);
    }
    s = s.replaceAll(RegExp(r'[.,]'), '');
    return fraction != null ? '$s.$fraction' : s;
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

  /// Normalizes Arabic letters for keyword matching.
  String _normalizeArabic(String text) {
    final buf = StringBuffer();
    for (final ch in text.runes) {
      if (ch == 0x0623 || ch == 0x0625 || ch == 0x0622 || ch == 0x0671) {
        buf.writeCharCode(0x0627); // أ إ آ ٱ -> ا
      } else if (ch == 0x0649) {
        buf.writeCharCode(0x064A); // ى -> ي
      } else if (ch == 0x0629) {
        buf.writeCharCode(0x0647); // ة -> ه
      } else if (ch >= 0x0621 && ch <= 0x064A) {
        buf.writeCharCode(ch);
      }
    }
    return buf.toString();
  }
}

class _OcrLine {
  final String raw;
  final String normalized;
  final double height;
  final Rect rect;

  const _OcrLine({
    required this.raw,
    required this.normalized,
    required this.height,
    required this.rect,
  });
}

class _TotalCandidate {
  final String value;
  final Rect rect;

  const _TotalCandidate({required this.value, required this.rect});
}
