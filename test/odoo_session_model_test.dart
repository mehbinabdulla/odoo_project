import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:do_your_projects/core/models/odoo_session_model.dart';

/// In-memory mock for the flutter_secure_storage method channel.
void mockSecureStorage() {
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (MethodCall call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      switch (call.method) {
        case 'write':
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return store[args['key'] as String];
        case 'readAll':
          return Map<String, String>.from(store);
        case 'delete':
          store.remove(args['key'] as String);
          return null;
        case 'deleteAll':
          store.clear();
          return null;
        default:
          return null;
      }
    },
  );
}

OdooSessionModel testModel() => OdooSessionModel(
      sessionId: 'sess-123',
      userLogin: 'admin',
      password: 's3cret',
      serverUrl: 'https://odoo.example.com',
      database: 'prod',
      userId: 7,
      userName: 'Admin',
      expiresAt: DateTime.utc(2030, 1, 2, 3, 4, 5),
      serverVersion: '17.0',
      selectedCompanyId: 1,
      allowedCompanyIds: const [1, 2],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
  });

  test('fromPrefs returns null when nothing was saved', () async {
    expect(await OdooSessionModel.fromPrefs(), isNull);
  });

  test('saveToPrefs -> fromPrefs round-trip preserves fields', () async {
    final model = testModel();
    await model.saveToPrefs();

    final loaded = await OdooSessionModel.fromPrefs();
    expect(loaded, isNotNull);
    expect(loaded!.sessionId, model.sessionId);
    expect(loaded.userLogin, model.userLogin);
    expect(loaded.password, model.password);
    expect(loaded.serverUrl, model.serverUrl);
    expect(loaded.database, model.database);
    expect(loaded.userId, model.userId);
    expect(loaded.userName, model.userName);
    expect(loaded.serverVersion, model.serverVersion);
    expect(loaded.selectedCompanyId, model.selectedCompanyId);
    expect(loaded.allowedCompanyIds, model.allowedCompanyIds);
    expect(
      loaded.expiresAt?.toIso8601String(),
      model.expiresAt?.toIso8601String(),
    );
  });

  test('secrets are not stored as plain text in SharedPreferences', () async {
    await testModel().saveToPrefs();

    final prefs = await SharedPreferences.getInstance();
    // Legacy plain-text copies must be gone; secrets live in secure storage.
    expect(prefs.getString('sessionId'), isNull);
    expect(prefs.getString('password'), isNull);
  });

  test('clearStored removes the saved session', () async {
    await testModel().saveToPrefs();
    expect(await OdooSessionModel.fromPrefs(), isNotNull);

    await OdooSessionModel.clearStored();
    expect(await OdooSessionModel.fromPrefs(), isNull);
  });

  test('majorVersion parses the server version', () {
    expect(testModel().majorVersion, 17);
    expect(
      testModel().copyWith(serverVersion: '18.4').majorVersion,
      18,
    );
    expect(
      testModel().copyWith(serverVersion: '').majorVersion,
      15,
    );
  });
}
