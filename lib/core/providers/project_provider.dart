import 'package:flutter/material.dart';
import '../models/project_models.dart';
import '../services/odoo_rpc_service.dart';
import 'session_provider.dart';

class ProjectProvider with ChangeNotifier {
  final SessionProvider sessionProvider;

  List<ProjectModel> _projects = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  int _totalProjectCount = 0;
  String? _error;
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, in_progress, done, blocked
  bool _isModuleMissing = false;

  List<ProjectModel> get projects => _projects;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  int get totalProjectCount => _totalProjectCount;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  String get filterStatus => _filterStatus;
  bool get isModuleMissing => _isModuleMissing;

  ProjectProvider({required this.sessionProvider});



  void setSearch(String q) {
    _searchQuery = q;
    loadProjects(showLoading: true);
  }

  void setFilter(String status) {
    _filterStatus = status;
    loadProjects(showLoading: true);
  }



  Future<void> loadProjects({bool showLoading = true, bool loadMore = false}) async {
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
        _totalProjectCount = await OdooRpcService.searchCount(
          model: 'project.project',
          domain: baseDomain,
        );
      }

      final fetchDomain = List<dynamic>.from(baseDomain);
      if (_searchQuery.isNotEmpty) {
        fetchDomain.add(['name', 'ilike', _searchQuery]);
      }
      if (_filterStatus == 'my_projects') {
        final uid = sessionProvider.userId;
        if (uid != null) fetchDomain.add(['user_id', '=', uid]);
      } else if (_filterStatus != 'all') {
        fetchDomain.add(['last_update_status', '=', _filterStatus]);
      }

      final limit = 50;
      final raw = await OdooRpcService.safeSearchRead(
        model: 'project.project',
        domain: fetchDomain,
        fields: OdooRpcService.projectFieldCandidates,
        order: 'is_favorite desc, name asc',
        limit: limit,
        offset: _offset,
      );
      
      final newProjects = raw.map((e) => ProjectModel.fromJson(e)).toList();
      
      if (loadMore) {
        _projects.addAll(newProjects);
      } else {
        _projects = newProjects;
      }
      
      if (newProjects.length < limit) {
        _hasMore = false;
      }
      
      _offset += newProjects.length;
      _error = null;
      _isModuleMissing = false;
    } catch (e) {
      final errStr = e.toString();
      _error = errStr.replaceFirst('Exception: ', '');
      
      // Specifically identify 404 or missing model errors as module missing
      if (errStr.contains('404') || errStr.contains('not found') || errStr.contains('Object not found')) {
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

  Future<List<TaskModel>> loadTasksForProject(int projectId) async {
    try {
      final raw = await OdooRpcService.safeSearchRead(
        model: 'project.task',
        domain: [['project_id', '=', projectId]],
        fields: OdooRpcService.taskFieldCandidates,
        order: 'sequence asc, id asc',
      );
      return raw.map((e) => TaskModel.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<bool> updateTaskStage(int taskId, int stageId) async {
    try {
      return await OdooRpcService.write(
        model: 'project.task',
        ids: [taskId],
        values: {'stage_id': stageId},
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateTaskState(int taskId, String state) async {
    try {
      return await OdooRpcService.write(
        model: 'project.task',
        ids: [taskId],
        values: {'state': state},
      );
    } catch (_) {
      return false;
    }
  }

  Future<List<ProjectStageModel>> loadStages(int projectId) async {
    try {
      final raw = await OdooRpcService.searchRead(
        model: 'project.task.type',
        domain: [['project_ids', 'in', [projectId]]],
        fields: ['id', 'name', 'sequence', 'fold'],
        order: 'sequence asc',
      );
      return raw.map((e) => ProjectStageModel.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> toggleFavorite(int projectId, bool isFavorite) async {
    try {
      final result = await OdooRpcService.write(
        model: 'project.project',
        ids: [projectId],
        values: {'is_favorite': !isFavorite},
      );
      if (result) {
        final i = _projects.indexWhere((p) => p.id == projectId);
        if (i != -1) {
          await loadProjects(showLoading: false);
        }
      }
      return result;
    } catch (_) {
      return false;
    }
  }

  Future<bool> createProject(Map<String, dynamic> values) async {
    try {
      final id = await OdooRpcService.create(
        model: 'project.project',
        values: values,
      );
      if (id != 0) {
        await loadProjects(showLoading: false);
        return true;
      }
      _error = 'Failed to create project';
      return false;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProject(int projectId, Map<String, dynamic> values) async {
    try {
      final result = await OdooRpcService.write(
        model: 'project.project',
        ids: [projectId],
        values: values,
      );
      if (result) {
        await loadProjects(showLoading: false);
      } else {
        _error = 'Failed to update project';
      }
      return result;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }
}

