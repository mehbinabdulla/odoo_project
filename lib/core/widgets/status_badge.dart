import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Visual recipe for an Odoo project-task state badge, matching the
/// colors of the web state-selection legend:
///   In Progress → neutral grey (tinted)  · Changes Requested → amber
///   Approved → green                     · Done → green, solid
///   Canceled → red, solid                · ( qualquer unknown → hash)
class OdooStateBadgeStyle {
  final Color color;
  final bool filled;

  const OdooStateBadgeStyle(this.color, {required this.filled});
}

/// Maps a task's `state` value (and/or its selection label) to the
/// Odoo legend palette. Terminal states (`1_*` — done/canceled) render
/// solid on the web, active states render as tinted pills.
OdooStateBadgeStyle odooStateBadgeStyle(String? state, String? label) {
  final key =
      '${(state ?? '').toLowerCase()} ${(label ?? '').toLowerCase()}';
  final filled = (state ?? '').toLowerCase().startsWith('1_');
  if (key.contains('requested')) {
    return OdooStateBadgeStyle(AppColors.statusReview, filled: filled);
  }
  if (key.contains('cancel')) {
    return OdooStateBadgeStyle(AppColors.statusBlocked, filled: filled);
  }
  if (key.contains('approve') || key.contains('done') || filled) {
    return OdooStateBadgeStyle(AppColors.statusDone, filled: filled);
  }
  return OdooStateBadgeStyle(AppColors.statusTodo, filled: filled);
}

/// [odooStateBadgeStyle] as a plain color.
Color taskStateColor(String? state, String? label) =>
    odooStateBadgeStyle(state, label).color;

/// Returns a deterministic accent color for an arbitrary status/stage label.
/// Shared by project, task and module badges so colors stay consistent.
/// Odoo-legend keywords win first so "Done"/"Canceled"/"Approved"… names
/// map to the same colors as the web client; free-form stage names fall
/// back to a stable hash.
Color statusColorForLabel(String? label) {
  if (label == null || label.isEmpty) return AppColors.statusTodo;
  final key = label.toLowerCase();
  if (key.contains('requested')) return AppColors.statusReview;
  if (key.contains('cancel')) return AppColors.statusBlocked;
  if (key.contains('approve') || key.contains('done') || key.contains('complete')) {
    return AppColors.statusDone;
  }
  if (key.contains('progress') || key.contains('waiting') || key.contains('new') || key.contains('todo')) {
    return AppColors.statusTodo;
  }
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
