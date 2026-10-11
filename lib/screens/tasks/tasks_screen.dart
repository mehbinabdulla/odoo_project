import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/models/project_models.dart';
import '../../core/providers/task_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/search_filter_bar.dart';
import '../../core/widgets/primary_button.dart';
import 'task_detail_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<TaskProvider>();
      if (provider.tasks.isEmpty && !provider.isLoading) {
        provider.loadTasks();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TaskProvider>();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: RefreshIndicator(
        onRefresh: () => provider.loadTasks(showLoading: false),
        color: AppColors.primary,
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            if (!provider.isLoadingMore &&
                provider.hasMore &&
                scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
              provider.loadTasks(loadMore: true);
            }
            return false;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              automaticallyImplyLeading: false,
              backgroundColor: theme.scaffoldBackgroundColor,
              elevation: 0,
              toolbarHeight: 112,
              flexibleSpace: FlexibleSpaceBar(
                background: Column(
                  children: [
                    _buildSearchAndFilter(context, provider),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            _buildBody(context, provider, theme),
            if (provider.isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    ));
  }

  Widget _buildSearchAndFilter(BuildContext context, TaskProvider provider) {
    return Column(
      children: [
        SearchFilterBar<String>(
          controller: _searchController,
          hintText: 'Search tasks...',
          onChanged: (v) {
            provider.setSearch(v);
            setState(() {});
          },
          onClear: () {
            _searchController.clear();
            provider.setSearch('');
            setState(() {});
          },
          currentFilter: provider.filterState,
          onFilterChanged: (v) => provider.setFilter(v),
          filters: const [
            SearchFilterItem(value: 'all', label: 'All Tasks'),
            SearchFilterItem(value: 'todo', label: 'To Do'),
            SearchFilterItem(value: 'in_progress', label: 'In Progress'),
            SearchFilterItem(value: 'done', label: 'Done'),
          ],
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    TaskProvider provider,
    ThemeData theme,
  ) {
    if (provider.isLoading) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, __) => const _TaskSkeleton(),
          childCount: 8,
        ),
      );
    }

    if (provider.error != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PhosphorIconsRegular.warningCircle, size: 48, color: AppColors.statusBlocked),
              const SizedBox(height: 16),
              Text(provider.error!, style: GoogleFonts.poppins()),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Retry',
                icon: PhosphorIconsBold.arrowsClockwise,
                onTap: () => provider.loadTasks(),
              ),
            ],
          ),
        ),
      );
    }

    if (provider.tasks.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: 0.2,
                child: Icon(PhosphorIconsRegular.checkCircle, size: 60, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 16),
              Text(
                'No tasks found',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.zero,
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => _TaskCard(task: provider.tasks[i]),
          childCount: provider.tasks.length,
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskModel task;
  const _TaskCard({required this.task});

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
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    task.name,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (task.stageName?.isNotEmpty == true) ...[
                  const SizedBox(width: 16),
                  _StatusBadge(task: task),
                ],
              ],
            ),
            if (task.projectName != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(PhosphorIconsRegular.folder, 
                    size: 14, 
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5)
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      task.projectName!,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (task.deadline != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(PhosphorIconsRegular.calendarBlank, 
                    size: 14, 
                    color: AppColors.statusBlocked.withValues(alpha: 0.8)
                  ),
                  const SizedBox(width: 4),
                  Text(
                    task.deadline!,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.statusBlocked.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final TaskModel task;
  const _StatusBadge({required this.task});

  @override
  Widget build(BuildContext context) {
    final String label = task.stageName?.isNotEmpty == true ? task.stageName! : 'No Stage';
    final colors = [
      AppColors.statusTodo,
      AppColors.statusInProgress,
      AppColors.statusDone,
      AppColors.statusReview,
      AppColors.accentPink,
    ];
    final color = colors[label.hashCode.abs() % colors.length];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _TaskSkeleton extends StatelessWidget {
  const _TaskSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white10 : Colors.black12;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 50,
                height: 16,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: 120,
            height: 12,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
