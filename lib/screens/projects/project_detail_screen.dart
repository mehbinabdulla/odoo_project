import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/models/project_models.dart';
import '../../core/providers/project_provider.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/collapsing_app_bar_page.dart';
import '../../core/widgets/search_filter_bar.dart';
import '../tasks/task_detail_screen.dart';
import '../tasks/task_form_screen.dart';
import 'project_form_screen.dart';
import '../../core/services/odoo_field_registry.dart';
import '../../core/services/odoo_rpc_service.dart';
import '../../core/utils/route_observer.dart';


class ProjectDetailScreen extends StatefulWidget {
  final ProjectModel project;

  const ProjectDetailScreen({super.key, required this.project});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with SingleTickerProviderStateMixin, RouteAwareRefetchMixin {
  List<TaskModel> _tasks = [];
  List<ProjectStageModel> _stages = [];
  bool _isLoading = true;
  String? _error;
  String _taskFilter = 'all';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Map<String, dynamic> _fieldDefs = {};
  Map<String, dynamic> _fieldValues = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void refetch() {
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final provider = context.read<ProjectProvider>();
      final results = await Future.wait([
        provider.loadTasksForProject(widget.project.id),
        provider.loadStages(widget.project.id),
        OdooFieldRegistry.getFieldDefs('project.project'),
      ]);

      _fieldDefs = results[2] as Map<String, dynamic>;
      _tasks = results[0] as List<TaskModel>;
      _stages = results[1] as List<ProjectStageModel>;

      List<String> fieldsToFetch = _fieldDefs.keys.toList();
      List<Map<String, dynamic>> records = [];

      try {
        records = await OdooRpcService.safeSearchRead(
          model: 'project.project',
          domain: [
            ['id', '=', widget.project.id],
          ],
          fields: fieldsToFetch,
        );
        if (records.isNotEmpty) {
          _fieldValues = records[0];
        }
      } catch (e) {
        debugPrint('Dynamic field fetch failed (non-fatal): $e');
      }

      setState(() {});
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<TaskModel> get _filteredTasks {
    List<TaskModel> list = _tasks;

    if (_searchQuery.isNotEmpty) {
      list = list
          .where(
            (t) => t.name.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }

    switch (_taskFilter) {
      case 'my_tasks':
        final userId = context.read<SessionProvider>().userId;
        return list.where((t) => t.userIds.contains(userId)).toList();
      case 'in_progress':
        return list.where((t) => t.state == 'in_progress').toList();
      case 'done':
        return list.where((t) => t.state == 'done').toList();
      case 'blocked':
        return list.where((t) => t.kanbanState == 1).toList();
      case 'overdue':
        return list.where((t) => t.isOverdue).toList();
      default:
        return list;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DefaultTabController(
      key: ValueKey('project_tabs_${_isLoading}_${_stages.length}'),
      length: (_isLoading || _stages.isNotEmpty) ? 3 : 2,
      child: CollapsingAppBarPage(
        title: widget.project.name,
        onRefresh: _loadData,
        titleWidget: Text(
          widget.project.name,
          style: GoogleFonts.dmSerifDisplay(
            fontSize: 30,
            height: 1.15,
            color: theme.colorScheme.onSurface,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProjectFormScreen(project: widget.project),
              ),
            ),
            icon: const Icon(PhosphorIconsBold.pencilSimple, size: 20),
          ),
          PopupMenuButton<String>(
            icon: const Icon(PhosphorIconsBold.dotsThreeVertical, size: 20),
            onSelected: (val) {
              if (val == 'details') {
                _showProjectDetailsPopup();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'details',
                child: Text(
                  'Project Details',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ],
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TaskFormScreen(initialProject: widget.project),
              ),
            );
          },
          label: Text(
            'New Task',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          icon: const Icon(PhosphorIconsBold.plus),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.only(left: 16, right: 16),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: theme.dividerColor,
              labelColor: theme.colorScheme.onSurface,
              unselectedLabelColor: theme.colorScheme.onSurface.withValues(
                alpha: 0.4,
              ),
              indicatorColor: AppColors.primary,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              tabs: [
                const Tab(text: 'Tasks'),
                if (_isLoading || _stages.isNotEmpty) const Tab(text: 'Kanban'),
                const Tab(text: 'Details'),
              ],
            ),
          ),
        ),
        body: Builder(
          builder: (context) {
            final tabController = DefaultTabController.of(context);
            return AnimatedBuilder(
              animation: tabController,
              builder: (context, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildTaskList(theme),
                          if (_isLoading || _stages.isNotEmpty)
                            _buildKanban(theme),
                          _buildProjectDetails(theme, isDark),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildProjectDetails(ThemeData theme, bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 20),
      children: [
        _detailItem(
          'Customer',
          widget.project.partnerName ?? 'N/A',
          PhosphorIconsRegular.user,
        ),
        _detailItem(
          'Status',
          _statusLabel(widget.project.lastUpdateStatus),
          PhosphorIconsRegular.info,
        ),
        _detailItem(
          'Planned Date',
          widget.project.date ?? 'N/A',
          PhosphorIconsRegular.calendar,
        ),
        _detailItem(
          'Total Tasks',
          '${widget.project.taskCount}',
          PhosphorIconsRegular.listChecks,
        ),
        if (widget.project.allocatedHours != null)
          _detailItem(
            'Allocated Hours',
            '${widget.project.allocatedHours}h',
            PhosphorIconsRegular.clock,
          ),
      ],
    );
  }

  Widget _detailItem(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary.withValues(alpha: 0.6)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey),
              ),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'on_track':
        return 'On Track';
      case 'at_risk':
        return 'At Risk';
      case 'off_track':
        return 'Off Track';
      default:
        return 'No Status';
    }
  }

  Widget _buildTaskList(ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    return Column(
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SearchFilterBar<String>(
            controller: _searchController,
            hintText: 'Search tasks...',
            onChanged: (v) => setState(() => _searchQuery = v),
            onClear: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
            currentFilter: _taskFilter,
            onFilterChanged: (val) => setState(() => _taskFilter = val),
            filters: const [
              SearchFilterItem(value: 'all', label: 'All Tasks'),
              SearchFilterItem(value: 'my_tasks', label: 'My Tasks'),
              SearchFilterItem(value: 'in_progress', label: 'In Progress'),
              SearchFilterItem(value: 'done', label: 'Completed'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _filteredTasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIconsRegular.listChecks,
                        size: 56,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No tasks found',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 16, bottom: 80, left: 16, right: 16),
                  itemCount: _filteredTasks.length,
                  itemBuilder: (_, i) => _TaskListItem(task: _filteredTasks[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildKanban(ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_stages.isEmpty) {
      return const Center(child: Text('No stages configured'));
    }

    return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            itemCount: _stages.length,
            itemBuilder: (_, i) {
              final stage = _stages[i];
        final stageTasks = _tasks.where((t) => t.stageId == stage.id).toList();
              return _KanbanColumn(stage: stage, tasks: stageTasks);
            },
    );
  }

  void _showProjectDetailsPopup() {
    final theme = Theme.of(context);

    // Filter fields: not null/false/empty AND not readonly
    final displayFields = _fieldDefs.keys.where((k) {
      final val = _fieldValues[k];
      final _ = _fieldDefs[k];

      if (val == null || val == false || val == '') return false;
      if (val is List && val.isEmpty) return false;

      // Skip common technical fields that aren't useful in a "Details" list
      if (k == 'id' || k == 'message_main_attachment_id' || k == 'active') {
        return false;
      }

      return true;
    }).toList();

    // Sort by label
    displayFields.sort((a, b) {
      final aLabel = _fieldDefs[a]['string'] ?? a;
      final bLabel = _fieldDefs[b]['string'] ?? b;
      return aLabel.toString().compareTo(bLabel.toString());
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Project Details',
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 24,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Dynamic fields from Odoo',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: displayFields.isEmpty
                  ? Center(
                      child: Text(
                        'No additional details available',
                        style: GoogleFonts.poppins(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                      itemCount: displayFields.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 32,
                        color: theme.dividerColor.withValues(alpha: 0.5),
                      ),
                      itemBuilder: (ctx, i) {
                        final key = displayFields[i];
                        final def = _fieldDefs[key];
                        final label = def['string'] ?? key;
                        final type = def['type'];
                        final val = _fieldValues[key];

                        String displayVal = val.toString();
                        if (type == 'many2one' &&
                            val is List &&
                            val.length == 2) {
                          displayVal = val[1].toString();
                        } else if ((type == 'many2many' ||
                                type == 'one2many') &&
                            val is List) {
                          displayVal = '${val.length} items';
                        } else if (type == 'selection') {
                          final selection = def['selection'] as List?;
                          if (selection != null) {
                            final match = selection.firstWhere(
                              (e) => e[0] == val,
                              orElse: () => [val, val.toString()],
                            );
                            displayVal = match[1];
                          }
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              displayVal,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskListItem extends StatelessWidget {
  final TaskModel task;

  const _TaskListItem({required this.task});

  Color _stateColor(String? state) {
    switch (state) {
      case 'in_progress':
        return AppColors.statusInProgress;
      case 'done':
        return AppColors.statusDone;
      case 'blocked':
        return AppColors.statusBlocked;
      default:
        return AppColors.statusTodo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TaskDetailScreen(task: task)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            // State indicator
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: _stateColor(task.state),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (task.isHighPriority)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            PhosphorIconsRegular.flag,
                            size: 14,
                            color: AppColors.statusBlocked,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          task.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            decoration: task.state == 'done'
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (task.stageName != null) ...[
                    const SizedBox(height: 4),
                    Text(task.stageName!, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (task.deadline != null)
                  _DeadlineBadge(
                    deadline: task.deadline!,
                    isOverdue: task.isOverdue,
                  ),
                if (task.allocatedHours != null && task.allocatedHours! > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${task.allocatedHours!.toStringAsFixed(0)}h',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeadlineBadge extends StatelessWidget {
  final String deadline;
  final bool isOverdue;

  const _DeadlineBadge({required this.deadline, required this.isOverdue});

  @override
  Widget build(BuildContext context) {
    final color = isOverdue ? AppColors.statusBlocked : AppColors.statusReview;
    try {
      final date = DateTime.parse(deadline);
      final formatted = '${date.day}/${date.month}';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          formatted,
          style: GoogleFonts.poppins(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    } catch (_) {
      return const SizedBox();
    }
  }
}

class _KanbanColumn extends StatelessWidget {
  final ProjectStageModel stage;
  final List<TaskModel> tasks;

  const _KanbanColumn({required this.stage, required this.tasks});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stage header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  stage.name,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    tasks.length.toString(),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Tasks
          Expanded(
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: tasks.length,
              itemBuilder: (_, i) => _KanbanCard(task: tasks[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _KanbanCard extends StatelessWidget {
  final TaskModel task;

  const _KanbanCard({required this.task});

  String _formatHours(double? hours) {
    if (hours == null || hours == 0) return '';
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sessionProvider = context.read<SessionProvider>();
    final serverUrl = sessionProvider.serverUrl;
    final avatarUrl = serverUrl != null ? task.getAvatarUrl(serverUrl) : null;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TaskDetailScreen(task: task)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.isHighPriority)
                  const Padding(
                    padding: EdgeInsets.only(right: 6, top: 2),
                    child: Icon(
                      PhosphorIconsFill.star,
                      size: 16,
                      color: Colors.amber,
                    ),
                  ),
                Expanded(
                  child: Text(
                    task.name,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (avatarUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: CircleAvatar(
                      radius: 10,
                      backgroundImage: NetworkImage(avatarUrl),
                    ),
                  ),
                Expanded(
                  child: Text(
                    task.userNames.isNotEmpty ? task.userNames.join(', ') : 'Unassigned',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (task.allocatedHours != null && task.allocatedHours! > 0)
                  Text(
                    _formatHours(task.allocatedHours),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
