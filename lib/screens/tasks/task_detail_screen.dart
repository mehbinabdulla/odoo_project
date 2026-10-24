import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/models/project_models.dart';

import '../../core/theme/app_theme.dart';

import '../../core/services/odoo_field_registry.dart';
import '../../core/services/odoo_rpc_service.dart';
import '../../core/widgets/collapsing_app_bar_page.dart';
import '../../core/widgets/odoo_detail_sections.dart';
import '../../core/utils/route_observer.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'task_form_screen.dart';

class TaskDetailScreen extends StatefulWidget {
  final TaskModel task;

  const TaskDetailScreen({super.key, required this.task});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> with RouteAwareRefetchMixin {

  bool _isLoading = true;

  Map<String, dynamic> _fieldDefs = {};
  final Map<String, dynamic> _fieldValues = {};
  final Map<String, dynamic> _rawValues = {};
  Set<String> _visibleFields = {};

  final Set<String> _defaultFields = {
    'project_id',
    'user_ids',
    'tag_ids',
    'partner_id',
    'date_deadline',
  };

  // Header-level fields rendered above the grid, not inside it.
  static const Set<String> _headerFields = {
    'name',
    'description',
    'state',
    'priority',
    'kanban_state',
  };

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
    final defs = await OdooFieldRegistry.getFieldDefs('project.task');
    if (!mounted) return;

    _fieldDefs = defs;
    _visibleFields = Set.from(_defaultFields);

    try {
      final records = await OdooRpcService.searchRead(
        model: 'project.task',
        domain: [
          ['id', '=', widget.task.id],
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
          rawOut: _rawValues,
        );
        if (!mounted) return;
        for (final key in valued) {
          if (!_headerFields.contains(key)) {
            _visibleFields.add(key);
          }
        }
      }
    } catch (e) {
      // Fallback
      if (!mounted) return;
      _fieldValues['project_id'] = widget.task.projectName;
      _fieldValues['user_ids'] = widget.task.userNames.join(', ');
      _fieldValues['tag_ids'] = widget.task.tagNames.join(', ');
      _fieldValues['partner_id'] = widget.task.partnerName;
      _fieldValues['date_deadline'] = widget.task.deadline;
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CollapsingAppBarPage(
      title: _fieldValues['name'] ?? widget.task.name,
      onRefresh: _loadData,
      titleWidget: Text(
        _fieldValues['name'] ?? widget.task.name,
        style: GoogleFonts.dmSerifDisplay(
          fontSize: 30,
          height: 1.15,
          color: theme.colorScheme.onSurface,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
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
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TaskFormScreen(task: widget.task),
              ),
            );
          },
          icon: const Icon(PhosphorIconsBold.pencilSimple, size: 20),
          tooltip: 'Edit Task',
        ),
        if (!_isLoading)
          PopupMenuButton<String>(
            icon: Icon(
              PhosphorIconsBold.dotsThreeVertical,
              color: theme.colorScheme.onSurface,
              size: 20,
            ),
            tooltip: 'More options',
            color: theme.cardTheme.color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (val) {
              if (val == 'subtasks') {
                _showRelatedList(context, 'Sub-tasks', []);
              } else {
                _showRelatedList(
                  context,
                  _fieldDefs[val]?['string'] ?? val,
                  _fieldValues[val] as List,
                );
              }
            },
            itemBuilder: (ctx) {
              final oneToManyKeys = _fieldValues.keys
                  .where(
                    (k) =>
                        _fieldDefs[k]?['type'] == 'one2many' &&
                        _fieldValues[k] is List,
                  )
                  .toList();
              return [
                PopupMenuItem(
                  value: 'subtasks',
                  child: Text(
                    'Sub-tasks',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                  ),
                ),
                for (final key in oneToManyKeys)
                  PopupMenuItem(
                    value: key,
                    child: Text(
                      _fieldDefs[key]?['string'] ?? key,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    ),
                  ),
              ];
            },
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
              // Content area
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((_fieldValues['description'] ?? widget.task.description) != null &&
                      (_fieldValues['description'] ?? widget.task.description)!.trim().isNotEmpty &&
                      (_fieldValues['description'] ?? widget.task.description) != 'false') ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: HtmlWidget(
                        _fieldValues['description'] ?? widget.task.description!,
                        textStyle: GoogleFonts.poppins(
                          fontSize: 14,
                          height: 1.6,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        _StatusBadge(
                          state: _fieldValues['state'] ?? widget.task.state ?? '',
                          label: _resolveStateLabel(
                            _fieldValues['state'] ?? widget.task.state ?? '',
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: List.generate(
                            3,
                            (i) => Icon(
                              _isStarFilled(i)
                                  ? PhosphorIconsFill.star
                                  : PhosphorIconsRegular.star,
                              size: 20,
                              color: _isStarFilled(i)
                                  ? AppColors.statusReview
                                  : theme.colorScheme.onSurface
                                        .withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Odoo Style Grid layout for fields
                  Builder(
                    builder: (context) {
                      final orderedFields =
                          OdooDetailSections.orderedDetailFields(
                        visible: _visibleFields,
                        fieldDefs: _fieldDefs,
                        defaultFields: _defaultFields,
                      );
                      final groups = OdooDetailSections.groupDetailFields(
                        ordered: orderedFields,
                        fieldDefs: _fieldDefs,
                      );

                      return OdooDetailGroups(
                        fieldDefs: _fieldDefs,
                        fieldValues: _fieldValues,
                        metricFields: groups['metrics']!,
                        dateFields: groups['dates']!,
                        booleanFields: groups['booleans']!,
                        otherFields: groups['other']!,
                      );
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showRelatedList(
    BuildContext context,
    String title,
    List<dynamic> items,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
          return CollapsingAppBarPage(
            title: title,
            leading: IconButton(
              icon: Icon(
                PhosphorIconsBold.caretLeft,
                color: theme.colorScheme.onSurface,
              ),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Back',
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.onSurface.withValues(
                  alpha: isDark ? 0.05 : 0.03,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            body: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PhosphorIconsRegular.listChecks,
                          size: 48,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No $title available',
                          style: GoogleFonts.poppins(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(24),
                    physics: const ClampingScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (ctx, i) {
                      final item = items[i];

                      if (item is Map<String, dynamic> &&
                          item.containsKey('unit_amount')) {
                        final name = item['name'] ?? 'Description';
                        final project = (item['project_id'] is List)
                            ? item['project_id'][1].toString()
                            : 'Unknown Project';
                        final hours =
                            (item['unit_amount'] as num?)?.toDouble() ?? 0.0;
                        final h = hours.floor();
                        final m = ((hours - h) * 60).round();

                        final hoursFormatted = '${h}h${m > 0 ? ' ${m.toString().padLeft(2, '0')}m' : ''}';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: theme.cardTheme.color,
                              ),
                              child: Row(
                                children: [
                                  // Hours badge
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          AppColors.gradientPurple.first.withValues(
                                            alpha: 0.15,
                                          ),
                                          AppColors.gradientPurple.last.withValues(alpha: 0.08),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Text(
                                        hoursFormatted,
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name.isNotEmpty ? name : '(No description)',
                                          style: theme.textTheme.titleSmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            const Icon(
                                              PhosphorIconsFill.folder,
                                              size: 11,
                                              color: AppColors.primary,
                                            ),
                                            const SizedBox(width: 3),
                                            Expanded(
                                              child: Text(
                                                project,
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: AppColors.primary,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Icon(
                                    PhosphorIconsRegular.caretRight,
                                    size: 16,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      final displayStr = item is Map<String, dynamic>
                          ? (item['display_name'] ?? item['name'] ?? 'Record')
                          : item.toString();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          displayStr,
                          style: GoogleFonts.poppins(
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }

  bool _isStarFilled(int index) {
    // Priority '1' in Odoo usually means "Starred" (1 star).
    // If your Odoo has multiple priority levels (0, 1, 2, 3), this maps them.
    final rawPriority = _rawValues['priority']?.toString() ??
                        (widget.task.isHighPriority ? '1' : '0');

    final priorityInt = int.tryParse(rawPriority) ?? 0;
    return priorityInt > index;
  }

  String _resolveStateLabel(String state) {
    if (state.startsWith('01_')) return 'In Progress';
    if (state.startsWith('1_')) return 'Done';
    if (state == '04_waiting_normal') return 'Waiting';

    switch (state) {
      case 'in_progress':
        return 'In Progress';
      case 'done':
        return 'Done';
      case 'todo':
        return 'To Do';
      default:
        return state.replaceAll('_', ' ');
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String state;
  final String label;

  const _StatusBadge({required this.state, required this.label});

  Color _getStatusColor() {
    if (state.contains('done') || state.startsWith('1_')) {
      return AppColors.statusDone;
    }
    if (state.contains('progress') || state.startsWith('01_')) {
      return AppColors.statusInProgress;
    }
    if (state.contains('waiting') || state.startsWith('04_')) {
      return AppColors.statusReview;
    }
    return AppColors.statusTodo;
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
