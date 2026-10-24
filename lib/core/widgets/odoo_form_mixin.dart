import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_theme.dart';
import '../services/odoo_field_registry.dart';
import '../services/odoo_rpc_service.dart';
import 'generic_picker_sheet.dart';
import 'manage_fields_sheet.dart';
import 'time_input_field.dart';

/// Shared state + logic for the dynamic Odoo form screens
/// (project / task / timesheet).
///
/// Screens keep only their genuinely unique parts:
/// - [odooModel] + [defaultFields]
/// - create-mode seeds / edit-mode fallbacks ([seedEditFallback])
/// - pre-submit validation ([validateBeforeSave])
/// - label/required/time-field overrides
/// - save wiring (provider calls)
///
/// Everything else (field-def loading, value processing, controllers,
/// date picking, save-value building, pickers, input widgets) lives here.
mixin OdooFormMixin<T extends StatefulWidget> on State<T> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  Map<String, dynamic> fieldDefs = {};
  bool isLoadingDefs = true;
  bool isSaving = false;

  Set<String> visibleFields = {};
  final Map<String, dynamic> fieldValues = {};
  final Map<String, TextEditingController> formControllers = {};

  /// Odoo model, e.g. `project.project`.
  String get odooModel;

  /// Fields visible by default, in display order.
  Set<String> get defaultFields;

  /// Display label for a field. Override for view-level renames
  /// (e.g. timesheet `unit_amount` -> "Hours Spent").
  String formFieldLabel(String field, Map<dynamic, dynamic> def) =>
      (def['string'] ?? field).toString();

  /// Whether the field is required. Override to force extras
  /// (e.g. project `name`).
  bool formFieldRequired(String field, Map<dynamic, dynamic> def) =>
      def['required'] == true;

  /// Whether a numeric field should use the HH:MM time input.
  /// Task forms opt out by overriding this to `false`.
  bool formIsTimeField(String field, Map<dynamic, dynamic> def) =>
      def['widget'] == 'timesheet_uom' ||
      field == 'unit_amount' ||
      field == 'allocated_hours' ||
      field == 'effective_hours';

  /// Whether text/html fields validate `required`. Project and timesheet
  /// forms don't; task forms do.
  bool formValidateTextField(String field, Map<dynamic, dynamic> def) => false;

  /// Icon for plain numeric fields. Task forms always use the generic
  /// number icon, even for monetary fields.
  IconData formNumericIcon(String type) => type == 'monetary'
      ? PhosphorIconsRegular.currencyDollar
      : PhosphorIconsRegular.numberSquareOne;

  /// Error message when a relation picker fetch fails. Timesheets use a
  /// shorter message without the exception details.
  String formRelationErrorText(String label, Object e) =>
      'Error fetching $label: $e';

  /// Extra search domain for relation pickers. The shared default filters
  /// `res.users` to internal users; screens extend it (timesheets also
  /// scope `project.task` to the selected project).
  List<dynamic> formRelationDomain(String relation) {
    if (relation == 'res.users') {
      return [
        ['share', '=', false],
      ];
    }
    return [];
  }

  // ── Lifecycle helpers ────────────────────────────────────────────────

  /// Loads field defs, drops technical fields, then runs [afterLoaded]
  /// (normally the screen's `_initFieldValues`) in the background.
  Future<void> loadFormFieldDefs(Future<void> Function() afterLoaded) async {
    final defs = await OdooFieldRegistry.getFieldDefs(odooModel);
    final skipped = await OdooFieldRegistry.getTechnicalFieldNames(odooModel);
    defs.removeWhere((k, _) => skipped.contains(k));
    if (!mounted) return;
    setState(() {
      fieldDefs = defs;
      isLoadingDefs = false;
    });
    await afterLoaded();
  }

  void disposeFormControllers() {
    for (final c in formControllers.values) {
      c.dispose();
    }
    formControllers.clear();
  }

  // ── Value handling ───────────────────────────────────────────────────

  /// Normalises one raw Odoo value into [fieldValues]. Returns true when a
  /// displayable value was stored. Covers many2one / x2many / date /
  /// selection / scalar, for both `search_read` and `default_get` shapes.
  Future<bool> processFormValue(String key, dynamic val) async {
    if (val == null || val == '' || val == false) return false;
    final def = fieldDefs[key];
    if (def == null) return false;
    final type = def['type'];

    if (type == 'many2one') {
      if (val is List && val.length == 2) {
        fieldValues[key] = {'id': val[0], 'name': val[1]};
        return true;
      } else if (val is int) {
        fieldValues[key] = {'id': val, 'name': 'ID: $val'};
        final relation = def['relation'] as String?;
        if (relation != null) {
          unawaitedFetchRelationName(key, relation, val);
        }
        return true;
      }
    } else if (type == 'many2many' || type == 'one2many') {
      final ids = extractRelationIds(val);
      if (ids.isNotEmpty) {
        final relation = def['relation'] as String?;
        if (relation != null) {
          try {
            final relRecords = await OdooRpcService.searchRead(
              model: relation,
              domain: [
                ['id', 'in', ids],
              ],
              fields: const ['id', 'display_name', 'name'],
            );
            if (!mounted) return false;
            fieldValues[key] = relRecords
                .map((r) => {
                      'id': r['id'],
                      'name': r['display_name'] ?? r['name'] ?? 'Unknown',
                    })
                .toList();
            return true;
          } catch (_) {
            if (!mounted) return false;
            fieldValues[key] =
                ids.map((id) => {'id': id, 'name': 'Record $id'}).toList();
            return true;
          }
        }
      }
    } else if (type == 'date' || type == 'datetime') {
      final parsed = DateTime.tryParse(val.toString());
      if (parsed != null) {
        fieldValues[key] = parsed;
        return true;
      }
    } else if (type == 'selection') {
      final selDef = def['selection'] as List?;
      if (selDef != null) {
        final match = selDef.firstWhere(
          (e) => e[0] == val,
          orElse: () => [val, val.toString()],
        );
        fieldValues[key] = {'id': match[0], 'name': match[1].toString()};
        return true;
      }
    } else {
      if (val is List && val.isEmpty) return false;
      fieldValues[key] = val;
      return true;
    }
    return false;
  }

  /// Extracts record ids from `search_read` ([ids]) and `default_get`
  /// (`[[6, 0, [ids]]]`) shapes.
  static List<int> extractRelationIds(dynamic val) {
    if (val is! List || val.isEmpty) return [];
    if (val[0] is List && val[0].length == 3 && val[0][0] == 6) {
      return List<int>.from(val[0][2] as List);
    }
    return val.whereType<int>().toList();
  }

  void unawaitedFetchRelationName(String field, String relation, int id) {
    fetchFormRelationName(field, relation, id);
  }

  Future<void> fetchFormRelationName(
    String field,
    String? relation,
    int id,
  ) async {
    if (relation == null) return;
    try {
      final records = await OdooRpcService.read(
        model: relation,
        ids: [id],
        fields: const ['display_name', 'name'],
      );
      if (records.isNotEmpty && mounted) {
        setState(() {
          fieldValues[field] = {
            'id': id,
            'name':
                records[0]['display_name'] ?? records[0]['name'] ?? 'ID: $id',
          };
        });
      }
    } catch (_) {}
  }

  /// Applies one fetched record (`search_read` row) to [fieldValues],
  /// marking valued fields visible.
  Future<void> applyFetchedRecord(Map<String, dynamic> data) async {
    for (final key in fieldDefs.keys) {
      final val = data[key];
      if (val == null || val == '') continue;
      final wasAdded = await processFormValue(key, val);
      if (!mounted) return;
      if (wasAdded && val != false) {
        visibleFields.add(key);
      }
    }
    if (mounted) setState(() {});
  }

  /// Applies `default_get` values (create mode).
  Future<void> applyDefaultValues(Map<String, dynamic> defaults) async {
    for (final entry in defaults.entries) {
      await processFormValue(entry.key, entry.value);
      if (!mounted) return;
    }
    if (mounted) setState(() {});
  }

  TextEditingController getFormController(String field) {
    final existing = formControllers[field];
    if (existing != null) return existing;
    String initial = '';
    final val = fieldValues[field];
    if (val is double) {
      initial = val.toStringAsFixed(val == val.truncateToDouble() ? 0 : 2);
    } else if (val != null) {
      initial = val.toString();
    }
    final controller = TextEditingController(text: initial);
    controller.addListener(() {
      fieldValues[field] = controller.text;
    });
    formControllers[field] = controller;
    return controller;
  }

  List<String> get orderedFormFields {
    final list =
        visibleFields.where((f) => fieldDefs.containsKey(f)).toList();
    final defaults = defaultFields.toList();
    list.sort((a, b) {
      final aDef = defaultFields.contains(a);
      final bDef = defaultFields.contains(b);
      if (aDef && !bDef) return -1;
      if (!aDef && bDef) return 1;
      if (aDef && bDef) {
        return defaults.indexOf(a).compareTo(defaults.indexOf(b));
      }
      return (fieldDefs[a]?['string'] ?? a)
          .toString()
          .compareTo((fieldDefs[b]?['string'] ?? b).toString());
    });
    return list;
  }

  Future<void> pickFormDate(String field) async {
    final raw = fieldValues[field];
    final current = raw is DateTime ? raw : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            datePickerTheme: DatePickerThemeData(
              backgroundColor: theme.cardTheme.color,
              surfaceTintColor: Colors.transparent,
            ),
            dialogTheme: theme.dialogTheme.copyWith(
              backgroundColor: theme.cardTheme.color,
              surfaceTintColor: Colors.transparent,
            ),
            colorScheme: theme.colorScheme.copyWith(
              primary: AppColors.primary,
              onPrimary: theme.colorScheme.onPrimary,
              surface: theme.cardTheme.color,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => fieldValues[field] = picked);
    }
  }

  /// Serialises visible field values to Odoo write/create values.
  Map<String, dynamic> buildFormSaveValues() {
    final values = <String, dynamic>{};
    for (final field in visibleFields) {
      final def = fieldDefs[field];
      if (def == null) continue;
      final type = def['type'];
      final val = fieldValues[field];
      if (val == null || (val is String && val.isEmpty)) continue;

      if (type == 'many2one') {
        values[field] = (val as Map)['id'];
      } else if (type == 'many2many') {
        final list = (val as List).map((e) => (e as Map)['id']).toList();
        values[field] = [
          [6, 0, list],
        ];
      } else if (type == 'date' || type == 'datetime') {
        values[field] = DateFormat('yyyy-MM-dd').format(val as DateTime);
      } else if (type == 'boolean') {
        values[field] = val == true;
      } else if (type == 'selection') {
        values[field] = (val as Map)['id'];
      } else if (type == 'integer') {
        values[field] = int.tryParse(val.toString()) ?? 0;
      } else if (type == 'float' || type == 'monetary') {
        values[field] = double.tryParse(val.toString()) ?? 0.0;
      } else {
        values[field] = val;
      }
    }
    return values;
  }

  Future<void> showFormHiddenFieldsPicker() async {
    final candidateFields = fieldDefs.entries
        .where(
          (e) =>
              e.value['readonly'] != true &&
              e.value['type'] != 'binary' &&
              e.value['type'] != 'one2many' &&
              e.key != 'id',
        )
        .toList();

    final candidateNames = candidateFields.map((e) => e.key).toList();
    final writeableNames =
        await OdooFieldRegistry.checkFieldAccessRights(
      odooModel,
      'write',
      candidateNames,
    );
    if (!mounted) return;

    final availableFields =
        candidateFields.where((e) => writeableNames.contains(e.key)).toList()
          ..sort(
            (a, b) => (a.value['string'] as String)
                .compareTo(b.value['string'] as String),
          );

    final availableNames = availableFields.map((e) => e.key).toList()..sort();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ManageFieldsSheet(
        fieldDefs: fieldDefs,
        availableFields: availableNames,
        visibleFields: visibleFields,
        defaultFields: defaultFields,
        onVisibleFieldsChanged: (newVisibleFields) {
          setState(() {
            visibleFields
              ..clear()
              ..addAll(newVisibleFields);
          });
        },
      ),
    );
  }

  // ── Shared field widgets ─────────────────────────────────────────────

  Widget formSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }

  InputDecoration formInputDecoration(
    String hint,
    IconData icon, {
    bool isMultiline = false,
  }) {
    Widget iconWidget = Padding(
      padding: EdgeInsets.only(left: 16, right: 8, top: isMultiline ? 12 : 0),
      child: Icon(icon, size: 20),
    );
    if (isMultiline) {
      iconWidget = UnconstrainedBox(
        alignment: Alignment.topCenter,
        child: iconWidget,
      );
    }
    return InputDecoration(
      hintText: hint,
      prefixIcon: iconWidget,
      prefixIconConstraints: isMultiline
          ? const BoxConstraints(minWidth: 0, minHeight: 130)
          : const BoxConstraints(minWidth: 0, minHeight: 0),
      filled: true,
      fillColor: Theme.of(context).cardTheme.color,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: isMultiline
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 16)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget formSelectorTile(
    String value,
    IconData icon,
    VoidCallback? onTap,
    ThemeData theme,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onTap != null)
              Icon(
                PhosphorIconsRegular.caretRight,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds the input widget for one visible field, or null when the type
  /// is not rendered. [textMaxLines] preserves the per-screen multiline
  /// height (project/task 5, timesheet 4).
  Widget? buildFormInput(
    String field,
    ThemeData theme, {
    int textMaxLines = 5,
  }) {
    final def = fieldDefs[field];
    if (def == null) return null;
    final type = def['type'];
    final label = formFieldLabel(field, def);
    final required = formFieldRequired(field, def);

    String? requiredValidator(String? v) =>
        required && (v == null || v.isEmpty) ? 'Required' : null;

    switch (type) {
      case 'char':
        return TextFormField(
          controller: getFormController(field),
          decoration: formInputDecoration(label, PhosphorIconsRegular.textT),
          style: GoogleFonts.poppins(fontSize: 16),
          validator: requiredValidator,
        );
      case 'text':
      case 'html':
        return TextFormField(
          controller: getFormController(field),
          maxLines: textMaxLines,
          decoration: formInputDecoration(
            '$label...',
            PhosphorIconsRegular.article,
            isMultiline: true,
          ),
          style: GoogleFonts.poppins(fontSize: 14),
          validator:
              formValidateTextField(field, def) ? requiredValidator : null,
        );
      case 'many2one':
        final val = fieldValues[field] as Map?;
        final relation = def['relation'] as String?;
        return formSelectorTile(
          val?['name']?.toString() ?? 'Select $label',
          PhosphorIconsRegular.link,
          relation == null
              ? null
              : () => showFormRelationPicker(field, relation, label, false),
          theme,
        );
      case 'many2many':
        final val = fieldValues[field] as List?;
        final text = (val == null || val.isEmpty)
            ? 'Add $label'
            : val.map((e) => (e as Map)['name']).join(', ');
        final relation = def['relation'] as String?;
        return formSelectorTile(
          text,
          PhosphorIconsRegular.users,
          relation == null
              ? null
              : () => showFormRelationPicker(field, relation, label, true),
          theme,
        );
      case 'date':
      case 'datetime':
        final val = fieldValues[field] is DateTime
            ? fieldValues[field] as DateTime
            : null;
        return formSelectorTile(
          val == null ? 'Set $label' : DateFormat('MMM dd, yyyy').format(val),
          PhosphorIconsRegular.calendarBlank,
          () => pickFormDate(field),
          theme,
        );
      case 'boolean':
        final val = fieldValues[field] == true;
        return SwitchListTile(
          title: Text(label, style: GoogleFonts.poppins()),
          value: val,
          activeThumbColor: AppColors.primary,
          onChanged: (v) => setState(() => fieldValues[field] = v),
          contentPadding: EdgeInsets.zero,
        );
      case 'selection':
        final val = fieldValues[field] as Map?;
        final selDef = def['selection'] as List?;
        return formSelectorTile(
          val?['name']?.toString() ?? 'Select $label',
          PhosphorIconsRegular.caretDown,
          selDef == null
              ? null
              : () => showFormSelectionPicker(field, selDef, label),
          theme,
        );
      case 'integer':
      case 'float':
      case 'monetary':
        if (formIsTimeField(field, def)) {
          final val = fieldValues[field];
          double initialVal = 0.0;
          if (val is double) {
            initialVal = val;
          } else if (val != null) {
            initialVal = double.tryParse(val.toString()) ?? 0.0;
          }
          return TimeInputField(
            initialValue: initialVal,
            onChanged: (v) {
              if (mounted) setState(() => fieldValues[field] = v);
            },
            decoration:
                formInputDecoration(label, PhosphorIconsRegular.clock),
            validator: requiredValidator,
          );
        }
        return TextFormField(
          controller: getFormController(field),
          keyboardType:
              TextInputType.numberWithOptions(decimal: type != 'integer'),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(type == 'integer' ? r'[0-9]' : r'[0-9.]'),
            ),
          ],
          decoration: formInputDecoration(label, formNumericIcon(type)),
          style: GoogleFonts.poppins(fontSize: 16),
          validator: requiredValidator,
        );
      default:
        return null;
    }
  }

  /// Wraps [buildFormInput] with the uppercase section label + spacing used
  /// by all three form screens.
  List<Widget> buildFormFieldList(
    ThemeData theme, {
    int textMaxLines = 5,
  }) {
    final widgets = <Widget>[];
    for (final field in orderedFormFields) {
      final def = fieldDefs[field];
      if (def == null) continue;
      final label = formFieldLabel(field, def);
      final input = buildFormInput(field, theme, textMaxLines: textMaxLines);
      if (input != null) {
        widgets.add(formSectionLabel(label.toUpperCase()));
        widgets.add(const SizedBox(height: 6));
        widgets.add(input);
        widgets.add(const SizedBox(height: 18));
      }
    }
    return widgets;
  }

  // ── Pickers ──────────────────────────────────────────────────────────

  Future<void> showFormRelationPicker(
    String field,
    String relation,
    String label,
    bool isMulti,
  ) async {
    try {
      final domain = formRelationDomain(relation);
      final records = await OdooRpcService.searchRead(
        model: relation,
        domain: domain,
        fields: const ['id', 'display_name', 'name'],
        limit: 80,
      );
      if (!mounted) return;

      final mapped = records
          .map((r) => {
                'id': r['id'],
                'name': r['display_name'] ?? r['name'] ?? 'Unknown',
              })
          .toList();

      List<Map<String, dynamic>> currentSelected = [];
      if (isMulti) {
        currentSelected = List<Map<String, dynamic>>.from(
          fieldValues[field] ?? [],
        );
      } else {
        final currentVal = fieldValues[field];
        if (currentVal != null) {
          if (currentVal is Map) {
            currentSelected = [Map<String, dynamic>.from(currentVal)];
          } else if (currentVal is List && currentVal.isNotEmpty) {
            currentSelected = [
              {
                'id': currentVal[0],
                'name': currentVal.length > 1 ? currentVal[1] : '',
              },
            ];
          }
        }
      }

      if (!mounted) return;
      showGenericPicker(
        context: context,
        title: 'Select $label',
        items: mapped,
        isMulti: isMulti,
        selectedItems: currentSelected,
        onSelect: (item) {
          if (!mounted) return;
          setState(() {
            if (isMulti) {
              final list = List<Map<String, dynamic>>.from(
                fieldValues[field] ?? [],
              );
              final idx = list.indexWhere((e) => e['id'] == item['id']);
              if (idx >= 0) {
                list.removeAt(idx);
              } else {
                list.add(item);
              }
              fieldValues[field] = list;
            } else {
              fieldValues[field] = item;
            }
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(formRelationErrorText(label, e))),
      );
    }
  }

  void showFormSelectionPicker(
    String field,
    List<dynamic>? selection,
    String label,
  ) {
    if (selection == null) return;
    final mapped =
        selection.map((e) => {'id': e[0], 'name': e[1].toString()}).toList();

    List<Map<String, dynamic>> currentSelected = [];
    final currentVal = fieldValues[field];
    if (currentVal != null) {
      if (currentVal is Map) {
        currentSelected = [Map<String, dynamic>.from(currentVal)];
      } else {
        final match = mapped.where((e) => e['id'] == currentVal).toList();
        if (match.isNotEmpty) {
          currentSelected = [match.first];
        }
      }
    }

    showGenericPicker(
      context: context,
      title: 'Select $label',
      items: mapped,
      selectedItems: currentSelected,
      onSelect: (item) {
        if (!mounted) return;
        setState(() => fieldValues[field] = item);
      },
    );
  }

  // ── Shared chrome ────────────────────────────────────────────────────

  /// Back chevron with tooltip (all form/detail screens).
  Widget formBackButton() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(PhosphorIconsBold.caretLeft, size: 20),
          tooltip: 'Back',
        ),
      ],
    );
  }

  Widget formLoadingIndicator() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }
}
