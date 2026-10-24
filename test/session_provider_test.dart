import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:do_your_projects/core/models/odoo_session_model.dart';
import 'package:do_your_projects/core/providers/session_provider.dart';

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

OdooSessionModel fakeSession() => OdooSessionModel(
      sessionId: 'sess-abc',
      userLogin: 'tester',
      password: 'secret',
      serverUrl: 'http://127.0.0.1:9',
      database: 'testdb',
      userId: 2,
      userName: 'Tester',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
  });

  test('initialize with empty prefs is logged out but initialized', () async {
    final provider = SessionProvider();
    await provider.initialize();

    expect(provider.isInitialized, isTrue);
    expect(provider.isLoggedIn, isFalse);
    expect(provider.session, isNull);
  });

  test('initialize restores a previously saved session', () async {
    await fakeSession().saveToPrefs();

    final provider = SessionProvider();
    await provider.initialize();

    expect(provider.isInitialized, isTrue);
    expect(provider.isLoggedIn, isTrue);
    expect(provider.session?.sessionId, 'sess-abc');
    expect(provider.userId, 2);
  });

  test('login against an unreachable server throws', () async {
    final provider = SessionProvider();
    await provider.initialize();

    await expectLater(
      provider.login(
        serverUrl: 'http://127.0.0.1:9',
        database: 'testdb',
        username: 'tester',
        password: 'secret',
      ),
      throwsA(isA<Exception>()),
    );
    expect(provider.isLoggedIn, isFalse);
  });

  test('updateSession marks logged in; logout clears everything', () async {
    final provider = SessionProvider();
    await provider.initialize();

    provider.updateSession(fakeSession());
    expect(provider.isLoggedIn, isTrue);
    expect(provider.sessionId, 'sess-abc');

    // logout() best-effort pings the fake server; connection refused
    // fails fast and never blocks logout.
    await provider.logout();

    expect(provider.isLoggedIn, isFalse);
    expect(provider.session, isNull);
    expect(provider.isLoggingOut, isFalse);
    expect(await OdooSessionModel.fromPrefs(), isNull);
  });

  test('clearExpiry resets the expiry flag', () async {
    final provider = SessionProvider();
    await provider.initialize();
    expect(provider.isSessionExpired, isFalse);

    provider.clearExpiry();
    expect(provider.isSessionExpired, isFalse);
  });
}
