import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/notification_provider.dart';
import '../theme/app_theme.dart';

class AppToastOverlay extends StatelessWidget {
  const AppToastOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final notification = context.watch<NotificationProvider>().current;
    if (notification == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color color;
    IconData icon;
    switch (notification.type) {
      case AppNotificationType.success:
        color = AppColors.statusDone;
        icon = PhosphorIconsFill.checkCircle;
        break;
      case AppNotificationType.error:
        color = AppColors.statusBlocked;
        icon = PhosphorIconsFill.warningCircle;
        break;
      case AppNotificationType.warning:
        color = AppColors.accentYellow;
        icon = PhosphorIconsFill.warning;
        break;
      default:
        color = AppColors.primary;
        icon = PhosphorIconsFill.info;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Align(
          alignment: Alignment.topCenter,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * -20),
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: color.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      notification.message,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
