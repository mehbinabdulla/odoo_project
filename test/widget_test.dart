import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:do_your_projects/core/models/odoo_session_model.dart';
import 'package:do_your_projects/core/providers/notification_provider.dart';
import 'package:do_your_projects/core/providers/project_provider.dart';
import 'package:do_your_projects/core/providers/session_provider.dart';
import 'package:do_your_projects/core/providers/task_provider.dart';
import 'package:do_your_projects/core/providers/theme_provider.dart';
import 'package:do_your_projects/core/providers/timesheet_provider.dart';
import 'package:do_your_projects/screens/home/home_screen.dart';
import 'package:do_your_projects/screens/login/login_screen.dart';

/// In-memory mock for the flutter_secure_storage method channel
/// (used by [OdooSessionModel] for secrets).
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
      sessionId: 'test-session-id',
      userLogin: 'tester',
      password: 'secret',
      serverUrl: 'http://127.0.0.1:9',
      database: 'testdb',
      userId: 2,
      userName: 'Tester',
    );

/// Builds the real app widget tree with an explicit [SessionProvider],
/// mirroring main.dart's provider setup. The [MaterialApp] itself is keyed
/// on login state so a session change rebuilds the route stack from the
/// matching screen (the production app instead navigates explicitly on
/// login/logout, which a test cannot trigger externally).
Widget buildApp(SessionProvider session) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProxyProvider<SessionProvider, ProjectProvider>(
        create: (ctx) => ProjectProvider(
          sessionProvider: ctx.read<SessionProvider>(),
        ),
        update: (_, s, prev) {
          if (prev == null) return ProjectProvider(sessionProvider: s);
          prev.updateSession(s);
          return prev;
        },
      ),
      ChangeNotifierProxyProvider<SessionProvider, TimesheetProvider>(
        create: (ctx) => TimesheetProvider(
          sessionProvider: ctx.read<SessionProvider>(),
        ),
        update: (_, s, prev) {
          if (prev == null) return TimesheetProvider(sessionProvider: s);
          prev.updateSession(s);
          return prev;
        },
      ),
      ChangeNotifierProxyProvider<SessionProvider, TaskProvider>(
        create: (ctx) => TaskProvider(
          sessionProvider: ctx.read<SessionProvider>(),
        ),
        update: (_, s, prev) {
          if (prev == null) return TaskProvider(sessionProvider: s);
          prev.updateSession(s);
          return prev;
        },
      ),
      ChangeNotifierProvider(create: (_) => NotificationProvider()),
    ],
    child: Consumer<SessionProvider>(
      builder: (_, s, __) => MaterialApp(
        key: ValueKey<bool>(s.isLoggedIn),
        home: s.isLoggedIn ? const HomeScreen() : const LoginScreen(),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    mockSecureStorage();
  });

  testWidgets('shows LoginScreen when logged out', (tester) async {
    final session = SessionProvider();
    await session.initialize();
    expect(session.isLoggedIn, isFalse);

    await tester.pumpWidget(buildApp(session));
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('shows HomeScreen when logged in, LoginScreen after logout',
      (tester) async {
    final session = SessionProvider();
    await session.initialize();

    await tester.pumpWidget(buildApp(session));
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);

    // Drive the app to the logged-in state via SessionProvider.
    session.updateSession(fakeSession());
    await tester.pump();
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    // Flush HomeScreen's connectivity-retry timers (2s/4s/6s backoff
    // against the unreachable fake server) so no timer is left pending.
    await tester.pump(const Duration(seconds: 30));

    // Logging out drives the app back to the login screen.
    await session.logout();
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });
}
