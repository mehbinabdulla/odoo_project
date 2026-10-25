import 'package:xml/xml.dart';
import 'package:xml/xpath.dart';

/// Result of merging an arch with its inheriting views.
class OdooViewInheritanceResult {
  final String merged;
  final int applied;
  final int total;

  const OdooViewInheritanceResult({
    required this.merged,
    required this.applied,
    required this.total,
  });
}

/// Applies Odoo view-inheritance patches to a form arch the same way
/// the web client does: every inheriting `ir.ui.view` contributes an
/// `<xpath expr="…" position="…">` instruction (optionally wrapped in
/// `<data>`), applied over the base arch.
///
/// Pure Dart (no Flutter imports) so it can be exercised outside the
/// app process.
class OdooViewInheritance {
  /// Applies [patches] in order to [base]. Positions supported:
  /// `inside` (default), `before`, `after`, `replace`, `attributes`.
  ///
  /// Inheriting views frequently target nodes that ANOTHER inheriting
  /// view creates first (chained inheritance), so the pass loops until
  /// no further patch can be applied. Unresolvable patches are skipped
  /// and counted; [onIssue] receives one line per unique skip reason.
  static OdooViewInheritanceResult merge({
    required String base,
    required List<String> patches,
    void Function(String issue)? onIssue,
  }) {
    var current = base;
    final pending = List<String>.from(patches);
    var appliedTotal = 0;
    var pass = 0;
    final seenIssues = <String>{};

    while (pending.isNotEmpty && pass < 4) {
      pass++;
      final progressed = <String>[];
      for (final patch in pending) {
        final doc = _parse(current);
        if (doc == null) {
          _issue(onIssue, seenIssues, 'base arch unparsable');
          continue;
        }
        final patchDoc = _parse(patch);
        if (patchDoc == null) {
          _issue(onIssue, seenIssues, 'inherit arch unparsable');
          continue;
        }
        try {
          if (_applyAll(doc, patchDoc.rootElement, onIssue, seenIssues)) {
            progressed.add(patch);
            appliedTotal++;
            current = doc.toString();
          }
        } catch (e) {
          _issue(onIssue, seenIssues, 'patch error: $e');
        }
      }
      for (final p in progressed) {
        pending.remove(p);
      }
      if (progressed.isEmpty) break;
    }

    return OdooViewInheritanceResult(
      merged: current,
      applied: appliedTotal,
      total: patches.length,
    );
  }

  /// Parses one patch document into the `<xpath>` instructions it wants
  /// applied against the base tree.
  static Iterable<XmlElement> _instructionsOf(XmlElement root) sync* {
    final local = root.name.local;
    if (local == 'data' || local == 'od') {
      yield* root.childElements;
    } else if (root.getAttribute('expr') != null ||
        root.getAttribute('position') != null) {
      yield root;
    }
  }

  /// Applies every instruction of [patchNode]; true when at least one
  /// patch landed on the tree.
  static bool _applyAll(
    XmlDocument doc,
    XmlElement patchNode,
    void Function(String)? onIssue,
    Set<String> seenIssues,
  ) {
    var applied = false;
    for (final instruction in _instructionsOf(patchNode)) {
      if (_applyOne(doc, instruction, onIssue, seenIssues)) applied = true;
    }
    return applied;
  }

  static bool _applyOne(
    XmlDocument doc,
    XmlElement instruction,
    void Function(String)? onIssue,
    Set<String> seenIssues,
  ) {
    final expr = instruction.getAttribute('expr') ?? '';
    final position = instruction.getAttribute('position') ?? 'inside';
    if (expr.isEmpty) {
      _issue(onIssue, seenIssues, 'xpath without expr skipped');
      return false;
    }

    Iterable<XmlNode> matches;
    try {
      matches = doc.rootElement.xpath(expr).toList();
    } catch (e) {
      _issue(onIssue, seenIssues, 'unsupported expr "$expr"');
      return false;
    }
    if (matches.isEmpty || matches.first is! XmlElement) {
      _issue(onIssue, seenIssues, 'no target for "$expr" (position=$position)');
      return false;
    }
    final target = matches.first as XmlElement;
    final newChildren =
        instruction.childElements.map((c) => c.copy()).toList();

    switch (position) {
      case 'inside':
        for (final c in newChildren) {
          target.children.add(c);
        }
        return true;
      case 'before':
      case 'after':
        final parent = target.parent;
        if (parent == null) {
          _issue(onIssue, seenIssues, 'target "$expr" has no parent');
          return false;
        }
        final siblings = parent.children;
        var at = siblings.indexOf(target);
        if (at < 0) return false;
        if (position == 'after') at++;
        for (final c in newChildren) {
          siblings.insert(at++, c);
        }
        return true;
      case 'replace':
        final parent = target.parent;
        if (parent == null) {
          _issue(onIssue, seenIssues, 'target "$expr" has no parent');
          return false;
        }
        final siblings = parent.children;
        final idx = siblings.indexOf(target);
        if (idx < 0) return false;
        siblings.removeAt(idx);
        var at = idx;
        for (final c in newChildren) {
          siblings.insert(at++, c);
        }
        return true;
      case 'attributes':
        for (final node in newChildren.whereType<XmlElement>()) {
          if (node.name.local == 'attribute') {
            final name = node.getAttribute('name');
            if (name != null) {
              target.setAttribute(name, node.innerText);
            }
          }
        }
        return true;
      default:
        _issue(onIssue, seenIssues, 'unsupported position "$position"');
        return false;
    }
  }

  static XmlDocument? _parse(String xml) {
    try {
      return XmlDocument.parse(xml);
    } catch (_) {
      return null;
    }
  }

  static void _issue(
    void Function(String)? onIssue,
    Set<String> seenIssues,
    String message,
  ) {
    if (seenIssues.add(message)) onIssue?.call(message);
  }
}
