import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/models/project_models.dart';
import '../../../core/providers/timesheet_provider.dart';
import '../../../core/providers/project_provider.dart';
import '../../../core/theme/app_theme.dart';

class LogTimeSheet extends StatefulWidget {
  final int? initialProjectId;
  final int? initialTaskId;

  const LogTimeSheet({super.key, this.initialProjectId, this.initialTaskId});

  @override
  State<LogTimeSheet> createState() => _LogTimeSheetState();
}

class _LogTimeSheetState extends State<LogTimeSheet> {
  final _formKey = GlobalKey<FormState>();
  ProjectModel? _selectedProject;
  TaskModel? _selectedTask;
  DateTime _date = DateTime.now();
  final _hoursController = TextEditingController(text: '1');
  final _descController = TextEditingController();
  bool _isSubmitting = false;
  List<TaskModel> _tasks = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (widget.initialProjectId == null) return;
    final projectProvider = context.read<ProjectProvider>();
    if (projectProvider.projects.isEmpty) return;
    final project = projectProvider.projects.firstWhere(
      (p) => p.id == widget.initialProjectId,
      orElse: () => projectProvider.projects.first,
    );
    setState(() => _selectedProject = project);

    final tasks = await projectProvider.loadTasksForProject(project.id);
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      if (widget.initialTaskId != null) {
        _selectedTask = tasks
            .where((t) => t.id == widget.initialTaskId)
            .firstOrNull;
      }
    });
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projects = context.watch<ProjectProvider>().projects;
    final insets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Log Time', style: theme.textTheme.titleLarge),
              const SizedBox(height: 20),
              DropdownButtonFormField<ProjectModel>(
                initialValue: _selectedProject,
                decoration: const InputDecoration(
                  labelText: 'Project',
                  prefixIcon: Icon(
                    PhosphorIconsRegular.folder,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                items: projects.map((p) {
                  return DropdownMenuItem(value: p, child: Text(p.name));
                }).toList(),
                onChanged: (p) async {
                  setState(() {
                    _selectedProject = p;
                    _selectedTask = null;
                    _tasks = [];
                  });
                  if (p != null) {
                    final projectProvider = context.read<ProjectProvider>();
                    final tasks = await projectProvider.loadTasksForProject(
                      p.id,
                    );
                    if (!mounted) return;
                    setState(() => _tasks = tasks);
                  }
                },
                validator: (v) => v == null ? 'Select a project' : null,
              ),
              const SizedBox(height: 12),
              // Task
              if (_tasks.isNotEmpty)
                DropdownButtonFormField<TaskModel>(
                  initialValue: _selectedTask,
                  decoration: const InputDecoration(
                    labelText: 'Task (optional)',
                    prefixIcon: Icon(
                      PhosphorIconsRegular.checkCircle,
                      color: AppColors.accent,
                      size: 20,
                    ),
                  ),
                  items: _tasks.map((t) {
                    return DropdownMenuItem(value: t, child: Text(t.name));
                  }).toList(),
                  onChanged: (t) => setState(() => _selectedTask = t),
                ),
              const SizedBox(height: 12),
              // Date + Hours row
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickDate,
                      child: AbsorbPointer(
                        child: TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'Date',
                            prefixIcon: Icon(
                              PhosphorIconsRegular.calendarBlank,
                              color: AppColors.primary,
                              size: 18,
                            ),
                          ),
                          controller: TextEditingController(
                            text: DateFormat('MMM d, y').format(_date),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _hoursController,
                      decoration: const InputDecoration(
                        labelText: 'Hours',
                        prefixIcon: Icon(
                          PhosphorIconsRegular.clock,
                          color: AppColors.accent,
                          size: 18,
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final h = double.tryParse(v ?? '');
                        if (h == null || h <= 0) return 'Enter valid hours';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Description
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(
                    PhosphorIconsRegular.fileText,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Save Entry'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (!mounted) return;
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final success = await context.read<TimesheetProvider>().createTimesheet(
        projectId: _selectedProject!.id,
        taskId: _selectedTask?.id,
        date: DateFormat('yyyy-MM-dd').format(_date),
        hours: double.parse(_hoursController.text),
        description: _descController.text.trim().isNotEmpty
            ? _descController.text.trim()
            : null,
      );
      if (mounted) {
        Navigator.pop(context);
        if (!success) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Failed to log time')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('An error occurred')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
