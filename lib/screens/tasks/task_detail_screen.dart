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
        ? (rawProject[0] is num ? (rawProject[0] as num).toInt() : rawProject[0])
        : null;
    final rawStage = _rawValues['stage_id'];
    final currentStageId = rawStage is List && rawStage.length >= 2
        ? (rawStage[0] is num ? (rawStage[0] as num).toInt() : rawStage[0])
        : null;
    // Per-stage elapsed times (stage id → "11h"), the same tracking
    // data web's `statusbar_duration` widget badges EVERY pipeline
    // stage with — `New 11h › Ongoing 45m › Completed` — not just the
    // active one.
    final durations = _stageDurations();

    List<Map<String, dynamic>> rows = const [];

    // Tier 1: Odoo 13+ expresses stage→project as the `project_ids`
    // m2m; a project-scoped task shows its own stage path. Mirrors the
    // project kanban's proven query shape (`ProjectProvider.loadStages`
    // — unique-id domain with `in`, plain id/name/sequence fields):
    // some Cyllo-style proxies accept only that shape, so deviating
    // from it is what leaves this screen with no pipeline while the
    // kanban columns still load.
    if (projectId != null) {
      try {
        rows = await OdooRpcService.searchRead(
          model: 'project.task.type',
          domain: [
            ['project_ids', 'in', [projectId]],
          ],
          fields: const ['id', 'name', 'sequence', 'fold'],
          order: 'sequence asc',
        );
      } catch (e) {
        debugPrint(
          '[stagePipeline] tier 1 (project_ids m2m) failed: '
          '${e.toString().split("\n").first}',
        );
        rows = const [];
      }
    }
    // Tier 2: legacy deployments carry the `project_id` m2o.
    if (rows.isEmpty) {
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
          fields: const ['id', 'name', 'sequence'],
          order: 'sequence asc',
        );
      } catch (e) {
        debugPrint(
          '[stagePipeline] tier 2 (project_id m2o) failed: '
          '${e.toString().split("\n").first}',
        );
        rows = const [];
      }
    }
    // Tier 3: last resort — every stage of the model, sequence
    // ordered. Cyllo/Studio DBs often share one global pipeline, and a
    // visible pipeline beats a silently empty one. The current stage
    // still highlights correctly by id.
    if (rows.isEmpty) {
      try {
        rows = await OdooRpcService.searchRead(
          model: 'project.task.type',
          domain: const [],
          fields: const ['id', 'name', 'sequence'],
          order: 'sequence asc',
        );
      } catch (e) {
        debugPrint(
          '[stagePipeline] tier 3 (global) failed: '
          '${e.toString().split("\n").first}',
        );
        rows = const [];
      }
    }

    final entries = <Map<String, dynamic>>[
      for (final r in rows)
        {
          if (r['id'] != null) 'id': r['id'],
          'name': r['name'],
          if (r['color'] != null) 'color': r['color'],
          // Web parity: every stage that has tracking data shows its
          // own badge ("New 11h › Ongoing 45m"); the current stage has
          // no recorded interval yet, so it stays bare.
          if (_durationForStage(r['id'], durations) != null) ...{
            'duration': _durationForStage(r['id'], durations),
          },
          if (r['id'] != null &&
              sameStageId(r['id'], currentStageId)) ...{
            'current': true,
          },
        },
    ];

    // Last-ditch visual: every tier came back empty (model blocked for
    // this tenant, RPC outage…). Show the task's own hydrated stage —
    // highlighted, carrying its tracked duration when computable —
    // instead of an empty row. The full pipeline appears whenever a
    // tier succeeds again.
    if (entries.isEmpty) {
      final hydratedName = _fieldValues['stage_id']?.toString();
      if (hydratedName != null && hydratedName.isNotEmpty) {
        debugPrint(
          '[stagePipeline] no stages fetched — degrading to the record '
          'stage "$hydratedName"; duration map: '
          '${durations.isEmpty ? "none" : "${durations.length} entries"}',
        );
        entries.add({
          'name': hydratedName,
          'current': true,
        });
      }
    }

    _stagePipeline
      ..clear()
      ..addAll(entries);
  }

  /// Stage-id equality tolerant of int/num/double jitter between the
  /// RPC payload and the hydrated many2one value.
  static bool sameStageId(Object? a, Object? b) {
    if (a == null || b == null) return false;
    final na = a is num ? a : num.tryParse(a.toString());
    final nb = b is num ? b : num.tryParse(b.toString());
    if (na != null && nb != null) return na.toInt() == nb.toInt();
    return a.toString() == b.toString();
  }

  /// Per-stage elapsed times formatted Odoo-style ("11h", "3d",
  /// "25m"), keyed by stage id — one badge per pipeline stage like
  /// web's `statusbar_duration`: `New 11h › Ongoing 45m › Completed`.
  /// Source of truth is the server-tracked `duration_tracking` JSON
  /// (`project.task.type/<id>` → seconds); when tracking carries no
  /// data at all it degrades to the wall-clock delta since
  /// `date_last_stage_update`, attributed to the current stage.
  Map<int, String> _stageDurations() {
    final rawStage = _rawValues['stage_id'];
    final rawCurrentId = rawStage is List && rawStage.length >= 2
        ? rawStage[0]
        : null;

    String? humanized(double seconds) =>
        seconds > 0 ? _humanizeStageDuration(seconds) : null;

    final byId = <int, double>{};
    // `duration_tracking` is a Json field: the RPC typically hands the
    // app an ALREADY-DECODED map (`project.task.type/3` → 39600.0).
    // Parsing strictly `is String` therefore silently discarded every
    // real value and left only the wall-clock badge on one stage.
    void accumulate(Object? rawKey, Object? rawValue) {
      final double? value;
      if (rawValue is num) {
        value = rawValue.toDouble();
      } else if (rawValue is String) {
        value = num.tryParse(rawValue.trim())?.toDouble();
      } else if (rawValue is Map) {
        // Wrapped pairs ({v: 39600} / {duration: …}) still count.
        value = () {
          for (final k in const ['value', 'duration', 'seconds', 'time']) {
            final v = rawValue[k];
            final n = v is num
                ? v.toDouble()
                : v is String
                    ? num.tryParse(v.trim())?.toDouble()
                    : null;
            if (n != null) return n;
          }
          return null;
        }();
      } else {
        value = null;
      }
      if (value == null) return;
      final key = '$rawKey';
      // Standard keys are "project.task.type/<id>"; some backends
      // store transition pairs ("…/3,project.task.type/7") where the
      // interval ENDED at the last segment; bare ids are tolerated.
      const idRe = 'project\\.task\\.type/\\s*(\\d+)';
      final RegExpMatch? match = switch (key) {
        final k when k.contains(',') =>
          RegExp(idRe).allMatches(k.split(',').last).lastOrNull,
        final k when RegExp(idRe).allMatches(k).length > 1 =>
          RegExp(idRe).allMatches(k).last,
        final k => RegExp(idRe).firstMatch(k),
      };
      final id = (match != null
              ? int.tryParse(match.group(1) ?? '')
              : null) ??
          int.tryParse(key.trim());
      if (id != null) {
        byId[id] = (byId[id] ?? 0) + value;
      }
    }

    final rawTracking = _rawValues['duration_tracking'];
    if (rawTracking is Map) {
      for (final entry in rawTracking.entries) {
        accumulate(entry.key, entry.value);
      }
    } else if (rawTracking is List) {
      // Paired arrays ("stageId,seconds") or chip-strings still count.
      for (final item in rawTracking) {
        if (item is Map) {
          for (final entry in item.entries) {
            accumulate(entry.key, entry.value);
          }
        } else if (item is List && item.length >= 2) {
          accumulate(item[0], item[1]);
        } else {
          accumulate(item, null);
        }
      }
    } else if (rawTracking is String && rawTracking.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTracking);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            accumulate(entry.key, entry.value);
          }
        }
      } catch (_) {/* fall through to the wall clock */}
    }

    if (byId.isNotEmpty) {
      debugPrint(
        '[stagePipeline] tracked stage times — ${byId.length} entries: '
        '${byId.map((k, v) => MapEntry(k, _humanizeStageDuration(v)))}',
      );
    } else if (rawTracking != null && rawTracking != false) {
      final raw = rawTracking.toString();
      debugPrint(
        '[stagePipeline] duration_tracking yielded no stage times — '
        'raw ${rawTracking.runtimeType}: '
        '"${raw.substring(0, raw.length > 240 ? 240 : raw.length)}"',
      );
    } else {
      debugPrint(
        '[stagePipeline] duration_tracking absent from the task payload '
        '— falling back to the wall clock',
      );
    }

    final durations = <int, String>{};
    for (final e in byId.entries) {
      final text = humanized(e.value);
      if (text != null) durations[e.key] = text;
    }
    if (durations.isNotEmpty) return durations;

    // Nothing tracked on the server — the only known interval is the
    // time spent sitting in the CURRENT stage.
    if (rawCurrentId == null) return const {};
    final currentId = rawCurrentId is num
        ? rawCurrentId.toInt()
        : int.tryParse(rawCurrentId.toString());
    if (currentId == null) return const {};
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
        final text = humanized(seconds.toDouble());
        if (text != null) return {currentId: text};
      }
    }
    return const {};
  }

  /// Stage-row id (num/num-doubled/string from RPC payloads) → the
  /// badge text tracked for that stage, if any.
  static String? _durationForStage(Object? stageId, Map<int, String> durations) {
    final id = stageId is num
        ? stageId.toInt()
        : int.tryParse(stageId.toString());
    return id == null ? null : durations[id];
  }

  /// Web-like duration text: minutes under an hour, hours under a
  /// day, days beyond that — `45m`, `11h`, `3d`.
  /// [seconds] are REAL seconds; the old version rounded raw seconds
  /// straight into the minutes slot ("379m" for 6 minutes).
  static String _humanizeStageDuration(double seconds) {
    final minutes = seconds / 60;
    if (minutes < 1) return '${seconds.round()}s';
    if (minutes < 60) return '${minutes.round()}m';
    final hours = minutes / 60;
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
