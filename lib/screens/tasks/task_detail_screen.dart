import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/models/project_models.dart';

import '../../core/theme/app_theme.dart';

import '../../core/services/odoo_field_registry.dart';
import '../../core/services/odoo_rpc_service.dart';
import '../../core/widgets/collapsing_app_bar_page.dart';
import '../../core/widgets/odoo_arch_detail_view.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/odoo_detail_sections.dart';
import '../../core/utils/route_observer.dart';
import 'task_form_screen.dart';

class TaskDetailScreen extends StatefulWidget {
  final TaskModel task;

  const TaskDetailScreen({super.key, required this.task});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen>
    with RouteAwareRefetchMixin {
  bool _isLoading = true;

  Map<String, dynamic> _fieldDefs = {};
  // View-level widget hints (widget="…") from the form view XML arch.
  Map<String, String> _viewWidgets = {};
  // Form view XML — drives the arch-based details layout.
  String? _arch;
  final Map<String, dynamic> _fieldValues = {};
  final Map<String, dynamic> _rawValues = {};

  /// Stage pipeline for the statusbar (`project.task.type` of the
  /// task's project, ordered by sequence).
  final List<Map<String, dynamic>> _stagePipeline = [];
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

  Future<void> _loadData({bool force = false}) async {
    if (mounted) setState(() => _isLoading = true);
    final defs = await OdooFieldRegistry.getFieldDefs(
      'project.task',
      force: force,
    );
    if (!mounted) return;

    _fieldDefs = defs;
    _visibleFields = Set.from(_defaultFields);
    _viewWidgets = await OdooFieldRegistry.getViewWidgets(
      'project.task',
      force: force,
    );
    _arch = await OdooFieldRegistry.getFormArch('project.task', force: force);

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
        // Stage pipeline for the header statusbar: the task's project
        // stages (plus the generic ones), ordered by sequence — the
        // same source the web statusbar uses. Failures degrade to no
        // pipeline row.
        await _loadStages();
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

  /// Fetches the stage path for the `stage_id` statusbar: project
  /// stages first, then generic (`project_ids` empty) ones, sequence
  ///-ordered like the web client. Odoo 19 expresses stage→project as
  /// the m2m `project_ids`; older deployments used the m2o
  /// `project_id` — both are tried before giving up. The current
  /// stage row carries the elapsed-in-stage duration when the record
  /// exposes `duration_tracking` (web's statusbar_duration source)
  /// or `date_last_stage_update` as fallback.
  Future<void> _loadStages() async {
    final rawProject = _rawValues['project_id'];
    final projectId = rawProject is List && rawProject.isNotEmpty
        ? rawProject[0]
        : null;
    final rawStage = _rawValues['stage_id'];
    final currentStageId =
        rawStage is List && rawStage.length >= 2 ? rawStage[0] : null;
    final duration = _stageDurationText();

    List<Map<String, dynamic>> rows;
    try {
      rows = await OdooRpcService.searchRead(
        model: 'project.task.type',
        domain: projectId != null
            ? [
                ['project_ids', '=', projectId],
              ]
            : const [
                ['project_ids', '=', false],
              ],
        fields: const ['name', 'color'],
        order: 'sequence',
      );
    } catch (_) {
      try {
        rows = await OdooRpcService.searchRead(
          model: 'project.task.type',
          domain: projectId != null
              ? [
                  '|',
                  ['project_id', '=', false],
                  ['project_id', '=', projectId],
                ]
              : const [
                  ['project_id', '=', false],
                ],
          fields: const ['name', 'color'],
          order: 'sequence',
        );
      } catch (_) {
        _stagePipeline.clear(); // no pipeline row on failure
        return;
      }
    }
    _stagePipeline
      ..clear()
      ..addAll([
        for (final r in rows)
          {
            'id': r['id'],
            'name': r['name'],
            if (r['color'] != null) 'color': r['color'],
            if (r['id'] != null && currentStageId == r['id'] && duration != null)
              'duration': duration,
          },
      ]);
  }

  /// Elapsed time in the current stage, formatted Odoo-style
  /// ("11h", "3d", "25m"). Prefers the server-tracked
  /// `duration_tracking` JSON (the same source the web
  /// statusbar_duration widget consumes) and degrades gracefully to
  /// the wall-clock delta since `date_last_stage_update`.
  String? _stageDurationText() {
    final rawStage = _rawValues['stage_id'];
    final currentId = rawStage is List && rawStage.length >= 2
        ? rawStage[0]
        : null;
    if (currentId == null) return null;

    final rawTracking = _rawValues['duration_tracking'];
    if (rawTracking is String && rawTracking.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTracking);
        if (decoded is Map) {
          var seconds = 0.0;
          for (final entry in decoded.entries) {
            // Keys look like "project.task.type/3,project.task.type/7"
            // — accumulate every interval that ENDS at the current
            // stage (task could loop back into it).
            final parts = entry.key.toString().split(',');
            final toId = parts.length == 2 ? int.tryParse(
              RegExp(r'(\d+)\s*$').firstMatch(parts[1])?.group(0) ?? '',
            ) : null;
            final value = entry.value is num
                ? entry.value as num
                : num.tryParse(entry.value.toString());
            if (toId != null && toId == currentId && value != null) {
              seconds += value;
            }
          }
          if (seconds > 0) return _humanizeStageDuration(seconds);
        }
      } catch (_) {/* fall through to the wall clock */}
    }

    final enteredAt = _rawValues['date_last_stage_update'];
    if (enteredAt is String && enteredAt.isNotEmpty) {
      final local = DateTime.tryParse(enteredAt);
      if (local != null) {
        // Odoo datetimes are naive UTC.
        final utc = DateTime.utc(
          local.year,
          local.month,
          local.day,
          local.hour,
          local.minute,
          local.second,
        );
        final seconds =
            DateTime.now().toUtc().difference(utc).inSeconds.clamp(0, 1 << 30);
        return _humanizeStageDuration(seconds.toDouble());
      }
    }
    return null;
  }

  /// Web-like duration text: minutes under an hour, hours under a
  /// day, days beyond that.
  static String _humanizeStageDuration(double seconds) {
    final hours = seconds / 3600;
    if (hours < 1) return '${seconds.round()}m';
    if (hours < 24) return '${hours.round()}h';
    return '${(hours / 24).round()}d';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Grouped layout kept as the fallback when the arch is unavailable.
    final orderedFields = OdooDetailSections.orderedDetailFields(
      visible: _visibleFields,
      fieldDefs: _fieldDefs,
      defaultFields: _defaultFields,
    );
    final groups = OdooDetailSections.groupDetailFields(
      ordered: orderedFields,
      fieldDefs: _fieldDefs,
    );

    // The tab strip lives in the OUTER pinned app bar (`bottom:`) —
    // the pinning path that works reliably under NestedScrollView.
    // Labels come from the exact pruning rules the body applies.
    final tabLabels = OdooArchDetailView.computeTabLabels(
      arch: _arch,
      fieldDefs: _fieldDefs,
      fieldValues: _fieldValues,
    );

    // Without tabs (arch still loading / arch has no notebook) there
    // is no strip, so no DefaultTabController is needed.
    final page = CollapsingAppBarPage(
      title: _fieldValues['name'] ?? widget.task.name,
      onRefresh: () => _loadData(force: true),
      // The status badge + priority need room under the expanded
      // title; they collapse away with it (see titleWidget below).
      expandedHeight: 132,
      bottom: tabLabels.isEmpty ? null : OdooArchTabStrip(labels: tabLabels),
      titleWidget: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _fieldValues['name'] ?? widget.task.name,
            style: GoogleFonts.dmSerifDisplay(
              fontSize: 30,
              height: 1.15,
              color: theme.colorScheme.onSurface,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          Row(
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
                        : theme.colorScheme.onSurface.withValues(
                            alpha: 0.2,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
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
      body: _isLoading
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 160),
                Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ],
            )
          : OdooArchDetailView(
              arch: _arch,
              fieldDefs: _fieldDefs,
              fieldValues: _fieldValues,
              viewWidgets: _viewWidgets,
              // The widget owns scrolling; the strip itself is pinned
              // by the outer app bar (bottom:) and the status /
              // priority row collapses with the expanded title, so the
              // body only carries the switching pane.
              stickyTabs: true,
              stripInBody: false,
              tabLabels: tabLabels,
              stagePipeline: _stagePipeline,
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
    );

    return tabLabels.isEmpty
        ? page
        : DefaultTabController(
            // Recreated only when the arch/label count changes so the
            // controller survives normal reloads.
            key: ValueKey('${_arch.hashCode}:strip${tabLabels.length}'),
            length: tabLabels.length,
            child: page,
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

                        final hoursFormatted =
                            '${h}h${m > 0 ? ' ${m.toString().padLeft(2, '0')}m' : ''}';
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
                                          AppColors.gradientPurple.first
                                              .withValues(alpha: 0.15),
                                          AppColors.gradientPurple.last
                                              .withValues(alpha: 0.08),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name.isNotEmpty
                                              ? name
                                              : '(No description)',
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
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
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
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.3),
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
    final rawPriority =
        _rawValues['priority']?.toString() ??
        (widget.task.isHighPriority ? '1' : '0');

    final priorityInt = int.tryParse(rawPriority) ?? 0;
    return priorityInt > index;
  }

  String _resolveStateLabel(String state) {
    final s = state.toLowerCase();
    if (s.startsWith('01_')) return 'In Progress';
    if (s.startsWith('02_')) return 'Changes Requested';
    if (s.startsWith('03_')) return 'Approved';
    if (s.startsWith('1_cancel')) return 'Canceled';
    if (s.startsWith('1_') || s == 'done') return 'Done';
    if (s == '04_waiting_normal') return 'Waiting';

    switch (s) {
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

/// Tinted status pill with the web client's project.task state
/// palette: In Progress (grey), Changes Requested (yellow),
/// Approved / Done (green), Canceled (red).
class _StatusBadge extends StatelessWidget {
  final String state;
  final String label;

  const _StatusBadge({required this.state, required this.label});

  /// Colors follow the Odoo web state-selection legend (centralized so
  /// list cards and popups match): neutral grey for active states,
  /// amber for changes-requested, green for approved/done, red for
  /// canceled — with terminal states (`1_*`) rendered solid.
  @override
  Widget build(BuildContext context) {
    final style = odooStateBadgeStyle(state, label);
    final color = style.color;
    final filled = style.filled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: filled ? color : color.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: filled ? Colors.white : color,
          letterSpacing: 0.5,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
