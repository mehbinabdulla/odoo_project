import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/models/project_models.dart';
import '../../core/providers/task_provider.dart';
import '../../core/services/odoo_rpc_service.dart';
import '../../core/widgets/collapsing_app_bar_page.dart';
import '../../core/widgets/odoo_form_mixin.dart';
import '../../core/widgets/primary_button.dart';

class TaskFormScreen extends StatefulWidget {
  final ProjectModel? initialProject;
  final TaskModel? task;

  const TaskFormScreen({super.key, this.initialProject, this.task});

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> with OdooFormMixin {
  @override
  String get odooModel => 'project.task';

  @override
  final Set<String> defaultFields = {
    'name',
    'project_id',
    'user_ids',
    'tag_ids',
    'partner_id',
    'date_deadline',
    'description',
  };

  // Tasks render numerics as plain number fields (no HH:MM time input)
  // and always use the generic number icon.
  @override
  bool formIsTimeField(String field, Map<dynamic, dynamic> def) => false;

  @override
  bool formValidateTextField(String field, Map<dynamic, dynamic> def) => true;

  @override
  IconData formNumericIcon(String type) => PhosphorIconsRegular.numberSquareOne;

  @override
  void initState() {
    super.initState();
    visibleFields = Set.from(defaultFields);
    loadFormFieldDefs(_initFieldValues);
  }

  Future<void> _initFieldValues() async {
    if (widget.task != null) {
      final t = widget.task!;
      fieldValues['name'] = t.name;
      fieldValues['description'] = t.description ?? '';

      try {
        final records = await OdooRpcService.searchRead(
          model: odooModel,
          domain: [
            ['id', '=', t.id]
          ],
          fields: fieldDefs.keys.toList(),
          limit: 1,
        );
        if (!mounted) return;
        if (records.isNotEmpty) {
          await applyFetchedRecord(records[0]);
        }
      } catch (_) {
        if (!mounted) return;
        // Fallback to static model if fetch fails
        if (t.projectId != null) {
          fieldValues['project_id'] = {
            'id': t.projectId,
            'name': t.projectName
          };
        }
        if (t.partnerId != null) {
          fieldValues['partner_id'] = {
            'id': t.partnerId,
            'name': t.partnerName
          };
        }
        if (t.deadline != null) {
          fieldValues['date_deadline'] = DateTime.tryParse(t.deadline!);
        }
        fieldValues['user_ids'] = List.generate(
          t.userIds.length,
          (i) => {'id': t.userIds[i], 'name': 'User ${t.userIds[i]}'},
        );
        fieldValues['tag_ids'] = List.generate(
          t.tagIds.length,
          (i) => {'id': t.tagIds[i], 'name': 'Tag ${t.tagIds[i]}'},
        );
        setState(() {});
      }
    } else {
      // Create mode: fetch defaults from Odoo
      try {
        final defaults = await OdooRpcService.defaultGet(
          model: odooModel,
          fields: fieldDefs.keys.toList(),
        );
        if (!mounted) return;
        await applyDefaultValues(defaults);
      } catch (_) {
      }

      if (widget.initialProject != null) {
        fieldValues['project_id'] = {
          'id': widget.initialProject!.id,
          'name': widget.initialProject!.name,
        };
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

    // In dynamic forms, we can't hardcode required project, but it's good UX.
    if (visibleFields.contains('project_id') &&
        fieldValues['project_id'] == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a project')));
      return;
    }

    setState(() => isSaving = true);
    final values = buildFormSaveValues();

    final provider = context.read<TaskProvider>();
    final bool success;
    if (widget.task != null) {
      success = await provider.updateTask(widget.task!.id, values);
    } else {
      success = await provider.createTask(values);
    }

    if (!mounted) return;
    setState(() => isSaving = false);
    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.task != null
                ? 'Task updated successfully'
                : 'Task created successfully',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${provider.error}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CollapsingAppBarPage(
      title: widget.task != null ? 'Edit Task' : 'New Task',
      leading: formBackButton(),
      actions: [
        if (!isLoadingDefs)
          IconButton(
            icon: const Icon(PhosphorIconsBold.listPlus, size: 22),
            onPressed: showFormHiddenFieldsPicker,
            tooltip: 'Manage Fields',
          )
      ],
      body: isLoadingDefs || isSaving
          ? formLoadingIndicator()
          : Form(
              key: formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  ...buildFormFieldList(theme),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: widget.task != null ? 'Save Task' : 'Create Task',
                    onTap: _save,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}
