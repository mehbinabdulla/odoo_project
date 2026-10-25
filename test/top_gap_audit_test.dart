import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:do_your_projects/core/widgets/odoo_arch_detail_view.dart';

/// Prints the vertical geometry at the TOP of the Details pane:
/// how much space sits between the tab strip and the first content
/// row ("Project"), with (a) empty stage pipeline — the reported
/// hole — and (b) a filled one.
void main() {
  const arch = '''
<form js_class="project_task_form">
  <header>
    <field name="stage_id" widget="statusbar_duration" options="{'display_duration': True}"/>
    <field name="state" widget="statusbar" invisible="1"/>
  </header>
  <sheet>
    <div class="oe_title"><field name="name"/></div>
    <group name="top">
      <group name="left">
        <field name="project_id"/>
        <field name="partner_id"/>
        <field name="date_deadline"/>
      </group>
    </group>
    <notebook>
      <page string="Description"><field name="description"/></page>
    </notebook>
  </sheet>
</form>
''';

  final defs = <String, dynamic>{
    'stage_id': {'string': 'Stage', 'type': 'many2one'},
    'state': {'string': 'Status', 'type': 'selection'},
    'name': {'string': 'Title', 'type': 'char'},
    'project_id': {'string': 'Project', 'type': 'many2one'},
    'partner_id': {'string': 'Customer', 'type': 'many2one'},
    'date_deadline': {'string': 'Deadline', 'type': 'date'},
    'description': {'string': 'Description', 'type': 'html'},
  };

  Future<void> pump(tester, List<Map<String, dynamic>> pipeline) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(411 * 2, 823 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final labels = OdooArchDetailView.computeTabLabels(
      arch: arch,
      fieldDefs: defs,
      fieldValues: const {},
    );
    // ignore: avoid_print
    print('labels: $labels');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DefaultTabController(
            length: labels.length,
            child: OdooArchDetailView(
              arch: arch,
              fieldDefs: defs,
              fieldValues: const {
                'stage_id': {'id': 1, 'name': 'New'},
              },
              stagePipeline: pipeline,
              tabLabels: labels,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void walkUp(WidgetTester tester, String label, double projectTop) {
    tester
        .element(find.text(label).first)
        .visitAncestorElements((cur) {
      final ro = cur.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        final bo = ro.localToGlobal(Offset.zero);
        print('  L${cur.widget.runtimeType} '
            'top=${bo.dy.toStringAsFixed(1)} h=${ro.size.height.toStringAsFixed(1)}');
      }
      return true; // keep climbing
    });
  }

  void depthWalk(Element el, int depth) {
    final ro = el.renderObject;
    String dh = '';
    if (ro is RenderBox && ro.hasSize) {
      final bo = ro.localToGlobal(Offset.zero);
      dh = ' (${ro.size.height.toStringAsFixed(1)}px @${bo.dy.toStringAsFixed(0)})';
    }
    print('${'  ' * depth}${el.widget.runtimeType}$dh');
    var d = depth + 1;
    el.visitChildren((c) => depthWalk(c, d));
  }

  testWidgets('gap audit — EMPTY pipeline', (tester) async {
    await pump(tester, const []);
    final project = tester.getRect(find.text('Project').first);
    printOnFailure('');
    final strip = tester.getRect(find.text('Details').first);
    // ignore: avoid_print
    print('EMPTY: stripLabel.top=${strip.top.toStringAsFixed(1)} '
        'h=${strip.height.toStringAsFixed(1)} '
        'Project.top=${project.top.toStringAsFixed(1)} '
        'GAP=${(project.top - strip.bottom).toStringAsFixed(1)}');
    walkUp(tester, 'Project', project.top);
    // every render box occupying the band between pane top (56) and
    // the group padding (128)
    print('── band 50..135 ──');
    final seen = <int>{};
    tester.allElements.where((e) {
      final ro = e.renderObject;
      return ro is RenderBox && ro.hasSize && !ro.size.isEmpty;
    }).forEach((e) {
      final ro = e.renderObject as RenderBox;
      final bo = ro.localToGlobal(Offset.zero);
      if (bo.dy >= 50 && bo.dy <= 135 && bo.dx < 40) {
        final key = identityHashCode(ro);
        if (seen.add(key)) {
          print('${e.widget.runtimeType} top=${bo.dy.toStringAsFixed(1)} '
              'h=${ro.size.height.toStringAsFixed(1)}');
        }
      }
    });

    // subtree of the 48px header Padding: what its Column contains
    final headerPad = tester.allElements.where((e) {
      final ro = e.renderObject;
      if (ro is! RenderBox || !ro.hasSize) return false;
      final bo = ro.localToGlobal(Offset.zero);
      return e.widget is Padding && bo.dy > 55 && bo.dy < 57;
    }).toList();
    for (final hp in headerPad) {
      print('── header subtree ──');
      depthWalk(hp, 0);
    }
  }, skip: false);

  testWidgets('gap audit — FILLED pipeline', (tester) async {
    await pump(tester, const [
      {'id': 1, 'name': 'New', 'current': true, 'duration': '10h'},
      {'id': 2, 'name': 'Ongoing'},
    ]);
    final project = tester.getRect(find.text('Project').first);
    // ignore: avoid_print
    print('FILLED: Project.top=${project.top.toStringAsFixed(1)}');
  }, skip: false);
}
