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


  static const bool aiStrictNoFallback = true;

  // --- OpenAI ----------------------------------------------------------------
  static const openAiBaseUrl = 'https://api.openai.com/v1/chat/completions';
  static const openAiModel = 'gemini-2.5-flash';


  static String get openAiApiKey => Secrets.openAiApiKey;

  // --- Google Gemini ---------------------------------------------------------
  /// Generative Language API host. The model + key are appended at call time.
  static const geminiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  /// Free-tier models tried in order. Each has its own quota; on 429 the next
  /// model (or API key) is used automatically before failing the request.
  static const geminiModels = [
    'gemini-flash-latest',
    'gemini-2.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemini-2.5-flash',
    'gemini-3.5-flash',
  ];

  static const geminiModel = 'gemini-flash-latest';

  static List<String> get geminiApiKeys => Secrets.geminiApiKeys;

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
