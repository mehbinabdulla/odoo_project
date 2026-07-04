import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class PrimaryButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? color;
  final double? fontSize;
  final double borderRadius;
  final EdgeInsets? padding;

  const PrimaryButton({
    super.key,
    this.label,
    this.icon,
    this.onTap,
    this.color,
    this.fontSize,
    this.borderRadius = 32,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePadding = padding ??
        (label != null
            ? const EdgeInsets.symmetric(vertical: 10, horizontal: 20)
            : const EdgeInsets.all(10));

    return Opacity(
      opacity: onTap == null ? 0.5 : 1.0,
      child: Material(
        color: color ?? AppColors.primary,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: effectivePadding,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null)
                  Icon(icon, size: 16, color: Colors.white),
                if (icon != null && label != null)
                  const SizedBox(width: 8),
                if (label != null)
                  Text(
                    label!,
                    style: GoogleFonts.poppins(
                      fontSize: fontSize ?? 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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
