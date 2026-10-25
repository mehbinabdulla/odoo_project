import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:do_your_projects/core/theme/app_theme.dart';
import 'package:do_your_projects/core/widgets/odoo_arch_detail_view.dart';

/// Measures the project.task detail page (Details + Description /
/// Timesheets / Sub-tasks) with every value EMPTY — the reported
/// misaligned state — and prints the key rects: strip tab labels vs
/// pane content edges, empty-state spacing, label↔value alignment.
void main() {
  const arch = '''
  <form>
    <group>
      <field name="project_id"/>
      <field name="partner_id"/>
      <field name="date_deadline"/>
      <field name="allocated_hours"/>
    </group>
    <notebook>
      <page string="Description"><field name="description"/></page>
      <page string="Timesheets"><field name="timesheet_ids"/></page>
      <page string="Sub-tasks"><field name="child_ids"/></page>
    </notebook>
  </form>
  ''';

  final defs = <String, dynamic>{
    'project_id': {'string': 'Project', 'type': 'many2one', 'relation': 'project.project'},
    'partner_id': {'string': 'Customer', 'type': 'many2one', 'relation': 'res.partner'},
    'date_deadline': {'string': 'Deadline', 'type': 'date'},
    'allocated_hours': {'string': 'Allocated Hours', 'type': 'float'},
    'description': {'string': 'Description', 'type': 'html'},
    'timesheet_ids': {'string': 'Timesheets', 'type': 'one2many', 'relation': 'account.analytic.line'},
    'child_ids': {'string': 'Sub-tasks', 'type': 'one2many', 'relation': 'project.task'},
  };

  Rect rect(WidgetTester tester, Finder f) => tester.getRect(f.first);

  void dump(WidgetTester tester, String tag, Finder f) {
    final r = rect(tester, f);
    // ignore: avoid_print
    print('$tag: left=${r.left.toStringAsFixed(1)} '
        'top=${r.top.toStringAsFixed(1)} '
        'w=${r.width.toStringAsFixed(1)} '
        'h=${r.height.toStringAsFixed(1)}');
  }

  testWidgets('strip ↔ empty pane alignment audit', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(820, 1800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final labels = OdooArchDetailView.computeTabLabels(
      arch: arch,
      fieldDefs: defs,
      fieldValues: const {},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: AppTheme
              .darkTheme.scaffoldBackgroundColor, // keep: dark surface
          body: DefaultTabController(
            length: labels.length,
            child: OdooArchDetailView(
              arch: arch,
              fieldDefs: defs,
              fieldValues: const {},
              tabLabels: labels,
            ),
          ),
        ),
      ),
    );
    // Swallow anyWh google_fonts asset-load noise from forbid-fetch mode.
    tester.takeException();

    // ignore: avoid_print
    print('labels: $labels');

    // ── Details tab (selected initially) ─────────────────────────────
    dump(tester, '[Details] "Project" tablabel', find.text('Details'));
    dump(tester, '[Details] "None" row (many2one)', find.text('None').first);

    // ── Switch to Sub-tasks: the cached tab was offscreen, so scroll
    // the strip left, then tap the now-visible label twice (once to
    // settle, once to be sure the index moved past Timesheets).
    await tester.drag(find.text('Details'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sub-tasks').first);
    await tester.pumpAndSettle();
    tester.takeException();

    // Both the strip tab and the pane label are Text('Sub-tasks').
    final subt = find.text('Sub-tasks').evaluate().toList();
    for (final e in subt) {
      final w = tester.getRect(find.byWidget(e.widget));
      // ignore: avoid_print
      print('[Sub-tasks text] left=${w.left.toStringAsFixed(1)} '
          'top=${w.top.toStringAsFixed(1)} w=${w.width.toStringAsFixed(1)} '
          'h=${w.height.toStringAsFixed(1)}');
    }

    // Every pane Text below the strip (top > 60): full alignment map.
    final texts = find.byType(Text).evaluate().toList();
    for (final e in texts) {
      final w = tester.getRect(find.byWidget(e.widget));
      if (w.top <= 60) continue;
      final data = (e.widget as Text).data ??
          (e.widget as Text).textSpan?.toPlainText() ?? '(complex)';
      // ignore: avoid_print
      print('[pane] "$data" left=${w.left.toStringAsFixed(1)} '
          'top=${w.top.toStringAsFixed(1)} w=${w.width.toStringAsFixed(1)} '
          'h=${w.height.toStringAsFixed(1)}');
    }
  });
}
