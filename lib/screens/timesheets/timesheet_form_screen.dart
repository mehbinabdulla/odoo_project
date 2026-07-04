import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/models/project_models.dart';
import '../../core/providers/timesheet_provider.dart';
import '../../core/services/odoo_rpc_service.dart';
import '../../core/services/odoo_field_registry.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/time_input_field.dart';
import '../../core/widgets/manage_fields_sheet.dart';
import '../../core/widgets/collapsing_app_bar_page.dart';
import '../../core/widgets/generic_picker_sheet.dart';

class TimesheetFormScreen extends StatefulWidget {
  /// When [timesheet] is provided the screen is in edit mode; otherwise create mode.
  final TimesheetModel? timesheet;

  /// Optional pre-seeded project ID (used when opened from task detail).
  final int? initialProjectId;

  /// Optional pre-seeded task ID (used when opened from task detail).
  final int? initialTaskId;

  const TimesheetFormScreen({
    super.key,
    this.timesheet,
    this.initialProjectId,
    this.initialTaskId,
  });

  @override
  State<TimesheetFormScreen> createState() => _TimesheetFormScreenState();
}

class _TimesheetFormScreenState extends State<TimesheetFormScreen> {
  final _formKey = GlobalKey<FormState>();

  Map<String, dynamic> _fieldDefs = {};
  bool _isLoadingDefs = true;
  bool _isSaving = false;

  // Always visible, always first
  final Set<String> _defaultFields = {
    'project_id',
    'task_id',
    'date',
    'unit_amount',
    'name',
  };

  Set<String> _visibleFields = {};
  final Map<String, dynamic> _fieldValues = {};
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _visibleFields = Set.from(_defaultFields);
    _loadFieldDefs();
  }

  Future<void> _loadFieldDefs() async {
    const model = 'account.analytic.line';
    final defs = await OdooFieldRegistry.getFieldDefs(model);
    final skipped = await OdooFieldRegistry.getTechnicalFieldNames(model);

    defs.removeWhere((k, _) => skipped.contains(k));

    if (mounted) {
      setState(() {
        _fieldDefs = defs;
        _isLoadingDefs = false;
      });
      _initFieldValues();
    }
  }

  Future<void> _initFieldValues() async {
    if (widget.timesheet != null) {
      final t = widget.timesheet!;
      // Seed from model
      _fieldValues['name'] = t.name ?? '';
      _fieldValues['unit_amount'] = t.unitAmount;

      try {
        final records = await OdooRpcService.searchRead(
          model: 'account.analytic.line',
          domain: [
            ['id', '=', t.id],
          ],
          fields: _fieldDefs.keys.toList(),
          limit: 1,
        );

        if (records.isNotEmpty) {
          final data = records[0];
          for (final key in _fieldDefs.keys) {
            final val = data[key];
            if (val == null || val == '') continue;
            final wasAdded = await _processFieldValue(key, val);
            if (wasAdded && val != false) {
              _visibleFields.add(key);
            }
          }
          if (mounted) setState(() {});
        }
      } catch (e) {
        debugPrint('TimesheetFormScreen: error fetching record: $e');
        // Fallback seeds
        if (t.projectId != null) {
          _fieldValues['project_id'] = {
            'id': t.projectId,
            'name': t.projectName,
          };
        }
        if (t.taskId != null) {
          _fieldValues['task_id'] = {'id': t.taskId, 'name': t.taskName};
        }
        _fieldValues['date'] = DateTime.tryParse(t.date) ?? DateTime.now();
      }
    } else {
      // Create mode: fetch Odoo defaults
      try {
        final defaults = await OdooRpcService.defaultGet(
          model: 'account.analytic.line',
          fields: _fieldDefs.keys.toList(),
        );
        for (final entry in defaults.entries) {
          await _processFieldValue(entry.key, entry.value);
        }
        if (mounted) setState(() {});
      } catch (e) {
        debugPrint('TimesheetFormScreen: error fetching defaults: $e');
      }
      // Default date to today
      if (!_fieldValues.containsKey('date') || _fieldValues['date'] == null) {
        _fieldValues['date'] = DateTime.now();
      }
      // Default hours to 1
      if (!_fieldValues.containsKey('unit_amount') ||
          _fieldValues['unit_amount'] == null) {
        _fieldValues['unit_amount'] = 1.0;
      }
      // Pre-seed project & task if given (e.g. opened from task detail)
      if (widget.initialProjectId != null &&
          !_fieldValues.containsKey('project_id')) {
        _fieldValues['project_id'] = {
          'id': widget.initialProjectId,
          'name': 'Loading...',
        };
        _fetchRelationName(
            'project_id', 'project.project', widget.initialProjectId!);
      }
      if (widget.initialTaskId != null &&
          !_fieldValues.containsKey('task_id')) {
        _fieldValues['task_id'] = {
          'id': widget.initialTaskId,
          'name': 'Loading...',
        };
        _fetchRelationName('task_id', 'project.task', widget.initialTaskId!);
      }
    }
    if (mounted) setState(() {});
  }

  Future<bool> _processFieldValue(String key, dynamic val) async {
    if (val == null || val == '') return false;
    final def = _fieldDefs[key];
    if (def == null) return false;
    final type = def['type'];

    if (type == 'many2one') {
      if (val is List && val.length == 2) {
        _fieldValues[key] = {'id': val[0], 'name': val[1]};
        return true;
      } else if (val is int) {
        _fieldValues[key] = {'id': val, 'name': 'ID: $val'};
        _fetchRelationName(key, def['relation'], val);
        return true;
      }
    } else if (type == 'many2many' || type == 'one2many') {
      List<int> ids = [];
      if (val is List) {
        if (val.isNotEmpty && val[0] is List && val[0].length == 3 && val[0][0] == 6) {
          ids = List<int>.from(val[0][2]);
        } else {
          ids = val.whereType<int>().toList();
        }
      }
      if (ids.isNotEmpty) {
        final relation = def['relation'];
        if (relation != null) {
          try {
            final relRecords = await OdooRpcService.searchRead(
              model: relation,
              domain: [
                ['id', 'in', ids],
              ],
              fields: ['id', 'display_name', 'name'],
            );
            _fieldValues[key] = relRecords
                .map((r) => {
                      'id': r['id'],
                      'name': r['display_name'] ?? r['name'] ?? 'Unknown',
                    })
                .toList();
            return true;
          } catch (_) {
            _fieldValues[key] =
                ids.map((id) => {'id': id, 'name': 'Record $id'}).toList();
            return true;
          }
        }
      }
    } else if (type == 'date' || type == 'datetime') {
      final parsed = DateTime.tryParse(val.toString());
      if (parsed != null) {
        _fieldValues[key] = parsed;
        return true;
      }
    } else if (type == 'selection') {
      final selDef = def['selection'] as List?;
      if (selDef != null) {
        final match = selDef.firstWhere(
          (e) => e[0] == val,
          orElse: () => [val, val.toString()],
        );
        _fieldValues[key] = {'id': match[0], 'name': match[1]};
        return true;
      }
    } else {
      if (val is List && val.isEmpty) return false;
      if (val == false) return false;
      _fieldValues[key] = val;
      return true;
    }
    return false;
  }

  Future<void> _fetchRelationName(
      String field, String? relation, int id) async {
    if (relation == null) return;
    try {
      final records = await OdooRpcService.read(
        model: relation,
        ids: [id],
        fields: ['display_name', 'name'],
      );
      if (records.isNotEmpty && mounted) {
        setState(() {
          _fieldValues[field] = {
            'id': id,
            'name': records[0]['display_name'] ??
                records[0]['name'] ??
                'ID: $id',
          };
        });
      }
    } catch (_) {}
  }

  TextEditingController _getController(String field) {
    if (!_controllers.containsKey(field)) {
      String initial = '';
      final val = _fieldValues[field];
      if (val is double) {
        initial = val.toStringAsFixed(val == val.truncateToDouble() ? 0 : 2);
      } else if (val != null) {
        initial = val.toString();
      }
      _controllers[field] = TextEditingController(text: initial);
      _controllers[field]!.addListener(() {
        _fieldValues[field] = _controllers[field]!.text;
      });
    }
    return _controllers[field]!;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _orderedVisibleFields {
    final list =
        _visibleFields.where((f) => _fieldDefs.containsKey(f)).toList();
    list.sort((a, b) {
      final aDef = _defaultFields.contains(a);
      final bDef = _defaultFields.contains(b);
      if (aDef && !bDef) return -1;
      if (!aDef && bDef) return 1;
      if (aDef && bDef) {
        return _defaultFields
            .toList()
            .indexOf(a)
            .compareTo(_defaultFields.toList().indexOf(b));
      }
      final aStr = _fieldDefs[a]?['string'] ?? a;
      final bStr = _fieldDefs[b]?['string'] ?? b;
      return aStr.toString().compareTo(bStr.toString());
    });
    return list;
  }

  Future<void> _pickDate(String field) async {
    final current = _fieldValues[field] is DateTime
        ? _fieldValues[field] as DateTime
        : DateTime.now();
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
            colorScheme: theme.colorScheme.copyWith(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: theme.cardTheme.color,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _fieldValues[field] = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_visibleFields.contains('project_id') &&
        _fieldValues['project_id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a project')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final values = <String, dynamic>{};
    for (final field in _visibleFields) {
      final def = _fieldDefs[field];
      if (def == null) continue;
      final type = def['type'];
      final val = _fieldValues[field];

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

    final provider = context.read<TimesheetProvider>();
    final bool success;
    if (widget.timesheet != null) {
      success = await provider.updateTimesheet(widget.timesheet!.id, values);
    } else {
      success = await provider.createTimesheetDynamic(values);
    }

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.timesheet != null
                  ? 'Timesheet updated successfully'
                  : 'Timesheet created successfully',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${provider.error ?? 'Unknown error'}'),
          ),
        );
      }
    }
  }

  void _showHiddenFieldsPicker() async {
    final candidateFields = _fieldDefs.entries
        .where(
          (e) =>
              e.value['readonly'] != true &&
              e.value['type'] != 'binary' &&
              e.value['type'] != 'one2many' &&
              e.key != 'id',
        )
        .toList();

    final candidateNames = candidateFields.map((e) => e.key).toList();
    final writeableNames = await OdooFieldRegistry.checkFieldAccessRights(
      'account.analytic.line',
      'write',
      candidateNames,
    );

    final availableFields = candidateFields
        .where((e) => writeableNames.contains(e.key))
        .toList();

    final availableNames = availableFields.map((e) => e.key).toList()..sort();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ManageFieldsSheet(
        fieldDefs: _fieldDefs,
        availableFields: availableNames,
        visibleFields: _visibleFields,
        defaultFields: _defaultFields,
        onVisibleFieldsChanged: (newVisibleFields) {
          setState(() {
            _visibleFields.clear();
            _visibleFields.addAll(newVisibleFields);
          });
        },
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return CollapsingAppBarPage(
      title: widget.timesheet != null ? 'Edit Time Entry' : 'Log Time',
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(PhosphorIconsBold.caretLeft, size: 20),
          ),
        ],
      ),
      actions: [
        if (!_isLoadingDefs)
          IconButton(
            icon: const Icon(PhosphorIconsBold.listPlus, size: 22),
            onPressed: _showHiddenFieldsPicker,
            tooltip: 'Manage Fields',
          ),
      ],
      body: _isLoadingDefs || _isSaving
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  ..._buildDynamicFields(theme, isDark),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: widget.timesheet != null
                        ? 'Save Entry'
                        : 'Create Entry',
                    onTap: _save,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  List<Widget> _buildDynamicFields(ThemeData theme, bool isDark) {
    final widgets = <Widget>[];

    for (final field in _orderedVisibleFields) {
      final def = _fieldDefs[field];
      if (def == null) continue;
      final type = def['type'];
      String label = def['string'] ?? field;
      
      // Odoo's fields_get returns the base model label ("Quantity") for unit_amount, 
      // but in timesheets it's typically overridden in the view to "Hours Spent".
      if (field == 'unit_amount') {
        label = 'Hours Spent';
      }

      final required = def['required'] == true;

      Widget? inputWidget;

      if (type == 'char') {
        inputWidget = TextFormField(
          controller: _getController(field),
          decoration: _inputDecoration(label, PhosphorIconsRegular.textT),
          style: GoogleFonts.poppins(fontSize: 16),
          validator: required
              ? (v) => v == null || v.isEmpty ? 'Required' : null
              : null,
        );
      } else if (type == 'text' || type == 'html') {
        inputWidget = TextFormField(
          controller: _getController(field),
          maxLines: 4,
          decoration: _inputDecoration(
            '$label...',
            PhosphorIconsRegular.article,
            isMultiline: true,
          ),
          style: GoogleFonts.poppins(fontSize: 14),
        );
      } else if (type == 'many2one') {
        final val = _fieldValues[field] as Map?;
        final relation = def['relation'] as String?;
        inputWidget = _buildSelectorTile(
          label,
          val?['name'] ?? 'Select $label',
          PhosphorIconsRegular.link,
          relation != null
              ? () => _showRelationPicker(field, relation, label, false)
              : null,
          theme,
          isDark,
        );
      } else if (type == 'many2many') {
        final val = _fieldValues[field] as List?;
        final text = (val == null || val.isEmpty)
            ? 'Add $label'
            : val.map((e) => (e as Map)['name']).join(', ');
        final relation = def['relation'] as String?;
        inputWidget = _buildSelectorTile(
          label,
          text,
          PhosphorIconsRegular.users,
          relation != null
              ? () => _showRelationPicker(field, relation, label, true)
              : null,
          theme,
          isDark,
        );
      } else if (type == 'date' || type == 'datetime') {
        final val = _fieldValues[field] is DateTime
            ? _fieldValues[field] as DateTime
            : null;
        inputWidget = _buildSelectorTile(
          label,
          val == null ? 'Set $label' : DateFormat('MMM dd, yyyy').format(val),
          PhosphorIconsRegular.calendarBlank,
          () => _pickDate(field),
          theme,
          isDark,
        );
      } else if (type == 'boolean') {
        final val = _fieldValues[field] == true;
        inputWidget = SwitchListTile(
          title: Text(label, style: GoogleFonts.poppins()),
          value: val,
          activeThumbColor: AppColors.primary,
          onChanged: (v) => setState(() => _fieldValues[field] = v),
          contentPadding: EdgeInsets.zero,
        );
      } else if (type == 'selection') {
        final val = _fieldValues[field] as Map?;
        final selDef = def['selection'] as List?;
        inputWidget = _buildSelectorTile(
          label,
          val?['name'] ?? 'Select $label',
          PhosphorIconsRegular.caretDown,
          selDef != null
              ? () => _showSelectionPicker(field, selDef, label)
              : null,
          theme,
          isDark,
        );
      } else if (type == 'integer' ||
          type == 'float' ||
          type == 'monetary') {
        final isTimeField = def['widget'] == 'timesheet_uom' ||
            field == 'unit_amount' ||
            field == 'allocated_hours' ||
            field == 'effective_hours';

        if (isTimeField) {
          final val = _fieldValues[field];
          double initialVal = 0.0;
          if (val is double) {
            initialVal = val;
          } else if (val != null) {
            initialVal = double.tryParse(val.toString()) ?? 0.0;
          }

          inputWidget = TimeInputField(
            initialValue: initialVal,
            onChanged: (v) => setState(() => _fieldValues[field] = v),
            decoration: _inputDecoration(label, PhosphorIconsRegular.clock),
            validator: required
                ? (v) => v == null || v.isEmpty ? 'Required' : null
                : null,
          );
        } else {
          inputWidget = TextFormField(
            controller: _getController(field),
            keyboardType:
                TextInputType.numberWithOptions(decimal: type != 'integer'),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(type == 'integer' ? r'[0-9]' : r'[0-9.]'),
              ),
            ],
            decoration: _inputDecoration(
              label,
              type == 'monetary'
                  ? PhosphorIconsRegular.currencyDollar
                  : PhosphorIconsRegular.numberSquareOne,
            ),
            style: GoogleFonts.poppins(fontSize: 16),
            validator: required
                ? (v) => v == null || v.isEmpty ? 'Required' : null
                : null,
          );
        }
      }

      if (inputWidget != null) {
        widgets.add(_buildSectionLabel(label.toUpperCase()));
        widgets.add(const SizedBox(height: 6));
        widgets.add(inputWidget);
        widgets.add(const SizedBox(height: 18));
      }
    }

    return widgets;
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: Theme.of(context)
            .colorScheme
            .onSurface
            .withValues(alpha: 0.5),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String hint,
    IconData icon, {
    bool isMultiline = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget iconWidget = Padding(
      padding:
          EdgeInsets.only(left: 16, right: 8, top: isMultiline ? 12 : 0),
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
      fillColor:
          isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: isMultiline
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 16)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget _buildSelectorTile(
    String label,
    String value,
    IconData icon,
    VoidCallback? onTap,
    ThemeData theme,
    bool isDark,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
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

  // ── Pickers ─────────────────────────────────────────────────────────────────

  void _showRelationPicker(
    String field,
    String relation,
    String label,
    bool isMulti,
  ) async {
    try {
      List<dynamic> domain = [];
      if (relation == 'res.users') {
        domain = [
          ['share', '=', false],
        ];
      }
      if (relation == 'project.task' &&
          _fieldValues['project_id'] is Map) {
        final projId = (_fieldValues['project_id'] as Map)['id'];
        if (projId != null) {
          domain = [
            ['project_id', '=', projId],
          ];
        }
      }

      final records = await OdooRpcService.searchRead(
        model: relation,
        domain: domain,
        fields: ['id', 'display_name', 'name'],
        limit: 80,
      );

      final mapped = records
          .map((r) => {
                'id': r['id'],
                'name': r['display_name'] ?? r['name'] ?? 'Unknown',
              })
          .toList();

      List<Map<String, dynamic>> currentSelected = [];
      if (isMulti) {
        currentSelected =
            List<Map<String, dynamic>>.from(_fieldValues[field] ?? []);
      } else {
        final currentVal = _fieldValues[field];
        if (currentVal != null) {
          if (currentVal is Map) {
            currentSelected = [Map<String, dynamic>.from(currentVal)];
          } else if (currentVal is List && currentVal.isNotEmpty) {
            currentSelected = [{'id': currentVal[0], 'name': currentVal.length > 1 ? currentVal[1] : ''}];
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
          setState(() {
            if (isMulti) {
              final list = List<Map<String, dynamic>>.from(
                _fieldValues[field] ?? [],
              );
              final idx = list.indexWhere((e) => e['id'] == item['id']);
              if (idx >= 0) {
                list.removeAt(idx);
              } else {
                list.add(item);
              }
              _fieldValues[field] = list;
            } else {
              _fieldValues[field] = item;
            }
          });
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load $label options')),
        );
      }
    }
  }

  void _showSelectionPicker(
      String field, List<dynamic> selDef, String label) {
    final mapped = selDef
        .map((e) => {'id': e[0], 'name': e[1].toString()})
        .toList();

    List<Map<String, dynamic>> currentSelected = [];
    final currentVal = _fieldValues[field];
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
      isMulti: false,
      selectedItems: currentSelected,
      onSelect: (item) {
        setState(() => _fieldValues[field] = item);
      },
    );
  }

}
