import 'package:flutter/material.dart';

class ActionBar extends StatelessWidget {
  final List<Widget> actions;
  final MainAxisAlignment mainAxisAlignment;
  final EdgeInsets padding;

  const ActionBar({
    super.key,
    required this.actions,
    this.mainAxisAlignment = MainAxisAlignment.spaceBetween,
    this.padding = const EdgeInsets.only(top: 8),
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: actions,
      ),
    );
  }
}
