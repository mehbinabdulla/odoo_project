import 'package:flutter/foundation.dart';
import 'odoo_rpc_service.dart';

/// Discovers and caches ALL readable fields for an Odoo model by calling
/// the server's native [fields_get] RPC method.
///
/// This completely avoids hardcoded field lists and works with any Odoo
/// version, any installed module set, and any custom fields.
///
/// Usage:
///   • Call [preloadForLogin] once after a successful login to warm up the
///     cache in the background for the three core models.
///   • Call [getFieldNames] anywhere to get the full list of readable fields
///     for a model (fetches on-demand and caches the result).
///   • Call [clear] on logout so the next session starts fresh.
class OdooFieldRegistry {
  OdooFieldRegistry._();

  // model name → map of field_name to field_metadata (string, type, relation, selection)
  static final Map<String, Map<String, dynamic>> _cache = {};

  // In-flight fetch deduplication
  static final Map<String, Future<Map<String, dynamic>>> _inFlight = {};

  // ── Core models that are preloaded right after login ──────────────────────

  static const List<String> _coreModels = [
    'project.project',
    'project.task',
    'account.analytic.line',
  ];

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Pre-warms the cache for the three core models **in parallel**.
  /// Call this right after a successful login (fire-and-forget is fine).
  static Future<void> preloadForLogin() => _preload(_coreModels);

  /// Returns the full map of field definitions for [model].
  static Future<Map<String, dynamic>> getFieldDefs(String model) async {
    if (_cache.containsKey(model)) return _cache[model]!;
    if (_inFlight.containsKey(model)) return _inFlight[model]!;

    final future = _fetchFieldDefs(model);
    _inFlight[model] = future;
    try {
      final defs = await future;
      // Only cache if we actually got fields back (more than just the fallback 'id')
      if (defs.length > 1) {
        _cache[model] = defs;
      }
      return defs;
    } finally {
      _inFlight.remove(model);
    }
  }

  /// Returns the cached list of readable field names for [model].
  /// Fetches from the server on first call; subsequent calls return instantly.
  static Future<List<String>> getFieldNames(String model) async {
    final defs = await getFieldDefs(model);
    return defs.keys.toList();
  }

  /// Returns the cached field names synchronously, or `null` if not yet loaded.
  static List<String>? getFieldNamesSync(String model) => _cache[model]?.keys.toList();

  /// Checks which of the provided [fields] the current user has [operation] access to.
  /// [operation] is usually 'read' or 'write'.
  static Future<List<String>> checkFieldAccessRights(String model, String operation, List<String> fields) async {
    try {
      final result = await OdooRpcService.callKw(
        model: model,
        method: 'check_field_access_rights',
        args: [operation, fields],
      );
      if (result is List) {
        return result.cast<String>().toList();
      }
      // Fail closed: an unexpected RPC shape grants nothing.
      debugPrint('OdooFieldRegistry: unexpected check_field_access_rights shape for $model; denying all.');
      return [];
    } catch (e) {
      // Fail closed: if the check itself fails, grant nothing rather than
      // leaking fields the user may not read.
      debugPrint('OdooFieldRegistry: check_field_access_rights failed for $model: $e');
      return [];
    }
  }

  /// Dynamically discovers fields that should be considered "technical" or
  /// "skipped" for the given [model] by querying [ir.model.fields].
  ///
  /// This replaces hardcoded skipped field lists with a server-driven approach.
  static Future<List<String>> getTechnicalFieldNames(String model) async {
    try {
      final records = await OdooRpcService.searchRead(
        model: 'ir.model.fields',
        domain: [
          ['model', '=', model],
          '|',
          ['selectable', '=', false],
          ['ttype', 'in', ['one2many', 'reference']],
        ],
        fields: ['name'],
        limit: 1000,
      );
      final list = records.map((r) => r['name'] as String).toList();
      
      // Always ensure common technical fields are included just in case
      // ir.model.fields flags are inconsistent.
      final common = {'message_ids', 'message_follower_ids', 'activity_ids', 'rating_ids'};
      for (var c in common) {
        if (!list.contains(c)) list.add(c);
      }
      
      return list;
    } catch (e) {
      debugPrint('OdooFieldRegistry error fetching technical fields for $model: $e');
      // Minimal fallback
      return ['id', 'create_uid', 'write_uid', 'create_date', 'write_date', 'active'];
    }
  }

  /// Returns `true` if the field registry for [model] is already cached.
  static bool isCached(String model) => _cache.containsKey(model);

  /// Clears the entire cache. Call on logout so a fresh session gets
  /// up-to-date field metadata from the new server / database.
  static void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  static Future<void> _preload(List<String> models) async {
    try {
      await Future.wait(models.map(getFieldNames));
    } catch (e) {
      debugPrint('OdooFieldRegistry preload failed: $e');
    }
  }

  /// Uses Odoo's [fields_get] RPC (not ir.model.fields) to retrieve the
  /// complete list of all readable field definitions for [model].
  ///
  /// [fields_get] returns computed, stored, and relational fields alike.
  static Future<Map<String, dynamic>> _fetchFieldDefs(String model) async {
    try {
      // fields_get returns: { 'field_name': { 'string': '…', 'type': '…', 'relation': '…' }, … }
      final result = await OdooRpcService.callKw(
        model: model,
        method: 'fields_get',
        args: [],
        kwargs: {},
      );

      if (result is Map) {
        final Map<String, dynamic> defs = Map<String, dynamic>.from(result);
        // Ensure 'id' is always present (it's implicit in Odoo).
        if (!defs.containsKey('id')) {
          defs['id'] = {'string': 'ID', 'type': 'integer', 'readonly': true};
        }
        return defs;
      }
      return {'id': {'string': 'ID', 'type': 'integer', 'readonly': true}};
    } catch (e, st) {
      debugPrint('OdooFieldRegistry error fetching fields for $model: $e\n$st');
      // If fields_get fails (permissions, old Odoo, etc.) return a fallback map
      // containing just 'id' so the app doesn't crash, but we don't cache it.
      return {'id': {'string': 'ID', 'type': 'integer', 'readonly': true}};
    }
  }
}
