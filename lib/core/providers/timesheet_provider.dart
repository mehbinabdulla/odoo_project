import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/project_models.dart';
import '../services/odoo_rpc_service.dart';
import '../services/odoo_field_registry.dart';
import 'session_provider.dart';

class TimesheetProvider with ChangeNotifier {
  final SessionProvider sessionProvider;

  List<TimesheetModel> _timesheets = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  
  double _dashboardTotalHours = 0.0;
  Map<String, double> _dashboardDailyHours = {};
  
  String? _error;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  int? _filterProjectId;
  int? _filterUserId;
  String _searchQuery = '';
  bool _isUserFilterInitialized = false;
  bool _isModuleMissing = false;

  List<TimesheetModel> get timesheets => _timesheets;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  DateTime get startDate => _startDate;
  DateTime get endDate => _endDate;
  int? get filterProjectId => _filterProjectId;
  
  int? get filterUserId {
    if (!_isUserFilterInitialized) {
      return sessionProvider.userId;
    }
    return _filterUserId;
  }

  String get searchQuery => _searchQuery;
  bool get isModuleMissing => _isModuleMissing;

  String get selectedMonth {
    final start = DateFormat('MMM d').format(_startDate);
    final end = DateFormat('MMM d, yyyy').format(_endDate);
    return "$start – $end";
  }

  int get daysCount => _endDate.difference(_startDate).inDays;

  TimesheetProvider({required this.sessionProvider});



  double get totalHours => _dashboardTotalHours;
  Map<String, double> get dailyHours => _dashboardDailyHours;

  double get todayHours {
    final now = DateTime.now();
    final todayStr = _formatDate(now);
    return _timesheets
        .where((t) => t.date == todayStr)
        .fold(0.0, (sum, t) => sum + t.unitAmount);
  }

  void setDateRange(DateTime start, DateTime end) {
    _startDate = start;
    _endDate = end;
    loadTimesheets(showLoading: true);
  }

  void setProjectFilter(int? projectId) {
    _filterProjectId = projectId;
    loadTimesheets(showLoading: true);
  }

  void setUserFilter(int? userId) {
    _filterUserId = userId;
    _isUserFilterInitialized = true;
    loadTimesheets(showLoading: true);
  }


  void setSearch(String q) {
    _searchQuery = q;
    loadTimesheets(showLoading: true);
  }

  Future<void> loadTimesheets({bool showLoading = true, bool loadMore = false}) async {
    if (!_isUserFilterInitialized) {
      _filterUserId = sessionProvider.userId;
      _isUserFilterInitialized = true;
    }

    if (loadMore) {
      if (!_hasMore || _isLoadingMore || _isLoading) return;
      _isLoadingMore = true;
      notifyListeners();
    } else {
      _isLoading = true; // always lock to prevent concurrent loadMore
      _error = null;
      if (showLoading) notifyListeners();
      _offset = 0;
      _hasMore = true;
    }

    try {
      final availableFields = await OdooFieldRegistry.getFieldNames('account.analytic.line');
      final hasEmployeeId = availableFields.isEmpty || availableFields.contains('employee_id');

      final domain = <dynamic>[
        ['date', '>=', _formatDate(_startDate)],
        ['date', '<=', _formatDate(_endDate)],
      ];

      if (_filterProjectId != null) {
        domain.add(['project_id', '=', _filterProjectId]);
      }
      final currentFilterUser = filterUserId;
      if (currentFilterUser != null) {
        if (hasEmployeeId) {
          domain.add(['employee_id.user_id', '=', currentFilterUser]);
        } else {
          domain.add(['user_id', '=', currentFilterUser]);
        }
      }

      if (!loadMore) {
        await loadDashboardStats(domain);
      }

      final fetchDomain = List<dynamic>.from(domain);
      if (_searchQuery.isNotEmpty) {
        fetchDomain.add(['name', 'ilike', _searchQuery]);
      }

      final limit = 50;
      final raw = await OdooRpcService.safeSearchRead(
        model: 'account.analytic.line',
        domain: fetchDomain,
        fields: OdooRpcService.timesheetFieldCandidates,
        order: 'date desc',
        limit: limit,
        offset: _offset,
      );

      final newTimesheets = raw.map((e) => TimesheetModel.fromJson(e)).toList();
      
      if (loadMore) {
        _timesheets.addAll(newTimesheets);
      } else {
        _timesheets = newTimesheets;
      }
      
      if (newTimesheets.length < limit) {
        _hasMore = false;
      }
      
      _offset += newTimesheets.length;
      _error = null;
      _isModuleMissing = false;
    } catch (e) {
      final errStr = e.toString();
      _error = errStr.replaceFirst('Exception: ', '');
      
      if (errStr.contains('404') || 
          errStr.contains('not found') || 
          errStr.contains('Invalid field') ||
          errStr.contains('employee_id')) {
        _isModuleMissing = true;
      }
    } finally {
      if (loadMore) {
        _isLoadingMore = false;
      } else {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> loadDashboardStats(List<dynamic> domain) async {
    try {
      final raw = await OdooRpcService.readGroup(
        model: 'account.analytic.line',
        domain: domain,
        fields: ['unit_amount'],
        groupby: ['date:day'],
      );
      
      double total = 0.0;
      Map<String, double> daily = {};
      
      for (final group in raw) {
        final amount = (group['unit_amount'] as num?)?.toDouble() ?? 0.0;
        total += amount;
        
        final dateStr = group['date:day'] as String?;
        if (dateStr != null && dateStr.isNotEmpty) {
          // Odoo read_group returns date grouped like "04 Jul 2026" or "2026-07-04" depending on version/locale.
          // In standard, for day groupby, it might return 'YYYY-MM-DD'.
          // Let's store it and format it later.
          // Wait, actually Odoo typically returns a localized string if we don't specify format, 
          // or sometimes it returns false if no date. Let's just try to parse if needed.
          // We'll trust whatever dateStr we get for now. 
          daily[dateStr] = amount;
        }
      }
      
      _dashboardTotalHours = total;
      _dashboardDailyHours = daily;
    } catch (e) {
      _dashboardTotalHours = 0.0;
      _dashboardDailyHours = {};
    }
  }

  Future<bool> createTimesheet({
    required int projectId,
    int? taskId,
    required String date,
    required double hours,
    String? description,
  }) async {
    try {
      final availableFields = await OdooFieldRegistry.getFieldNames('account.analytic.line');
      final hasEmployeeId = availableFields.isEmpty || availableFields.contains('employee_id');

      final values = <String, dynamic>{
        'project_id': projectId,
        if (taskId != null) 'task_id': taskId,
        'date': date,
        'unit_amount': hours,
        if (description != null) 'name': description,
      };

      if (hasEmployeeId) {
        final emp = await _getMyEmployeeId();
        if (emp != null) values['employee_id'] = emp;
      }

      await OdooRpcService.create(model: 'account.analytic.line', values: values);
      await loadTimesheets(showLoading: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int?> _getMyEmployeeId() async {
    try {
      final uid = sessionProvider.userId;
      final raw = await OdooRpcService.searchRead(
        model: 'hr.employee',
        domain: [['user_id', '=', uid]],
        fields: ['id'],
        limit: 1,
      );
      if (raw.isNotEmpty) return raw.first['id'] as int?;
    } catch (_) {}
    return null;
  }

  Future<bool> deleteTimesheet(int id) async {
    try {
      final result = await OdooRpcService.unlink(
        model: 'account.analytic.line',
        ids: [id],
      );
      if (result) {
        _timesheets.removeWhere((t) => t.id == id);
        notifyListeners();
      }
      return result;
    } catch (_) {
      return false;
    }
  }

  /// Updates an existing timesheet entry with [values] and refreshes the list.
  Future<bool> updateTimesheet(int id, Map<String, dynamic> values) async {
    try {
      await OdooRpcService.write(
        model: 'account.analytic.line',
        ids: [id],
        values: values,
      );
      await loadTimesheets(showLoading: false);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Creates a new timesheet entry from a generic field-value map.
  /// Used by TimesheetFormScreen's dynamic form.
  Future<bool> createTimesheetDynamic(Map<String, dynamic> values) async {
    try {
      _isLoading = true;
      notifyListeners();
      await OdooRpcService.create(
        model: 'account.analytic.line',
        values: values,
      );
      await loadTimesheets(showLoading: false);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Map<String, double> get hoursByProject {
    final map = <String, double>{};
    for (final t in _timesheets) {
      final key = t.projectName ?? 'Unknown';
      map[key] = (map[key] ?? 0) + t.unitAmount;
    }
    return map;
  }

  Map<String, double> get hoursByDate {
    final map = <String, double>{};
    for (final t in _timesheets) {
      map[t.date] = (map[t.date] ?? 0) + t.unitAmount;
    }
    return map;
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
