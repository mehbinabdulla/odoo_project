import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'primary_button.dart';

class GenericPickerSheet extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final Function(Map<String, dynamic>) onSelect;
  final bool isMulti;
  final List<Map<String, dynamic>> selectedItems;

  const GenericPickerSheet({
    super.key,
    required this.title,
    required this.items,
    required this.onSelect,
    this.isMulti = false,
    this.selectedItems = const [],
  });

  @override
  State<GenericPickerSheet> createState() => _GenericPickerSheetState();
}

class _GenericPickerSheetState extends State<GenericPickerSheet> {
  late TextEditingController _searchController;
  late List<Map<String, dynamic>> _localSelected;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _localSelected = List.from(widget.selectedItems);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      builder: (_, controller) {
        final query = _searchController.text.toLowerCase();
        final filteredItems = query.isEmpty
            ? widget.items
            : widget.items.where((item) {
                final name = (item['name']?.toString() ?? '').toLowerCase();
                return name.contains(query);
              }).toList();

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(
                  widget.title,
                  style: GoogleFonts.dmSerifDisplay(
                    fontSize: 24,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  focusNode: _focusNode,
                  controller: _searchController,
                  autofocus: false,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.35),
                    ),
                    prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass, size: 20),
                    suffixIcon: (_searchController.text.isNotEmpty || _focusNode.hasFocus)
                        ? IconButton(
                            icon: const Icon(PhosphorIconsRegular.x, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _focusNode.unfocus();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: filteredItems.length,
                  itemBuilder: (context, i) {
                    final item = filteredItems[i];
                    final isSelected = _localSelected.any((si) => si['id'] == item['id']);
                    return ListTile(
                      title: Text(item['name'], style: GoogleFonts.poppins()),
                      trailing: widget.isMulti
                          ? (isSelected
                              ? const Icon(
                                  PhosphorIconsFill.checkCircle,
                                  color: AppColors.primary,
                                )
                              : const Icon(PhosphorIconsRegular.circle))
                          : (isSelected
                              ? const Icon(
                                  PhosphorIconsBold.check,
                                  color: AppColors.primary,
                                )
                              : null),
                      onTap: () {
                        if (widget.isMulti) {
                          setState(() {
                            if (isSelected) {
                              _localSelected.removeWhere(
                                (si) => si['id'] == item['id'],
                              );
                            } else {
                              _localSelected.add(item);
                            }
                          });
                        }
                        widget.onSelect(item);
                        if (!widget.isMulti) Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
              if (widget.isMulti)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: PrimaryButton(
                    label: 'Done',
                    onTap: () => Navigator.pop(context),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

void showGenericPicker({
  required BuildContext context,
  required String title,
  required List<Map<String, dynamic>> items,
  required Function(Map<String, dynamic>) onSelect,
  bool isMulti = false,
  List<Map<String, dynamic>> selectedItems = const [],
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => GenericPickerSheet(
      title: title,
      items: items,
      onSelect: onSelect,
      isMulti: isMulti,
      selectedItems: selectedItems,
    ),
  );
}
