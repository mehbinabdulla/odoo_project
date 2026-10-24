import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'primary_button.dart';

class ManageFieldsSheet extends StatefulWidget {
  final Map<String, dynamic> fieldDefs;
  final List<String> availableFields;
  final Set<String> visibleFields;
  final Set<String> defaultFields;
  final ValueChanged<Set<String>> onVisibleFieldsChanged;

  const ManageFieldsSheet({
    super.key,
    required this.fieldDefs,
    required this.availableFields,
    required this.visibleFields,
    required this.defaultFields,
    required this.onVisibleFieldsChanged,
  });

  @override
  State<ManageFieldsSheet> createState() => _ManageFieldsSheetState();
}

class _ManageFieldsSheetState extends State<ManageFieldsSheet> {
  late TextEditingController _searchController;
  late Set<String> _currentVisibleFields;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _currentVisibleFields = Set.from(widget.visibleFields);
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
        final filteredFields = query.isEmpty
            ? widget.availableFields
            : widget.availableFields.where((f) {
                final def = widget.fieldDefs[f];
                final label = (def?['string'] as String? ?? f).toLowerCase();
                return label.contains(query) || f.toLowerCase().contains(query);
              }).toList();

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                  'Manage Fields',
                  style: GoogleFonts.dmSerifDisplay(
                    fontSize: 24,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              // ── Search bar ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  focusNode: _focusNode,
                  controller: _searchController,
                  autofocus: false,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search fields…',
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.35),
                    ),
                    prefixIcon: const Icon(
                      PhosphorIconsRegular.magnifyingGlass,
                      size: 20,
                    ),
                    suffixIcon:
                        (_searchController.text.isNotEmpty ||
                            _focusNode.hasFocus)
                        ? IconButton(
                            icon: const Icon(PhosphorIconsRegular.x, size: 18),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              _focusNode.unfocus();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              // ── Field list ────────────────────────────────────────────
              Expanded(
                child: filteredFields.isEmpty
                    ? Center(
                        child: Text(
                          'No fields match "${_searchController.text}"',
                          style: GoogleFonts.poppins(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: controller,
                        itemCount: filteredFields.length,
                        itemBuilder: (context, i) {
                          final key = filteredFields[i];
                          final def = widget.fieldDefs[key];
                          final isVisible = _currentVisibleFields.contains(key);
                          final isDefault = widget.defaultFields.contains(key);

                          // Custom label logic for Odoo overrides
                          String label = def?['string'] ?? key;
                          if (key == 'unit_amount') label = 'Hours Spent';

                          return CheckboxListTile(
                            title: Text(label, style: GoogleFonts.poppins()),
                            subtitle: Text(
                              key,
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                            value: isVisible,
                            activeColor: AppColors.primary,
                            onChanged: isDefault
                                ? null
                                : (val) {
                                    setState(() {
                                      if (val == true) {
                                        _currentVisibleFields.add(key);
                                      } else {
                                        _currentVisibleFields.remove(key);
                                      }
                                    });
                                    widget.onVisibleFieldsChanged(
                                      _currentVisibleFields,
                                    );
                                  },
                          );
                        },
                      ),
              ),
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
