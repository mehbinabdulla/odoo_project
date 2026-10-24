import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/providers/session_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/project_provider.dart';
import 'core/providers/timesheet_provider.dart';
import 'core/providers/task_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/notification_provider.dart';
import 'core/widgets/app_toast.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'core/utils/route_observer.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final sessionProvider = SessionProvider();
  final themeProvider = ThemeProvider();

  await Future.wait([
    sessionProvider.initialize(),
    themeProvider.initialize(),
  ]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: sessionProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProxyProvider<SessionProvider, ProjectProvider>(
          create: (ctx) => ProjectProvider(
            sessionProvider: ctx.read<SessionProvider>(),
          ),
          update: (_, session, prev) {
            if (prev == null) return ProjectProvider(sessionProvider: session);
            prev.updateSession(session);
            return prev;
          },
        ),
        ChangeNotifierProxyProvider<SessionProvider, TimesheetProvider>(
          create: (ctx) => TimesheetProvider(
            sessionProvider: ctx.read<SessionProvider>(),
          ),
          update: (_, session, prev) {
            if (prev == null) return TimesheetProvider(sessionProvider: session);
            prev.updateSession(session);
            return prev;
          },
        ),
        ChangeNotifierProxyProvider<SessionProvider, TaskProvider>(
          create: (ctx) => TaskProvider(
            sessionProvider: ctx.read<SessionProvider>(),
          ),
          update: (_, session, prev) {
            if (prev == null) return TaskProvider(sessionProvider: session);
            prev.updateSession(session);
            return prev;
          },
        ),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: const DoYourProjectsApp(),
    ),
  );
}

class DoYourProjectsApp extends StatefulWidget {
  const DoYourProjectsApp({super.key});

  @override
  State<DoYourProjectsApp> createState() => _DoYourProjectsAppState();
}

class _DoYourProjectsAppState extends State<DoYourProjectsApp> {
  bool _previousLoggedIn = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isLoggedIn = context.watch<SessionProvider>().isLoggedIn;
    
    // If user was logged in and now logged out, clear stack
    if (_previousLoggedIn && !isLoggedIn) {
      Future.microtask(() {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      });
    }
    _previousLoggedIn = isLoggedIn;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final sessionProvider = context.watch<SessionProvider>();

    if (!sessionProvider.isInitialized) {
      return MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Do Your Projects',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeProvider.themeMode,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Do Your Projects',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      navigatorObservers: [routeObserver],
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            const AppToastOverlay(),
            _SessionExpiredListener(child: child),
          ],
        );
      },
      home: sessionProvider.isLoggedIn
          ? const HomeScreen()
          : const LoginScreen(),
    );
  }
}

class _SessionExpiredListener extends StatefulWidget {
  final Widget? child;
  const _SessionExpiredListener({this.child});

  @override
  State<_SessionExpiredListener> createState() => _SessionExpiredListenerState();
}

class _SessionExpiredListenerState extends State<_SessionExpiredListener> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    // Single listener: react to expiry flag changes here only.
    // The _handled guard ensures the toast + logout fire exactly once
    // per expiry event.
    final isExpired =
        context.select<SessionProvider, bool>((p) => p.isSessionExpired);

    if (!isExpired) {
      _handled = false;
    } else if (!_handled) {
      _handled = true;
      final sessionProvider = context.read<SessionProvider>();
      final notificationProvider = context.read<NotificationProvider>();
      Future.microtask(() {
        sessionProvider.clearExpiry();
        notificationProvider.show(
          'Session expired. Please log in again.',
          type: AppNotificationType.error,
        );
        // Logout triggers the home property change in MaterialApp.
        sessionProvider.logout();
      });
    }

    return const SizedBox.shrink();
  }
}
