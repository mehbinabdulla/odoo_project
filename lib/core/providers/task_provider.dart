import 'dart:async';
import 'package:flutter/material.dart';
import '../models/project_models.dart';
import '../services/odoo_rpc_service.dart';
import 'session_provider.dart';

class TaskProvider with ChangeNotifier {
  SessionProvider sessionProvider;

  Timer? _filterDebounce;
  int _loadGen = 0;

  List<TaskModel> _tasks = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  int _totalTaskCount = 0;
  String? _error;
  String _searchQuery = '';
  String _filterState = 'all'; // all, todo, in_progress, done, cancelled

  List<TaskModel> get tasks => _tasks;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  String get filterState => _filterState;

  TaskProvider({required this.sessionProvider});

  /// Called by the ChangeNotifierProxyProvider `update:` callback so the
  /// latest SessionProvider is always propagated.
  void updateSession(SessionProvider session) {
    sessionProvider = session;
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    super.dispose();
  }

  void setSearch(String q) {
    _searchQuery = q;
    _debouncedLoad();
  }

  void setFilter(String state) {
    _filterState = state;
    _debouncedLoad();
  }

  void _debouncedLoad() {
    _filterDebounce?.cancel();
    // Invalidate any in-flight fresh load so its stale results are dropped.
    _loadGen++;
    _filterDebounce = Timer(const Duration(milliseconds: 400), () {
      loadTasks(showLoading: true);
    });
  }



  Future<void> loadTasks({bool showLoading = true, bool loadMore = false}) async {
    // loadMore must not invalidate the in-flight fresh load's generation.
    final int gen = loadMore ? _loadGen : ++_loadGen;
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
      final baseDomain = <dynamic>[['active', '=', true]];
      
      // Fetch total count if it's the first page
      if (!loadMore) {
        // Dashboard needs the total unfiltered count
        _totalTaskCount = await OdooRpcService.searchCount(
          model: 'project.task',
          domain: baseDomain,
        );
      }

      final fetchDomain = List<dynamic>.from(baseDomain);
      if (_searchQuery.isNotEmpty) {
        fetchDomain.add(['name', 'ilike', _searchQuery]);
      }
      if (_filterState != 'all') {
        if (sessionProvider.majorVersion >= 16) {
          fetchDomain.add(['state', '=', _filterState]);
        }
      }

      final limit = 50;
      final raw = await OdooRpcService.safeSearchRead(
        model: 'project.task',
        domain: fetchDomain,
        fields: OdooRpcService.taskFieldCandidates,
        order: 'priority desc, date_deadline asc, id desc',
        limit: limit,
        offset: _offset,
      );
      
      final newTasks = raw.map((e) => TaskModel.fromJson(e)).toList();

      if (gen != _loadGen) return; // superseded by a newer request
      if (loadMore) {
        _tasks.addAll(newTasks);
      } else {
        _tasks = newTasks;
      }
      
      if (newTasks.length < limit) {
        _hasMore = false;
      }
      
      _offset += newTasks.length;
      _error = null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (loadMore) {
        _isLoadingMore = false;
      } else {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  int get todoCount => _tasks.where((t) => t.kanbanState == 0).length;
  int get totalCount => _totalTaskCount;

  Future<bool> updateTask(int taskId, Map<String, dynamic> values) async {
    try {
      await OdooRpcService.write(
        model: 'project.task',
        ids: [taskId],
        values: values,
      );
      
      // Update local state
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index != -1) {
        // Reload all tasks to get clean state or just update local if possible
        // For simplicity and correctness with stage names, we reload
        await loadTasks(showLoading: false);
      }
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> createTask(Map<String, dynamic> values) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final id = await OdooRpcService.create(
        model: 'project.task',
        values: values,
      );
      
      if (id != 0) {
        await loadTasks(showLoading: false);
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
