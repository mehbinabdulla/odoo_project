import 'package:xml/xml.dart';
import 'odoo_rpc_service.dart';
import 'odoo_view_inheritance.dart';

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

  // model name → map of field_name → view-level widget attr
  // (from <field name="x" widget="badge"/> in the model's form view arch).
  static final Map<String, Map<String, String>> _viewWidgets = {};

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

  /// Returns the full map of field definitions for [model]. [force]
  /// bypasses the session cache — use it after the form-view arch was
  /// re-fetched, because a fresh arch can expose fields the cached
  /// metadata never saw (e.g. Studio additions).
  static Future<Map<String, dynamic>> getFieldDefs(
    String model, {
    bool force = false,
  }) async {
    if (force) {
      final defs = await _fetchFieldDefs(model);
      // Only cache if we actually got fields back (more than just 'id').
      if (defs.length > 1) _cache[model] = defs;
      return defs;
    }
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
      return [];
    } catch (_) {
      // Fail closed: if the check itself fails, grant nothing rather than
      // leaking fields the user may not read.
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
    } catch (_) {
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
    _viewWidgets.clear();
    _archCache.clear();
    _archStamp.clear();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  static Future<void> _preload(List<String> models) async {
    try {
      await Future.wait(models.map(getFieldNames));
    } catch (_) {
      // preload is best-effort: failures surface when callers fetch.
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
    } catch (_) {
      // If fields_get fails (permissions, old Odoo, etc.) return a fallback map
      // containing just 'id' so the app doesn't crash, but we don't cache it.
      return {'id': {'string': 'ID', 'type': 'integer', 'readonly': true}};
    }
  }

  /// View-level widget hints for [model] fields, e.g.
  /// `{"favorite": "boolean_heart", "kanban_state": "state_selection"}`
  /// — read once from the model's default form view XML arch
  /// (`<field name="x" widget="badge"/>`) and cached.
  ///
  /// Empty map if unavailable (no access / fetch failure / missing xml pkg).
  static Future<Map<String, String>> getViewWidgets(
    String model, {
    bool force = false,
  }) async {
    await getFormArch(model, force: force);
    return _viewWidgets[model] ?? const {};
  }

  static final Map<String, String> _archCache = {};
  static final Map<String, DateTime> _archStamp = {};

  /// How long a fetched form-view arch is trusted before a background
  /// refresh happens. Server-side view edits surface automatically.
  static const Duration archTtl = Duration(minutes: 10);

  /// The model's default form view XML arch — the source for both
  /// [getViewWidgets] and arch-driven layouts. [force] (pull-to-refresh)
  /// bypasses the TTL.
  ///
  /// Falls back to the last cached arch (if any) when refresh fails.
  static Future<String?> getFormArch(String model, {bool force = false}) async {
    final cached = _archCache[model];
    final stamp = _archStamp[model];
    final fresh =
        cached != null &&
        stamp != null &&
        DateTime.now().difference(stamp) < archTtl;
    if (!force && fresh) return cached;

    String? arch;

    // 1) Client-side combination — base arch + ALL inheriting views'
    //    <xpath position="..."> patches, i.e. exactly what Odoo web
    //    renders. Uses only searchRead on ir.ui.view, which works even
    //    where get_views/get_view is unavailable.
    try {
      final base = await OdooRpcService.searchRead(
        model: 'ir.ui.view',
        domain: [
          ['model', '=', model],
          ['type', '=', 'form'],
        ],
        fields: ['id', 'arch'],
        limit: 1,
        order: 'priority asc',
      );
      if (base.isNotEmpty && base[0]['arch'] is String && base[0]['arch'].isNotEmpty) {
        var merged = base[0]['arch'] as String;
        // ALL form views inheriting this model's views (not just
        // direct children of the base — chained ones are resolved by
        // the merge retry passes). Empty archs are filtered
        // client-side rather than via domain, so the search stays
        // simple and portable.
        final inherited = await OdooRpcService.searchRead(
          model: 'ir.ui.view',
          domain: [
            ['model', '=', model],
            ['type', '=', 'form'],
            ['inherit_id', '!=', false],
          ],
          fields: ['id', 'arch'],
          limit: 200,
          order: 'priority asc, id asc',
        );
        final patches = <String>[];
        final patchIds = <int>[];
        for (final row in inherited) {
          final a = row['arch'];
          if (a is String && a.isNotEmpty) {
            patches.add(a);
            patchIds.add(row['id'] is num ? (row['id'] as num).toInt() : 0);
          }
        }
        if (patches.isNotEmpty) {
          final result = OdooViewInheritance.merge(
            base: merged,
            patches: patches,
          );
          merged = result.merged;
        }
        arch = merged;
      }
    } catch (_) {
      // merge request failed — the later get_views/get_view/raw fallbacks
      // still provide an arch.
    }

    // 2) get_views — the combined-form response the web client itself
    //    uses: base arch + ALL inherited views applied. Pages injected
    //    by inheritance (Timesheets, Sub-tasks…) exist only here.
    try {
      final res = await OdooRpcService.callKw(
        model: 'ir.ui.view',
        method: 'get_views',
        args: [
          [model],
        ],
        kwargs: {'options': const {}},
      );
      if (res is Map) {
        dynamic node = res['views'];
        if (node is Map && node[model] != null) node = node[model];
        if (node is Map && node['views'] is Map) {
          node = (node['views'] as Map)['form'];
        }
        if (node is Map && node['arch'] is String && node['arch'].isNotEmpty) {
          arch = node['arch'] as String;
        }
      }
    } catch (_) {
      // unavailable endpoints fall through to get_view / raw searchRead.
    }

    // 2b) get_view — combined arch via the single-view endpoint.
    if (arch == null) {
      try {
        final res = await OdooRpcService.callKw(
          model: 'ir.ui.view',
          method: 'get_view',
          args: const [],
          kwargs: {
            'view_id': false,
            'view_type': 'form',
            'model': model,
            'toolbar': false,
          },
        );
        if (res is Map && res['arch'] is String && res['arch'].isNotEmpty) {
          arch = res['arch'] as String;
        }
      } catch (_) {
        // fall through to the raw-arch fallback below.
      }
    }

    // 3) Fallback: the raw `arch` field of the best-priority form view
    //    (no inherits applied — may lack extension pages).
    if (arch == null) {
      try {
        final rows = await OdooRpcService.searchRead(
          model: 'ir.ui.view',
          domain: [
            ['model', '=', model],
            ['type', '=', 'form'],
          ],
          fields: ['arch'],
          limit: 1,
          order: 'priority asc',
        );
        if (rows.isNotEmpty) {
          final a = rows[0]['arch'];
          if (a is String && a.isNotEmpty) arch = a;
        }
      } catch (_) {
        // no arch from any endpoint — caller shows cached content.
      }
    }

    if (arch != null && arch.isNotEmpty) {
      _archCache[model] = arch;
      _archStamp[model] = DateTime.now();
      _viewWidgets[model] = parseViewWidgets(arch);
      // A freshly fetched arch can reference brand-new fields (Studio
      // additions). Refresh the metadata cache alongside it so the
      // layout engine knows those fields instead of pruning their
      // pages to nothing.
      try {
        await getFieldDefs(model, force: true);
      } catch (_) {}
    }
    return arch ?? cached;
  }

  /// Extracts `widget="…"` (and style hints) per field name from a
  /// form/button view XML arch.
  static Map<String, String> parseViewWidgets(String arch) {
    final widgets = <String, String>{};
    try {
      final doc = XmlDocument.parse(arch);
      for (final node in doc.findAllElements('field')) {
        final name = node.getAttribute('name');
        final widget = node.getAttribute('widget') ??
            node.getAttribute('style'); // classless fallback hint
        if (name != null && widget != null && widget != 'none') {
          widgets[name] = widget;
        }
      }
    } catch (_) {
      // widget extraction is best-effort; arch still renders.
    }
    return widgets;
  }
}
