import 'package:flutter/material.dart';

/// Single shared skeleton placeholder used by all list screens.
///
/// Replaces the per-screen `_XxxSkeleton` / `_ShimmerList` widgets so
/// loading states stay consistent and only one widget needs maintenance.
class ShimmerCard extends StatelessWidget {
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  const ShimmerCard({
    super.key,
    this.height = 80,
    this.borderRadius = 16,
    this.margin = const EdgeInsets.only(bottom: 8),
    this.padding,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      height: child == null ? height : null,
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: child,
    );
  }
}

/// Simple vertical list of [ShimmerCard]s for Sliver/List loading states.
class ShimmerList extends StatelessWidget {
  final int count;
  final double height;
  final double borderRadius;

  const ShimmerList({
    super.key,
    this.count = 6,
    this.height = 80,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (i) => ShimmerCard(height: height, borderRadius: borderRadius),
      ),
    );
  }
}
