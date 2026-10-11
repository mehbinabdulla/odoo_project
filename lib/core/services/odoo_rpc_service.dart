import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'client_provider.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import '../models/odoo_session_model.dart';
import 'odoo_field_registry.dart';

class OdooRpcService {
  static final OdooRpcService _instance = OdooRpcService._internal();
  factory OdooRpcService() => _instance;
  OdooRpcService._internal();

  static final http.BaseClient _httpClient = buildHttpClient();
  static OdooSessionModel? _session;
  static Function? onSessionExpired;

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  // ─── Session management ───────────────────────────────────────────────────

  static void setSession(OdooSessionModel session) {
    _session = session;
  }

  static void clearSession() {
    _session = null;
    OdooFieldRegistry.clear(); // flush cached field lists on logout
  }

  static OdooSessionModel? get currentSession => _session;
  static bool get isAuthenticated => _session != null;

  // ─── Auth ─────────────────────────────────────────────────────────────────

  static Future<List<String>> listDatabases(String baseUrl) async {
    try {
      final uri = Uri.parse('$baseUrl/web/database/list');
      final resp = await _httpClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': _ua,
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {},
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      if (data['result'] is List) {
        return List<String>.from(data['result']);
      }
      return [];
    } catch (e) {
      throw Exception('DB Fetch error: $e');
    }
  }

  static Future<OdooSessionModel?> authenticate({
    required String serverUrl,
    required String database,
    required String username,
    required String password,
  }) async {
    String url = serverUrl.trim();
    if (!url.startsWith('http')) url = 'https://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/odoo')) url = url.substring(0, url.length - 5);

    try {
      final client = OdooClient(url, httpClient: _httpClient);
      OdooSession? odooSession;

      try {
        odooSession = await client.authenticate(database, username, password);
      } catch (e) {
        // Fallback: manual auth via JSON-RPC
        final resp = await _httpClient.post(
          Uri.parse('$url/web/session/authenticate'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': _ua,
          },
          body: jsonEncode({
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {
              'db': database,
              'login': username,
              'password': password,
            },
            'id': DateTime.now().millisecondsSinceEpoch,
          }),
        );

        if (resp.statusCode != 200) {
          throw Exception('Auth failed: HTTP ${resp.statusCode}');
        }

        final body = jsonDecode(resp.body);
        if (body['error'] != null) {
          throw Exception(body['error']['message'] ?? 'Authentication failed');
        }

        final result = body['result'];
        var uid = result['uid'];
        if (uid is bool) {
          throw Exception('Invalid credentials');
        }

        String? sessionId;
        if (result['session_id'] != null) {
          sessionId = result['session_id'] as String;
        } else if (resp.headers['set-cookie'] != null) {
          final m = RegExp(r'session_id=([^;]+)').firstMatch(resp.headers['set-cookie']!);
          sessionId = m?.group(1);
        }

        if (sessionId == null) throw Exception('No session ID');
        if (uid == null) throw Exception('two factor authentication required');

        odooSession = OdooSession(
          id: sessionId,
          userId: uid as int,
          partnerId: result['partner_id'] ?? 0,
          userLogin: result['username'] ?? username,
          userName: result['name'] ?? '',
          userLang: result['user_context']?['lang'] ?? 'en_US',
          userTz: result['user_context']?['tz'] ?? 'UTC',
          isSystem: result['is_system'] ?? false,
          dbName: result['db'] ?? database,
          serverVersion: result['server_version'] ?? '',
          companyId: result['company_id'] ?? 0,
          allowedCompanies: [],
        );
      }

      final sessionModel = OdooSessionModel(
        sessionId: odooSession.id,
        userLogin: username,
        password: password,
        serverUrl: url,
        database: database,
        userId: odooSession.userId,
        userName: odooSession.userName,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        serverVersion: odooSession.serverVersion,
        selectedCompanyId: odooSession.companyId,
        allowedCompanyIds: [odooSession.companyId],
      );

      setSession(sessionModel);
      return sessionModel;
    } catch (e) {
      rethrow;
    }
  }

  // ─── Generic call_kw RPC ──────────────────────────────────────────────────

  static Future<dynamic> callKw({
    required String model,
    required String method,
    required List<dynamic> args,
    Map<String, dynamic> kwargs = const {},
  }) async {
    if (_session == null) throw Exception('Not authenticated');

    final payload = {
      'jsonrpc': '2.0',
      'method': 'call',
      'id': DateTime.now().millisecondsSinceEpoch,
      'params': {
        'model': model,
        'method': method,
        'args': args,
        'kwargs': kwargs,
      },
    };

    final resp = await _httpClient
        .post(
          Uri.parse('${_session!.serverUrl}/web/dataset/call_kw'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'User-Agent': _ua,
            'Cookie': 'session_id=${_session!.sessionId}',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      throw Exception('RPC HTTP error: ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body);
    if (data['error'] != null) {
      final err = data['error'];
      final msg = err['data']?['message'] ?? err['message'] ?? 'RPC Error';
      
      if (msg.toLowerCase().contains('session expired') || 
          msg.toLowerCase().contains('session has expired')) {
        onSessionExpired?.call();
      }
      
      throw Exception(msg);
    }
    return data['result'];
  }

  // ─── default_get helper ───────────────────────────────────────────────────

  /// Fetches default values for [fields] in [model] from the Odoo server.
  static Future<Map<String, dynamic>> defaultGet({
    required String model,
    required List<String> fields,
  }) async {
    final result = await callKw(
      model: model,
      method: 'default_get',
      args: [fields],
    );
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return {};
  }

  // ─── search_read helper ────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> searchRead({
    required String model,
    List<dynamic> domain = const [],
    required List<String> fields,
    int? limit,
    int? offset,
    String? order,
  }) async {
    final result = await callKw(
      model: model,
      method: 'search_read',
      args: [domain],
      kwargs: {
        'fields': fields,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        if (order != null) 'order': order,
      },
    );

    if (result is List) {
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  // ─── safeSearchRead – fully dynamic via fields_get ───────────────────────

  /// Fetches records for [model] using only fields that actually exist on the
  /// connected Odoo server.
  ///
  /// • When [fields] is provided, any names not present on the server are
  ///   silently removed before the request is sent.
  /// • If a field is present but the user lacks access rights, the resulting
  ///   error is caught, the field is removed, and the request is retried.
  static Future<List<Map<String, dynamic>>> safeSearchRead({
    required String model,
    List<dynamic> domain = const [],
    List<String> fields = const [],       // empty → fallback to 'id' only
    int? limit,
    int? offset,
    String? order,
  }) async {
    List<String> resolvedFields;

    if (fields.isEmpty) {
      resolvedFields = ['id'];
    } else {
      // Caller gave a list → prune any that don't exist on the server.
      final available = await OdooFieldRegistry.getFieldNames(model);
      resolvedFields = available.isEmpty
          ? List.from(fields)                            // no info – trust caller
          : fields.where(available.contains).toList(); // prune invalid fields
      if (resolvedFields.isEmpty) resolvedFields = ['id'];
    }

    // Auto-retry loop to handle field-level access rights errors.
    // Sometimes fields_get says a field exists, but search_read fails because
    // the current user doesn't belong to the required security group.
    while (true) {
      try {
        return await searchRead(
          model: model,
          domain: domain,
          fields: resolvedFields,
          limit: limit,
          offset: offset,
          order: order,
        );
      } catch (e) {
        final errStr = e.toString();
        // Odoo error messages for field-level issues usually follow these patterns:
        // - "You do not have enough rights to access the field 'field_name'..."
        // - "Invalid field 'field_name' on model..."
        // We look for any "field '...'" or 'field "..."' pattern.
        final match = RegExp(r'''field ["']([^"']+)["']''', caseSensitive: false).firstMatch(errStr);
        
        if (match != null && match.groupCount >= 1) {
          final badField = match.group(1)!;
          if (resolvedFields.contains(badField)) {
            debugPrint('Access denied or invalid field: $badField. Retrying without it.');
            resolvedFields.remove(badField);
            if (resolvedFields.isEmpty) resolvedFields = ['id'];
            continue; // Retry without the bad field
          }
        }
        rethrow;
      }
    }
  }

  // ─── search_count helper ───────────────────────────────────────────────────

  static Future<int> searchCount({
    required String model,
    List<dynamic> domain = const [],
  }) async {
    final result = await callKw(
      model: model,
      method: 'search_count',
      args: [domain],
    );
    return result as int? ?? 0;
  }

  // ─── read_group helper ─────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> readGroup({
    required String model,
    required List<dynamic> domain,
    required List<String> fields,
    required List<String> groupby,
    int? limit,
    int? offset,
    String? orderby,
    bool lazy = true,
  }) async {
    final kwargs = <String, dynamic>{
      'groupby': groupby,
      'lazy': lazy,
    };
    if (limit != null) kwargs['limit'] = limit;
    if (offset != null) kwargs['offset'] = offset;
    if (orderby != null) kwargs['orderby'] = orderby;

    final result = await callKw(
      model: model,
      method: 'read_group',
      args: [domain, fields, groupby],
      kwargs: kwargs,
    );
    
    if (result is List) {
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  // ─── read helper ──────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> read({
    required String model,
    required List<int> ids,
    required List<String> fields,
  }) async {
    final result = await callKw(
      model: model,
      method: 'read',
      args: [ids],
      kwargs: {'fields': fields},
    );
    if (result is List) {
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  // ─── write helper ─────────────────────────────────────────────────────────

  static Future<bool> write({
    required String model,
    required List<int> ids,
    required Map<String, dynamic> values,
  }) async {
    final result = await callKw(
      model: model,
      method: 'write',
      args: [ids, values],
    );
    return result as bool? ?? false;
  }

  // ─── create helper ────────────────────────────────────────────────────────

  static Future<int> create({
    required String model,
    required Map<String, dynamic> values,
  }) async {
    final result = await callKw(
      model: model,
      method: 'create',
      args: [values],
    );
    return result as int? ?? 0;
  }

  // ─── unlink helper ────────────────────────────────────────────────────────

  static Future<bool> unlink({
    required String model,
    required List<int> ids,
  }) async {
    final result = await callKw(
      model: model,
      method: 'unlink',
      args: [ids],
    );
    return result as bool? ?? false;
  }

  // ─── Session info ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getSessionInfo() async {
    if (_session == null) throw Exception('Not authenticated');
    final resp = await _httpClient.post(
      Uri.parse('${_session!.serverUrl}/web/session/get_session_info'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'session_id=${_session!.sessionId}',
      },
      body: jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'params': {}}),
    );
    final data = jsonDecode(resp.body);
    return Map<String, dynamic>.from(data['result'] ?? {});
  }

  // ─── Field candidate lists (registry will prune invalid ones) ─────────────
  //
  // These list ALL fields we'd ever want, across all supported Odoo versions.
  // The OdooFieldRegistry will automatically drop any that don't exist on the
  // connected server, or safeSearchRead will drop them if they hit access errors.

  static const List<String> projectFieldCandidates = [
    'id', 'name', 'description', 'active', 'user_id', 'partner_id',
    'company_id', 'task_count', 'task_count_with_subtasks', 'closed_task_count',
    'date', 'create_date', 'privacy_visibility', 'is_favorite', 
    'last_update_status', 'stage_id', 'last_update_color', 'alias_id', 
    'tag_ids', 'color',
  ];

  static const List<String> taskFieldCandidates = [
    // ── Core identity
    'id', 'name', 'active', 'sequence', 'color',

    // ── Dates
    'create_date', 'write_date', 'date_deadline', 'date_assign',
    'date_last_stage_update',

    // ── Relations: project & stage
    'project_id', 'stage_id', 'personal_stage_type_id',

    // ── Relations: people
    'user_ids',          // assignees (Many2many)
    'user_id',           // single responsible (older versions)
    'partner_id',        // customer
    'reviewer_id',       // reviewer

    // ── Tags & categorisation
    'tag_ids',           // project tags (Many2many)

    // ── Hierarchy
    'parent_id',         // parent task
    'child_ids',         // sub-tasks (Many2many)
    'depend_on_ids',     // task dependencies

    // ── Milestone
    'milestone_id',

    // ── Status / state fields
    'state',             // Odoo 16+: in_progress, done, blocked, cancelled
    'kanban_state',      // normal / blocked / done
    'kanban_state_label',

    // ── Priority
    'priority',          // 0 = normal, 1 = high/starred

    // ── Hours / progress
    'allocated_hours',
    'effective_hours',
    'remaining_hours',
    'planned_hours',     // alias used in some versions
    'subtask_effective_hours',
    'total_hours_spent',

    // ── Description / notes
    'description',
    'description_picking',

    // ── Company
    'company_id',
  ];

  static const List<String> timesheetFieldCandidates = [
    'id', 'name', 'date', 'project_id', 'task_id', 'unit_amount',
    'company_id', 'user_id', 'employee_id', 'partner_id',
    'account_id', 'currency_id',
  ];

  // ─── Legacy versioned helpers (kept for compatibility) ─────────────────────
  //
  // Prefer using the *Candidates constants + safeSearchRead instead.

  /// @deprecated Use [projectFieldCandidates] with [safeSearchRead] instead.
  static List<String> projectFields(int majorVersion) =>
      List<String>.from(projectFieldCandidates);

  /// @deprecated Use [taskFieldCandidates] with [safeSearchRead] instead.
  static List<String> taskFields(int majorVersion) =>
      List<String>.from(taskFieldCandidates);

  /// @deprecated Use [timesheetFieldCandidates] with [safeSearchRead] instead.
  static List<String> timesheetFields(int majorVersion) =>
      List<String>.from(timesheetFieldCandidates);
}
