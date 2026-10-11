class ProjectModel {
  final int id;
  final String name;
  final String? description;
  final bool active;
  final String? stage;
  final int? userId;
  final String? userLogin;
  final int? partnerId;
  final String? partnerName;
  final int? companyId;
  final String? companyName;
  final String? lastUpdateStatus;
  final String? date;
  final DateTime? createDate;
  final int taskCount;
  final int? closedTaskCount;
  final int? personalStageTypeIds;
  final double? allocatedHours;
  final double? effectiveHours;
  final String? privacy;
  final bool favorite;

  ProjectModel({
    required this.id,
    required this.name,
    this.description,
    this.active = true,
    this.stage,
    this.userId,
    this.userLogin,
    this.partnerId,
    this.partnerName,
    this.companyId,
    this.companyName,
    this.lastUpdateStatus,
    this.date,
    this.createDate,
    this.taskCount = 0,
    this.closedTaskCount,
    this.personalStageTypeIds,
    this.allocatedHours,
    this.effectiveHours,
    this.privacy,
    this.favorite = false,
  });

  factory ProjectModel.fromJson(Map<String, dynamic> json) {
    return ProjectModel(
      id: json['id'] as int,
      name: _fieldString(json['name']) ?? '',
      description: _cleanHtml(_fieldString(json['description'])),
      active: json['active'] == true,
      stage: _fieldName(json['stage_id']),
      userId: _fieldId(json['user_id']),
      userLogin: _fieldName(json['user_id']),
      partnerId: _fieldId(json['partner_id']),
      partnerName: _fieldName(json['partner_id']),
      companyId: _fieldId(json['company_id']),
      companyName: _fieldName(json['company_id']),
      lastUpdateStatus: _fieldString(json['last_update_status']),
      date: _fieldString(json['date']),
      createDate: json['create_date'] != null && json['create_date'] != false ? DateTime.tryParse(json['create_date'].toString()) : null,
      taskCount: (json['task_count'] as int?) ?? (json['task_count_with_subtasks'] as int?) ?? 0,
      closedTaskCount: json['closed_task_count'] as int?,
      allocatedHours: (json['allocated_hours'] as num?)?.toDouble(),
      effectiveHours: (json['effective_hours'] as num?)?.toDouble(),
      privacy: _fieldString(json['privacy_visibility']),
      favorite: json['is_favorite'] == true || json['favorite'] == true,
    );
  }

  static String? _fieldString(dynamic field) {
    if (field is String) return field;
    if (field != null && field != false) return field.toString();
    return null;
  }

  static int? _fieldId(dynamic field) {
    if (field is List && field.isNotEmpty) return field[0] as int?;
    if (field is int) return field;
    return null;
  }

  static String? _fieldName(dynamic field) {
    if (field is List && field.length > 1) return field[1] as String?;
    if (field is String) return field;
    return null;
  }

  static String? _cleanHtml(String? html) {
    if (html == null || html == 'false' || html.isEmpty) return null;
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  double get progressPercent {
    if (taskCount == 0) return 0;
    final closed = closedTaskCount ?? 0;
    return (closed / taskCount * 100).clamp(0, 100);
  }
}

class TaskModel {
  final int id;
  final String name;
  final String? description;
  final int? projectId;
  final String? projectName;
  final int? stageId;
  final String? stageName;
  final String? state; // in_progress, done, blocked, cancelled
  final List<int> userIds;
  final List<String> userNames;
  final String? deadline;
  final String? dateAssign;
  final double? allocatedHours;
  final double? effectiveHours;
  final double? remainingHours;
  final String? priority; // 0=normal, 1=high
  final int? sequence;
  final bool active;
  final int? parentId;
  final String? parentName;
  final List<int> tagIds;
  final List<String> tagNames;
  final int? kanbanState; // 0=normal, 1=blocked, 2=ready for next stage
  final String? kanbanStateLabel;
  final int? partnerId;
  final String? partnerName;
  final int? userId;
  final String? userName;

  TaskModel({
    required this.id,
    required this.name,
    this.description,
    this.projectId,
    this.projectName,
    this.stageId,
    this.stageName,
    this.state,
    this.userIds = const [],
    this.userNames = const [],
    this.deadline,
    this.dateAssign,
    this.allocatedHours,
    this.effectiveHours,
    this.remainingHours,
    this.priority,
    this.sequence,
    this.active = true,
    this.parentId,
    this.parentName,
    this.tagIds = const [],
    this.tagNames = const [],
    this.kanbanState,
    this.kanbanStateLabel,
    this.partnerId,
    this.partnerName,
    this.userId,
    this.userName,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    final userIdsRaw = json['user_ids'];
    final tagIdsRaw = json['tag_ids'];

    return TaskModel(
      id: json['id'] as int,
      name: _fieldString(json['name']) ?? '',
      description: _cleanHtml(_fieldString(json['description'])),
      projectId: _fieldId(json['project_id']),
      projectName: _fieldName(json['project_id']),
      stageId: _fieldId(json['stage_id']),
      stageName: _fieldName(json['stage_id']),
      state: _fieldString(json['state']),
      userIds:
          userIdsRaw is List ? userIdsRaw.map((e) => e as int).toList() : [],
      deadline: _fieldString(json['date_deadline']),
      dateAssign: _fieldString(json['date_assign']),
      allocatedHours: (json['allocated_hours'] as num?)?.toDouble(),
      effectiveHours: (json['effective_hours'] as num?)?.toDouble(),
      remainingHours: (json['remaining_hours'] as num?)?.toDouble(),
      priority: _fieldString(json['priority']),
      sequence: json['sequence'] as int?,
      active: json['active'] == true,
      parentId: _fieldId(json['parent_id']),
      parentName: _fieldName(json['parent_id']),
      tagIds: tagIdsRaw is List ? tagIdsRaw.map((e) => e as int).toList() : [],
      kanbanState: json['kanban_state'] == 'normal'
          ? 0
          : json['kanban_state'] == 'blocked'
              ? 1
              : json['kanban_state'] == 'done'
                  ? 2
                  : 0,
      kanbanStateLabel: _fieldString(json['kanban_state_label']),
      partnerId: _fieldId(json['partner_id']),
      partnerName: _fieldName(json['partner_id']),
      userId: _fieldId(json['user_id']),
      userName: _fieldName(json['user_id']),
      userNames: json['user_id'] != null && json['user_id'] is List
          ? [json['user_id'][1].toString()]
          : [],
    );
  }

  static String? _fieldString(dynamic field) {
    if (field is String) return field;
    if (field != null && field != false) return field.toString();
    return null;
  }

  bool get isHighPriority => priority == '1';

  String? getAvatarUrl(String serverUrl) {
    if (userId == null) return null;
    return '$serverUrl/web/image?model=res.users&id=$userId&field=avatar_128';
  }

  bool get isOverdue {
    if (deadline == null) return false;
    try {
      final d = DateTime.parse(deadline!);
      return d.isBefore(DateTime.now()) && state != 'done';
    } catch (_) {
      return false;
    }
  }

  static int? _fieldId(dynamic field) {
    if (field is List && field.isNotEmpty) return field[0] as int?;
    if (field is int) return field;
    return null;
  }

  static String? _fieldName(dynamic field) {
    if (field is List && field.length > 1) return field[1] as String?;
    if (field is String) return field;
    return null;
  }

  static String? _cleanHtml(String? html) {
    if (html == null || html == 'false' || html.isEmpty) return null;
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
}

class TimesheetModel {
  final int id;
  final String? name;
  final String date;
  final int? projectId;
  final String? projectName;
  final int? taskId;
  final String? taskName;
  final int? userId;
  final String? userName;
  final double unitAmount; // hours
  final int? companyId;

  TimesheetModel({
    required this.id,
    this.name,
    required this.date,
    this.projectId,
    this.projectName,
    this.taskId,
    this.taskName,
    this.userId,
    this.userName,
    required this.unitAmount,
    this.companyId,
  });

  factory TimesheetModel.fromJson(Map<String, dynamic> json) {
    return TimesheetModel(
      id: json['id'] as int,
      name: _fieldString(json['name']),
      date: _fieldString(json['date']) ?? '',
      projectId: _fieldId(json['project_id']),
      projectName: _fieldName(json['project_id']),
      taskId: _fieldId(json['task_id']),
      taskName: _fieldName(json['task_id']),
      userId: _fieldId(json['employee_id']) ?? _fieldId(json['user_id']),
      userName: _fieldName(json['employee_id']) ?? _fieldName(json['user_id']),
      unitAmount: (json['unit_amount'] as num?)?.toDouble() ?? 0.0,
      companyId: _fieldId(json['company_id']),
    );
  }

  static String? _fieldString(dynamic field) {
    if (field is String) return field;
    if (field != null && field != false) return field.toString();
    return null;
  }

  static int? _fieldId(dynamic field) {
    if (field is List && field.isNotEmpty) return field[0] as int?;
    if (field is int) return field;
    return null;
  }

  static String? _fieldName(dynamic field) {
    if (field is List && field.length > 1) return field[1] as String?;
    if (field is String) return field;
    return null;
  }

  String get hoursFormatted {
    if (unitAmount == unitAmount.roundToDouble()) {
      return '${unitAmount.toInt()}h';
    }
    return '${unitAmount.toStringAsFixed(2)}h';
  }
}

class OdooModuleModel {
  final int id;
  final String name;
  final String shortdesc;
  final String? summary;
  final String state; // installed, uninstalled, to install, etc.
  final String? latestVersion;
  final String? author;
  final String? website;
  final String? category;
  final bool application;
  final bool autoInstall;

  OdooModuleModel({
    required this.id,
    required this.name,
    required this.shortdesc,
    this.summary,
    required this.state,
    this.latestVersion,
    this.author,
    this.website,
    this.category,
    this.application = false,
    this.autoInstall = false,
  });

  factory OdooModuleModel.fromJson(Map<String, dynamic> json) {
    return OdooModuleModel(
      id: json['id'] as int,
      name: _fieldString(json['name']) ?? '',
      shortdesc: _fieldString(json['shortdesc']) ?? '',
      summary: _fieldString(json['summary']),
      state: _fieldString(json['state']) ?? 'uninstalled',
      latestVersion: _fieldString(json['latest_version']),
      author: _fieldString(json['author']),
      website: _fieldString(json['website']),
      category: json['category_id'] is List ? json['category_id'][1] : null,
      application: json['application'] as bool? ?? false,
      autoInstall: json['auto_install'] == true,
    );
  }

  static String? _fieldString(dynamic field) {
    if (field is String) return field;
    if (field != null && field != false) return field.toString();
    return null;
  }

  bool get isInstalled => state == 'installed';
  bool get canInstall => state == 'uninstalled' || state == 'to install';
  bool get canUpgrade => state == 'to upgrade';
}

class ProjectStageModel {
  final int id;
  final String name;
  final int sequence;
  final bool fold;

  ProjectStageModel({
    required this.id,
    required this.name,
    required this.sequence,
    this.fold = false,
  });

  factory ProjectStageModel.fromJson(Map<String, dynamic> json) {
    return ProjectStageModel(
      id: json['id'] as int,
      name: _fieldString(json['name']) ?? '',
      sequence: json['sequence'] as int? ?? 0,
      fold: json['fold'] == true,
    );
  }

  static String? _fieldString(dynamic field) {
    if (field is String) return field;
    if (field != null && field != false) return field.toString();
    return null;
  }
}
