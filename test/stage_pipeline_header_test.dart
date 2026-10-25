import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:do_your_projects/core/widgets/odoo_arch_detail_view.dart';

void main() {
  // Stock project.task form shape: <header> as a SIBLING of <sheet>,
  // stage_id carrying the statusbar_duration widget (Odoo 19 form).
  const arch = '''
<form js_class="project_task_form">
  <header>
    <field name="stage_id" widget="statusbar_duration" options="{'display_duration': True}"/>
    <field name="state" widget="statusbar" invisible="1"/>
  </header>
  <sheet>
    <div class="oe_title">
      <field name="name" placeholder="My Task"/>
    </div>
    <notebook>
      <page string="Description">
        <field name="description"/>
      </page>
    </notebook>
  </sheet>
</form>
''';

  final defs = {
    'stage_id': {'type': 'many2one', 'string': 'Stage'},
    'state': {'type': 'selection', 'string': 'Status'},
    'name': {'type': 'char', 'string': 'Title'},
    'description': {'type': 'text', 'string': 'Description'},
  };

  final stages = [
    {'id': 1, 'name': 'New', 'current': true, 'duration': '10h'},
    {'id': 2, 'name': 'Ongoing', 'duration': '45m'},
    {'id': 3, 'name': 'Completed', 'fold': true},
  ];

  testWidgets('header statusbar_duration renders the stage pipeline',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OdooArchDetailView(
            arch: arch,
            fieldDefs: defs,
            fieldValues: const {
              'stage_id': {'id': 1, 'name': 'New'},
            },
            stagePipeline: stages,
            fallback: const Text('FALLBACK'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Pipeline stages are visible…
    expect(find.text('New'), findsOneWidget);
    expect(find.text('10h'), findsOneWidget);
    expect(find.text('Ongoing'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    // …with web parity durations — EVERY tracked stage shows its own
    // badge, not only the active one.
    expect(find.text('45m'), findsOneWidget);
    // …and Details got its label from the sheet content.
    expect(find.text('Details'), findsWidgets);
  });

  test('parser keeps the header node when sheet exists', () {
    final labels = OdooArchDetailView.computeTabLabels(
      arch: arch,
      fieldDefs: defs,
      fieldValues: const {},
    );
    expect(labels.first, 'Details');
  });

  testWidgets(
      'statusbar still shows the record stage when the pipeline RPC '
      'never returned stages', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OdooArchDetailView(
            arch: arch,
            fieldDefs: defs,
            fieldValues: const {
              'stage_id': 'Ongoing',
            },
            // All three tier queries failed/returned nothing.
            stagePipeline: const [],
            fallback: const Text('FALLBACK'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The record's own stage is highlighted instead of an empty row.
    expect(find.text('Ongoing'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);
  });
}
