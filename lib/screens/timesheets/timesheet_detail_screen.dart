import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/models/project_models.dart';
import '../../core/services/odoo_field_registry.dart';
import '../../core/services/odoo_rpc_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/collapsing_app_bar_page.dart';
import '../../core/utils/route_observer.dart';
import 'timesheet_form_screen.dart';

class TimesheetDetailScreen extends StatefulWidget {
  final TimesheetModel timesheet;

  const TimesheetDetailScreen({super.key, required this.timesheet});

  @override
  State<TimesheetDetailScreen> createState() => _TimesheetDetailScreenState();
}

class _TimesheetDetailScreenState extends State<TimesheetDetailScreen> with RouteAwareRefetchMixin {
  bool _isLoading = true;

  Map<String, dynamic> _fieldDefs = {};
  Map<String, dynamic> _fieldValues = {};
  Set<String> _visibleFields = {};

  // Fields that are always shown first (in order)
  final Set<String> _defaultFields = {
    'project_id',
    'task_id',
    'date',
    'unit_amount',
    'employee_id',
    'user_id',
    'name',
  };

  // Header-level fields not shown in the grid
  static const Set<String> _headerFields = {'name', 'unit_amount', 'date'};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void refetch() {
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);

    final defs = await OdooFieldRegistry.getFieldDefs('account.analytic.line');
    if (!mounted) return;

    _fieldDefs = defs;
    _fieldValues = {};
    _visibleFields = Set.from(_defaultFields);

    try {
      final records = await OdooRpcService.searchRead(
        model: 'account.analytic.line',
        domain: [
          ['id', '=', widget.timesheet.id],
        ],
        fields: _fieldDefs.keys.toList(),
        limit: 1,
      );

      if (records.isNotEmpty) {
        final data = records[0];

        for (final key in _fieldDefs.keys) {
          final type = _fieldDefs[key]['type'];
          final val = data[key];

          if (val == null || val == false || val == '') continue;

          if (type == 'many2one' && val is List && val.length == 2) {
            _fieldValues[key] = val[1];
          } else if ((type == 'many2many' || type == 'one2many') &&
              val is List &&
              val.isNotEmpty) {
            final relation = _fieldDefs[key]['relation'];
            if (relation != null) {
              try {
                final relRecords = await OdooRpcService.searchRead(
                  model: relation,
                  domain: [
                    ['id', 'in', val],
                  ],
                  fields: ['display_name', 'name'],
                );
                if (type == 'one2many') {
                  _fieldValues[key] = relRecords;
                } else {
                  final names = relRecords
                      .map((r) => r['display_name'] ?? r['name'] ?? 'Unknown')
                      .toList();
                  _fieldValues[key] = names.join(', ');
                }
              } catch (_) {
                _fieldValues[key] = type == 'one2many'
                    ? List.generate(val.length, (i) => 'Record ${val[i]}')
                    : '${val.length} records';
              }
            }
          } else if (type == 'date' || type == 'datetime') {
            final parsed = DateTime.tryParse(val.toString());
            if (parsed != null) {
              _fieldValues[key] = parsed.toString().split(' ')[0];
            }
          } else if (type == 'selection') {
            final selectionDef = _fieldDefs[key]['selection'] as List?;
            if (selectionDef != null) {
              final match = selectionDef.firstWhere(
                (e) => e[0] == val,
                orElse: () => [val, val.toString()],
              );
              _fieldValues[key] = match[1];
            }
          } else {
            if (val is List && val.isEmpty) continue;
            _fieldValues[key] = val.toString();
          }

          if (!_headerFields.contains(key) && _fieldValues[key] != null) {
            _visibleFields.add(key);
          }
        }
      }
    } catch (e) {
      // Fallback to model values
      if (widget.timesheet.projectName != null) {
        _fieldValues['project_id'] = widget.timesheet.projectName;
      }
      if (widget.timesheet.taskName != null) {
        _fieldValues['task_id'] = widget.timesheet.taskName;
      }
      _fieldValues['date'] = widget.timesheet.date;
      _fieldValues['unit_amount'] = widget.timesheet.unitAmount.toString();
      if (widget.timesheet.userName != null) {
        _fieldValues['employee_id'] = widget.timesheet.userName;
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ts = widget.timesheet;
    final hoursStr = ts.hoursFormatted;

    return CollapsingAppBarPage(
      title: ts.name?.isNotEmpty == true ? ts.name! : 'Timesheet Entry',
      onRefresh: _loadData,
      titleWidget: Text(
        hoursStr,
        style: GoogleFonts.dmSerifDisplay(
          fontSize: 36,
          height: 1.1,
          color: AppColors.primary,
        ),
      ),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(PhosphorIconsBold.caretLeft, size: 20),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TimesheetFormScreen(timesheet: widget.timesheet),
              ),
            );
            // Refresh after edit
            _loadData();
          },
          icon: const Icon(PhosphorIconsBold.pencilSimple, size: 20),
        ),
      ],
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else
              _buildContent(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    // Header info row: date + project
    final dateStr = _fieldValues['date']?.toString() ?? widget.timesheet.date;
    final projectStr =
        _fieldValues['project_id']?.toString() ??
        widget.timesheet.projectName ??
        '';
    final taskStr =
        _fieldValues['task_id']?.toString() ?? widget.timesheet.taskName;
    final descStr = _fieldValues['name']?.toString() ?? widget.timesheet.name;

    // Build ordered visible fields (excluding header ones already shown above)
    final orderedFields = _visibleFields
        .where(
          (f) =>
              _fieldDefs.containsKey(f) &&
              !_headerFields.contains(f) &&
              f != 'project_id' &&
              f != 'task_id',
        )
        .toList();

    orderedFields.sort((a, b) {
      final aDef = _defaultFields.contains(a);
      final bDef = _defaultFields.contains(b);
      if (aDef && !bDef) return -1;
      if (!aDef && bDef) return 1;
      if (aDef && bDef) {
        return _defaultFields
            .toList()
            .indexOf(a)
            .compareTo(_defaultFields.toList().indexOf(b));
      }
      final aStr = _fieldDefs[a]?['string'] ?? a;
      final bStr = _fieldDefs[b]?['string'] ?? b;
      return aStr.toString().compareTo(bStr.toString());
    });

    final dateFields = <String>[];
    final metricFields = <String>[];
    final booleanFields = <String>[];
    final otherFields = <String>[];

    for (final f in orderedFields) {
      final type = _fieldDefs[f]?['type'];
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Summary card ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (descStr != null && descStr.isNotEmpty) ...[
                  Text(
                    descStr,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      height: 1.5,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Project row
                Row(
                  children: [
                    Icon(
                      PhosphorIconsFill.folder,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        projectStr,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Date chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIconsRegular.calendarBlank,
                            size: 12,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dateStr,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (taskStr != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        PhosphorIconsRegular.checkCircle,
                        size: 13,
                        color: isDark ? Colors.white70 : AppColors.accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          taskStr,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : AppColors.accent,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        // ── Metrics ───────────────────────────────────────────────────────────
        if (metricFields.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Metrics',
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 20,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
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
                  child: _infoCard(
                    _fieldDefs[f]['string'] ?? f,
                    _fieldValues[f].toString(),
                    PhosphorIconsRegular.chartBar,
                    theme,
                    isDark,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],

        // ── Timeline ──────────────────────────────────────────────────────────
        if (dateFields.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Timeline',
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 20,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
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
                      Icon(
                        PhosphorIconsRegular.calendar,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fieldDefs[f]['string'] ?? f,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          Text(
                            _fieldValues[f].toString(),
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

        // ── Flags ─────────────────────────────────────────────────────────────
        if (booleanFields.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Flags',
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 20,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
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
                    color: Colors.green,
                    size: 18,
                  ),
                  label: Text(
                    _fieldDefs[f]['string'] ?? f,
                    style: GoogleFonts.poppins(fontSize: 12),
                  ),
                  backgroundColor: Colors.green.withValues(alpha: 0.1),
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

        // ── Details ───────────────────────────────────────────────────────────
        if (otherFields.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Details',
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 20,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: otherFields.map((f) {
                final valStr = _fieldValues[f]?.toString() ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: _fieldRow(
                      _fieldDefs[f]['string'] ?? f,
                      valStr.isEmpty ? 'None' : valStr,
                      theme,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _fieldRow(String label, String value, ThemeData theme) {
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
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _infoCard(
    String label,
    String value,
    IconData icon,
    ThemeData theme,
    bool isDark,
  ) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
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
