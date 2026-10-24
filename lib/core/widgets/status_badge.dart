import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Returns a deterministic accent color for an arbitrary status/stage label.
/// Shared by project, task and module badges so colors stay consistent.
Color statusColorForLabel(String? label) {
  if (label == null || label.isEmpty) return AppColors.statusTodo;
  const colors = [
    AppColors.statusTodo,
    AppColors.statusInProgress,
    AppColors.statusDone,
    AppColors.statusReview,
    AppColors.accentPink,
  ];
  return colors[label.hashCode.abs() % colors.length];
}

/// Single shared status/stage badge used across list screens.
///
/// Pass an explicit [color] for fixed mappings (e.g. installed vs.
/// uninstalled); otherwise the color is derived from [label] via
/// [statusColorForLabel].
class StatusBadge extends StatelessWidget {
  final String label;
  final Color? color;
  final bool showDot;

  const StatusBadge({
    super.key,
    required this.label,
    this.color,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final effective = color ?? statusColorForLabel(label);
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: effective.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDot) ...[
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: effective,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: effective,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
