import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/models/project_models.dart';
import '../../core/providers/project_provider.dart';
import '../../core/theme/app_theme.dart';
import 'project_detail_screen.dart';

import '../../core/widgets/search_filter_bar.dart';




class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<ProjectProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: RefreshIndicator(
        onRefresh: () => provider.loadProjects(showLoading: false),
        color: AppColors.primary,
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            if (!provider.isLoadingMore &&
                provider.hasMore &&
                scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
              provider.loadProjects(loadMore: true);
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
                    _buildSearchBar(context, provider),
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

  Widget _buildSearchBar(BuildContext context, ProjectProvider provider) {
    return SearchFilterBar<String>(
      controller: _searchController,
      hintText: 'Search projects...',
      onChanged: (v) {
        provider.setSearch(v);
        setState(() {});
      },
      onClear: () {
        _searchController.clear();
        provider.setSearch('');
        setState(() {});
      },
      currentFilter: provider.filterStatus,
      onFilterChanged: (value) => provider.setFilter(value),
      filters: const [
        SearchFilterItem(value: 'all', label: 'All Projects'),
        SearchFilterItem(value: 'my_projects', label: 'My Projects'),
        SearchFilterItem(value: 'on_track', label: 'On Track'),
        SearchFilterItem(value: 'at_risk', label: 'At Risk'),
        SearchFilterItem(value: 'off_track', label: 'Off Track'),
      ],
    );
  }

  Widget _buildBody(
      BuildContext context, ProjectProvider provider, ThemeData theme) {
    if (provider.isModuleMissing) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    
    if (provider.isLoading) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => const _ProjectSkeleton(),
          childCount: 6,
        ),
      );
    }

    if (provider.error != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIconsRegular.cloudSlash,
                  size: 64,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  provider.error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => provider.loadProjects(),
                  icon: const Icon(PhosphorIconsRegular.arrowsClockwise),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (provider.projects.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsRegular.folderMinus,
                size: 64,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No projects found',
                style: theme.textTheme.titleMedium?.copyWith(
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
          (_, i) => _ProjectListItem(
            project: provider.projects[i],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProjectDetailScreen(project: provider.projects[i]),
              ),
            ),
            onFavoriteTap: () => provider.toggleFavorite(
              provider.projects[i].id,
              !provider.projects[i].favorite,
            ),
          ),
          childCount: provider.projects.length,
        ),
      ),
    );
  }
}

class _ProjectListItem extends StatelessWidget {
  final ProjectModel project;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  const _ProjectListItem({
    required this.project,
    required this.onTap,
    required this.onFavoriteTap,
  });

  Color _statusColor(String? status) {
    switch (status) {
      case 'on_track':
        return AppColors.statusDone;
      case 'at_risk':
        return AppColors.statusReview;
      case 'off_track':
        return AppColors.statusBlocked;
      default:
        return AppColors.statusTodo;
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = _statusColor(project.lastUpdateStatus);
    final progress = (project.progressPercent / 100).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Status Badge (similar to hours badge)
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            PhosphorIconsRegular.folder,
                            color: statusColor,
                            size: 20,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${(progress * 100).toInt()}%',  
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            project.partnerName ?? 'Internal Project',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Favorite with cleaner touch
                    IconButton(
                      icon: Icon(
                        project.favorite
                            ? PhosphorIconsFill.star
                            : PhosphorIconsRegular.star,
                        color: project.favorite
                            ? AppColors.accentYellow
                            : theme.colorScheme.onSurface.withValues(alpha: 0.2),
                      ),
                      onPressed: onFavoriteTap,
                      splashRadius: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Stats row
                Row(
                  children: [
                    _infoPill(
                      PhosphorIconsRegular.checkCircle,
                      '${project.taskCount} tasks',
                      theme,
                      isDark,
                    ),
                    const SizedBox(width: 8),
                    _infoPill(
                      PhosphorIconsFill.circle,
                      _statusLabel(project.lastUpdateStatus),
                      theme,
                      isDark,
                      iconColor: statusColor,
                    ),
                    if (project.createDate != null) ...[
                      const Spacer(),
                      Text(
                        'Created ${DateFormat('MMM d, HH:mm').format(project.createDate!)}',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoPill(
    IconData icon,
    String label,
    ThemeData theme,
    bool isDark, {
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: icon == PhosphorIconsFill.circle ? 6 : 10,
            color: iconColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

}

class _ProjectSkeleton extends StatelessWidget {
  const _ProjectSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 110,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
