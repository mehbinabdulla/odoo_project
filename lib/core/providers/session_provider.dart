import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/odoo_session_model.dart';
import '../services/client_provider.dart';
import '../services/odoo_rpc_service.dart';
import '../services/odoo_field_registry.dart';

class SessionProvider with ChangeNotifier {
  static const _secureStorage = FlutterSecureStorage();
  // Saved-credential keys from the login screen: non-secrets live in prefs,
  // secrets live in secure storage.
  static const _savedPrefsKeys = ['saved_server', 'saved_db'];
  static const _savedSecureKeys = ['saved_login', 'saved_password'];

  OdooSessionModel? _session;
  bool _isInitialized = false;
  bool _isLoggingOut = false;
  bool _isSessionExpired = false;

  OdooSessionModel? get session => _session;
  bool get isLoggedIn => _session != null;
  bool get isInitialized => _isInitialized;
  bool get isLoggingOut => _isLoggingOut;
  bool get isSessionExpired => _isSessionExpired;

  String? get serverUrl => _session?.serverUrl;
  String? get userName => _session?.userName;
  String? get userLogin => _session?.userLogin;
  int? get userId => _session?.userId;
  String? get sessionId => _session?.sessionId;
  int get majorVersion => _session?.majorVersion ?? 17;

  SessionProvider() {
    OdooRpcService.onSessionExpired = () {
      _isSessionExpired = true;
      notifyListeners();
    };
  }

  Future<void> initialize() async {
    try {
      final saved = await OdooSessionModel.fromPrefs();
      if (saved != null) {
        _session = saved;
        OdooRpcService.setSession(saved);
      }
    } catch (_) {}
    _isInitialized = true;
    notifyListeners();
  }

  Future<bool> login({
    required String serverUrl,
    required String database,
    required String username,
    required String password,
  }) async {
    try {
      final session = await OdooRpcService.authenticate(
        serverUrl: serverUrl,
        database: database,
        username: username,
        password: password,
      );
      if (session != null) {
        _session = session;
        await session.saveToPrefs();
        notifyListeners();
        // Pre-warm the field registry in the background so the first
        // data load doesn't need extra round-trips to fields_get.
        OdooFieldRegistry.preloadForLogin(); // fire-and-forget
        return true;
      }
      return false;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    _isLoggingOut = true;
    notifyListeners();

    // Best-effort server-side session destroy; never blocks logout.
    try {
      final baseUrl = _session?.serverUrl;
      final sid = _session?.sessionId;
      if (baseUrl != null && baseUrl.isNotEmpty) {
        final client = buildHttpClient();
        try {
          await client.post(
            Uri.parse('$baseUrl/web/session/destroy'),
            headers: {
              'Content-Type': 'application/json',
              if (sid != null && sid.isNotEmpty) 'Cookie': 'session_id=$sid',
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {},
            }),
          ).timeout(const Duration(seconds: 8));
        } finally {
          client.close();
        }
      }
    } catch (_) {}

    // Remove only session/auth keys; leave unrelated prefs intact.
    try {
      await OdooSessionModel.clearStored();
      final prefs = await SharedPreferences.getInstance();
      for (final key in _savedPrefsKeys) {
        await prefs.remove(key);
      }
      // Legacy plain-text copies of saved secrets (migrated to secure).
      await prefs.remove('saved_login');
      await prefs.remove('saved_password');
      for (final key in _savedSecureKeys) {
        await _secureStorage.delete(key: key);
      }
    } catch (_) {}

    OdooRpcService.clearSession();
    _session = null;
    _isLoggingOut = false;
    notifyListeners();
  }

  void updateSession(OdooSessionModel session) {
    _session = session;
    _isSessionExpired = false;
    OdooRpcService.setSession(session);
    unawaited(session.saveToPrefs().catchError((_) {}));
    notifyListeners();
  }

  void clearExpiry() {
    _isSessionExpired = false;
    notifyListeners();
  }
}
