import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/models/project_models.dart';
import '../../core/providers/task_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/search_filter_bar.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/shimmer_card.dart';
import '../../core/widgets/status_badge.dart';
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
                scrollInfo.metrics.pixels >=
                    scrollInfo.metrics.maxScrollExtent - 200) {
              provider.loadTasks(loadMore: true);
            }
            return false;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
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
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter(BuildContext context, TaskProvider provider) {
    return Column(
      children: [
        SearchFilterBar<String>(
          controller: _searchController,
          hintText: 'Search tasks...',
          onChanged: (v) {
            provider.setSearch(v);
          },
          onClear: () {
            _searchController.clear();
            provider.setSearch('');
          },
          currentFilter: provider.filterState,
          onFilterChanged: (v) => provider.setFilter(v),
          filters: const [
            SearchFilterItem(value: 'all', label: 'All Tasks'),
            SearchFilterItem(value: 'my', label: 'My Tasks'),
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
          (_, __) => const ShimmerCard(
            height: 110,
            borderRadius: 20,
            margin: EdgeInsets.only(bottom: 12),
          ),
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
              Icon(
                PhosphorIconsRegular.warningCircle,
                size: 48,
                color: AppColors.statusBlocked,
              ),
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
                child: Icon(
                  PhosphorIconsRegular.checkCircle,
                  size: 60,
                  color: theme.colorScheme.onSurface,
                ),
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

    return Semantics(
      button: true,
      label: 'Open task ${task.name}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TaskDetailScreen(task: task)),
            ),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                        StatusBadge(label: task.stageName!),
                      ],
                    ],
                  ),
                  if (task.projectName != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          PhosphorIconsRegular.folder,
                          size: 14,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            task.projectName!,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
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
                        Icon(
                          PhosphorIconsRegular.calendarBlank,
                          size: 14,
                          color: AppColors.statusBlocked.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          task.deadline!,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.statusBlocked.withValues(
                              alpha: 0.8,
                            ),
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
