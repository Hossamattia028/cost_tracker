import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../models/account.dart';
import '../models/account_day_summary.dart';
import '../models/app_user.dart';
import '../models/cost_record.dart';
import '../models/pool_transfer.dart';
import 'auth_service.dart';
import 'export_service.dart';
import 'firebase_service.dart';
import 'firestore_helper.dart';
import 'image_api_service.dart';
import 'share_intent_service.dart';

class AppProvider extends ChangeNotifier {
  static const _prefThemeMode = 'theme_mode';
  static const _prefAccountPin = 'account_pin';
  static const _defaultAccountPin = '123';

  AppProvider({
    AuthService? authService,
    FirebaseService? firebaseService,
    ImageApiService? imageApiService,
    ExportService? exportService,
    ShareIntentService? shareIntentService,
  })  : _auth = authService ?? AuthService(),
        _firebase = firebaseService ?? FirebaseService(),
        _imageApi = imageApiService ?? ImageApiService(),
        _export = exportService ?? ExportService(),
        _shareIntent = shareIntentService ?? ShareIntentService();

  final AuthService _auth;
  final FirebaseService _firebase;
  final ImageApiService _imageApi;
  final ExportService _export;
  final ShareIntentService _shareIntent;
  SharedPreferences? _prefs;

  AppUser? _currentUser;
  List<Account> _accounts = [];
  List<CostRecord> _records = [];
  List<AppUser> _users = [];
  bool _loading = false;
  bool _profileLoading = false;
  String? _profileError;
  List<File> _pendingSharedImages = [];
  ThemeMode _themeMode = ThemeMode.system;
  double _globalPoolBalance = 0;
  List<PoolTransfer> _poolTransfers = [];

  StreamSubscription? _accountsSub;
  StreamSubscription? _recordsSub;
  StreamSubscription? _usersSub;
  StreamSubscription? _poolSub;
  StreamSubscription? _poolTransfersSub;
  StreamSubscription? _shareSub;
  StreamSubscription? _authSub;

  AppUser? get currentUser => _currentUser;
  List<Account> get accounts => _visibleAccounts;
  List<CostRecord> get records => _records;
  List<AppUser> get users => _users;
  bool get loading => _loading;
  bool get profileLoading => _profileLoading;
  String? get profileError => _profileError;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  List<File> get pendingSharedImages => _pendingSharedImages;
  ThemeMode get themeMode => _themeMode;
  double get globalPoolBalance => _globalPoolBalance;
  List<PoolTransfer> get poolTransfers => _poolTransfers;
  bool get hasAccountPin => (_prefs?.getString(_prefAccountPin) ?? '').isNotEmpty;

  List<Account> get _visibleAccounts {
    final user = _currentUser;
    if (user == null) return [];
    if (user.isAdmin) return _accounts;
    return _accounts.where((a) => user.canAccessAccount(a.id)).toList();
  }

  Map<String, Account> get accountsById => {
        for (final a in _accounts) a.id: a,
      };

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _themeMode = _themeModeFromString(_prefs?.getString(_prefThemeMode));
    if ((_prefs?.getString(_prefAccountPin) ?? '').isEmpty) {
      await _prefs?.setString(_prefAccountPin, _defaultAccountPin);
    }
    _authSub = _auth.authStateChanges.listen(_onAuthChanged);
    _shareSub = _shareIntent.sharedImages.listen((files) {
      _pendingSharedImages = files;
      notifyListeners();
    });

    try {
      await _shareIntent.init().timeout(const Duration(seconds: 5));
    } catch (_) {}

    // لا نوقف تشغيل التطبيق إذا فشل إنشاء المدير أثناء الإقلاع.
    unawaited(
      _auth.ensureAdminExists().timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      ).catchError((_) {}),
    );
  }

  Future<void> _onAuthChanged(user) async {
    if (user == null) {
      await _accountsSub?.cancel();
      await _recordsSub?.cancel();
      await _usersSub?.cancel();
      await _poolSub?.cancel();
      await _poolTransfersSub?.cancel();
      _currentUser = null;
      _accounts = [];
      _records = [];
      _users = [];
      _globalPoolBalance = 0;
      _poolTransfers = [];
      _profileLoading = false;
      _profileError = null;
      notifyListeners();
      return;
    }

    // بعد تسجيل الدخول الناجح، لا نعيد الجلب ونخرج المستخدم.
    if (_currentUser?.uid == user.uid) {
      _profileLoading = false;
      _profileError = null;
      _attachDataListeners();
      notifyListeners();
      return;
    }

    await _accountsSub?.cancel();
    await _recordsSub?.cancel();
    await _usersSub?.cancel();

    _profileLoading = true;
    _profileError = null;
    notifyListeners();
    try {
      _currentUser = await _auth.getCurrentAppUser();
      if (_currentUser == null) {
        _profileError =
            'لم يتم العثور على ملف المستخدم. تأكد من نشر قواعد Firestore.';
        await _auth.signOut();
        return;
      }
      _attachDataListeners();
    } on FirebaseException catch (e) {
      _profileError = firestoreErrorMessage(e);
      await _auth.signOut();
    } catch (e) {
      _profileError = e.toString();
      await _auth.signOut();
    } finally {
      _profileLoading = false;
      notifyListeners();
    }
  }

  void _attachDataListeners() {
    _accountsSub?.cancel();
    _recordsSub?.cancel();
    _usersSub?.cancel();
    _poolSub?.cancel();
    _poolTransfersSub?.cancel();

    _accountsSub = _firebase.watchAccounts().listen((data) {
      _accounts = data;
      notifyListeners();
    });
    _recordsSub = _firebase.watchRecords().listen((data) {
      _records = data;
      notifyListeners();
      unawaited(_syncMissingImageUrls());
    });
    _poolSub = _firebase.watchGlobalPoolBalance().listen((balance) {
      _globalPoolBalance = balance;
      notifyListeners();
    });
    _poolTransfersSub = _firebase.watchPoolTransfers().listen((data) {
      _poolTransfers = data;
      notifyListeners();
    });
    if (_currentUser?.isAdmin ?? false) {
      _usersSub = _firebase.watchUsers().listen((data) {
        _users = data.where((u) => !u.isAdmin).toList();
        notifyListeners();
      });
    }
  }

  Future<AppUser> signIn(String email, String password) async {
    _loading = true;
    _profileError = null;
    notifyListeners();
    try {
      final user = await _auth.signIn(email, password);
      _currentUser = user;
      _profileError = null;
      _attachDataListeners();
      return user;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> addAccount(Account account) async {
    final id = await _firebase.addAccount(account);
    if (!(_currentUser?.isAdmin ?? false)) return;
    // accounts stream updates automatically
    debugPrint('Account created: $id');
  }

  Future<void> updateAccount(Account account) =>
      _firebase.updateAccount(account);

  Future<void> deleteAccount(String id) async {
    final imageIds = _records
        .where((r) => r.accountId == id)
        .map((r) => r.receiptImageId)
        .whereType<int>()
        .toList();
    await _firebase.deleteAccount(id);
    for (final imageId in imageIds) {
      unawaited(_deleteImageQuietly(imageId));
    }
  }

  Future<double> getTotalForAccount(String accountId) =>
      _firebase.getTotalForAccount(accountId);

  double spentForAccount(String accountId) => _records
      .where((r) => r.accountId == accountId)
      .fold(0, (totalSpent, r) => totalSpent + r.amount);

  double spentForAccountBefore(String accountId, DateTime before) => _records
      .where((r) => r.accountId == accountId && r.createdAt.isBefore(before))
      .fold(0, (totalSpent, r) => totalSpent + r.amount);

  double spentForAccountBetween(
    String accountId,
    DateTime start,
    DateTime end,
  ) =>
      _records
          .where(
            (r) =>
                r.accountId == accountId &&
                !r.createdAt.isBefore(start) &&
                r.createdAt.isBefore(end),
          )
          .fold(0, (totalSpent, r) => totalSpent + r.amount);

  double todaySpentForAccount(String accountId) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return spentForAccountBetween(accountId, start, end);
  }

  double remainingForAccount(Account account) =>
      account.totalBalance - spentForAccount(account.id);

  double todayOpeningForAccount(Account account) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    return account.totalBalance - spentForAccountBefore(account.id, startOfToday);
  }

  double todayRemainingForAccount(Account account) {
    final now = DateTime.now();
    final endOfToday =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    return account.totalBalance - spentForAccountBefore(account.id, endOfToday);
  }

  AccountDaySummary accountSummaryForRange(
    Account account,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final opening =
        account.totalBalance - spentForAccountBefore(account.id, rangeStart);
    final withdrawn = spentForAccountBetween(account.id, rangeStart, rangeEnd);
    final remaining =
        account.totalBalance - spentForAccountBefore(account.id, rangeEnd);
    return AccountDaySummary(
      accountId: account.id,
      accountName: account.name,
      currency: account.currency,
      opening: opening,
      withdrawn: withdrawn,
      remaining: remaining,
    );
  }

  List<AccountDaySummary> summariesForDateRange({
    required DateTime from,
    required DateTime to,
    String? accountId,
  }) {
    final start = _startOfDay(from);
    final end = _endExclusiveForRange(from, to);
    final accounts = accountId == null
        ? this.accounts
        : this.accounts.where((a) => a.id == accountId).toList();
    return accounts
        .map((a) => accountSummaryForRange(a, start, end))
        .toList();
  }

  static DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime _endExclusiveForRange(DateTime from, DateTime to) {
    final start = _startOfDay(from);
    final endDay = _startOfDay(to);
    if (endDay.isBefore(start)) {
      return start.add(const Duration(days: 1));
    }
    return endDay.add(const Duration(days: 1));
  }

  List<CostRecord> getFilteredRecordsByRange({
    required DateTime from,
    required DateTime to,
    String? accountId,
  }) {
    final start = _startOfDay(from);
    final end = _endExclusiveForRange(from, to);
    return _records.where((record) {
      if (accountId != null && record.accountId != accountId) return false;
      if (!(_currentUser?.canAccessAccount(record.accountId) ?? false)) {
        return false;
      }
      return !record.createdAt.isBefore(start) && record.createdAt.isBefore(end);
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<AccountDaySummary> summariesForPeriod({
    required ReportPeriod period,
    String? accountId,
  }) {
    final range = _periodRange(period);
    final accounts = accountId == null
        ? this.accounts
        : this.accounts.where((a) => a.id == accountId).toList();
    return accounts
        .map(
          (a) => accountSummaryForRange(a, range.start, range.end),
        )
        .toList();
  }

  ({DateTime start, DateTime end}) _periodRange(ReportPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case ReportPeriod.day:
        final start = DateTime(now.year, now.month, now.day);
        return (start: start, end: start.add(const Duration(days: 1)));
      case ReportPeriod.week:
        final start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return (start: start, end: start.add(const Duration(days: 7)));
      case ReportPeriod.month:
        final start = DateTime(now.year, now.month, 1);
        return (start: start, end: DateTime(now.year, now.month + 1, 1));
    }
  }

  Future<void> refreshData() async {
    if (_currentUser == null) return;
    final results = await Future.wait([
      _firebase.fetchAccounts(),
      _firebase.fetchRecords(),
      _firebase.getGlobalPoolBalance(),
      _firebase.fetchPoolTransfers(),
    ]);
    _accounts = results[0] as List<Account>;
    _records = results[1] as List<CostRecord>;
    _globalPoolBalance = results[2] as double;
    _poolTransfers = results[3] as List<PoolTransfer>;
    notifyListeners();
  }

  Future<void> addToGlobalPool(double amount) async {
    if (amount <= 0) throw ArgumentError('Amount must be positive');
    final previous = _globalPoolBalance;
    _globalPoolBalance += amount;
    notifyListeners();
    try {
      await _firebase.adjustGlobalPoolBalance(amount);
    } catch (e) {
      _globalPoolBalance = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _deductFromPoolAndLog({
    required double amount,
    required String accountId,
    required String accountName,
    required String recordId,
  }) async {
    if (amount <= 0) return;
    if (_globalPoolBalance < amount) {
      throw StateError('الرصيد الكلي العام غير كافٍ');
    }
    final previous = _globalPoolBalance;
    _globalPoolBalance -= amount;
    notifyListeners();
    try {
      await _firebase.adjustGlobalPoolBalance(-amount);
      await _firebase.addPoolTransfer(
        PoolTransfer(
          id: '',
          amount: amount,
          accountId: accountId,
          accountName: accountName,
          createdAt: DateTime.now(),
          createdBy: _currentUser?.uid ?? '',
          recordId: recordId,
        ),
      );
    } catch (e) {
      _globalPoolBalance = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _refundPoolForRecords(Iterable<String> recordIds) async {
    final idSet = recordIds.toSet();
    final transfers =
        _poolTransfers.where((t) => idSet.contains(t.recordId)).toList();
    var refund = 0.0;
    for (final transfer in transfers) {
      refund += transfer.amount;
    }
    if (refund <= 0) {
      await _firebase.deletePoolTransfersByRecordIds(idSet.toList());
      return;
    }
    final previous = _globalPoolBalance;
    _globalPoolBalance += refund;
    notifyListeners();
    try {
      await _firebase.adjustGlobalPoolBalance(refund);
      await _firebase.deletePoolTransfersByRecordIds(idSet.toList());
    } catch (e) {
      _globalPoolBalance = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs?.setString(_prefThemeMode, mode.name);
    notifyListeners();
  }

  Future<void> setAccountPin(String pin) async {
    final trimmed = pin.trim();
    if (trimmed.isEmpty) {
      await _prefs?.remove(_prefAccountPin);
    } else {
      await _prefs?.setString(_prefAccountPin, trimmed);
    }
    notifyListeners();
  }

  Future<bool> changeAccountPin({
    required String currentPin,
    required String newPin,
  }) async {
    final saved = _prefs?.getString(_prefAccountPin) ?? _defaultAccountPin;
    if (saved.isNotEmpty && saved != currentPin.trim()) return false;
    await setAccountPin(newPin);
    return true;
  }

  bool verifyAccountPin(String pin) {
    final saved = _prefs?.getString(_prefAccountPin) ?? _defaultAccountPin;
    if (saved.isEmpty) return true;
    return saved == pin.trim();
  }

  ThemeMode _themeModeFromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> addRecordsBatch({
    required String accountId,
    required List<File> images,
    required List<double> amounts,
    String? note,
    required DateTime createdAt,
  }) async {
    final user = _currentUser;
    if (user == null) throw StateError('Not signed in');

    _loading = true;
    notifyListeners();
    try {
      final account = accountsById[accountId];
      if (account == null) throw StateError('Account not found');
      final totalAmount = amounts.fold<double>(0, (s, a) => s + a);
      if (_globalPoolBalance < totalAmount) {
        throw StateError('الرصيد الكلي العام غير كافٍ');
      }

      final records = List.generate(
        images.length,
        (i) => CostRecord(
          id: '',
          accountId: accountId,
          amount: amounts[i],
          note: note,
          imageUrl: '',
          createdAt: createdAt,
          createdBy: user.uid,
        ),
      );
      final ids = await _firebase.addRecords(records);
      for (var i = 0; i < ids.length; i++) {
        await _deductFromPoolAndLog(
          amount: amounts[i],
          accountId: accountId,
          accountName: account.name,
          recordId: ids[i],
        );
      }
      for (var i = 0; i < images.length; i++) {
        unawaited(_uploadAndLinkImage(ids[i], images[i]));
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Adds a text-based record (no image). Used by the "نص" mode where the
  /// amount is recognized from typed/pasted text.
  Future<void> addManualRecord({
    required String accountId,
    required double amount,
    String? note,
    required DateTime createdAt,
  }) =>
      addManualRecords(
        accountId: accountId,
        amounts: [amount],
        note: note,
        createdAt: createdAt,
      );

  /// Adds several text-based records at once (no images) — e.g. all the
  /// transfers parsed from a single chat/summary for a customer.
  Future<void> addManualRecords({
    required String accountId,
    required List<double> amounts,
    String? note,
    required DateTime createdAt,
  }) async {
    final user = _currentUser;
    if (user == null) throw StateError('Not signed in');
    if (amounts.isEmpty) return;

    _loading = true;
    notifyListeners();
    try {
      final account = accountsById[accountId];
      if (account == null) throw StateError('Account not found');
      final totalAmount = amounts.fold<double>(0, (s, a) => s + a);
      if (_globalPoolBalance < totalAmount) {
        throw StateError('الرصيد الكلي العام غير كافٍ');
      }

      final records = [
        for (final amount in amounts)
          CostRecord(
            id: '',
            accountId: accountId,
            amount: amount,
            note: note,
            imageUrl: '',
            createdAt: createdAt,
            createdBy: user.uid,
          ),
      ];
      final ids = await _firebase.addRecords(records);
      for (var i = 0; i < ids.length; i++) {
        await _deductFromPoolAndLog(
          amount: amounts[i],
          accountId: accountId,
          accountName: account.name,
          recordId: ids[i],
        );
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _uploadAndLinkImage(String recordId, File image) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final uploaded = await _imageApi.uploadImage(image);
        await _firebase.linkRecordImage(
          recordId: recordId,
          receiptImageId: uploaded.id,
          imageUrl: uploaded.url,
        );
        debugPrint('Saved image URL to Firestore for $recordId: ${uploaded.url}');
        return;
      } catch (e, st) {
        debugPrint(
          'Image upload/link attempt $attempt failed for $recordId: $e\n$st',
        );
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
  }

  Future<void> _syncMissingImageUrls() async {
    for (final record in _records) {
      final imageId = record.receiptImageId;
      if (imageId == null || record.imageUrl.isNotEmpty) continue;
      unawaited(_fetchAndSaveImageUrl(record.id, imageId));
    }
  }

  Future<void> _fetchAndSaveImageUrl(String recordId, int imageId) async {
    try {
      final url = await _imageApi.getImageUrl(imageId);
      await _firebase.linkRecordImage(
        recordId: recordId,
        receiptImageId: imageId,
        imageUrl: url,
      );
      debugPrint('Backfilled image URL to Firestore for $recordId: $url');
    } catch (e, st) {
      debugPrint('Failed to backfill image URL for $recordId: $e\n$st');
    }
  }

  Future<void> _deleteImageQuietly(int imageId) async {
    try {
      await _imageApi.deleteImage(imageId);
    } catch (e, st) {
      debugPrint('Image delete failed for id $imageId: $e\n$st');
    }
  }

  Future<void> deleteRecord(String id) async {
    int? imageId;
    for (final record in _records) {
      if (record.id == id) {
        imageId = record.receiptImageId;
        break;
      }
    }
    await _firebase.deleteRecord(id);
    await _refundPoolForRecords([id]);
    if (imageId != null) {
      unawaited(_deleteImageQuietly(imageId));
    }
  }

  Future<void> deleteRecords(
    Iterable<String> ids, {
    bool refundPool = true,
  }) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final imageIds = _records
        .where((r) => idSet.contains(r.id))
        .map((r) => r.receiptImageId)
        .whereType<int>()
        .toList();
    await _firebase.deleteRecords(idSet.toList());
    if (refundPool) {
      await _refundPoolForRecords(idSet);
    }
    for (final imageId in imageIds) {
      unawaited(_deleteImageQuietly(imageId));
    }
  }

  Future<void> deleteAllRecordsForAccount(String accountId) {
    final ids = _records
        .where((r) => r.accountId == accountId)
        .map((r) => r.id)
        .toList();
    return deleteRecords(ids);
  }

  Future<void> resetAccount(String accountId) async {
    final account = accountsById[accountId];
    if (account == null) return;
    final remaining = remainingForAccount(account);
    final ids = _records
        .where((r) => r.accountId == accountId)
        .map((r) => r.id)
        .toList();
    await deleteRecords(ids, refundPool: false);
    await updateAccount(
      account.copyWith(
        totalBalance: remaining,
        openingBalance: remaining,
      ),
    );
  }

  Future<void> updateRecordDate(String recordId, DateTime createdAt) async {
    final normalized = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final index = _records.indexWhere((r) => r.id == recordId);
    CostRecord? previous;
    if (index >= 0) {
      previous = _records[index];
      _records[index] = previous.copyWith(createdAt: normalized);
      notifyListeners();
    }
    try {
      await _firebase.updateRecord(recordId, {
        'createdAt': Timestamp.fromDate(normalized),
      });
    } catch (e) {
      if (previous != null && index >= 0) {
        _records[index] = previous;
        notifyListeners();
      }
      rethrow;
    }
  }

  List<CostRecord> getFilteredRecords({
    required ReportPeriod period,
    String? accountId,
  }) {
    final now = DateTime.now();
    late DateTime start;
    late DateTime end;

    switch (period) {
      case ReportPeriod.day:
        start = DateTime(now.year, now.month, now.day);
        end = start.add(const Duration(days: 1));
      case ReportPeriod.week:
        start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        end = start.add(const Duration(days: 7));
      case ReportPeriod.month:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 1);
    }

    return _records.where((record) {
      if (accountId != null && record.accountId != accountId) return false;
      if (!(_currentUser?.canAccessAccount(record.accountId) ?? false)) {
        return false;
      }
      return !record.createdAt.isBefore(start) && record.createdAt.isBefore(end);
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> exportFilteredRecords({
    required List<CostRecord> records,
    required String periodLabel,
  }) =>
      _export.exportRecordsCsv(
        records: records,
        accountsById: accountsById,
        periodLabel: periodLabel,
      );

  Future<void> createUser({
    required String name,
    required String email,
    required String password,
    required List<String> allowedAccountIds,
  }) =>
      _auth.createUser(
        name: name,
        email: email,
        password: password,
        allowedAccountIds: allowedAccountIds,
      );

  Future<void> deleteUser(String uid) => _auth.deleteUser(uid);

  void clearPendingSharedImages() {
    _pendingSharedImages = [];
    _shareIntent.resetInitial();
    notifyListeners();
  }

  @override
  void dispose() {
    _accountsSub?.cancel();
    _recordsSub?.cancel();
    _usersSub?.cancel();
    _poolSub?.cancel();
    _poolTransfersSub?.cancel();
    _shareSub?.cancel();
    _authSub?.cancel();
    _shareIntent.dispose();
    _imageApi.dispose();
    super.dispose();
  }
}
