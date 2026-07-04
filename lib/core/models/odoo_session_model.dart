import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OdooSessionModel {
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
    await prefs.setString('sessionId', sessionId);
    await prefs.setString('userLogin', userLogin);
    await prefs.setString('password', password);
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

    final sessionId = prefs.getString('sessionId');
    final userLogin = prefs.getString('userLogin');
    final password = prefs.getString('password');
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
}
