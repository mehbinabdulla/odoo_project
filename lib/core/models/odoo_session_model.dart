import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure-storage keys for secrets. Non-secrets stay in SharedPreferences.
class OdooSessionModel {
  static const _secureStorage = FlutterSecureStorage();
  static const secureKeySessionId = 'sessionId';
  static const secureKeyPassword = 'password';
  final String sessionId;
  final String userLogin;
  final String password;
  final String serverUrl;
  final String database;
  final int? userId;
  final String? userName;
  final DateTime? expiresAt;
  final int? selectedCompanyId;
  final List<int> allowedCompanyIds;
  final String? serverVersion;

  OdooSessionModel({
    required this.sessionId,
    required this.userLogin,
    required this.password,
    required this.serverUrl,
    required this.database,
    this.userId,
    this.userName,
    this.expiresAt,
    this.selectedCompanyId,
    this.allowedCompanyIds = const [],
    this.serverVersion,
  });

  int get majorVersion {
    if (serverVersion == null || serverVersion!.isEmpty) return 15;
    try {
      final v = serverVersion!.split('.').first;
      return int.parse(v);
    } catch (_) {
      return 15;
    }
  }

  OdooSession get odooSession {
    return OdooSession(
      id: sessionId,
      userId: userId ?? 0,
      partnerId: 0,
      userLogin: userLogin,
      userName: userName ?? '',
      userLang: '',
      userTz: '',
      isSystem: false,
      dbName: database,
      serverVersion: serverVersion ?? '',
      companyId: selectedCompanyId ?? 0,
      allowedCompanies: allowedCompanyIds
          .map((id) => Company(id: id, name: 'Company $id'))
          .toList(),
    );
  }

  OdooSessionModel copyWith({
    String? sessionId,
    String? userLogin,
    String? password,
    String? serverUrl,
    String? database,
    int? userId,
    String? userName,
    DateTime? expiresAt,
    int? selectedCompanyId,
    List<int>? allowedCompanyIds,
    String? serverVersion,
  }) {
    return OdooSessionModel(
      sessionId: sessionId ?? this.sessionId,
      userLogin: userLogin ?? this.userLogin,
      password: password ?? this.password,
      serverUrl: serverUrl ?? this.serverUrl,
      database: database ?? this.database,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      expiresAt: expiresAt ?? this.expiresAt,
      selectedCompanyId: selectedCompanyId ?? this.selectedCompanyId,
      allowedCompanyIds: allowedCompanyIds ?? this.allowedCompanyIds,
      serverVersion: serverVersion ?? this.serverVersion,
    );
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    // Secrets go to encrypted secure storage.
    await _secureStorage.write(key: secureKeySessionId, value: sessionId);
    await _secureStorage.write(key: secureKeyPassword, value: password);
    // Remove any legacy secret copies from SharedPreferences.
    await prefs.remove('sessionId');
    await prefs.remove('password');
    // Non-secrets stay in SharedPreferences.
    await prefs.setString('userLogin', userLogin);
    await prefs.setString('database', database);
    await prefs.setString('serverUrl', serverUrl);
    if (userId != null) await prefs.setInt('userId', userId!);
    if (userName != null) await prefs.setString('userName', userName!);
    if (expiresAt != null) {
      await prefs.setString('expiresAt', expiresAt!.toIso8601String());
    }
    if (serverVersion != null) {
      await prefs.setString('serverVersion', serverVersion!);
    }
    if (selectedCompanyId != null) {
      await prefs.setInt('selected_company_id', selectedCompanyId!);
    }
    await prefs.setStringList(
      'allowed_company_ids',
      allowedCompanyIds.map((e) => e.toString()).toList(),
    );
    await prefs.setBool('isLoggedIn', true);
  }

  static Future<OdooSessionModel?> fromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    if (!isLoggedIn) return null;

    // Read secrets from secure storage, falling back to legacy prefs copies.
    var sessionId = await _secureStorage.read(key: secureKeySessionId);
    sessionId ??= prefs.getString('sessionId');
    var password = await _secureStorage.read(key: secureKeyPassword);
    password ??= prefs.getString('password');
    final userLogin = prefs.getString('userLogin');
    final rawServerUrl = prefs.getString('serverUrl');
    final database = prefs.getString('database');

    if ([sessionId, userLogin, password, rawServerUrl, database].contains(null)) {
      return null;
    }

    String serverUrl = rawServerUrl!.trim();
    while (serverUrl.endsWith('/')) {
      serverUrl = serverUrl.substring(0, serverUrl.length - 1);
    }
    if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
      serverUrl = 'https://$serverUrl';
    }

    return OdooSessionModel(
      sessionId: sessionId!,
      userLogin: userLogin!,
      password: password!,
      serverUrl: serverUrl,
      database: database!,
      userId: prefs.getInt('userId'),
      userName: prefs.getString('userName'),
      expiresAt: prefs.getString('expiresAt') != null
          ? DateTime.tryParse(prefs.getString('expiresAt')!)
          : null,
      serverVersion: prefs.getString('serverVersion'),
      selectedCompanyId: prefs.getInt('selected_company_id'),
      allowedCompanyIds: prefs
          .getStringList('allowed_company_ids')
          ?.map((e) => int.tryParse(e) ?? -1)
          .where((e) => e > 0)
          .toList() ?? [],
    );
  }

  /// Session/auth keys owned by this model (SharedPreferences side).
  static const prefsKeys = [
    'sessionId', // legacy secret copy (migrated to secure storage)
    'userLogin',
    'password', // legacy secret copy (migrated to secure storage)
    'database',
    'serverUrl',
    'userId',
    'userName',
    'expiresAt',
    'serverVersion',
    'selected_company_id',
    'allowed_company_ids',
    'isLoggedIn',
  ];

  /// Removes only this model's session/auth keys from prefs + secure storage.
  static Future<void> clearStored() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefsKeys) {
      await prefs.remove(key);
    }
    await _secureStorage.delete(key: secureKeySessionId);
    await _secureStorage.delete(key: secureKeyPassword);
  }
}
