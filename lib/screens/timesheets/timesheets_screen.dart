import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/models/project_models.dart';
import '../../core/providers/timesheet_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/search_filter_bar.dart';
import '../../core/widgets/shimmer_card.dart';

import '../../core/widgets/primary_button.dart';

import 'timesheet_detail_screen.dart';
import 'timesheet_form_screen.dart';

class TimesheetsScreen extends StatefulWidget {
  const TimesheetsScreen({super.key});

  @override
  State<TimesheetsScreen> createState() => _TimesheetsScreenState();
}

class _TimesheetsScreenState extends State<TimesheetsScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TimesheetProvider>();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: RefreshIndicator(
        onRefresh: () => provider.loadTimesheets(showLoading: false),
        color: AppColors.primary,
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            if (!provider.isLoadingMore &&
                provider.hasMore &&
                scrollInfo.metrics.pixels >=
                    scrollInfo.metrics.maxScrollExtent - 200) {
              provider.loadTimesheets(loadMore: true);
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
                      _buildUserFilter(context, provider, theme),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              _buildTimesheetList(context, provider, theme),
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

  Widget _buildUserFilter(
    BuildContext context,
    TimesheetProvider provider,
    ThemeData theme,
  ) {
    final myUserId = provider.sessionProvider.userId;

    return SearchFilterBar<int?>(
      controller: _searchController,
      hintText: 'Search timesheets...',
      onChanged: (v) {
        provider.setSearch(v);
      },
      onClear: () {
        _searchController.clear();
        provider.setSearch('');
      },
      currentFilter: provider.filterUserId,
      onFilterChanged: (value) {
        provider.setUserFilter(value);
        provider.loadTimesheets();
      },
      filters: [
        SearchFilterItem(value: myUserId, label: 'My Entries'),
        SearchFilterItem(value: null, label: 'All Entries'),
      ],
      filterIcon: PhosphorIconsRegular.funnel,
    );
  }

  Widget _buildTimesheetList(
    BuildContext context,
    TimesheetProvider provider,
    ThemeData theme,
  ) {
    if (provider.isModuleMissing) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    PhosphorIconsFill.clock,
                    size: 64,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Timesheets Not Available',
                  style: GoogleFonts.dmSerifDisplay(
                    fontSize: 24,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'The Timesheet module is not installed on your Odoo server. Time tracking features are currently disabled.',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      );
    }

    if (provider.isLoading) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, __) => const ShimmerCard(height: 80, borderRadius: 16),
          childCount: 6,
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
              Text(
                provider.error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Retry',
                icon: PhosphorIconsBold.arrowsClockwise,
                onTap: () => provider.loadTimesheets(),
              ),
            ],
          ),
        ),
      );
    }

    if (provider.timesheets.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: 0.2,
                child: Icon(
                  PhosphorIconsRegular.clock,
                  size: 60,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No timesheet entries',
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

    // Group by date
    final grouped = <String, List<TimesheetModel>>{};
    for (final ts in provider.timesheets) {
      grouped.putIfAbsent(ts.date, () => []).add(ts);
    }
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return SliverPadding(
      padding: EdgeInsets.zero,
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, i) {
          final date = dates[i];
          final entries = grouped[date]!;
          final total = entries.fold(0.0, (s, t) => s + t.unitAmount);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Text(
                      _friendlyDate(date),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Text(
                      '${total.toStringAsFixed(1)}h total',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              ...entries.map(
                (ts) => _TimesheetCard(
                  timesheet: ts,
                  onDelete: () => _deleteTimesheet(context, ts.id),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TimesheetDetailScreen(timesheet: ts),
                    ),
                  ),
                  onEdit: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TimesheetFormScreen(timesheet: ts),
                    ),
                  ),
                ),
              ),
            ],
          );
        }, childCount: dates.length),
      ),
    );
  }

  Future<void> _deleteTimesheet(BuildContext context, int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text(
          'Are you sure you want to delete this timesheet entry?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusBlocked,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (confirm == true) {
      await context.read<TimesheetProvider>().deleteTimesheet(id);
    }
  }

  String _friendlyDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        return 'Today';
      }
      final yesterday = now.subtract(const Duration(days: 1));
      if (date.year == yesterday.year &&
          date.month == yesterday.month &&
          date.day == yesterday.day) {
        return 'Yesterday';
      }
      return DateFormat('EEEE, MMM d').format(date);
    } catch (_) {
      return dateStr;
    }
  }
}

// ── Timesheet Card ─────────────────────────────────────────────────────────────

class _TimesheetCard extends StatelessWidget {
  final TimesheetModel timesheet;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _TimesheetCard({
    required this.timesheet,
    required this.onDelete,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Dismissible(
          key: Key('ts_${timesheet.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: AppColors.statusBlocked,
            child: const Icon(PhosphorIconsFill.trash, color: Colors.white),
          ),
          confirmDismiss: (_) async {
            onDelete();
            return false;
          },
          child: Semantics(
            button: true,
            label:
                'Open timesheet ${timesheet.name?.isNotEmpty == true ? timesheet.name! : timesheet.hoursFormatted}',
            child: Material(
              color: theme.cardTheme.color,
              child: InkWell(
                onTap: onTap,
                onLongPress: onEdit,
                child: Tooltip(
                  message: 'Open timesheet details. Long-press to edit.',
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        // Hours badge
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.gradientPurple.first.withValues(
                                  alpha: 0.15,
                                ),
                                AppColors.gradientPurple.last.withValues(
                                  alpha: 0.08,
                                ),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              timesheet.hoursFormatted,
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                timesheet.name?.isNotEmpty == true
                                    ? timesheet.name!
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
                                      timesheet.projectName ?? 'No project',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: AppColors.primary),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (timesheet.taskName != null) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      PhosphorIconsRegular.checkCircle,
                                      size: 11,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Text(
                                        timesheet.taskName!,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.6),
                                            ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          PhosphorIconsRegular.caretRight,
                          size: 18,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
