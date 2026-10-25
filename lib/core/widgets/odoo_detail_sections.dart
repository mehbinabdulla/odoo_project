import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
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

  /// Relations whose records carry a square `image_128` avatar.
  static const Set<String> _avatarModels = {
    'res.users',
    'res.partner',
    'hr.employee',
  };

  static String? _avatarFieldFor(String? relation) =>
      _avatarModels.contains(relation) ? 'image_128' : null;

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
        // Inline dict records (some deployments return display data
        // with the ids).
        final inlineNames = val.map((e) {
          if (e is Map) {
            return (e['display_name'] ?? e['name'] ?? '#${e['id']}').toString();
          }
          return e.toString();
        }).toList();

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
                'date',
                'employee_id',
              ];
            } else if (type == 'many2many' &&
                _avatarFieldFor(relation) != null) {
              // Pull the member avatar alongside the display name so
              // many2many chips can render the photo like the web
              // client's m2o tags.
              fieldsToFetch = [...fieldsToFetch, _avatarFieldFor(relation)!];
            }
            // Hydrate by ids with plain `read` — matching the web
            // client. `search_read` applies Odoo's default
            // `active_test=True` and silently drops archived members
            // (deactivated bot users, archived tags…) from x2many chips.
            final ids = [
              for (final e in val)
                if (e is num) e.toInt(),
            ];
            if (ids.isNotEmpty) {
              final relRecords = await OdooRpcService.read(
                model: relation,
                ids: ids,
                fields: fieldsToFetch,
              );
              // one2many feeds the record mini-lists; many2many keeps
              // the hydrated records so chips can show both the
              // display name and the member avatar photo.
              out[key] = relRecords;
            } else {
              out[key] = inlineNames;
            }
          } catch (_) {
            if (type == 'one2many') {
              out[key] = List.generate(
                val.length,
                (i) => {'id': val[i], 'display_name': 'Record ${val[i]}'},
              );
            } else {
              out[key] = inlineNames;
            }
          }
        } else {
          out[key] = inlineNames;
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

  /// Fields Odoo web renders via its own widgets (title bar, chatter,
  /// stat buttons) that add no value in a mobile details list.
  static const Set<String> noiseDetailFields = {
    'display_name',
    'portal_url',
    'message_follower_ids',
    'message_ids',
    'message_main_attachment_id',
    'status_time',
  };

  /// Field keys that are internal plumbing (tokens, hashes); hidden
  /// from the mobile details list in addition to the explicit set.
  static bool isNoiseKey(String key) =>
      noiseDetailFields.contains(key) ||
      key.endsWith('_token') ||
      key.endsWith('_hash');

  /// Orders visible fields: defaults first (in default order), then
  /// alphabetically by label.
  static List<String> orderedDetailFields({
    required Set<String> visible,
    required Map<String, dynamic> fieldDefs,
    required Set<String> defaultFields,
    Set<String> exclude = const {},
  }) {
    final defaults = defaultFields.toList();
    final dropped = {...exclude};
    final list = visible
        .where(
          (f) =>
              fieldDefs.containsKey(f) &&
              !dropped.contains(f) &&
              !OdooDetailSections.isNoiseKey(f),
        )
        .toList();
    list.sort((a, b) {
      final aDef = defaultFields.contains(a);
      final bDef = defaultFields.contains(b);
      if (aDef && !bDef) return -1;
      if (!aDef && bDef) return 1;
      if (aDef && bDef) {
        return defaults.indexOf(a).compareTo(defaults.indexOf(b));
      }
      return (fieldDefs[a]?['string'] ?? a).toString().compareTo(
        (fieldDefs[b]?['string'] ?? b).toString(),
      );
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

/// Renders one details-list field with widget-type-specific visuals,
/// mirroring how Odoo web renders its field widgets — mobile-tuned.
class OdooTypedValueWidget extends StatelessWidget {
  final String label;
  final String type;
  final String? relation;
  final dynamic value;

  /// View-level widget attr (e.g. `badge` from
  /// `<field name="x" widget="badge"/>`); wins over the field type.
  final String? viewWidget;

  const OdooTypedValueWidget({
    super.key,
    required this.label,
    required this.type,
    this.relation,
    this.value,
    this.viewWidget,
  });

  @override
  Widget build(BuildContext context) {
    switch (_effectiveType(viewWidget, type)) {
      case 'badge':
        return _ChipDetail(
          label: label,
          items: _chipItems(value),
          icon: _leadIconFor(relation),
        );
      case 'url':
        return _MonoDetail(label: label, value: value?.toString());
      case 'email':
        return _MonoDetail(label: label, value: value?.toString());
      case 'many2one':
        return _LinkDetail(
          label: label,
          value: value?.toString(),
          icon: _leadIconFor(relation),
        );
      case 'many2many':
      case 'one2many':
        return _ChipDetail(
          label: label,
          items: _chipItems(value),
          icon: _leadIconFor(relation),
        );
      case 'selection':
      case 'stateSelection':
      case 'radio':
        return _SelectionDetail(label: label, value: value?.toString());
      case 'text':
        return _TextDetail(label: label, value: value?.toString());
      case 'html':
      case 'htmlc':
        return _HtmlDetail(label: label, value: value?.toString());
      case 'char':
        return _LinkDetail(
          label: label,
          value: value?.toString(),
          icon: _leadIconFor(relation, fallback: PhosphorIconsRegular.textbox),
          mono: _looksLikeUrl(value),
        );
      // Proper rows for primitive types — no more generic "$" card for
      // numbers, dates and booleans.
      case 'floatTime':
        return _FloatTimeDetail(label: label, value: value);
      case 'float':
      case 'integer':
      case 'monetary':
      case 'number':
        return _NumberDetail(label: label, value: value);
      case 'percent':
        return _NumberDetail(label: label, value: value, suffix: '%');
      case 'date':
      case 'datetime':
        return _DateDetail(label: label, value: value?.toString());
      case 'boolean':
        return _BooleanDetail(label: label, value: value);
      case 'priority':
        return _PriorityDetail(label: label, value: value);
      case 'properties':
        return _PropertiesDetail(value);
      default:
        return _LinkDetail(
          label: label,
          value: value?.toString(),
          icon: _leadIconFor(
            relation,
            fallback: PhosphorIconsRegular.currencyDollar,
          ),
          mono: _looksLikeUrl(value),
        );
    }
  }

  /// Maps view-level `widget="…"` renderers onto the renderer family
  /// that knows how to draw them. Without this, common Odoo widgets
  /// like `many2many_tags` fell to the generic branch and dumped raw
  /// values ("[]") instead of chips.
  static String _effectiveType(String? viewWidget, String type) {
    switch (viewWidget) {
      case 'many2many_tags':
      case 'many2many_checkboxes':
      case 'many2many':
        return 'many2many';
      case 'one2many_list':
      // Widget-name mapping: Odoo ≤ 17 uses <tree>, Odoo 18+ renamed
      // the tag to <list> — both accepted as the x2many list widget.
      case 'list':
      case 'tree':
        return 'one2many';
      case 'url':
        return 'url';
      case 'email':
        return 'email';
      case 'badge':
        return 'badge';
      // Rich text content (web shows it in an editor field).
      case 'html':
        return 'html';
      // Odoo time/unit widgets → hours "02:30".
      case 'float_time':
      case 'timesheet_uom':
      case 'timesheet_uom_no_toggle':
        return 'floatTime';
      // Boolean renderers → yes/no pill.
      case 'boolean_icon':
      case 'boolean_button':
        return 'boolean';
      // Priority (star count).
      case 'priority':
      case 'priority_switch':
        return 'priority';
      // Stat info numbers / progress bars (progress carries a % suffix).
      case 'statinfo':
        return 'number';
      case 'progressbar':
        return 'percent';
      default:
        return type;
    }
  }

  static bool _looksLikeUrl(dynamic v) {
    final s = v?.toString() ?? '';
    return s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.startsWith('/');
  }

  static IconData _leadIconFor(
    String? relation, {
    IconData fallback = PhosphorIconsRegular.cube,
  }) {
    switch (relation) {
      case 'res.partner':
      case 'res.users':
        return PhosphorIconsRegular.user;
      case 'res.company':
        return PhosphorIconsRegular.buildings;
      case 'project.project':
        return PhosphorIconsRegular.briefcase;
      case 'project.task':
        return PhosphorIconsRegular.checkSquare;
      case 'account.analytic.account':
        return PhosphorIconsRegular.chartLine;
      default:
        return fallback;
    }
  }

  /// Decodes an inline base64 avatar (accepts data-uri prefixes);
  /// returns null for anything that isn't a real image so the chip
  /// falls back to its icon instead of an error box.
  static Uint8List? _decodeAvatar(dynamic raw) {
    if (raw is! String || raw.trim().length < 16) return null;
    var b64 = raw.trim();
    final marker = b64.indexOf('base64,');
    if (marker >= 0) b64 = b64.substring(marker + 7);
    try {
      final bytes = base64Decode(b64.replaceAll('\n', ''));
      final looksLikeImage =
          bytes.length > 8 &&
          ((bytes[0] == 0x89 && bytes[1] == 0x50) || // PNG
              (bytes[0] == 0xFF && bytes[1] == 0xD8) || // JPEG
              (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46));
      return looksLikeImage ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  /// chip data → list of [display name, optional avatar bytes].
  static List<_ChipItem> _chipItems(dynamic v) {
    if (v is List) {
      return v.map((e) {
        if (e is Map) {
          return _ChipItem(
            (e['display_name'] ?? e['name'] ?? '#${e['id']}').toString(),
            _decodeAvatar(e['image_128']),
          );
        }
        return _ChipItem(e.toString());
      }).toList();
    }
    if (v is String && v.trim().isNotEmpty) {
      return v.split(', ').map(_ChipItem.new).toList();
    }
    return [];
  }
}

/// The shared visual shell of the detail field cards — inner padding,
/// corner radius, fill and border live HERE so a styling tweak is a
/// single-place edit. The matching lead icon tile is [_TintedLead].
/// Tune the static [padding] / [radius] fields to restyle every card.
class _DetailCard extends StatelessWidget {
  /// Inner spacing shared by every detail field card.
  static const EdgeInsetsGeometry padding = EdgeInsets.symmetric(
    horizontal: 6,
    vertical: 6,
  );

  /// Corner radius shared by every detail field card.
  static const double radius = 12;

  final Widget child;

  const _DetailCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: child,
    );
  }
}

/// Tinted circular badge with the field-type icon.
class _TintedLead extends StatelessWidget {
  final IconData icon;

  const _TintedLead(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 16, color: AppColors.primary),
    );
  }
}

/// Shared label header for the typed details widgets.
class _DetailLabel extends StatelessWidget {
  final String label;

  const _DetailLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// many2one: icon + linked-looking value + chevron (like Odoo's
/// many2one tag with a pointer into the record).
class _LinkDetail extends StatelessWidget {
  final String label;
  final String? value;
  final IconData icon;
  final bool mono;

  const _LinkDetail({
    required this.label,
    this.value,
    required this.icon,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = (value == null || value!.trim().isEmpty) ? 'None' : value!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailLabel(label),
        const SizedBox(height: 8),
        _DetailCard(
          child: Row(
            children: [
              _TintedLead(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: mono
                      ? GoogleFonts.robotoMono(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface,
                        )
                      : GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                PhosphorIconsRegular.caretRight,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// x2many: bordered card holding one compact chip per related record —
/// matches the visual weight of the other field cards (link, value…).
/// One many2many chip: display name plus an optional member avatar.
class _ChipItem {
  final String label;
  final Uint8List? avatar;

  const _ChipItem(this.label, [this.avatar]);
}

/// x2many: bordered card holding one compact chip per related record —
/// matches the visual weight of the other field cards (link, value…).
/// Chips render the member's `image_128` avatar when hydration
/// provides one, mirroring the web client's m2o tags.
class _ChipDetail extends StatelessWidget {
  final String label;
  final List<_ChipItem> items;
  final IconData icon;

  const _ChipDetail({
    required this.label,
    required this.items,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Empty relation → single 'None' placeholder chip.
    final displayed = items.isEmpty
        ? <_ChipItem>[_ChipItem(label)]
        : items;
    final isEmpty = items.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailLabel(label),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in displayed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isEmpty
                        ? null
                        : AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isEmpty
                          ? theme.colorScheme.outline.withValues(alpha: 0.3)
                          : AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.avatar != null)
                        ClipOval(
                          child: Image.memory(
                            item.avatar!,
                            width: 16,
                            height: 16,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _chipIcon(context, isEmpty),
                          ),
                        )
                      else
                        _chipIcon(context, isEmpty),
                      const SizedBox(width: 5),
                      Text(
                        item.label,
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chipIcon(BuildContext context, bool isEmpty) {
    final theme = Theme.of(context);
    return Icon(
      isEmpty ? PhosphorIconsRegular.circleDashed : icon,
      size: 12,
      color: isEmpty
          ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
          : AppColors.primary,
    );
  }
}

/// selection: tinted status pill.
class _SelectionDetail extends StatelessWidget {
  final String label;
  final String? value;

  const _SelectionDetail({required this.label, this.value});

  static Color _tintFor(String v) {
    final s = v.toLowerCase();
    if (s.contains('done') || s.contains('paid') || s.contains('approved')) {
      return AppColors.statusDone;
    }
    if (s.contains('cancel') || s.contains('block') || s.contains('denied')) {
      return AppColors.statusBlocked;
    }
    if (s.contains('progress') || s.contains('progress')) {
      return AppColors.statusInProgress;
    }
    if (s.contains('wait') || s.contains('review')) {
      return AppColors.statusReview;
    }
    return AppColors.statusInProgress;
  }

  @override
  Widget build(BuildContext context) {
    final tint = _tintFor(value ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailLabel(label),
        const SizedBox(height: 8),
        Wrap(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsFill.circle, size: 9, color: tint),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      (value == null || value!.isEmpty) ? 'None' : value!,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tint,
                      ),
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// text: selectable multi-line block.
class _TextDetail extends StatelessWidget {
  final String label;
  final String? value;

  const _TextDetail({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailLabel(label),
        const SizedBox(height: 6),
        SelectableText(
          value ?? 'None',
          style: GoogleFonts.poppins(
            fontSize: 14,
            height: 1.5,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.9),
          ),
          maxLines: 8,
        ),
      ],
    );
  }
}

/// html: rendered rich content — shown inside the standard field card
/// so it aligns with the other field rows. Empty / 'false' values fall
/// back to the same "None" placeholder as the other cards.
class _HtmlDetail extends StatelessWidget {
  final String label;
  final String? value;

  const _HtmlDetail({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = value ?? '';
    final trimmed = text.toLowerCase().trim();
    final hasContent =
        trimmed.isNotEmpty && trimmed != 'false' && trimmed != '<p><br></p>';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailLabel(label),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: hasContent
              ? HtmlWidget(
                  text,
                  // data-URI images inside rich text (Odoo inline
                  // screenshots/embedded svg) can fail the codec — show a
                  // small placeholder instead of printing the exception.
                  onErrorBuilder: (context, element, error) => Icon(
                    PhosphorIconsRegular.imageBroken,
                    size: 24,
                    color: AppColors.primary.withValues(alpha: 0.5),
                  ),
                  textStyle: GoogleFonts.poppins(
                    fontSize: 13.5,
                    height: 1.55,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                )
              : Text(
                  'None',
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Copyable monospace block (urls, paths, references).
class _MonoDetail extends StatelessWidget {
  final String label;
  final String? value;

  const _MonoDetail({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailLabel(label),
        const SizedBox(height: 8),
        _DetailCard(
          child: Row(
            children: [
              _TintedLead(PhosphorIconsRegular.linkSimpleHorizontal),
              const SizedBox(width: 10),
              Expanded(
                child: SelectableText(
                  value ?? '/None',
                  style: GoogleFonts.robotoMono(
                    fontSize: 13,
                    color: AppColors.primary,
                    decoration: TextDecoration.underline,
                  ),
                  maxLines: 2,
                ),
              ),
              IconButton(
                tooltip: 'Copy to clipboard',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Copied to clipboard'),
                      backgroundColor: AppColors.statusDone,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: Icon(
                  PhosphorIconsRegular.copy,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shared small value card: tinted icon + value text under a label —
/// the same visual language as the many2one link card, minus chevron.
class _ValueCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final bool mono;

  const _ValueCard({
    required this.label,
    required this.icon,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailLabel(label),
        const SizedBox(height: 8),
        _DetailCard(
          child: Row(
            children: [
              _TintedLead(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value.isEmpty ? 'None' : value,
                  style: mono
                      ? GoogleFonts.robotoMono(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        )
                      : GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Odoo float_time / timesheet_uom → hours rendered "02:30", like the
/// web widget shows "00:00 (0 %)".
class _FloatTimeDetail extends StatelessWidget {
  final String label;
  final dynamic value;

  const _FloatTimeDetail({required this.label, this.value});

  static String _hours(num v) {
    final negative = v < 0;
    final n = v.abs();
    final h = n.floor();
    final m = ((n - h) * 60).round();
    final raw =
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    return negative ? '-$raw' : raw;
  }

  @override
  Widget build(BuildContext context) {
    final n = value is num
        ? value as num
        : num.tryParse(value?.toString() ?? '');
    return _ValueCard(
      label: label,
      icon: PhosphorIconsRegular.clock,
      value: n == null ? '' : _hours(n),
      mono: true,
    );
  }
}

/// Numeric fields (float / integer / monetary) — plain number row,
/// replacing the old generic currency-icon card.
class _NumberDetail extends StatelessWidget {
  final String label;
  final dynamic value;

  /// Unit suffix appended to the value, e.g. "%" for progress bars.
  final String? suffix;

  const _NumberDetail({required this.label, this.value, this.suffix});

  @override
  Widget build(BuildContext context) {
    String text;
    if (value is num) {
      text = ArchNumber.format(value as num);
    } else {
      final raw = value?.toString() ?? '';
      final d = double.tryParse(raw);
      text = d == null ? raw : ArchNumber.format(d);
    }
    if (suffix != null && text.isNotEmpty && text != 'None') {
      text = '$text $suffix';
    }
    return _ValueCard(
      label: label,
      icon: PhosphorIconsRegular.chartBar,
      value: text,
    );
  }
}

/// Date / datetime row with the calendar lead icon (web shows a
/// datepicker chip).
class _DateDetail extends StatelessWidget {
  final String label;
  final String? value;

  const _DateDetail({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    return _ValueCard(
      label: label,
      icon: PhosphorIconsRegular.calendarBlank,
      value: value ?? '',
    );
  }
}

/// Tri-state coercion: true / false / unknown.
bool? _asTriState(dynamic v) {
  if (v == true) return true;
  if (v == null || v == false) return false;
  final s = v.toString();
  if (s == 'true' || s == 'True' || s == '1') return true;
  if (s == 'false' || s == 'False' || s == '0' || s.isEmpty) return false;
  return null;
}

/// Boolean (boolean_icon widget or plain bool) → Yes / No tinted pill,
/// like the web's ✓ / ✗ boolean buttons.
class _BooleanDetail extends StatelessWidget {
  final String label;
  final dynamic value;

  const _BooleanDetail({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final v = _asTriState(value);
    final on = v == true;
    final tint = on ? AppColors.statusDone : AppColors.statusTodo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailLabel(label),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: tint.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on
                    ? PhosphorIconsFill.checkCircle
                    : PhosphorIconsRegular.circleDashed,
                size: 14,
                color: tint,
              ),
              const SizedBox(width: 6),
              Text(
                on ? 'Yes' : (v == false ? 'No' : '—'),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Odoo priority (star rating) — filled stars up to the value, like the
/// web form's star switcher.
class _PriorityDetail extends StatelessWidget {
  final String label;
  final dynamic value;

  const _PriorityDetail({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = value?.toString() ?? '';
    final parsed = int.tryParse(raw) ?? double.tryParse(raw)?.round() ?? 0;
    final stars = parsed.clamp(0, 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailLabel(label),
        const SizedBox(height: 8),
        Row(
          children: List.generate(3, (i) {
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                i < stars ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
                size: 20,
                color: i < stars
                    ? AppColors.statusReview
                    : theme.colorScheme.onSurface.withValues(alpha: 0.2),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// Number formatting without float noise: 0.0 → "0", 2.5 → "2.5".
class ArchNumber {
  const ArchNumber._();

  static String format(num v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toString();
  }
}

/// Odoo "properties" field (per-task dynamic attributes defined on the
/// project). The web client renders nothing when the value list is
/// empty — mirror that; otherwise one label:value chip per property.
class _PropertiesDetail extends StatelessWidget {
  final dynamic value;

  const _PropertiesDetail(this.value);

  static String _propValue(Map p) {
    final v = p['value'];
    if (v is List) {
      return v
          .map(
            (e) => e is Map
                ? (e['display_name'] ?? e['name'] ?? '').toString()
                : e.toString(),
          )
          .join(', ');
    }
    if (v is bool) return v ? 'Yes' : 'No';
    return v?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final props = [
      if (value is List)
        for (final p in value as List)
          if (p is Map) p,
    ];
    // Empty properties → the web form shows no section at all.
    if (props.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in props)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIconsRegular.tag,
                      size: 13,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${p['string'] ?? p['name'] ?? '?'}: ${_propValue(p)}',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
          ],
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

  /// View-level widget hints per field, e.g. {"name": "badge"}
  /// from `<field name="name" widget="badge"/>` in the form view XML.
  final Map<String, String> viewWidgets;

  const OdooDetailGroups({
    super.key,
    required this.fieldDefs,
    required this.fieldValues,
    required this.metricFields,
    required this.dateFields,
    required this.booleanFields,
    required this.otherFields,
    this.viewWidgets = const {},
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
                  backgroundColor: AppColors.statusDone.withValues(alpha: 0.1),
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
              children: otherFields
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OdooTypedValueWidget(
                          label: fieldDefs[f]['string']?.toString() ?? f,
                          type: fieldDefs[f]['type']?.toString() ?? '',
                          relation: fieldDefs[f]['relation']?.toString(),
                          value: fieldValues[f],
                          viewWidget: viewWidgets[f],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }
}
