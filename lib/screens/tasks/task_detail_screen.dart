import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/models/project_models.dart';

import '../../core/theme/app_theme.dart';

import '../../core/services/odoo_field_registry.dart';
import '../../core/services/odoo_rpc_service.dart';
import '../../core/widgets/collapsing_app_bar_page.dart';
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

      if (records.isNotEmpty) {
        final data = records[0];
        
        for (final key in _fieldDefs.keys) {
          final type = _fieldDefs[key]['type'];
          final val = data[key];

          if (val == null || val == false || val == '') continue;
          
          _rawValues[key] = val; // Store the raw Odoo value (e.g. '1' for priority)

          if (type == 'many2one' && val is List && val.length == 2) {
            _fieldValues[key] = val[1];
          } else if ((type == 'many2many' || type == 'one2many') &&
              val is List &&
              val.isNotEmpty) {
            final relation = _fieldDefs[key]['relation'];
            if (relation != null) {
              try {
                List<String> fieldsToFetch = ['display_name', 'name'];
                if (relation == 'account.analytic.line') {
                  fieldsToFetch = [
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
                  _fieldValues[key] = relRecords;
                } else {
                  final names = relRecords
                      .map((r) => r['display_name'] ?? r['name'] ?? 'Unknown')
                      .toList();
                  _fieldValues[key] = names.join(', ');
                }
              } catch (_) {
                if (type == 'one2many') {
                  _fieldValues[key] = List.generate(
                    val.length,
                    (i) => 'Record ${val[i]}',
                  );
                } else {
                  _fieldValues[key] = '${val.length} records';
                }
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

          // Decide if this field belongs in the dynamic grid or the header
          final isHeaderField = (key == 'name' || 
                                 key == 'description' || 
                                 key == 'state' || 
                                 key == 'priority' || 
                                 key == 'kanban_state');
          
          if (!isHeaderField && _fieldValues[key] != null) {
            _visibleFields.add(key);
          }
        }
      }
    } catch (e) {
      // Fallback
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
    final isDark = theme.brightness == Brightness.dark;

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
        ),
        if (!_isLoading)
          PopupMenuButton<String>(
            icon: Icon(
              PhosphorIconsBold.dotsThreeVertical,
              color: theme.colorScheme.onSurface,
              size: 20,
            ),
            color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
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
                                  ? Colors.amber
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
                      final orderedFields = _visibleFields
                          .where((f) => _fieldDefs.containsKey(f))
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
                        } else if (type == 'integer' ||
                            type == 'float' ||
                            type == 'monetary') {
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
                                        color: theme.dividerColor.withValues(
                                          alpha: 0.5,
                                        ),
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _fieldDefs[f]['string'] ?? f,
                                              style: GoogleFonts.poppins(
                                                fontSize: 10,
                                                color: theme.colorScheme.onSurface
                                                    .withValues(alpha: 0.5),
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
                                    backgroundColor: Colors.green.withValues(
                                      alpha: 0.1,
                                    ),
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
                                        isDark,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ],
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
              style: IconButton.styleFrom(
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
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

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1A1A1A)
                                : const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF2A2020)
                                      : AppColors.primary.withValues(
                                          alpha: 0.1,
                                        ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${h}h',
                                  style: GoogleFonts.poppins(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          PhosphorIconsFill.folder,
                                          size: 14,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            project,
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              color: AppColors.primary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                '${h}h ${m.toString().padLeft(2, '0')}m',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
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
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }

  Widget _fieldRow(String label, String value, ThemeData theme, bool isDark) {
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
          Icon(
            icon,
            size: 20,
            color: AppColors.primary,
          ),
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
      ),
    );
  }
}
