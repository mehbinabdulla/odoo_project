import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// A reusable page scaffold with a collapsing top bar.
class CollapsingAppBarPage extends StatelessWidget {
  final String title;
  final Widget? titleWidget;
  final List<Widget> actions;
  final Widget? leading;
  final double? leadingWidth;
  final double expandedHeight;
  final PreferredSizeWidget? bottom;
  final Widget body;
  final Widget? floatingActionButton;
  final Future<void> Function()? onRefresh;

  const CollapsingAppBarPage({
    super.key,
    required this.title,
    this.titleWidget,
    this.actions = const [],
    this.leading,
    this.leadingWidth,
    this.expandedHeight = 96.0,
    this.bottom,
    required this.body,
    this.floatingActionButton,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = Navigator.canPop(context);
    final double topPadding = MediaQuery.of(context).padding.top;

    final Widget content = NestedScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverPersistentHeader(
          pinned: true,
          delegate: _CollapsingHeaderDelegate(
            title: title,
            titleWidget: titleWidget,
            actions: actions,
            leading: leading,
            leadingWidth: leadingWidth,
            canPop: canPop,
            theme: theme,
            topPadding: topPadding,
            expandedHeight: expandedHeight,
            bottom: bottom,
          ),
        ),
      ],
      body: body,
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      floatingActionButton: floatingActionButton,
      body: onRefresh != null
          ? RefreshIndicator(
              onRefresh: onRefresh!,
              edgeOffset: topPadding + _kBarHeight,
              color: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.surface,
              notificationPredicate: (notification) {
                // IMPORTANT: NestedScrollView creates inner scrollables.
                // We must catch notifications from both depth 0 (outer) and depth 1 (inner).
                return notification.depth == 0 || notification.depth == 1;
              },
              child: content,
            )
          : content,
    );
  }
}

const double _kBarHeight = 56.0;

class _CollapsingHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final Widget? titleWidget;
  final List<Widget> actions;
  final Widget? leading;
  final double? leadingWidth;
  final bool canPop;
  final ThemeData theme;
  final double topPadding;
  final double expandedHeight;
  final PreferredSizeWidget? bottom;

  const _CollapsingHeaderDelegate({
    required this.title,
    required this.titleWidget,
    required this.actions,
    required this.leading,
    required this.leadingWidth,
    required this.canPop,
    required this.theme,
    required this.topPadding,
    required this.expandedHeight,
    this.bottom,
  });

  @override
  double get minExtent =>
      topPadding + _kBarHeight + (bottom?.preferredSize.height ?? 0);

  @override
  double get maxExtent =>
      topPadding + _kBarHeight + expandedHeight + (bottom?.preferredSize.height ?? 0);

  @override
  bool shouldRebuild(_CollapsingHeaderDelegate old) =>
      old.title != title ||
      old.titleWidget != titleWidget ||
      old.canPop != canPop ||
      old.theme != theme ||
      old.topPadding != topPadding ||
      old.expandedHeight != expandedHeight ||
      old.actions.length != actions.length;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final t = (shrinkOffset / expandedHeight).clamp(0.0, 1.0);
    final double collapsedTitleOpacity = t;
    final double expandedTitleOpacity = (1.0 - t * 2.0).clamp(0.0, 1.0);

    final ButtonStyle barButtonStyle = IconButton.styleFrom(
      backgroundColor: Colors.transparent,
      fixedSize: const Size(40, 40),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    final Widget? defaultLeading = canPop
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(PhosphorIconsBold.caretLeft, size: 20),
              ),
            ],
          )
        : null;

    final Widget? actualLeading = leading ?? defaultLeading;

    double effectiveLeadingWidth;
    if (leadingWidth != null) {
      effectiveLeadingWidth = leadingWidth!;
    } else if (actualLeading == null) {
      effectiveLeadingWidth = 0;
    } else if (actualLeading is Row) {
      final btnCount = actualLeading.children.whereType<IconButton>().length;
      effectiveLeadingWidth = btnCount > 0
          ? btnCount * 40.0 + (btnCount - 1) * 4.0 + 8.0
          : 56.0;
    } else {
      effectiveLeadingWidth = 48.0;
    }

    return Material(
      color: theme.colorScheme.surface,
      elevation: overlapsContent ? 1 : 0,
      shadowColor: theme.shadowColor.withValues(alpha: 0.06),
      child: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: _kBarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    if (actualLeading != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: _styledLeading(
                          actualLeading,
                          barButtonStyle,
                          effectiveLeadingWidth,
                          isDark,
                        ),
                      ),
                    Expanded(
                      child: Opacity(
                        opacity: collapsedTitleOpacity,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            title,
                            style: GoogleFonts.dmSerifDisplay(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    ..._styledActions(actions, barButtonStyle, isDark),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Opacity(
                opacity: expandedTitleOpacity,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 50, 20),
                    child:
                        titleWidget ??
                        Text(
                          title,
                          style: GoogleFonts.dmSerifDisplay(
                            fontSize: 30,
                            height: 1.15,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  ),
                ),
              ),
            ),
            if (bottom != null) bottom!,
          ],
        ),
      ),
    );
  }

  Widget _styledLeading(
    Widget actualLeading,
    ButtonStyle style,
    double width,
    bool isDark,
  ) {
    if (actualLeading is Row) {
      return SizedBox(
        width: width,
        child: _applyStyleToChildren(actualLeading, style),
      );
    }
    return SizedBox(width: width, child: _applyStyle(actualLeading, style));
  }

  Widget _applyStyle(Widget w, ButtonStyle style) {
    if (w is IconButton) {
      return IconButton(
        icon: w.icon,
        onPressed: w.onPressed,
        tooltip: w.tooltip,
        style: style,
      );
    }
    return w;
  }

  Widget _applyStyleToChildren(Row row, ButtonStyle style) {
    return Row(
      mainAxisSize: row.mainAxisSize,
      children: row.children.map((c) => _applyStyle(c, style)).toList(),
    );
  }

  List<Widget> _styledActions(
    List<Widget> actions,
    ButtonStyle style,
    bool isDark,
  ) {
    return actions.map((a) {
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: _applyStyle(a, style),
      );
    }).toList();
  }
}
