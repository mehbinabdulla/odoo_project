import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/models/project_models.dart';
import '../../core/providers/project_provider.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/collapsing_app_bar_page.dart';
import '../../core/widgets/odoo_arch_detail_view.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/search_filter_bar.dart';
import '../tasks/task_detail_screen.dart';
import '../tasks/task_form_screen.dart';
import 'project_form_screen.dart';
import '../../core/services/odoo_field_registry.dart';
import '../../core/services/odoo_rpc_service.dart';
import '../../core/utils/route_observer.dart';
import '../../core/widgets/odoo_detail_sections.dart';

class ProjectDetailScreen extends StatefulWidget {
  final ProjectModel project;

  const ProjectDetailScreen({super.key, required this.project});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class KanbanColumnState {
  final ProjectStageModel stage;
  List<TaskModel> tasks;
  int offset;
  bool hasMore;
  bool isLoadingMore;

  KanbanColumnState({
    required this.stage,
    this.tasks = const [],
    this.offset = 0,
    this.hasMore = true,
    this.isLoadingMore = false,
  });
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with SingleTickerProviderStateMixin, RouteAwareRefetchMixin {
  List<ProjectStageModel> _stages = [];
  bool _isLoading = true;
  String? _error;
  String _taskFilter = 'all';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Map<String, dynamic> _fieldDefs = {};
  // Form view arch + widget hints (strict arch-mode for the popup).
  Map<String, String> _viewWidgets = {};
  String? _arch;
  Map<String, dynamic> _fieldValues = {};

  // Pagination state for Tasks List tab
  List<TaskModel> _listTasks = [];
  int _listOffset = 0;
  bool _listHasMore = true;
  bool _isListLoadingMore = false;

  // Pagination state for Kanban board columns
  Map<int, KanbanColumnState> _kanbanState = {};

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

  Future<void> _loadData({bool force = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final provider = context.read<ProjectProvider>();
      final results = await Future.wait([
        provider.loadStages(widget.project.id),
        OdooFieldRegistry.getFieldDefs('project.project', force: force),
      ]);

      _stages = results[0] as List<ProjectStageModel>;
      _fieldDefs = results[1] as Map<String, dynamic>;
      _viewWidgets = await OdooFieldRegistry.getViewWidgets('project.project');
      _arch = await OdooFieldRegistry.getFormArch('project.project');

      // Initialize kanban states
      _kanbanState = {
        for (var stage in _stages) stage.id: KanbanColumnState(stage: stage),
      };

      // Fetch dynamic fields for the project
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
      } catch (_) {
        // detail pane falls back to the card's own field values.
      }

      // Initial task loads
      await Future.wait([
        _loadListTasks(reset: true, showLoading: false),
        _loadAllKanbanColumns(reset: true),
      ]);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadListTasks({
    bool reset = false,
    bool showLoading = true,
  }) async {
    if (reset) {
      _listOffset = 0;
      _listHasMore = true;
      if (showLoading && mounted) setState(() => _isLoading = true);
    } else {
      if (!_listHasMore || _isListLoadingMore) return;
      if (mounted) setState(() => _isListLoadingMore = true);
    }

    try {
      final provider = context.read<ProjectProvider>();
      final newTasks = await provider.loadTasksForProject(
        widget.project.id,
        offset: _listOffset,
        limit: 50,
        searchQuery: _searchQuery,
        filterState: _taskFilter,
      );

      if (!mounted) return;
      setState(() {
        if (reset) {
          _listTasks = newTasks;
        } else {
          _listTasks.addAll(newTasks);
        }
        _listOffset += newTasks.length;
        _listHasMore = newTasks.length >= 50;
      });
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isListLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadAllKanbanColumns({bool reset = false}) async {
    final futures = _stages.map(
      (stage) => _loadKanbanColumn(stage.id, reset: reset),
    );
    await Future.wait(futures);
  }

  Future<void> _loadKanbanColumn(int stageId, {bool reset = false}) async {
    final state = _kanbanState[stageId];
    if (state == null) return;

    if (reset) {
      state.offset = 0;
      state.hasMore = true;
    } else {
      if (!state.hasMore || state.isLoadingMore) return;
    }

    if (mounted) setState(() => state.isLoadingMore = true);

    try {
      final provider = context.read<ProjectProvider>();
      final newTasks = await provider.loadTasksForProject(
        widget.project.id,
        stageId: stageId,
        offset: state.offset,
        limit: 20, // Load fewer items per column
        searchQuery: _searchQuery,
        filterState: _taskFilter,
      );

      if (!mounted) return;
      setState(() {
        if (reset) {
          state.tasks = newTasks;
        } else {
          state.tasks.addAll(newTasks);
        }
        state.offset += newTasks.length;
        state.hasMore = newTasks.length >= 20;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => state.isLoadingMore = false);
    }
  }

  void _onSearchOrFilterChanged() {
    setState(() => _isLoading = true);
    Future.wait([
      _loadListTasks(reset: true, showLoading: false),
      _loadAllKanbanColumns(reset: true),
    ]).then((_) {
      if (mounted) setState(() => _isLoading = false);
    });
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
        onRefresh: () => _loadData(force: true),
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
            tooltip: 'Edit Project',
          ),
          PopupMenuButton<String>(
            icon: const Icon(PhosphorIconsBold.dotsThreeVertical, size: 20),
            tooltip: 'More options',
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
          child: SizedBox(
            width: double.infinity,
            child: TabBar(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              // isScrollable: true,
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
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      children: [
        if (widget.project.partnerName?.isNotEmpty == true)
          _detailItem(
            'Customer',
            widget.project.partnerName!,
            PhosphorIconsRegular.user,
          ),
        if (widget.project.userLogin != null)
          _detailItem(
            'Project Manager',
            widget.project.userLogin!,
            PhosphorIconsRegular.userFocus,
          ),
        if (widget.project.companyName != null)
          _detailItem(
            'Company',
            widget.project.companyName!,
            PhosphorIconsRegular.buildings,
          ),
        _detailItem(
          'Status / Stage',
          widget.project.stage ?? 'No Stage',
          PhosphorIconsRegular.info,
        ),
        if (widget.project.privacy != null)
          _detailItem(
            'Visibility',
            widget.project.privacy!,
            PhosphorIconsRegular.lockKey,
          ),
        if (widget.project.date != null)
          _detailItem(
            'Planned Date',
            widget.project.date!,
            PhosphorIconsRegular.calendar,
          ),
        if (widget.project.createDate != null)
          _detailItem(
            'Created On',
            DateFormat('yyyy-MM-dd').format(widget.project.createDate!),
            PhosphorIconsRegular.clock,
          ),
        _detailItem(
          'Total Tasks',
          '${widget.project.taskCount}',
          PhosphorIconsRegular.listChecks,
        ),
        if (widget.project.allocatedHours != null &&
            widget.project.allocatedHours! > 0)
          _detailItem(
            'Allocated Hours',
            '${widget.project.allocatedHours!.toStringAsFixed(2)}h',
            PhosphorIconsRegular.hourglass,
          ),
        if (widget.project.effectiveHours != null &&
            widget.project.effectiveHours! > 0)
          _detailItem(
            'Effective Hours',
            '${widget.project.effectiveHours!.toStringAsFixed(2)}h',
            PhosphorIconsRegular.timer,
          ),
      ],
    );
  }

  Widget _detailItem(String label, String value, IconData icon) {
    final labelColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary.withValues(alpha: 0.6)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(fontSize: 10, color: labelColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
            onChanged: (v) {
              _searchQuery = v;
              _onSearchOrFilterChanged();
            },
            onClear: () {
              _searchController.clear();
              _searchQuery = '';
              _onSearchOrFilterChanged();
            },
            currentFilter: _taskFilter,
            onFilterChanged: (val) {
              _taskFilter = val;
              _onSearchOrFilterChanged();
            },
            filters: [
              const SearchFilterItem(value: 'all', label: 'All Tasks'),
              const SearchFilterItem(value: 'my_tasks', label: 'My Tasks'),
              ..._stages.map(
                (s) => SearchFilterItem(value: 'stage_${s.id}', label: s.name),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _listTasks.isEmpty
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
              : NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification scrollInfo) {
                    if (!_isListLoadingMore &&
                        _listHasMore &&
                        scrollInfo.metrics.pixels >=
                            scrollInfo.metrics.maxScrollExtent - 200) {
                      _loadListTasks();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(
                      top: 16,
                      bottom: 80,
                      left: 16,
                      right: 16,
                    ),
                    itemCount: _listTasks.length + (_isListLoadingMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _listTasks.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        );
                      }
                      return _TaskListItem(task: _listTasks[i]);
                    },
                  ),
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
        final state = _kanbanState[stage.id];
        if (state == null) return const SizedBox();
        return _KanbanColumn(
          state: state,
          onLoadMore: () => _loadKanbanColumn(stage.id),
        );
      },
    );
  }

  void _showProjectDetailsPopup() {
    final theme = Theme.of(context);

    // Filter fields: not null/false/empty; skip technical extras that
    // aren't useful in a "Details" list.
    final valuedFields = _fieldDefs.keys.where((k) {
      final val = _fieldValues[k];

      if (val == null || val == false || val == '') return false;
      if (val is List && val.isEmpty) return false;

      if (k == 'id' || k == 'message_main_attachment_id' || k == 'active') {
        return false;
      }

      return true;
    }).toSet();

    // Sort by label via the shared detail helper.
    final displayFields = OdooDetailSections.orderedDetailFields(
      visible: valuedFields,
      fieldDefs: _fieldDefs,
      defaultFields: const {},
    );

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
              child: OdooArchDetailView(
                arch: _arch,
                fieldDefs: _fieldDefs,
                fieldValues: _fieldValues,
                viewWidgets: _viewWidgets,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                fallback: displayFields.isEmpty
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
                        shrinkWrap: true,
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
                          final val = _fieldValues[key];

                          final displayVal =
                              OdooDetailSections.detailDisplayValue(def, val);

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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                displayVal,
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          );
                        },
                      ),
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

  Color _stateColor(String? stageName) {
    // Centralized Odoo-legend mapping (semantic keywords first, stable
    // hash for free-form stage names) — matches the detail-screen chip.
    return statusColorForLabel(stageName);
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
                color: _stateColor(task.stageName),
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
                    Text(
                      task.stageName!,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
  final KanbanColumnState state;
  final VoidCallback onLoadMore;

  const _KanbanColumn({required this.state, required this.onLoadMore});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                Expanded(
                  child: Text(
                    state.stage.name,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${state.tasks.length}${state.hasMore ? '+' : ''}',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification scrollInfo) {
                if (!state.isLoadingMore &&
                    state.hasMore &&
                    scrollInfo.metrics.pixels >=
                        scrollInfo.metrics.maxScrollExtent - 200) {
                  onLoadMore();
                }
                return false;
              },
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: state.tasks.length + (state.isLoadingMore ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == state.tasks.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    );
                  }
                  return _KanbanCard(task: state.tasks[i]);
                },
              ),
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
    final sessionId = sessionProvider.session?.sessionId;    final avatarUrl = sessionId != null && sessionId.isNotEmpty
        ? (serverUrl != null ? task.getAvatarUrl(serverUrl) : null)
        : null;

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
                      backgroundColor: theme.colorScheme.outline.withValues(
                        alpha: 0.3,
                      ),
                      backgroundImage: NetworkImage(avatarUrl, headers: {
                        'Cookie': 'session_id=$sessionId',
                      },),
                      onBackgroundImageError: (_, __) {},
                    ),
                  ),
                Expanded(
                  child: Text(
                    task.userNames.isNotEmpty
                        ? task.userNames.join(', ')
                        : 'Unassigned',
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
