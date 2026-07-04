import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/models/project_models.dart';
import '../../core/providers/module_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/search_filter_bar.dart';


class ModulesScreen extends StatefulWidget {
  const ModulesScreen({super.key});

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ModuleProvider>();
      if (provider.modules.isEmpty && !provider.isLoading) {
        provider.loadModules();
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
    final provider = context.watch<ModuleProvider>();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: RefreshIndicator(
        onRefresh: () => provider.loadModules(showLoading: false),
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              automaticallyImplyLeading: false,
              backgroundColor: theme.scaffoldBackgroundColor,
              elevation: 0,
              toolbarHeight: 170,
              flexibleSpace: FlexibleSpaceBar(
                background: Column(
                  children: [
                    _buildSearchAndFilter(context, provider),
                    const SizedBox(height: 8),
                    _buildStats(provider, theme),
                  ],
                ),
              ),
            ),
            _buildBody(context, provider, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter(BuildContext context, ModuleProvider provider) {
    return Column(
      children: [
        const SizedBox(height: 10),
        SearchFilterBar<String>(
          controller: _searchController,
          hintText: 'Search modules...',
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
            SearchFilterItem(value: 'all', label: 'All Modules'),
            SearchFilterItem(value: 'installed', label: 'Installed'),
            SearchFilterItem(value: 'uninstalled', label: 'Not Installed'),
          ],
        ),
      ],
    );
  }

  Widget _buildStats(ModuleProvider provider, ThemeData theme) {
    if (provider.modules.isEmpty) return const SizedBox();
    return Row(
      children: [
        _MiniStat(
          label: 'Total',
          value: provider.totalCount,
          color: AppColors.primary,
        ),
        const SizedBox(width: 8),
        _MiniStat(
          label: 'Installed',
          value: provider.installedCount,
          color: AppColors.statusDone,
        ),
        const SizedBox(width: 8),
        _MiniStat(
          label: 'Available',
          value: provider.totalCount - provider.installedCount,
          color: AppColors.statusTodo,
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    ModuleProvider provider,
    ThemeData theme,
  ) {
    if (provider.isLoading) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, __) => const _ModuleSkeleton(),
          childCount: 8,
        ),
      );
    }

    if (provider.error != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsRegular.puzzlePiece,
                size: 64,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                provider.error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: provider.loadModules,
                icon: const Icon(PhosphorIconsRegular.arrowsClockwise),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (provider.modules.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            'No modules found',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => _ModuleCard(module: provider.modules[i]),
          childCount: provider.modules.length,
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final OdooModuleModel module;

  const _ModuleCard({required this.module});

  Color get _stateColor {
    switch (module.state) {
      case 'installed':
        return AppColors.statusDone;
      case 'uninstalled':
        return AppColors.statusTodo;
      case 'to install':
        return AppColors.statusInProgress;
      case 'to upgrade':
        return AppColors.accentYellow;
      case 'uninstallable':
        return AppColors.statusBlocked;
      default:
        return AppColors.statusTodo;
    }
  }

  String get _stateLabel {
    switch (module.state) {
      case 'installed':
        return 'Installed';
      case 'uninstalled':
        return 'Not Installed';
      case 'to install':
        return 'Pending Install';
      case 'to upgrade':
        return 'Pending Upgrade';
      case 'uninstallable':
        return 'Uninstallable';
      default:
        return module.state;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color:
                  (module.isInstalled
                          ? AppColors.statusDone
                          : AppColors.primary)
                      .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              module.application ? PhosphorIconsRegular.squaresFour : PhosphorIconsRegular.puzzlePiece,
              color: module.isInstalled
                  ? AppColors.statusDone
                  : AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        module.shortdesc,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StateBadge(color: _stateColor, label: _stateLabel),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  module.name,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                if (module.summary != null && module.summary!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    module.summary!,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (module.latestVersion != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (module.author != null)
                        Text(
                          module.author!,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      const Spacer(),
                      Text(
                        'v${module.latestVersion!}',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  final Color color;
  final String label;

  const _StateBadge({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}



class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            value.toString(),
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleSkeleton extends StatelessWidget {
  const _ModuleSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 80,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
      ),
    );
  }
}
