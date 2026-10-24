import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/providers/session_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../login/login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.watch<SessionProvider>().session;
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leadingWidth: 62,
        title: Text(
          'Settings',
          style: GoogleFonts.dmSerifDisplay(
            fontSize: 24,
            height: 1.2,
            color: theme.colorScheme.onSurface,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(PhosphorIconsBold.caretLeft, size: 20),
          tooltip: 'Back',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile section
          _SectionHeader(title: 'Account'),
          _SettingsCard(
            children: [
              _ProfileItem(session: session),
              const Divider(),
              _InfoRow(
                icon: PhosphorIconsRegular.database,
                label: 'Database',
                value: session?.database ?? '—',
              ),
              const Divider(),
              _InfoRow(
                icon: PhosphorIconsRegular.hardDrives,
                label: 'Server',
                value: session?.serverUrl ?? '—',
                isLink: true,
              ),
              const Divider(),
              _InfoRow(
                icon: PhosphorIconsRegular.info,
                label: 'Odoo Version',
                value: session?.serverVersion != null
                    ? 'Odoo ${session!.majorVersion}'
                    : '—',
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Appearance
          _SectionHeader(title: 'Appearance'),
          _SettingsCard(
            children: [
              ListTile(
                leading: Icon(
                  themeProvider.isDark
                      ? PhosphorIconsRegular.moon
                      : PhosphorIconsRegular.sun,
                  color: AppColors.primary,
                ),
                title: const Text('Theme'),
                subtitle: Text(
                  themeProvider.isDark ? 'Dark' : 'Light',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
                trailing: Switch(
                  value: themeProvider.isDark,
                  onChanged: (_) => themeProvider.toggleTheme(),
                  activeThumbColor: AppColors.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // About
          _SectionHeader(title: 'About'),
          _SettingsCard(
            children: [
              _InfoRow(
                icon: PhosphorIconsRegular.rocket,
                label: 'App Name',
                value: 'Do Your Projects',
              ),
              const Divider(),
              _InfoRow(
                icon: PhosphorIconsRegular.tag,
                label: 'Version',
                value: '1.0.0',
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Danger zone
          _SectionHeader(title: 'Session'),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.signOut,
                  color: AppColors.statusBlocked,
                ),
                title: const Text(
                  'Sign Out',
                  style: TextStyle(color: AppColors.statusBlocked),
                ),
                onTap: () => _confirmLogout(context),
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    // Capture Navigator/dependencies before the dialog so the outer
    // context is never used across the async logout gap.
    final navigator = Navigator.of(context);
    final sessionProvider = context.read<SessionProvider>();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await sessionProvider.logout();
              if (!navigator.mounted) return;
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusBlocked,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkBorder
              : AppColors.lightBorder,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(children: children),
    );
  }
}

class _ProfileItem extends StatelessWidget {
  final dynamic session;

  const _ProfileItem({this.session});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: AppColors.gradientPurple),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                (session?.userName ?? session?.userLogin ?? 'U')
                    .substring(0, 1)
                    .toUpperCase(),
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session?.userName ?? 'User',
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  session?.userLogin ?? '',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLink;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLink = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 20),
      title: Text(label, style: theme.textTheme.bodyMedium),
      trailing: Text(
        value,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: isLink
              ? AppColors.primary
              : theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
