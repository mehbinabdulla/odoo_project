import 'package:flutter/material.dart';
import '../models/project_models.dart';
import '../services/odoo_rpc_service.dart';

class ModuleProvider with ChangeNotifier {
  List<OdooModuleModel> _modules = [];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  String _filterState = 'all'; // all, installed, uninstalled

  List<OdooModuleModel> get modules => _filteredModules;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  String get filterState => _filterState;

  List<OdooModuleModel> get _filteredModules {
    var list = _modules;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((m) =>
              m.name.toLowerCase().contains(q) ||
              m.shortdesc.toLowerCase().contains(q))
          .toList();
    }
    if (_filterState == 'installed') {
      list = list.where((m) => m.isInstalled).toList();
    } else if (_filterState == 'uninstalled') {
      list = list.where((m) => !m.isInstalled).toList();
    }
    return list;
  }

  void setSearch(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  void setFilter(String state) {
    _filterState = state;
    notifyListeners();
  }

  Future<void> loadModules({bool showLoading = true}) async {
    if (showLoading) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final raw = await OdooRpcService.searchRead(
        model: 'ir.module.module',
        domain: [],
        fields: [
          'id', 'name', 'shortdesc', 'summary', 'state',
          'latest_version', 'author', 'website', 'category_id',
          'application', 'auto_install',
        ],
        order: 'application desc, state asc, shortdesc asc',
        limit: 500,
      );
      _modules = raw.map((e) => OdooModuleModel.fromJson(e)).toList();
      _error = null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  int get installedCount => _modules.where((m) => m.isInstalled).length;
  int get totalCount => _modules.length;
}
