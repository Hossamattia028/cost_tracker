import 'secrets.dart';

class AppConstants {
  static const adminEmail = 'admin@costtracker.com';
  static const adminPassword = 'Admin@123456';
  static const defaultCurrency = 'EGP';

  /// Cost Tracker API host (working Postman base URL).
  static const costTrackerBaseUrl = 'https://costtracker.elearn-acadmy.com';

  /// POST/GET /api/images
  static const imageApiBaseUrl = '$costTrackerBaseUrl/api';

  // ---------------------------------------------------------------------------
  // Amount recognition engine
  //
  // Switch [amountEngine] to [AmountEngine.localOcr] to fully revert to the old
  // on-device ML Kit OCR. [AmountEngine.ai] uses OpenAI (image + text) and falls
  // back to local OCR automatically if the AI call fails.
  // ---------------------------------------------------------------------------
  static const AmountEngine amountEngine = AmountEngine.ai;

  /// Which AI backend to use when [amountEngine] is [AmountEngine.ai].
  ///   * [AiProvider.openAi] — OpenAI (requires a funded key).
  ///   * [AiProvider.gemini] — Google Gemini (free tier from Google AI Studio).
  static const AiProvider aiProvider = AiProvider.gemini;

  /// When true, the AI engine never falls back to local OCR. A failed/uncertain
  /// read surfaces an error instead of saving a possibly-wrong number.
  static const bool aiStrictNoFallback = true;

  // --- OpenAI ----------------------------------------------------------------
  static const openAiBaseUrl = 'https://api.openai.com/v1/chat/completions';
  static const openAiModel = 'gpt-4o';

  /// Set in `lib/core/secrets.dart` (copy from `secrets.example.dart`).
  static String get openAiApiKey => Secrets.openAiApiKey;

  // --- Google Gemini ---------------------------------------------------------
  /// Generative Language API host. The model + key are appended at call time.
  static const geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Vision-capable, fast, with a free tier (this key's working model).
  static const geminiModel = 'gemini-2.5-flash';

  /// Set in `lib/core/secrets.dart` (copy from `secrets.example.dart`).
  static String get geminiApiKey => Secrets.geminiApiKey;
}

enum AmountEngine { ai, localOcr }

enum AiProvider { openAi, gemini }

enum UserRole { admin, user }

extension UserRoleX on UserRole {
  String get firestoreValue => name;

  static UserRole fromString(String? value) {
    if (value == UserRole.admin.name) return UserRole.admin;
    return UserRole.user;
  }
}

enum ReportPeriod { day, week, month }

extension ReportPeriodX on ReportPeriod {
  String get labelAr {
    switch (this) {
      case ReportPeriod.day:
        return 'اليوم';
      case ReportPeriod.week:
        return 'الأسبوع';
      case ReportPeriod.month:
        return 'الشهر';
    }
  }
}
