import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/providers/project_provider.dart';
import '../../core/providers/timesheet_provider.dart';
import '../../core/providers/task_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shimmer_card.dart';
import '../projects/project_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  final Function(int) onNavigate;

  const DashboardScreen({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isModuleMissing = context.select(
      (TimesheetProvider p) => p.isModuleMissing,
    );

    return RefreshIndicator(
      onRefresh: () async {
        final projectProvider = context.read<ProjectProvider>();
        final timesheetProvider = context.read<TimesheetProvider>();
        final taskProvider = context.read<TaskProvider>();
        await Future.wait([
          projectProvider.loadProjects(showLoading: false),
          timesheetProvider.loadTimesheets(showLoading: false),
          taskProvider.loadTasks(showLoading: false),
        ]);
      },
      color: AppColors.primary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildFilterBar(context)),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(child: _buildMetricsOverview(context)),
            if (!isModuleMissing) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(child: const TimesheetChartWidget()),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(child: const TaskDonutChartWidget()),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(child: _buildRecentProjects(context, theme)),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Consumer<TimesheetProvider>(
      builder: (context, provider, _) =>
          _buildFilterBarContent(context, provider),
    );
  }

  Widget _buildFilterBarContent(
    BuildContext context,
    TimesheetProvider provider,
  ) {
    String formatDate(DateTime d) => DateFormat('MMM d, yyyy').format(d);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label:
                'Select date range, currently ${formatDate(provider.startDate)} to ${formatDate(provider.endDate)}',
            child: InkWell(
              onTap: () => _pickDateRange(context, provider),
              borderRadius: BorderRadius.circular(16),
              child: Tooltip(
                message: 'Select date range',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        PhosphorIconsRegular.calendarBlank,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${formatDate(provider.startDate)} – ${formatDate(provider.endDate)}',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        PhosphorIconsRegular.caretRight,
                        size: 18,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDateRange(
    BuildContext context,
    TimesheetProvider provider,
  ) async {
    final theme = Theme.of(context);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: provider.startDate,
        end: provider.endDate,
      ),
      builder: (context, child) {
        // Derive from the app theme so dark/light mode is preserved and
        // only the brand primary is overridden — no hardcoded colors.
        final scheme = theme.colorScheme;
        return Theme(
          data: theme.copyWith(
            colorScheme: scheme.copyWith(
              primary: AppColors.primary,
              onPrimary: scheme.onPrimary,
            ),
            appBarTheme: theme.appBarTheme.copyWith(elevation: 0),
            datePickerTheme: theme.datePickerTheme.copyWith(
              headerHeadlineStyle: GoogleFonts.dmSerifDisplay(
                fontSize: 32,
                fontWeight: FontWeight.w400,
                color: scheme.onSurface,
              ),
              headerHelpStyle: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (!context.mounted) return;
    if (range != null) {
      provider.setDateRange(range.start, range.end);
      provider.loadTimesheets();
    }
  }

  Widget _buildMetricsOverview(BuildContext context) {
    // Scoped so only this row rebuilds when counts change.
    return Consumer3<ProjectProvider, TaskProvider, TimesheetProvider>(
      builder: (context, projects, tasks, timesheets, _) {
        return _buildMetricsContent(context, projects, tasks, timesheets);
      },
    );
  }

  Widget _buildMetricsContent(
    BuildContext context,
    ProjectProvider projects,
    TaskProvider tasks,
    TimesheetProvider timesheets,
  ) {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            title: 'Projects',
            value: projects.totalProjectCount.toString(),
            icon: PhosphorIconsRegular.folder,
            gradient: AppColors.gradientRed,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            title: 'Tasks',
            value: tasks.totalCount.toString(),
            icon: PhosphorIconsRegular.checkCircle,
            gradient: AppColors.gradientOrange,
          ),
        ),
        if (!timesheets.isModuleMissing) ...[
          const SizedBox(width: 12),
          Expanded(
            child: _MetricCard(
              title: 'Hours',
              value: timesheets.totalHours.toStringAsFixed(1),
              icon: PhosphorIconsRegular.clock,
              gradient: AppColors.gradientPurple,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRecentProjects(BuildContext context, ThemeData theme) {
    // Scoped so keystrokes/date changes elsewhere don't rebuild this list.
    return Consumer3<ProjectProvider, TimesheetProvider, TaskProvider>(
      builder: (context, provider, timesheetProvider, taskProvider, _) {
        return _buildRecentProjectsContent(
          context,
          theme,
          provider,
          timesheetProvider,
          taskProvider,
        );
      },
    );
  }

  Widget _buildRecentProjectsContent(
    BuildContext context,
    ThemeData theme,
    ProjectProvider provider,
    TimesheetProvider timesheetProvider,
    TaskProvider taskProvider,
  ) {
    final useTaskFallback =
        timesheetProvider.isModuleMissing ||
        timesheetProvider.timesheets.isEmpty;

    final sortedProjects = provider.projects.toList();
    sortedProjects.sort((a, b) {
      if (useTaskFallback) {
        final aTasks = taskProvider.tasks.where((t) => t.projectId == a.id);
        final bTasks = taskProvider.tasks.where((t) => t.projectId == b.id);
        final aLatestId = aTasks.isEmpty
            ? 0
            : aTasks.map((t) => t.id).reduce((x, y) => x > y ? x : y);
        final bLatestId = bTasks.isEmpty
            ? 0
            : bTasks.map((t) => t.id).reduce((x, y) => x > y ? x : y);

        if (aLatestId == 0 && bLatestId == 0) return b.id.compareTo(a.id);
        if (aLatestId == 0) return 1;
        if (bLatestId == 0) return -1;
        return bLatestId.compareTo(aLatestId);
      } else {
        final aTimesheets = timesheetProvider.timesheets.where(
          (t) => t.projectId == a.id,
        );
        final bTimesheets = timesheetProvider.timesheets.where(
          (t) => t.projectId == b.id,
        );
        final aLatest = aTimesheets.isEmpty
            ? ''
            : aTimesheets
                  .map((t) => t.date)
                  .reduce((x, y) => x.compareTo(y) > 0 ? x : y);
        final bLatest = bTimesheets.isEmpty
            ? ''
            : bTimesheets
                  .map((t) => t.date)
                  .reduce((x, y) => x.compareTo(y) > 0 ? x : y);

        if (aLatest.isEmpty && bLatest.isEmpty) return b.id.compareTo(a.id);
        if (aLatest.isEmpty) return 1;
        if (bLatest.isEmpty) return -1;
        return bLatest.compareTo(aLatest);
      }
    });

    final recentProjects = sortedProjects.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Recent Projects', style: theme.textTheme.titleMedium),
            const Spacer(),
            TextButton(
              onPressed: () => onNavigate(1),
              child: Text(
                'See all',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (provider.isLoading)
          const ShimmerList(count: 5, height: 80)
        else if (provider.error != null)
          _ErrorCard(
            message:
                (provider.error!.contains('SocketException') ||
                    provider.error!.contains('Failed host lookup') ||
                    provider.error!.contains('OS Error'))
                ? 'Could not connect to server. Retrying…'
                : provider.error!,
          )
        else if (recentProjects.isEmpty)
          const _EmptyCard(
            icon: PhosphorIconsRegular.folderMinus,
            message: 'No projects found',
          )
        else ...[
          for (var i = 0; i < recentProjects.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i < recentProjects.length - 1 ? 10 : 0,
              ),
              child: _ProjectCard(project: recentProjects[i]),
            ),
        ],
      ],
    );
  }
}

class TaskDonutChartWidget extends StatefulWidget {
  const TaskDonutChartWidget({super.key});

  @override
  State<TaskDonutChartWidget> createState() => _TaskDonutChartWidgetState();
}

class _TaskDonutChartWidgetState extends State<TaskDonutChartWidget> {
  int touchedIndex = -1;
  bool hideTodo = false;
  bool hideInProgress = false;
  bool hideDone = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasks = context.watch<TaskProvider>();
    if (tasks.tasks.isEmpty && !tasks.isLoading) return const SizedBox();

    int todo = 0;
    int inProgress = 0;
    int done = 0;

    for (final task in tasks.tasks) {
      if (task.state == 'done' || task.state == '1_done') {
        done++;
      } else if (task.state == 'in_progress' ||
          task.state == '03_in_progress') {
        inProgress++;
      } else {
        todo++;
      }
    }

    final total = todo + inProgress + done;
    if (total == 0 && !tasks.isLoading) return const SizedBox();

    return Semantics(
      label:
          'Task status chart: $todo to do, $inProgress in progress, $done done, $total total',
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    PhosphorIconsRegular.chartPieSlice,
                    color: AppColors.accentOrange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Task Status',
                      style: GoogleFonts.dmSerifDisplay(
                        fontSize: 20,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Overall distribution of tasks',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (tasks.isLoading)
              const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Builder(
                builder: (context) {
                  int todoIndex = -1;
                  int inProgressIndex = -1;
                  int doneIndex = -1;
                  int currentIndex = 0;

                  if (todo > 0 && !hideTodo) todoIndex = currentIndex++;
                  if (inProgress > 0 && !hideInProgress) {
                    inProgressIndex = currentIndex++;
                  }
                  if (done > 0 && !hideDone) doneIndex = currentIndex++;

                  return Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 160,
                          child: PieChart(
                            PieChartData(
                              pieTouchData: PieTouchData(
                                touchCallback:
                                    (FlTouchEvent event, pieTouchResponse) {
                                      setState(() {
                                        if (!event
                                                .isInterestedForInteractions ||
                                            pieTouchResponse == null ||
                                            pieTouchResponse.touchedSection ==
                                                null) {
                                          touchedIndex = -1;
                                          return;
                                        }
                                        touchedIndex = pieTouchResponse
                                            .touchedSection!
                                            .touchedSectionIndex;
                                      });
                                    },
                              ),
                              sectionsSpace: 4,
                              centerSpaceRadius: 40,
                              sections: [
                                if (currentIndex == 0)
                                  PieChartSectionData(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.05),
                                    value: 1,
                                    showTitle: false,
                                    radius: 20,
                                  ),
                                if (todo > 0 && !hideTodo)
                                  PieChartSectionData(
                                    color: AppColors.primary,
                                    value: todo.toDouble(),
                                    showTitle: false,
                                    radius: touchedIndex == todoIndex ? 25 : 20,
                                    badgeWidget: touchedIndex == todoIndex
                                        ? CustomTooltipWidget(
                                            theme: theme,
                                            count: '$todo',
                                            label: 'To Do',
                                          )
                                        : null,
                                    badgePositionPercentageOffset: 1.2,
                                  ),
                                if (inProgress > 0 && !hideInProgress)
                                  PieChartSectionData(
                                    color: AppColors.accentYellow,
                                    value: inProgress.toDouble(),
                                    showTitle: false,
                                    radius: touchedIndex == inProgressIndex
                                        ? 29
                                        : 24,
                                    badgeWidget: touchedIndex == inProgressIndex
                                        ? CustomTooltipWidget(
                                            theme: theme,
                                            count: '$inProgress',
                                            label: 'In Progress',
                                          )
                                        : null,
                                    badgePositionPercentageOffset: 1.2,
                                  ),
                                if (done > 0 && !hideDone)
                                  PieChartSectionData(
                                    color: AppColors.statusDone,
                                    value: done.toDouble(),
                                    showTitle: false,
                                    radius: touchedIndex == doneIndex ? 25 : 20,
                                    badgeWidget: touchedIndex == doneIndex
                                        ? CustomTooltipWidget(
                                            theme: theme,
                                            count: '$done',
                                            label: 'Done',
                                          )
                                        : null,
                                    badgePositionPercentageOffset: 1.2,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _LegendItem(
                              color: AppColors.primary,
                              label: 'To Do',
                              count: todo,
                              isToggledOff: hideTodo,
                              onTap: () => setState(() => hideTodo = !hideTodo),
                            ),
                            const SizedBox(height: 12),
                            _LegendItem(
                              color: AppColors.accentYellow,
                              label: 'In Progress',
                              count: inProgress,
                              isToggledOff: hideInProgress,
                              onTap: () => setState(
                                () => hideInProgress = !hideInProgress,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _LegendItem(
                              color: AppColors.statusDone,
                              label: 'Done',
                              count: done,
                              isToggledOff: hideDone,
                              onTap: () => setState(() => hideDone = !hideDone),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CustomTooltipWidget extends StatelessWidget {
  final ThemeData theme;
  final String count;
  final String label;

  const CustomTooltipWidget({
    super.key,
    required this.theme,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            count,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final List<Color> gradient;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  gradient.first.withValues(alpha: 0.2),
                  gradient.last.withValues(alpha: 0.2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: gradient.first, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  final bool isToggledOff;
  final VoidCallback? onTap;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.count,
    this.isToggledOff = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Toggle $label series, $count tasks',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: 'Toggle $label',
          child: Opacity(
            opacity: isToggledOff ? 0.3 : 1.0,
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final dynamic project;

  const _ProjectCard({required this.project});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (project.progressPercent / 100).clamp(0.0, 1.0);

    return Semantics(
      button: true,
      label: 'Open project ${project.name}',
      child: Material(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProjectDetailScreen(project: project),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Tooltip(
            message: 'Open project ${project.name}',
            child: Container(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (project.favorite)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(
                            PhosphorIconsFill.star,
                            color: AppColors.accentYellow,
                            size: 16,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          project.name,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${project.taskCount} tasks',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (project.taskCount > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: theme.colorScheme.surface
                                .withValues(alpha: 0.1),
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.statusDone,
                            ),
                            borderRadius: BorderRadius.circular(4),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${project.progressPercent.toStringAsFixed(0)}%',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 48,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.statusBlocked.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const Icon(
            PhosphorIconsRegular.warningCircle,
            color: AppColors.statusBlocked,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.statusBlocked,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TimesheetChartWidget extends StatefulWidget {
  const TimesheetChartWidget({super.key});

  @override
  State<TimesheetChartWidget> createState() => _TimesheetChartWidgetState();
}

class _TimesheetChartWidgetState extends State<TimesheetChartWidget> {
  int _pageOffset = 0;
  int _touchedIndex = -1;
  Offset? _touchOffset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timesheets = context.watch<TimesheetProvider>();

    final start = timesheets.startDate;
    final end = timesheets.endDate;
    final totalDays = end.difference(start).inDays + 1;
    final maxPages = (totalDays / 7).ceil();

    if (_pageOffset >= maxPages && maxPages > 0) {
      _pageOffset = maxPages - 1;
    }
    if (_pageOffset < 0) _pageOffset = 0;

    final viewEnd = end.subtract(Duration(days: _pageOffset * 7));
    final viewStart = viewEnd.subtract(const Duration(days: 6));

    double maxHours = 0;
    for (int i = 0; i < 7; i++) {
      final date = viewStart.add(Duration(days: i));
      if (date.isBefore(start) || date.isAfter(end)) continue;
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final hours = timesheets.dailyHours[dateStr] ?? 0.0;
      if (hours > maxHours) maxHours = hours;
    }

    final double backgroundHeight = maxHours > 8 ? maxHours * 1.2 : 8;
    final List<BarChartGroupData> barGroups = [];

    for (int i = 0; i < 7; i++) {
      final date = viewStart.add(Duration(days: i));
      double hours = 0;

      if (!date.isBefore(start) && !date.isAfter(end)) {
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        hours = timesheets.dailyHours[dateStr] ?? 0.0;
      }

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: hours,
              gradient: const LinearGradient(
                colors: AppColors.gradientPurple,
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
              width: 16,
              borderRadius: BorderRadius.circular(6),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: backgroundHeight,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
              ),
            ),
          ],
        ),
      );
    }

    final canGoBack = _pageOffset < maxPages - 1;
    final canGoForward = _pageOffset > 0;
    final String windowRange =
        '${DateFormat('MMM d').format(viewStart)} - ${DateFormat('MMM d').format(viewEnd)}';

    return Semantics(
      label: 'Timesheet activity chart for $windowRange',
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    PhosphorIconsRegular.chartBar,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Timesheet Activity',
                        style: GoogleFonts.dmSerifDisplay(
                          fontSize: 20,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        windowRange,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    _buildNavButton(
                      theme,
                      icon: PhosphorIconsRegular.caretLeft,
                      tooltip: 'Previous week',
                      enabled: canGoBack,
                      onTap: () => setState(() => _pageOffset++),
                    ),
                    const SizedBox(width: 8),
                    _buildNavButton(
                      theme,
                      icon: PhosphorIconsRegular.caretRight,
                      tooltip: 'Next week',
                      enabled: canGoForward,
                      onTap: () => setState(() => _pageOffset--),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 200,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: backgroundHeight,
                      barTouchData: BarTouchData(
                        enabled: true,
                        handleBuiltInTouches: false,
                        touchCallback: (FlTouchEvent event, barTouchResponse) {
                          setState(() {
                            if (!event.isInterestedForInteractions ||
                                barTouchResponse == null ||
                                barTouchResponse.spot == null) {
                              _touchedIndex = -1;
                              _touchOffset = null;
                              return;
                            }
                            _touchedIndex =
                                barTouchResponse.spot!.touchedBarGroupIndex;
                            _touchOffset = barTouchResponse.spot!.offset;
                          });
                        },
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final date = viewStart.add(
                                Duration(days: value.toInt()),
                              );
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  DateFormat('dd').format(date),
                                  style: GoogleFonts.poppins(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            },
                            reservedSize: 28,
                          ),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      barGroups: barGroups,
                    ),
                  ),
                  if (_touchedIndex != -1 && _touchOffset != null)
                    Builder(
                      builder: (context) {
                        final touchedDate = viewStart.add(
                          Duration(days: _touchedIndex),
                        );
                        final dateStr = DateFormat(
                          'yyyy-MM-dd',
                        ).format(touchedDate);
                        final hours = timesheets.dailyHours[dateStr] ?? 0.0;
                        return Positioned(
                          left: _touchOffset!.dx,
                          top: _touchOffset!.dy,
                          child: FractionalTranslation(
                            translation: const Offset(-0.5, -1.2),
                            child: CustomTooltipWidget(
                              theme: theme,
                              label:
                                  '${DateFormat('MMM d').format(touchedDate)} ',
                              count: '${hours.toStringAsFixed(1)}h',
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavButton(
    ThemeData theme, {
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    // 48x48 target with tooltip for accessibility.
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        onPressed: enabled ? onTap : null,
        tooltip: tooltip,
        icon: Icon(icon, size: 16),
        color: theme.colorScheme.onSurface,
        disabledColor: theme.colorScheme.onSurface.withValues(alpha: 0.2),
        style: IconButton.styleFrom(
          backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          disabledBackgroundColor: theme.colorScheme.onSurface.withValues(
            alpha: 0.02,
          ),
        ),
      ),
    );
  }
}
