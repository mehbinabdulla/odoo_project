import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/models/project_models.dart';
import '../../core/providers/timesheet_provider.dart';
import '../../core/services/odoo_rpc_service.dart';
import '../../core/widgets/collapsing_app_bar_page.dart';
import '../../core/widgets/odoo_form_mixin.dart';
import '../../core/widgets/primary_button.dart';

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

class _TimesheetFormScreenState extends State<TimesheetFormScreen>
    with OdooFormMixin {
  @override
  String get odooModel => 'account.analytic.line';

  // Always visible, always first
  @override
  final Set<String> defaultFields = {
    'project_id',
    'task_id',
    'date',
    'unit_amount',
    'name',
  };

  // Odoo's fields_get returns the base model label ("Quantity") for
  // unit_amount, but in timesheets it's typically overridden in the view
  // to "Hours Spent".
  @override
  String formFieldLabel(String field, Map<dynamic, dynamic> def) {
    if (field == 'unit_amount') return 'Hours Spent';
    return super.formFieldLabel(field, def);
  }

  @override
  String formRelationErrorText(String label, Object e) =>
      'Could not load $label options';

  @override
  List<dynamic> formRelationDomain(String relation) {
    // Scope task options to the selected project when one is chosen.
    if (relation == 'project.task' && fieldValues['project_id'] is Map) {
      final projId = (fieldValues['project_id'] as Map)['id'];
      if (projId != null) {
        return [
          ['project_id', '=', projId],
        ];
      }
    }
    return super.formRelationDomain(relation);
  }

  @override
  void initState() {
    super.initState();
    visibleFields = Set.from(defaultFields);
    loadFormFieldDefs(_initFieldValues);
  }

  Future<void> _initFieldValues() async {
    if (widget.timesheet != null) {
      final t = widget.timesheet!;
      // Seed from model
      fieldValues['name'] = t.name ?? '';
      fieldValues['unit_amount'] = t.unitAmount;

      try {
        final records = await OdooRpcService.searchRead(
          model: odooModel,
          domain: [
            ['id', '=', t.id],
          ],
          fields: fieldDefs.keys.toList(),
          limit: 1,
        );
        if (!mounted) return;
        if (records.isNotEmpty) {
          await applyFetchedRecord(records[0]);
        }
      } catch (e) {
        debugPrint('TimesheetFormScreen: error fetching record: $e');
        if (!mounted) return;
        // Fallback seeds
        if (t.projectId != null) {
          fieldValues['project_id'] = {
            'id': t.projectId,
            'name': t.projectName,
          };
        }
        if (t.taskId != null) {
          fieldValues['task_id'] = {'id': t.taskId, 'name': t.taskName};
        }
        fieldValues['date'] = DateTime.tryParse(t.date) ?? DateTime.now();
        setState(() {});
      }
    } else {
      // Create mode: fetch Odoo defaults
      try {
        final defaults = await OdooRpcService.defaultGet(
          model: odooModel,
          fields: fieldDefs.keys.toList(),
        );
        if (!mounted) return;
        await applyDefaultValues(defaults);
      } catch (e) {
        debugPrint('TimesheetFormScreen: error fetching defaults: $e');
      }
      if (!mounted) return;
      // Default date to today
      if (!fieldValues.containsKey('date') || fieldValues['date'] == null) {
        fieldValues['date'] = DateTime.now();
      }
      // Default hours to 1
      if (!fieldValues.containsKey('unit_amount') ||
          fieldValues['unit_amount'] == null) {
        fieldValues['unit_amount'] = 1.0;
      }
      // Pre-seed project & task if given (e.g. opened from task detail)
      if (widget.initialProjectId != null &&
          !fieldValues.containsKey('project_id')) {
        fieldValues['project_id'] = {
          'id': widget.initialProjectId,
          'name': 'Loading...',
        };
        fetchFormRelationName(
            'project_id', 'project.project', widget.initialProjectId!);
      }
      if (widget.initialTaskId != null &&
          !fieldValues.containsKey('task_id')) {
        fieldValues['task_id'] = {
          'id': widget.initialTaskId,
          'name': 'Loading...',
        };
        fetchFormRelationName('task_id', 'project.task', widget.initialTaskId!);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    disposeFormControllers();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;

    if (visibleFields.contains('project_id') &&
        fieldValues['project_id'] == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a project')),
      );
      return;
    }

    setState(() => isSaving = true);
    final values = buildFormSaveValues();

    final provider = context.read<TimesheetProvider>();
    final bool success;
    if (widget.timesheet != null) {
      success = await provider.updateTimesheet(widget.timesheet!.id, values);
    } else {
      success = await provider.createTimesheetDynamic(values);
    }

    if (!mounted) return;
    setState(() => isSaving = false);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CollapsingAppBarPage(
      title: widget.timesheet != null ? 'Edit Time Entry' : 'Log Time',
      leading: formBackButton(),
      actions: [
        if (!isLoadingDefs)
          IconButton(
            icon: const Icon(PhosphorIconsBold.listPlus, size: 22),
            onPressed: showFormHiddenFieldsPicker,
            tooltip: 'Manage Fields',
          ),
      ],
      body: isLoadingDefs || isSaving
          ? formLoadingIndicator()
          : Form(
              key: formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  ...buildFormFieldList(theme, textMaxLines: 4),
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
}
