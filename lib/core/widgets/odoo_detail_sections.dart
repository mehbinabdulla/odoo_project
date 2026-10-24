import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../services/odoo_rpc_service.dart';
import '../theme/app_theme.dart';

/// Shared parsing + section widgets for the Odoo detail screens
/// (project popup / task / timesheet).
///
/// Task and timesheet details share the same record-parsing rules
/// (many2one / x2many / date / selection) and the same
/// Metrics / Timeline / Flags / Details grouping. Project details reuses
/// the display-value formatter and the row/card widgets for its popup.
class OdooDetailSections {
  const OdooDetailSections._();

  /// Parses one `search_read` row into display-ready [out] values.
  /// Returns the set of valued field names (callers add the non-header ones
  /// to their visible set). Handles the `account.analytic.line` one2many
  /// special-case (fetches project/unit_amount for timesheet rows).
  static Future<Set<String>> parseDetailRecord({
    required Map<String, dynamic> data,
    required Map<String, dynamic> fieldDefs,
    required Map<String, dynamic> out,
    Map<String, dynamic>? rawOut,
  }) async {
    final valued = <String>{};
    for (final key in fieldDefs.keys) {
      final type = fieldDefs[key]['type'];
      final val = data[key];
      if (val == null || val == false || val == '') continue;

      rawOut?[key] = val;

      if (type == 'many2one' && val is List && val.length == 2) {
        out[key] = val[1];
      } else if ((type == 'many2many' || type == 'one2many') &&
          val is List &&
          val.isNotEmpty) {
        final relation = fieldDefs[key]['relation'] as String?;
        if (relation != null) {
          try {
            List<String> fieldsToFetch = const ['display_name', 'name'];
            if (relation == 'account.analytic.line') {
              fieldsToFetch = const [
                'display_name',
                'name',
                'project_id',
                'unit_amount',
              ];
            }
            final relRecords = await OdooRpcService.searchRead(
              model: relation,
              domain: [
                ['id', 'in', val],
              ],
              fields: fieldsToFetch,
            );
            if (type == 'one2many') {
              out[key] = relRecords;
            } else {
              final names = relRecords
                  .map((r) => r['display_name'] ?? r['name'] ?? 'Unknown')
                  .toList();
              out[key] = names.join(', ');
            }
          } catch (_) {
            if (type == 'one2many') {
              out[key] =
                  List.generate(val.length, (i) => 'Record ${val[i]}');
            } else {
              out[key] = '${val.length} records';
            }
          }
        }
      } else if (type == 'date' || type == 'datetime') {
        final parsed = DateTime.tryParse(val.toString());
        if (parsed != null) {
          out[key] = parsed.toString().split(' ')[0];
        }
      } else if (type == 'selection') {
        final selectionDef = fieldDefs[key]['selection'] as List?;
        if (selectionDef != null) {
          final match = selectionDef.firstWhere(
            (e) => e[0] == val,
            orElse: () => [val, val.toString()],
          );
          out[key] = match[1];
        }
      } else {
        if (val is List && val.isEmpty) continue;
        out[key] = val.toString();
      }

      if (out[key] != null) valued.add(key);
    }
    return valued;
  }

  /// Human-readable value for popup/detail lists (many2one label,
  /// "N items" for x2many, selection label).
  static String detailDisplayValue(Map<dynamic, dynamic> def, dynamic val) {
    final type = def['type'];
    if (type == 'many2one' && val is List && val.length == 2) {
      return val[1].toString();
    }
    if ((type == 'many2many' || type == 'one2many') && val is List) {
      return '${val.length} items';
    }
    if (type == 'selection') {
      final selection = def['selection'] as List?;
      if (selection != null) {
        final match = selection.firstWhere(
          (e) => e[0] == val,
          orElse: () => [val, val.toString()],
        );
        return match[1].toString();
      }
    }
    return val.toString();
  }

  /// Orders visible fields: defaults first (in default order), then
  /// alphabetically by label.
  static List<String> orderedDetailFields({
    required Set<String> visible,
    required Map<String, dynamic> fieldDefs,
    required Set<String> defaultFields,
    Set<String> exclude = const {},
  }) {
    final defaults = defaultFields.toList();
    final list = visible
        .where((f) => fieldDefs.containsKey(f) && !exclude.contains(f))
        .toList();
    list.sort((a, b) {
      final aDef = defaultFields.contains(a);
      final bDef = defaultFields.contains(b);
      if (aDef && !bDef) return -1;
      if (!aDef && bDef) return 1;
      if (aDef && bDef) {
        return defaults.indexOf(a).compareTo(defaults.indexOf(b));
      }
      return (fieldDefs[a]?['string'] ?? a)
          .toString()
          .compareTo((fieldDefs[b]?['string'] ?? b).toString());
    });
    return list;
  }

  /// Splits ordered fields into date / metric / boolean / other buckets.
  static Map<String, List<String>> groupDetailFields({
    required List<String> ordered,
    required Map<String, dynamic> fieldDefs,
  }) {
    final dateFields = <String>[];
    final metricFields = <String>[];
    final booleanFields = <String>[];
    final otherFields = <String>[];
    for (final f in ordered) {
      final type = fieldDefs[f]?['type'];
      if (type == 'date' || type == 'datetime') {
        dateFields.add(f);
      } else if (type == 'integer' || type == 'float' || type == 'monetary') {
        metricFields.add(f);
      } else if (type == 'boolean') {
        booleanFields.add(f);
      } else {
        otherFields.add(f);
      }
    }
    return {
      'dates': dateFields,
      'metrics': metricFields,
      'booleans': booleanFields,
      'other': otherFields,
    };
  }
}

/// Small label/value row used by all three detail screens.
class OdooFieldRow extends StatelessWidget {
  final String label;
  final String value;

  const OdooFieldRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Metric card used by the Metrics horizontal lists.
class OdooInfoCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const OdooInfoCard({
    super.key,
    required this.label,
    required this.value,
    this.icon = PhosphorIconsRegular.chartBar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: 130,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? 0.05 : 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const Spacer(),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Serif section heading ("Metrics", "Timeline", ...).
class OdooSectionTitle extends StatelessWidget {
  final String title;

  const OdooSectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        title,
        style: GoogleFonts.dmSerifDisplay(
          fontSize: 20,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Full Metrics / Timeline / Flags / Details group used by task +
/// timesheet detail screens.
class OdooDetailGroups extends StatelessWidget {
  final Map<String, dynamic> fieldDefs;
  final Map<String, dynamic> fieldValues;
  final List<String> metricFields;
  final List<String> dateFields;
  final List<String> booleanFields;
  final List<String> otherFields;

  const OdooDetailGroups({
    super.key,
    required this.fieldDefs,
    required this.fieldValues,
    required this.metricFields,
    required this.dateFields,
    required this.booleanFields,
    required this.otherFields,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (metricFields.isNotEmpty) ...[
          const OdooSectionTitle('Metrics'),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              clipBehavior: Clip.none,
              itemCount: metricFields.length,
              itemBuilder: (ctx, i) {
                final f = metricFields[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: OdooInfoCard(
                    label: fieldDefs[f]['string'] ?? f,
                    value: fieldValues[f].toString(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
        if (dateFields.isNotEmpty) ...[
          const OdooSectionTitle('Timeline'),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: dateFields.map((f) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        PhosphorIconsRegular.calendar,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fieldDefs[f]['string'] ?? f,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          Text(
                            fieldValues[f].toString(),
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 32),
        ],
        if (booleanFields.isNotEmpty) ...[
          const OdooSectionTitle('Flags'),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: booleanFields.map((f) {
                return Chip(
                  avatar: const Icon(
                    PhosphorIconsFill.checkCircle,
                    color: AppColors.statusDone,
                    size: 18,
                  ),
                  label: Text(
                    fieldDefs[f]['string'] ?? f,
                    style: GoogleFonts.poppins(fontSize: 12),
                  ),
                  backgroundColor:
                      AppColors.statusDone.withValues(alpha: 0.1),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 32),
        ],
        if (otherFields.isNotEmpty) ...[
          const OdooSectionTitle('Details'),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: otherFields.map((f) {
                final valStr = fieldValues[f]?.toString() ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OdooFieldRow(
                      label: fieldDefs[f]['string'] ?? f,
                      value: valStr.isEmpty ? 'None' : valStr,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}
