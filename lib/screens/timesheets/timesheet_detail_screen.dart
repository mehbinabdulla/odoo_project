import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/models/project_models.dart';
import '../../core/services/odoo_field_registry.dart';
import '../../core/services/odoo_rpc_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/collapsing_app_bar_page.dart';
import '../../core/widgets/odoo_arch_detail_view.dart';
import '../../core/widgets/odoo_detail_sections.dart';
import '../../core/utils/route_observer.dart';
import 'timesheet_form_screen.dart';

class TimesheetDetailScreen extends StatefulWidget {
  final TimesheetModel timesheet;

  const TimesheetDetailScreen({super.key, required this.timesheet});

  @override
  State<TimesheetDetailScreen> createState() => _TimesheetDetailScreenState();
}

class _TimesheetDetailScreenState extends State<TimesheetDetailScreen>
    with RouteAwareRefetchMixin {
  bool _isLoading = true;

  Map<String, dynamic> _fieldDefs = {};
  Map<String, dynamic> _fieldValues = {};
  Set<String> _visibleFields = {};
  // View-level widget hints (widget="…") from the form view XML arch.
  Map<String, String> _viewWidgets = {};
  // Form view XML — drives the arch-based details layout.
  String? _arch;

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

  Future<void> _loadData({bool force = false}) async {
    if (mounted) setState(() => _isLoading = true);

    final defs = await OdooFieldRegistry.getFieldDefs(
      'account.analytic.line',
      force: force,
    );
    if (!mounted) return;

    _fieldDefs = defs;
    _fieldValues = {};
    _visibleFields = Set.from(_defaultFields);
    _viewWidgets = await OdooFieldRegistry.getViewWidgets(
      'account.analytic.line',
      force: force,
    );
    _arch = await OdooFieldRegistry.getFormArch(
      'account.analytic.line',
      force: force,
    );

    try {
      final records = await OdooRpcService.searchRead(
        model: 'account.analytic.line',
        domain: [
          ['id', '=', widget.timesheet.id],
        ],
        fields: _fieldDefs.keys.toList(),
        limit: 1,
      );
      if (!mounted) return;

      if (records.isNotEmpty) {
        final valued = await OdooDetailSections.parseDetailRecord(
          data: records[0],
          fieldDefs: _fieldDefs,
          out: _fieldValues,
        );
        if (!mounted) return;
        for (final key in valued) {
          if (!_headerFields.contains(key)) {
            _visibleFields.add(key);
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
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
      onRefresh: () => _loadData(force: true),
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
            tooltip: 'Back',
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
            if (!mounted) return;
            // Refresh after edit
            _loadData();
          },
          icon: const Icon(PhosphorIconsBold.pencilSimple, size: 20),
          tooltip: 'Edit Time Entry',
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
    final orderedFields = OdooDetailSections.orderedDetailFields(
      visible: _visibleFields,
      fieldDefs: _fieldDefs,
      defaultFields: _defaultFields,
      exclude: {..._headerFields, 'project_id', 'task_id'},
    );
    final groups = OdooDetailSections.groupDetailFields(
      ordered: orderedFields,
      fieldDefs: _fieldDefs,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Summary card ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
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
                    const Icon(
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
                          const Icon(
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

        OdooArchDetailView(
          arch: _arch,
          fieldDefs: _fieldDefs,
          fieldValues: _fieldValues,
          viewWidgets: _viewWidgets,
          fallback: OdooDetailGroups(
            fieldDefs: _fieldDefs,
            fieldValues: _fieldValues,
            metricFields: groups['metrics']!,
            dateFields: groups['dates']!,
            booleanFields: groups['booleans']!,
            otherFields: groups['other']!,
            viewWidgets: _viewWidgets,
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
