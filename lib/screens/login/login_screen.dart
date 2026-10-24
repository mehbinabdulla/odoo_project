import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/providers/session_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/services/odoo_rpc_service.dart';
import '../../core/services/biometric_service.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();

  String _selectedProtocol = 'https://';
  static const _secureStorage = FlutterSecureStorage();
  // Saved-credential keys: non-secrets in prefs, secrets in secure storage.
  static const _savedServerKey = 'saved_server';
  static const _savedDbKey = 'saved_db';
  static const _savedLoginKey = 'saved_login';
  static const _savedPasswordKey = 'saved_password';
  List<String> _databases = [];
  String? _selectedDatabase;
  bool _urlChecked = false;
  bool _isLoadingDatabases = false;
  bool _isLoggingIn = false;
  bool _obscurePassword = true;
  int _currentStep = 0;
  bool _canCheckBiometric = false;
  bool _isBiometricAuthAvailable = false;
  Timer? _debounce;
  // Last URL whose databases were already fetched (skips redundant auto checks).
  String? _checkedUrl;

  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  // Safety net: ignore late async completions that fire after dispose.
  @override
  void setState(VoidCallback fn) {
    if (!mounted) return;
    super.setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_fadeController);

    _slideController.forward();
    _fadeController.forward();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final canCheck = await BiometricService.canCheckBiometrics();
    final isSupported = await BiometricService.isDeviceSupported();
    final savedLogin = await _secureStorage.read(key: _savedLoginKey);
    // Fall back to legacy plain-text prefs copy (pre-migration).
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final hasSavedCreds =
        savedLogin != null || prefs.getString(_savedLoginKey) != null;

    if (!mounted) return;
    setState(() {
      _canCheckBiometric = canCheck && isSupported;
      _isBiometricAuthAvailable = _canCheckBiometric && hasSavedCreds;
    });

    if (_isBiometricAuthAvailable) {
      // Auto-trigger if they just came from a session expired event?
      // For now, just let them tap the button.
    }
  }

  Future<void> _handleBiometricLogin() async {
    final authenticated = await BiometricService.authenticate(
      reason: 'Use biometrics to sign in to your Odoo account',
    );

    if (authenticated) {
      if (!mounted) return;
      setState(() => _isLoggingIn = true);
      try {
        final prefs = await SharedPreferences.getInstance();
        final server = prefs.getString(_savedServerKey);
        final db = prefs.getString(_savedDbKey);
        final login = await _secureStorage.read(key: _savedLoginKey) ??
            prefs.getString(_savedLoginKey);
        final pass = await _secureStorage.read(key: _savedPasswordKey) ??
            prefs.getString(_savedPasswordKey);

        if (server != null && db != null && login != null && pass != null) {
          if (!mounted) return;
          final provider = context.read<SessionProvider>();
          await provider.login(
            serverUrl: server,
            database: db,
            username: login,
            password: pass,
          );

          if (mounted && provider.isLoggedIn) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
              (_) => false,
            );
          }
        } else {
          _showErrorToast('No saved sign-in',
              'Sign in once with your password first to enable fingerprint login.');
        }
      } catch (e) {
        final (title, msg) = _friendlyLoginError(e);
        _showErrorToast(title, msg);
      } finally {
        if (mounted) setState(() => _isLoggingIn = false);
      }
    }
  }

  void _showErrorToast(String title, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            // Container(
            //   padding: const EdgeInsets.all(6),
            //   decoration: BoxDecoration(
            //     color: Colors.white.withValues(alpha: 0.2),
            //     shape: BoxShape.circle,
            //   ),
            //   child: const Icon(
            //     Icons.warning_amber_rounded,
            //     color: Colors.white,
            //     size: 20,
            //   ),
            // ),
            // const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.9),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.statusBlocked,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 8,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showWarningToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 8,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Maps raw exceptions from the sign-in flow to a friendly
  /// (title, message) pair for the error toast.
  (String, String) _friendlyLoginError(Object e) {
    final message = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    final text = message.toLowerCase();
    final server = _fullUrl.isEmpty ? 'the server' : _fullUrl;

    if (text.contains('invalid credentials') ||
        text.contains('access denied') ||
        text.contains('authentication failed')) {
      return (
        'Sign-in failed',
        'Incorrect username or password for this database. '
            'Double-check your details and try again.',
      );
    }
    if (text.contains('socketexception') ||
        text.contains('connection refused') ||
        text.contains('failed host lookup') ||
        text.contains('network error') ||
        text.contains('network is unreachable')) {
      return (
        'Server unreachable',
        "Couldn't connect to $server. Check the server address and "
            'your internet connection.',
      );
    }
    if (text.contains('timed out') || text.contains('timeoutexception')) {
      return (
        'Connection timed out',
        'The server took too long to respond. Try again in a moment.',
      );
    }
    // e.g. "Auth failed: HTTP 502"
    final httpCode =
        RegExp(r'HTTP (\d+)').firstMatch(message.toUpperCase())?.group(1);
    if (httpCode != null) {
      return (
        'Server error (HTTP $httpCode)',
        'The server is having trouble right now. Please try again shortly.',
      );
    }
    if (text.contains('invalid server response') ||
        text.contains('formatexception') ||
        text.contains('unexpected response') ||
        text.contains('invalid server response')) {
      return (
        'Unexpected server response',
        "The server sent data we couldn't read. Confirm this is a "
            'compatible Odoo server.',
      );
    }
    if (text.contains('two factor') || text.contains('2fa')) {
      return (
        'Two-factor required',
        'This account needs a security code to sign in. '
            'Ask your administrator for help.',
      );
    }
    if (text.contains('serverfault:')) {
      final detail = message.replaceFirst(RegExp(r'^.*?ServerFault:\s*'), '');
      return (
        'Server error',
        'The server crashed while completing your sign-in — this is a '
            'server-side issue, not your credentials. Contact the server '
            'administrator. (Server said: "$detail")',
      );
    }
    // Terse server faults (e.g. "Cyllo Server Error") give away no details.
    return (
      'Sign-in failed',
      'The server rejected the sign-in without details ("$message"). '
          'Verify the database name and that this account is active.',
    );
  }

  void _onUrlChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (_urlController.text.trim().isNotEmpty) {
        _checkServer(silent: true);
      } else {
        if (!mounted) return;
        _checkedUrl = null;
        setState(() {
          _databases = [];
          _urlChecked = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _debounce = null;
    _slideController.dispose();
    _fadeController.dispose();
    _urlController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _fullUrl {
    final url = _urlController.text.trim();
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '$_selectedProtocol$url';
  }

  Future<void> _checkServer({bool silent = false}) async {
    if (!mounted) return;
    if (_urlController.text.trim().isEmpty) {
      _showErrorToast('Server URL required',
          'Enter your Odoo server address first.');
      return;
    }

    // Auto checks fired while typing stay quiet and skip repeats of
    // an already-checked URL; explicit checks always run.
    if (silent && _checkedUrl == _fullUrl) return;

    setState(() {
      _isLoadingDatabases = true;
      _databases = [];
      _selectedDatabase = null;
    });

    try {
      final dbs = await OdooRpcService.listDatabases(_fullUrl);
      if (!mounted) return;
      if (dbs.isEmpty) {
        if (!silent) {
          _showErrorToast('No databases found',
              "The server didn't list any databases. Enter the database name manually.");
        }
        setState(() {
          _urlChecked = true;
        });
      } else {
        setState(() {
          _databases = dbs;
          _selectedDatabase = dbs.first;
          _urlChecked = true;
        });
      }
    } catch (e) {
      // Explicit checks surface friendly errors; typing-triggered
      // auto checks stay quiet to avoid toast spam.
      if (!silent) {
        final (title, msg) = _friendlyLoginError(e);
        _showErrorToast(title, msg);
      }
    } finally {
      _checkedUrl = _fullUrl;
      if (mounted) setState(() => _isLoadingDatabases = false);
    }
  }

  Future<void> _login() async {
    if (!mounted) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDatabase == null || _selectedDatabase!.isEmpty) {
      _showErrorToast('Database required',
          'Choose or enter a database before signing in.');
      return;
    }

    setState(() {
      _isLoggingIn = true;
    });

    try {
      final provider = context.read<SessionProvider>();
      await provider.login(
        serverUrl: _fullUrl,
        database: _selectedDatabase!,
        username: _loginController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted && provider.isLoggedIn) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_savedServerKey, _fullUrl);
        await prefs.setString(_savedDbKey, _selectedDatabase!);
        // Secrets go to encrypted secure storage; clear legacy prefs copies.
        await _secureStorage.write(
          key: _savedLoginKey,
          value: _loginController.text.trim(),
        );
        await _secureStorage.write(
          key: _savedPasswordKey,
          value: _passwordController.text,
        );
        await prefs.remove(_savedLoginKey);
        await prefs.remove(_savedPasswordKey);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      final (title, msg) = _friendlyLoginError(e);
      _showErrorToast(title, msg);
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                // gradient: LinearGradient(
                //   begin: Alignment.topLeft,
                //   end: Alignment.bottomRight,
                //   colors: isDark
                //       ? [AppColors.darkBg, const Color.fromARGB(255, 35, 15, 15), AppColors.darkSurface]
                //       : [const Color.fromARGB(255, 255, 240, 240), AppColors.lightBg, const Color.fromARGB(255, 255, 232, 232)],
                // ),
              ),
            ),
          ),
          // Decorative circles
          Positioned(
            top: -80,
            right: -80,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -60,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.08),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildAppLogo(theme),
                              const Spacer(),
                              // Logo + Title
                              _buildHeader(theme),
                              const SizedBox(height: 24),
                              // Form Card
                              _buildFormCard(theme, isDark),
                              const Spacer(),
                              const SizedBox(height: 24),
                              _buildFooter(theme),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppLogo(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'DYP',
            style: GoogleFonts.dmSerifDisplay(
              fontSize: 24,
              fontWeight: FontWeight.w400,
              color: theme.colorScheme.onSurface,
            ),
          ),
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
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connect to Odoo',
          style: GoogleFonts.dmSerifDisplay(
            fontSize: 32,
            color: theme.colorScheme.onSurface,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Connect to your Odoo server to manage projects, timesheets and modules.',
          style: GoogleFonts.poppins(
            fontSize: 15,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_currentStep == 0) ...[
              // Protocol + URL
              Text(
                'Server URL',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.transparent
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
                child: Row(
                  children: [
                    // Protocol selector
                    Container(
                      padding: const EdgeInsets.only(left: 12, right: 0),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(9),
                          bottomLeft: Radius.circular(9),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedProtocol,
                          items: ['https://', 'http://'].map((p) {
                            return DropdownMenuItem(
                              value: p,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 0),
                                child: Text(
                                  p,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                          isDense: true,
                          iconSize: 20,
                          icon: const Icon(PhosphorIconsRegular.caretDown, size: 20),
                          padding: EdgeInsets.zero,
                          onChanged: (v) {
                            setState(() => _selectedProtocol = v!);
                            if (v == 'http://') {
                              _showWarningToast(
                                'HTTP sends credentials unencrypted. Use only for local/dev servers.',
                              );
                            }
                            if (_urlController.text.trim().isNotEmpty) {
                              _checkServer();
                            }
                          },
                          dropdownColor: isDark
                              ? AppColors.darkCard
                              : AppColors.lightCard,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextFormField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          hintText: 'mycompany.odoo.com',
                          fillColor: Colors.transparent,
                          filled: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          contentPadding: EdgeInsets.only(left: 0, top: 0, right:8, bottom: 0),
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) => _onUrlChanged(),
                        onFieldSubmitted: (_) => _checkServer(),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter server URL'
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Database
              if (_databases.isNotEmpty) ...[
                Text(
                  'Database',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedDatabase,
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      PhosphorIconsRegular.database,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  dropdownColor: isDark
                      ? AppColors.darkCard
                      : AppColors.lightCard,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                  items: _databases.map((db) {
                    return DropdownMenuItem(value: db, child: Text(db));
                  }).toList(),
                  validator: (v) => v == null ? 'Select a database' : null,
                  onChanged: (v) => setState(() => _selectedDatabase = v),
                ),
                const SizedBox(height: 16),
              ] else if (_urlChecked) ...[
                Text(
                  'Database',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  decoration: const InputDecoration(
                    hintText: 'Enter database name',
                    prefixIcon: Icon(
                      PhosphorIconsRegular.database,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  onChanged: (v) =>
                      setState(() => _selectedDatabase = v.trim()),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter database name'
                      : null,
                ),
                const SizedBox(height: 16),
              ],
            ],
            if (_currentStep == 1) ...[
              // Email
              Text(
                'Email / Username',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _loginController,
                decoration: const InputDecoration(
                  hintText: 'admin@example.com',
                  prefixIcon: Icon(
                    PhosphorIconsRegular.user,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Enter email or username'
                    : null,
              ),
              const SizedBox(height: 24),

              // Password
              Text(
                'Password',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: '••••••••',
                  prefixIcon: const Icon(
                    PhosphorIconsRegular.lock,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? PhosphorIconsRegular.eye
                          : PhosphorIconsRegular.eyeSlash,
                      color: AppColors.darkTextMuted,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Enter password' : null,
                onFieldSubmitted: (_) => _login(),
              ),
            ],


            if (_currentStep == 0)
              (_databases.isEmpty && !_urlChecked)
                  ? SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isLoadingDatabases ? null : _checkServer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _isLoadingDatabases
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(PhosphorIconsRegular.magnifyingGlass),
                        label: Text(
                          'Check Server',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
                      ),
                    )
                  : SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          if (_selectedDatabase == null ||
                              _selectedDatabase!.isEmpty) {
                            _showErrorToast('Database required',
                                'Choose or enter a database before signing in.');
                          } else {
                            setState(() {
                              _currentStep = 1;
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Next',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ),
                    )
            else
             if (_currentStep == 1) ...[
              // Login button
              const SizedBox(height: 16),
              Row(
                children: [
                   SizedBox(
                    height: 48,
                    width: 48,
                    
                    child: ElevatedButton(
                      onPressed: () => setState(() {
                    _currentStep = 0;
                  }),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Theme.of(context).dividerTheme.color!),
                        ),
                      ),
                      child: Icon(PhosphorIconsBold.caretLeft, size: 24, color: Theme.of(context).textTheme.bodyLarge?.color,)
                    ),
                  ),
                  const SizedBox(width: 8),
                if (_isBiometricAuthAvailable) ...[
                  SizedBox(
                    height: 48,
                    width: 48,
                    child: ElevatedButton(
                      onPressed: _handleBiometricLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
                        foregroundColor: AppColors.primary,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                          ),
                        ),
                      ),
                      child: const Icon(PhosphorIconsRegular.fingerprint, size: 24),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isLoggingIn ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isLoggingIn
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                'Sign In',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                ),
                              ),
                      ),
                    ),
                ),
                
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Center(
      child: Text(
        'Compatible with Odoo 15 · 16 · 17 · 18 · 19 · 20',
        style: GoogleFonts.poppins(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
