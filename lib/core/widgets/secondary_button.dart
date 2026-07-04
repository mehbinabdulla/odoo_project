import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class SecondaryButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final double borderRadius;
  final EdgeInsets? padding;

  const SecondaryButton({
    super.key,
    this.label,
    this.icon,
    this.onTap,
    this.borderRadius = 32,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final effectivePadding = padding ?? (label != null
        ? const EdgeInsets.symmetric(vertical: 10, horizontal: 20)
        : const EdgeInsets.all(10));

    return Opacity(
      opacity: onTap == null ? 0.6 : 1.0,
      child: Material(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Container(
            padding: effectivePadding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null)
                  Icon(
                    icon,
                    size: 16,
                    color: theme.colorScheme.onSurface,
                  ),
                if (icon != null && label != null)
                  const SizedBox(width: 8),
                if (label != null)
                  Text(
                    label!,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
