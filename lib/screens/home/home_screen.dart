import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/providers/project_provider.dart';
import '../../core/providers/session_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/providers/timesheet_provider.dart';
import '../../core/providers/task_provider.dart';
import '../../core/theme/app_theme.dart';
import '../projects/projects_screen.dart';
import '../projects/project_form_screen.dart';
import '../timesheets/timesheets_screen.dart';
import '../tasks/tasks_screen.dart';
import '../tasks/task_form_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../settings/settings_screen.dart';
import '../timesheets/timesheet_form_screen.dart';
import '../../core/widgets/odoo_network_image.dart';
import '../../core/utils/route_observer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAwareRefetchMixin {
  int _currentIndex = 0;
  bool _moduleMissingDialogShown = false;

  final _tabs = [
    _TabItem(
      icon: PhosphorIconsRegular.house,
      activeIcon: PhosphorIconsFill.house,
      label: 'Home',
    ),
    _TabItem(
      icon: PhosphorIconsRegular.squaresFour,
      activeIcon: PhosphorIconsFill.squaresFour,
      label: 'Projects',
    ),
    _TabItem(
      icon: PhosphorIconsRegular.puzzlePiece,
      activeIcon: PhosphorIconsFill.puzzlePiece,
      label: 'Tasks',
    ),
    _TabItem(
      icon: PhosphorIconsRegular.clock,
      activeIcon: PhosphorIconsFill.clock,
      label: 'Timesheets',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialData());
  }

  Future<void> _loadInitialData({int attempt = 1}) async {
    final projectProvider = context.read<ProjectProvider>();
    final timesheetProvider = context.read<TimesheetProvider>();
    final taskProvider = context.read<TaskProvider>();
    await Future.wait([
      projectProvider.loadProjects(),
      timesheetProvider.loadTimesheets(),
      taskProvider.loadTasks(),
    ]);

    // Auto-retry on network/connectivity errors (e.g. DNS not ready at startup)
    final isNetworkError = _isConnectivityError(projectProvider.error) ||
        _isConnectivityError(timesheetProvider.error) ||
        _isConnectivityError(taskProvider.error);

    if (isNetworkError && attempt < 4 && mounted) {
      final delay = Duration(seconds: attempt * 2); // 2s, 4s, 6s
      await Future.delayed(delay);
      if (mounted) _loadInitialData(attempt: attempt + 1);
    }
  }

  bool _isConnectivityError(String? error) {
    if (error == null) return false;
    return error.contains('SocketException') ||
        error.contains('Failed host lookup') ||
        error.contains('Network is unreachable') ||
        error.contains('Connection refused') ||
        error.contains('OS Error');
  }

  void _navigateTo(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
    
    // Refetch data when switching tabs
    if (!mounted) return;
    switch (index) {
      case 0:
        _loadInitialData();
        break;
      case 1:
        context.read<ProjectProvider>().loadProjects(showLoading: false);
        break;
      case 2:
        context.read<TaskProvider>().loadTasks(showLoading: false);
        break;
      case 3:
        context.read<TimesheetProvider>().loadTimesheets(showLoading: false);
        break;
    }
  }

  @override
  void refetch() {
    // When returning to this screen from a pushed route, refresh the current tab
    if (!mounted) return;
    switch (_currentIndex) {
      case 0:
        _loadInitialData();
        break;
      case 1:
        context.read<ProjectProvider>().loadProjects(showLoading: false);
        break;
      case 2:
        context.read<TaskProvider>().loadTasks(showLoading: false);
        break;
      case 3:
        context.read<TimesheetProvider>().loadTimesheets(showLoading: false);
        break;
    }
  }

  List<Widget> get _screens => [
    DashboardScreen(onNavigate: _navigateTo),
    const ProjectsScreen(),
    const TasksScreen(),
    const TimesheetsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final session = context.watch<SessionProvider>().session;

    final projectProvider = context.watch<ProjectProvider>();
    if (projectProvider.isModuleMissing && !_moduleMissingDialogShown) {
      _moduleMissingDialogShown = true;
      final ctx = context; // capture before async boundary
      Future.microtask(() {
        if (!mounted) return;
        showDialog(
          context: ctx, // ignore: use_build_context_synchronously
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(
              'Module Not Installed',
              style: GoogleFonts.dmSerifDisplay(),
            ),
            content: Text(
              'The Project module is not installed on this Odoo server. Please install it or contact your administrator.',
              style: GoogleFonts.poppins(),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.read<SessionProvider>().logout();
                },
                child: Text(
                  'OK',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        );
      });
    }

    return Scaffold(
      extendBody: false,
      floatingActionButton: _buildFAB(context),
      appBar: AppBar(
        // leading: _buildLogo(),
        title: Text(
          _currentIndex == 0 ? 'Dashboard' : _tabs[_currentIndex].label,
          style: GoogleFonts.dmSerifDisplay(
            fontSize: 30,
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          // Theme toggle
          Consumer<ThemeProvider>(
            builder: (_, tp, __) => IconButton(
              onPressed: tp.toggleTheme,
              icon: Icon(
                tp.isDark ? PhosphorIconsBold.sun : PhosphorIconsBold.moon,
                color: theme.colorScheme.onSurface.withValues(alpha: 1),
              ),
              tooltip: 'Toggle Theme',
            ),
          ),
          // User avatar / logout
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 8),
            child: GestureDetector(
              onTap: () => _showUserMenu(context),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: (session != null && session.userId != null)
                    ? OdooNetworkImage(
                        url: '${session.serverUrl}/web/image?model=res.users&field=image_128&id=${session.userId}',
                        headers: {
                          'Cookie': 'session_id=${session.sessionId}',
                        },
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(8),
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: AppColors.gradientPurple,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                (session.userName ?? session.userLogin).isEmpty
                                    ? 'U'
                                    : (session.userName ?? session.userLogin)
                                          .substring(0, 1)
                                          .toUpperCase(),
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: AppColors.gradientPurple,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            (session?.userName ?? session?.userLogin ?? 'U')
                                .substring(0, 1)
                                .toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
        toolbarHeight: 70,
      ),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outline, width: 1),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(_tabs.length, (index) {
                final isSelected = _currentIndex == index;
                final tab = _tabs[index];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _navigateTo(index),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            isSelected ? tab.activeIcon : tab.icon,
                            color: isSelected
                                ? AppColors.primary
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.4,
                                  ),
                            size: 26,
                          ),
                        ),
                        Text(
                          tab.label,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? AppColors.primary
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.4,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  void _showUserMenu(BuildContext context) {
    final session = context.read<SessionProvider>().session;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _UserMenuSheet(session: session),
    );
  }

  Widget? _buildFAB(BuildContext context) {
    String label = '';
    IconData icon = PhosphorIconsBold.plus;
    VoidCallback? onTap;

    final projectProvider = context.read<ProjectProvider>();
    final timesheetProvider = context.read<TimesheetProvider>();

    switch (_currentIndex) {
      case 0: // Dashboard
        label = 'Log Time';
        icon = PhosphorIconsBold.clock;
        if (timesheetProvider.isModuleMissing) return null;
        onTap = () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TimesheetFormScreen()),
        );
        break;
      case 1: // Projects
        label = 'New Project';
        if (projectProvider.isModuleMissing) return null;
        onTap = () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProjectFormScreen()),
        );
        break;
      case 2: // Tasks
        label = 'New Task';
        onTap = () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TaskFormScreen()),
          );
        };
        if (projectProvider.isModuleMissing) return null;
        break;
      case 3: // Timesheets
        label = 'Log Time';
        icon = PhosphorIconsBold.clock;
        if (timesheetProvider.isModuleMissing) return null;
        onTap = () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TimesheetFormScreen()),
        );
        break;
      default:
        return null;
    }

    return FloatingActionButton.extended(
      onPressed: onTap,
      label: Text(
        label,
        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
      ),
      icon: Icon(icon),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }


}

class _UserMenuSheet extends StatelessWidget {
  final dynamic session;

  const _UserMenuSheet({this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessionProvider = context.read<SessionProvider>();
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[500],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 24),
        // Avatar
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(20),
          ),
          child: session?.userId != null && session?.serverUrl != null
              ? OdooNetworkImage(
                  url: '${session!.serverUrl}/web/image?model=res.users&field=image_128&id=${session.userId}',
                  headers: {'Cookie': 'session_id=${session.sessionId}'},
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(20),
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: AppColors.gradientPurple,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          (session.userName ?? session.userLogin ?? 'U')
                              .substring(0, 1)
                              .toUpperCase(),
                          style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    );
                  },
                )
              : Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: AppColors.gradientPurple,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(
                    child: Text(
                      (session?.userName ?? session?.userLogin ?? 'U')
                          .substring(0, 1)
                          .toUpperCase(),
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Text(session?.userName ?? 'User', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          session?.userLogin ?? '',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 8),
        // Server info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            session?.serverUrl ?? '',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Odoo version badge
        if (session?.serverVersion != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Odoo ${session?.majorVersion ?? 17}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 24),
        // Settings
        ListTile(
          leading: const Icon(
            PhosphorIconsRegular.gear,
            color: AppColors.primary,
          ),
          title: const Text('Settings'),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const Divider(),
        // Logout
        ListTile(
          leading: const Icon(
            PhosphorIconsRegular.signOut,
            color: AppColors.statusBlocked,
          ),
          title: const Text('Sign Out'),
          textColor: AppColors.statusBlocked,
          onTap: () async {
            Navigator.pop(context);
            await sessionProvider.logout();
          },
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _TabItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
