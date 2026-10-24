import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/models/project_models.dart';
import '../../core/providers/project_provider.dart';
import '../../core/services/odoo_rpc_service.dart';
import '../../core/widgets/collapsing_app_bar_page.dart';
import '../../core/widgets/odoo_form_mixin.dart';
import '../../core/widgets/primary_button.dart';

class ProjectFormScreen extends StatefulWidget {
  final ProjectModel? project; // null = create mode

  const ProjectFormScreen({super.key, this.project});

  @override
  State<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends State<ProjectFormScreen>
    with OdooFormMixin {
  @override
  String get odooModel => 'project.project';

  // Fields shown by default
  @override
  final Set<String> defaultFields = {
    'name',
    'user_id',
    'partner_id',
    'date_start',
    'date',
    'description',
    'privacy_visibility',
    'tag_ids',
  };

  @override
  bool formFieldRequired(String field, Map<dynamic, dynamic> def) =>
      def['required'] == true || field == 'name';

  @override
  void initState() {
    super.initState();
    visibleFields = Set.from(defaultFields);
    loadFormFieldDefs(_initFieldValues);
  }

  Future<void> _initFieldValues() async {
    if (widget.project != null) {
      final p = widget.project!;
      fieldValues['name'] = p.name;
      if (p.description != null) fieldValues['description'] = p.description;

      try {
        final records = await OdooRpcService.searchRead(
          model: odooModel,
          domain: [
            ['id', '=', p.id],
          ],
          fields: fieldDefs.keys.toList(),
          limit: 1,
        );
        if (!mounted) return;
        if (records.isNotEmpty) {
          await applyFetchedRecord(records[0]);
        }
      } catch (e) {
        debugPrint('Error fetching project data: $e');
        if (!mounted) return;
        // Fallback from ProjectModel
        if (p.userId != null) {
          fieldValues['user_id'] = {
            'id': p.userId,
            'name': p.userLogin ?? 'User',
          };
        }
        if (p.partnerId != null) {
          fieldValues['partner_id'] = {
            'id': p.partnerId,
            'name': p.partnerName ?? 'Customer',
          };
        }
        if (p.date != null) {
          fieldValues['date'] = DateTime.tryParse(p.date!);
        }
        if (p.privacy != null) {
          fieldValues['privacy_visibility'] = {
            'id': p.privacy,
            'name': p.privacy!,
          };
        }
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
      } catch (e) {
        debugPrint('Error fetching defaults: $e');
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

    if (fieldValues['name'] == null ||
        (fieldValues['name'] as String).trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Project name is required')));
      return;
    }

    setState(() => isSaving = true);
    final values = buildFormSaveValues();

    final provider = context.read<ProjectProvider>();
    final bool success;
    if (widget.project != null) {
      success = await provider.updateProject(widget.project!.id, values);
    } else {
      success = await provider.createProject(values);
    }

    if (!mounted) return;
    setState(() => isSaving = false);
    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.project != null
                ? 'Project updated successfully'
                : 'Project created successfully',
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
      title: widget.project != null ? 'Edit Project' : 'New Project',
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
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  ...buildFormFieldList(theme),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: widget.project != null
                        ? 'Save Project'
                        : 'Create Project',
                    onTap: _save,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}
