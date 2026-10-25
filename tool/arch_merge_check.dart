import 'dart:io';
import 'package:xml/xml.dart';
import 'package:do_your_projects/core/services/odoo_view_inheritance.dart';

void main() {
  const base = '''
  <form string="Task">
    <sheet>
      <group>
        <field name="project_id"/>
        <field name="user_ids" widget="many2many_tags"/>
        <field name="tag_ids" widget="many2many_tags"/>
      </group>
      <notebook>
        <page name="description_page" string="Description">
          <field name="description" type="html"/>
        </page>
        <page name="extra" string="Extra Info">
          <group>
            <field name="account_id"/>
          </group>
        </page>
      </notebook>
    </sheet>
  </form>
''';

  const h1 = '''
  <xpath expr="//notebook" position="inside">
    <page string="Timesheets">
      <field name="timesheet_ids"/>
    </page>
  </xpath>
''';

  const h2 = '''
  <data>
    <xpath expr="//field[@name='tag_ids']" position="after">
      <field name="partner_id"/>
      <field name="date_deadline"/>
    </xpath>
  </data>
''';

  const h3 = '''
  <xpath expr="//page[@name='description_page']//field[@name='description']" position="attributes">
    <attribute name="placeholder">Add details about this task...</attribute>
  </xpath>
''';

  const h4 = '''
  <xpath expr="//field[@name='planned_hours']" position="before">
    <field name="planned_date_begin"/>  <!-- chained: target missing until h5 -->
  </xpath>
''';

  const h5 = '''
  <xpath expr="//group" position="inside">
    <field name="planned_hours"/>
  </xpath>
''';

  const unreachable = '''
  <xpath expr="//group[@name='never_exists']" position="inside">
    <field name="xyz"/>
  </xpath>
''';

  final issues = <String>[];
  final result = OdooViewInheritance.merge(
    base: base,
    patches: [h1, h2, h3, h4, h5, unreachable],
    onIssue: issues.add,
  );

  final merged = result.merged;
  var ok = true;
  void check(String label, bool cond) {
    stdout.writeln('${cond ? 'PASS' : 'FAIL'}: $label');
    if (!cond) ok = false;
  }

  check('applied ${result.applied}/6 == 5', result.applied == 5);
  check('Timesheets page present', merged.contains('<page string="Timesheets">'));
  check('partner_id after tag_ids',
      merged.indexOf('<field name="tag_ids"') < merged.indexOf('<field name="partner_id"') &&
      merged.indexOf('<field name="partner_id"') < merged.indexOf('<field name="date_deadline"'));
  check('attribute patch applied',
      merged.contains('placeholder="Add details about this task..."'));
  check('chained patch resolved (planned_date_begin before planned_hours)',
      merged.indexOf('<field name="planned_date_begin"/>') <
          merged.indexOf('<field name="planned_hours"/>'));
  check('unreachable patch reported', issues.any((i) => i.contains('never_exists')));
  check('base untouched', merged.contains('<page name="extra" string="Extra Info">'));
  check('valid XML after merge', () {
    try {
      XmlDocument.parse(result.merged);
      return true;
    } catch (_) {
      return false;
    }
  }());

  final last =
      OdooViewInheritance.merge(base: base, patches: List.filled(6, unreachable));
  check('no-progress terminates', last.applied == 0 && last.merged == base);

  stdout.writeln(ok ? 'ALL OK' : 'FAILURES PRESENT');
}
