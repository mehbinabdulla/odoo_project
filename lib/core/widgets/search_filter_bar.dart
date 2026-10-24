import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../theme/app_theme.dart';

class SearchFilterBar<T> extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final List<SearchFilterItem<T>> filters;
  final T currentFilter;
  final ValueChanged<T> onFilterChanged;
  final IconData? filterIcon;

  const SearchFilterBar({
    super.key,
    required this.controller,
    this.hintText = 'Search...',
    required this.onChanged,
    required this.onClear,
    required this.filters,
    required this.currentFilter,
    required this.onFilterChanged,
    this.filterIcon,
  });

  @override
  State<SearchFilterBar<T>> createState() => _SearchFilterBarState<T>();
}

class _SearchFilterBarState<T> extends State<SearchFilterBar<T>> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search Field
        TextField(
          focusNode: _focusNode,
          controller: widget.controller,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            fillColor: isDark ? AppColors.darkCard : AppColors.lightCard,
            filled: true,
            hintText: widget.hintText,
            prefixIcon: const Icon(
              PhosphorIconsRegular.magnifyingGlass,
              size: 18,
            ),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, child) {
                if (value.text.isEmpty && !_focusNode.hasFocus) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  icon: const Icon(PhosphorIconsRegular.x, size: 16),
                  tooltip: 'Clear search',
                  onPressed: () {
                    widget.onClear();
                    _focusNode.unfocus();
                  },
                );
              },
            ),
          ),
          onChanged: widget.onChanged,
        ),
        if (widget.filters.isNotEmpty) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: widget.filters.map((f) {
                final isSelected = f.value == widget.currentFilter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => widget.onFilterChanged(f.value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark
                                  ? AppColors.darkCard
                                  : AppColors.lightCard),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : theme.dividerColor.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Text(
                        f.label,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class SearchFilterItem<T> {
  final T value;
  final String label;
  const SearchFilterItem({required this.value, required this.label});
}
