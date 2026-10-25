import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:xml/xml.dart';

import '../theme/app_theme.dart';
import 'odoo_detail_sections.dart';

/// Renders a record's fields as a faithful, fully dynamic mobile mirror
/// of its Odoo form view XML arch:
///   • `<group>` / nested groups → mobile sections in arch order
///   • `<notebook><page string="…">` → pill tabs that swap the pane
///     below, mirroring the web form tabs
///   • `<div>` — real containers (not chrome): recursed so fields the
///     web lays out inside wrapper divs still render. Special divs:
///     `oe_title` / `oe_chatter` are skipped (title & chatter live in
///     the app bar / elsewhere on mobile), `oe_button_box` renders as
///     a row of stat-info cards.
///   • `<widget name="web_ribbon">` → red "Archived" banner
///   • `<field>` rows designed by widget attr (`float_time` → 00:00,
///     `boolean_icon` → chips, dates → calendar rows, x2many with an
///     inline `<tree>` → record mini-lists, `properties` → props view)
///   • `invisible="…"` / legacy `attrs` conditions evaluated on values
///   • STRICT: fields absent from the arch never render
///
/// Everything is derived from the arch at runtime — nothing static.
/// [fallback] renders when the arch is unavailable or empty.
class OdooArchDetailView extends StatefulWidget {
  /// Form view XML (from `OdooFieldRegistry.getFormArch`). May be null.
  final String? arch;
  final Map<String, dynamic> fieldDefs;
  final Map<String, dynamic> fieldValues;
  final Map<String, String> viewWidgets;
  final Widget? fallback;
  final EdgeInsetsGeometry padding;

  /// Content rendered above the tab strip that scrolls away with the
  /// page (e.g. the status / priority row). Only used with
  /// [stickyTabs].
  final Widget? header;

  /// When true the widget owns scrolling: it renders a CustomScrollView
  /// meant to be the `body` of a CollapsingAppBarPage / NestedScrollView
  /// screen. When the arch has no pages, a plain scrollable column is
  /// rendered instead.
  final bool stickyTabs;

  /// Where the sticky strip lives:
  ///  • true (default) → a pinned [SliverPersistentHeader] inside the
  ///    body scroll (standalone screens, no NestedScrollView quirks).
  ///  • false → the body carries no strip; the screen renders it in the
  ///    outer pinned app bar via `CollapsingAppBarPage.bottom` with
  ///    [OdooArchTabStrip] and labels from [computeTabLabels] — the
  ///    reliable pinning path under NestedScrollView.
  final bool stripInBody;

  /// Pre-computed tab labels from [computeTabLabels]. When provided,
  /// the widget trusts them (label count + Details-first mapping) so
  /// body and outer strip always agree.
  final List<String>? tabLabels;

  /// Stage pipeline for the form-header statusbar (`stage_id`) —
  /// `[{id, name}]` ordered by sequence, typically fetched from
  /// `project.task.type`. Empty (default) hides the pipeline row.
  final List<Map<String, dynamic>> stagePipeline;

  const OdooArchDetailView({
    super.key,
    required this.arch,
    required this.fieldDefs,
    required this.fieldValues,
    this.viewWidgets = const {},
    this.fallback,
    this.padding = const EdgeInsets.all(24),
    this.header,
    this.stickyTabs = false,
    this.stripInBody = true,
    this.tabLabels,
    this.stagePipeline = const [],
  });

  /// Parsed-arch cache (arch text → top nodes) shared across the
  /// renderer and the static helpers so the XML is parsed once.
  static final Map<String, List<_ArchNode>> _parseCache =
      <String, List<_ArchNode>>{};

  static List<_ArchNode> _parseArchCached(String arch) {
    final hit = _parseCache[arch];
    if (hit != null) return hit;
    final nodes = OdooArchLayoutParser(arch)._parseNodes();
    if (_parseCache.length > 4) _parseCache.remove(_parseCache.keys.first);
    _parseCache[arch] = nodes;
    return nodes;
  }

  /// Visible tab labels ("Details" first, then the surviving notebook
  /// page titles) for [arch] — resolved with the exact pruning rules
  /// the renderer applies. Lets sticky screens size a
  /// DefaultTabController and build an [OdooArchTabStrip] in the outer
  /// pinned app bar BEFORE the body widget mounts.
  static List<String> computeTabLabels({
    required String? arch,
    required Map<String, dynamic> fieldDefs,
    Map<String, dynamic> fieldValues = const {},
  }) {
    if (arch == null || arch.trim().isEmpty) return const [];
    try {
      final tops = _parseArchCached(arch);
      if (tops.isEmpty) return const [];

      final pruner = _ArchPruner(fieldDefs, fieldValues);
      final pruned = <_ArchNode>[];
      for (final n in tops) {
        final p = pruner.prune(n);
        if (p != null) pruned.add(p);
      }

      final pre = <_ArchNode>[];
      final pages = <_ArchNode>[];
      var seenNotebook = false;
      for (final node in pruned) {
        if (node.kind == _ArchKind.notebook && !seenNotebook) {
          seenNotebook = true;
          pages.addAll(node.children);
          continue;
        }
        // Nodes before the notebook form the Details tab; anything
        // after it renders below the strip and doesn't affect labels.
        if (!seenNotebook) pre.add(node);
      }

      return <String>[
        if (pre.isNotEmpty) 'Details',
        for (var i = 0; i < pages.length; i++)
          pages[i].title?.isNotEmpty == true
              ? pages[i].title!
              : 'Page ${i + 1}',
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  State<OdooArchDetailView> createState() => _OdooArchDetailViewState();
}

class _OdooArchDetailViewState extends State<OdooArchDetailView> {
  List<_ArchNode>? _nodes;

  @override
  void initState() {
    super.initState();
    _parseArch();
  }

  @override
  void didUpdateWidget(covariant OdooArchDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.arch != widget.arch) _parseArch();
  }

  void _parseArch() {
    _nodes = null;
    final String? arch = widget.arch;
    if (arch == null || arch.trim().isEmpty) return;
    try {
      _nodes = OdooArchDetailView._parseArchCached(arch);
    } catch (_) {
      _nodes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _nodes;
    if (nodes == null) return widget.fallback ?? const SizedBox.shrink();

    final pruner = _ArchPruner(widget.fieldDefs, widget.fieldValues);
    final pruned = <_ArchNode>[];
    for (final n in nodes) {
      final p = pruner.prune(n);
      if (p != null) pruned.add(p);
    }

    // Unified mobile tab strip: everything before the first notebook
    // becomes a synthetic "Details" tab in first position; the
    // notebook's pages join the same strip as farther tabs — one strip
    // mirroring the web form's body-then-tabs layout.
    final pre = <_ArchNode>[];
    final pages = <_ArchNode>[];
    final post = <_ArchNode>[];
    int? notebookKey;
    var seenNotebook = false;
    for (final node in pruned) {
      if (node.kind == _ArchKind.notebook && !seenNotebook) {
        seenNotebook = true;
        notebookKey = node.notebookKey;
        pages.addAll(node.children);
        continue;
      }
      (seenNotebook ? post : pre).add(node);
    }

    // No notebook in the arch → straight content, no tab strip.
    if (pages.isEmpty) {
      final out = _renderTopNodes(pre);
      if (widget.stickyTabs) {
        // The widget owns the scroll here (it is the screen body), so
        // keep the content scrollable even without tabs.
        final children = <Widget>[
          if (widget.header != null) widget.header!,
          ...out,
        ];
        final fallback = widget.fallback ?? const SizedBox.shrink();
        if (out.isEmpty) children.add(fallback);
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        );
      }
      if (widget.header != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            widget.header!,
            ...out,
            if (out.isEmpty && widget.fallback != null) widget.fallback!,
          ],
        );
      }
      if (out.isEmpty) return widget.fallback ?? const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: out,
      );
    }

    // Rendered once up front — also decides whether a Details tab
    // exists at all (nothing before the notebook → no Details tab).
    final detailsContent = _renderTopNodes(pre);
    // When labels were pre-computed via [computeTabLabels] for the
    // outer strip, trust them so the body mapping and the strip
    // always agree even if a pane happens to render empty.
    final bool detailsVisible = widget.tabLabels != null
        ? (widget.tabLabels!.isNotEmpty && widget.tabLabels!.first == 'Details')
        : detailsContent.isNotEmpty;
    final labels =
        widget.tabLabels ??
        <String>[
          if (detailsVisible) 'Details',
          for (var i = 0; i < pages.length; i++)
            pages[i].title?.isNotEmpty == true
                ? pages[i].title!
                : 'Page ${i + 1}',
        ];

    Widget buildPane(int selected) {
      if (detailsVisible && selected == 0) {
        // Rows in [detailsContent] already carry screen padding.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: detailsContent,
        );
      }
      final page = pages[selected - (detailsVisible ? 1 : 0)];
      return Padding(
        padding: widget.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildGroupContent(page),
        ),
      );
    }

    // Sticky mode: the widget is the screen body. The tab strip either
    // pins as a sliver inside the body scroll (stripInBody), or lives
    // in the outer app bar's bottom slot (stripInBody: false) — then
    // the widget renders only the switching pane and must NOT wrap its
    // own DefaultTabController, or the two controllers would desync.
    if (widget.stickyTabs) {
      final scroll = CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Content above the tabs scrolls away with the page.
          if (widget.header != null) SliverToBoxAdapter(child: widget.header!),
          // Pinned strip sliver (embedded flavor): sticks at the top of
          // this inner viewport as soon as it is reached.
          if (widget.stripInBody)
            SliverPersistentHeader(
              pinned: true,
              delegate: OdooArchTabStripDelegate(labels: labels),
            ),
          SliverToBoxAdapter(
            child: Builder(
              builder: (context) {
                // The screen owns the controller (stripInBody: false)
                // or the widget wrapped the scroll itself; when neither
                // exists the first pane renders statically.
                final controller = DefaultTabController.maybeOf(context);
                return AnimatedBuilder(
                  animation: controller ?? const AlwaysStoppedAnimation(0),
                  builder: (context, _) {
                    final selected = (controller?.index ?? 0).clamp(
                      0,
                      labels.length - 1,
                    );
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: KeyedSubtree(
                        key: ValueKey('stickyPane$notebookKey:$selected'),
                        child: buildPane(selected),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (post.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _renderTopNodes(post),
                ),
              ),
            ),
        ],
      );

      if (widget.stripInBody) {
        return DefaultTabController(
          key: ValueKey(
            'stickyTop$notebookKey:${widget.arch?.hashCode}:${labels.length}',
          ),
          length: labels.length,
          child: scroll,
        );
      }
      // Strip lives outside: the screen owns the DefaultTabController.
      return scroll;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.header != null) widget.header!,
        _tabbedSection(
          keyId: 'top$notebookKey',
          labels: labels,
          paneBuilder: buildPane,
        ),
        // Nodes after the notebook (chatter usually — pruned away by
        // the parser) render plainly below the tab area when present.
        if (post.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _renderTopNodes(post),
            ),
          ),
      ],
    );
  }

  // ── Rendering ─────────────────────────────────────────────────────────────

  /// Tab strip + animated pane in the exact Material [TabBar] style the
  /// project-details screen uses (bold 14pt poppins labels, red
  /// label-width underline, full-width divider). Wrapped in a
  /// [DefaultTabController] so the pane can follow the controller; the
  /// key embeds the arch identity + visible-tab count so a changed
  /// selection starts back on the first tab.
  Widget _tabbedSection({
    required String keyId,
    required List<String> labels,
    required Widget Function(int selected) paneBuilder,
  }) {
    return DefaultTabController(
      key: ValueKey('$keyId:${widget.arch?.hashCode}:tabs${labels.length}'),
      length: labels.length,
      child: Builder(
        builder: (context) {
          final controller = DefaultTabController.of(context);
          final theme = Theme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              archStripTabBar(theme, labels),
              const SizedBox(height: 8),
              AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  // Rows already carry their own screen padding.
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey('$keyId:${controller.index}'),
                      child: paneBuilder(controller.index),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// Top-level node renderer: fields, stat-card rows, ribbon, groups,
  /// containers and (post-notebook descendants) whole notebooks. Every
  /// widget supplies its own outer horizontal padding so this list can
  /// sit inside a tab pane without double padding.
  List<Widget> _renderTopNodes(List<_ArchNode> nodes) {
    final out = <Widget>[];
    var started = false;
    for (final node in nodes) {
      switch (node.kind) {
        case _ArchKind.notebook:
          if (started) out.add(const SizedBox(height: 28));
          out.add(
            Padding(padding: widget.padding, child: _renderNotebook(node)),
          );
          started = true;
        case _ArchKind.field:
          final row = _buildFieldRow(node);
          if (row is SizedBox) continue;
          if (started) out.add(const SizedBox(height: 24));
          out.add(Padding(padding: widget.padding, child: row));
          started = true;
        case _ArchKind.statButtons:
          final row = _renderStatButtons(node);
          if (row == null) continue;
          if (started) out.add(const SizedBox(height: 16));
          out.add(row);
          started = true;
        case _ArchKind.ribbon:
          if (started) out.add(const SizedBox(height: 16));
          out
            ..add(
              Padding(
                padding: widget.padding,
                child: _RibbonBanner(node.title ?? 'Archived'),
              ),
            )
            ..add(const SizedBox(height: 16));
          started = true;
        case _ArchKind.container:
          final content = _buildGroupContent(node);
          if (content.isEmpty) continue;
          if (started) out.add(const SizedBox(height: 16));
          out.add(
            Padding(
              padding: widget.padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: content,
              ),
            ),
          );
          started = true;
        default:
          final content = _buildGroupContent(node);
          if (content.isEmpty) continue;
          if (started) out.add(const SizedBox(height: 24));
          if (node.title != null && node.title!.isNotEmpty) {
            out
              ..add(OdooSectionTitle(node.title!)) // pads itself
              ..add(const SizedBox(height: 12));
          }
          out.add(
            Padding(
              padding: widget.padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: content,
              ),
            ),
          );
          started = true;
      }
    }
    return out.where((w) => !_isZeroSized(w)).toList();
  }

  /// Invisible placeholders — widgets that render nothing at all:
  /// `SizedBox.shrink()` (zero width/height, not null!) and a bare
  /// `SizedBox()`. Filtered out of group/container content so hidden
  /// rows (statusbar with no pipeline data, fully-pruned chrome) stop
  /// reserving phantom vertical slots in the pane, while real spacing
  /// boxes (height:16) are kept.
  static bool _isZeroSized(Widget w) =>
      w is SizedBox &&
      (w.width ?? 0) == 0 &&
      (w.height ?? 0) == 0 &&
      w.child == null;

  /// Rows for a group node: fields, then nested sub-groups (small
  /// heading + content), then nested notebooks, then plain containers
  /// (div/span subtrees) flattened, plus stat-info buttons.
  List<Widget> _buildGroupContent(_ArchNode node) {
    final out = <Widget>[];
    for (final child in node.children) {
      switch (child.kind) {
        case _ArchKind.field:
          out.add(_buildFieldRow(child));
          break;
        case _ArchKind.notebook:
          out
            ..add(_renderNotebook(child))
            ..add(const SizedBox(height: 16));
          break;
        case _ArchKind.statButtons:
          final row = _renderStatButtons(child);
          if (row != null) {
            out
              ..add(row)
              ..add(const SizedBox(height: 8));
          }
          break;
        case _ArchKind.ribbon:
          out
            ..add(
              Padding(
                padding: widget.padding,
                child: _RibbonBanner(child.title ?? 'Archived'),
              ),
            )
            ..add(const SizedBox(height: 8));
          break;
        case _ArchKind.container:
          out.addAll(_buildGroupContent(child));
          break;
        case _ArchKind.group:
          final content = _buildGroupContent(child);
          if (content.isEmpty) break;
          final title = child.title;
          if (title != null && title.isNotEmpty) {
            out
              ..add(
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              )
              ..add(const SizedBox(height: 10));
          }
          out.addAll(content);
          out.add(const SizedBox(height: 4));
          break;
        default:
          break;
      }
    }
    return out.where((w) => !_isZeroSized(w)).toList();
  }

  /// One field row, styled by the Odoo widget that renders it on web.
  /// x2many fields with an inline `<tree>` come out as record mini-lists
  /// mirroring the web list columns.
  Widget _buildFieldRow(_ArchNode field) {
    final def = widget.fieldDefs[field.name];
    if (def == null) return const SizedBox.shrink();
    final label = def['string']?.toString() ?? field.name ?? '';
    final type = def['type']?.toString() ?? '';
    final viewWidget = field.widget ?? widget.viewWidgets[field.name];

    // Form-header statusbar fields: stage_id becomes the dynamic
    // stage pipeline when the screen supplies stages; the state
    // switcher is already the screen's own status badge (no
    // duplicate row); with no pipeline data everything stays hidden,
    // matching the pre-header-support behaviour.
    if (viewWidget == 'statusbar' || viewWidget == 'statusbar_duration') {
      final currentName = widget.fieldValues['stage_id']?.toString();
      // The screen's stage pipeline when the project.task.type RPC
      // returned stages; otherwise degrade to the record's own
      // hydrated stage — one highlighted chip, the same name/casing
      // the list-view badge shows, instead of an empty row.
      final pipeline = widget.stagePipeline.isNotEmpty
          ? widget.stagePipeline
          : (currentName != null && currentName.isNotEmpty
                ? <Map<String, dynamic>>[
                    {'name': currentName, 'current': true},
                  ]
                : const <Map<String, dynamic>>[]);
      if (field.name == 'stage_id' && pipeline.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _StagePipeline(stages: pipeline, currentName: currentName),
        );
      }
      return const SizedBox.shrink();
    }

    // one2many (record lists): chips would dump a wall of display names —
    // give them the tree-flavoured mini list instead.
    if (type == 'one2many') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _RecordList(
          label: label,
          records: widget.fieldValues[field.name],
          columnHints: field.treeHints,
          fieldDefs: widget.fieldDefs,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        child: OdooTypedValueWidget(
          label: label,
          type: type,
          relation: def['relation']?.toString(),
          value: widget.fieldValues[field.name],
          viewWidget: viewWidget,
        ),
      ),
    );
  }

  /// `oe_button_box`: one compact stat card per visible button, like
  /// the web form's stat-info buttons (Sub-tasks 2, Blocking Tasks 1…).
  Widget? _renderStatButtons(_ArchNode box) {
    final cards = <Widget>[];
    for (final button in box.children) {
      if (button.kind != _ArchKind.statButton) continue;
      final raw = widget.fieldValues[button.name];
      final value = raw == null
          ? ''
          : (raw is num ? ArchFmt.number(raw) : raw.toString());
      final label =
          button.title ?? (widget.fieldDefs[button.name]?['string'] ?? '');
      if (value.isEmpty) continue;
      cards.add(
        _StatCard(icon: _statIcon(button.widget), value: value, label: label),
      );
    }
    if (cards.isEmpty) return null;
    return Padding(
      padding: widget.padding,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (final c in cards) ...[c, const SizedBox(width: 12)],
          ],
        ),
      ),
    );
  }

  /// fa-*-class (from the button's `<i class="fa …">`) → Phosphor icon.
  static IconData _statIcon(String? cls) {
    final c = cls ?? '';
    if (c.contains('fa-tasks')) return PhosphorIconsRegular.checkSquare;
    if (c.contains('fa-repeat')) return PhosphorIconsRegular.repeat;
    if (c.contains('fa-smile')) return PhosphorIconsRegular.smiley;
    if (c.contains('fa-meh')) return PhosphorIconsRegular.smileySad;
    if (c.contains('fa-frown')) return PhosphorIconsRegular.smileySad;
    if (c.contains('fa-usd') || c.contains('fa-money')) {
      return PhosphorIconsRegular.currencyDollar;
    }
    if (c.contains('fa-envelope')) return PhosphorIconsRegular.envelopeSimple;
    if (c.contains('fa-clock')) return PhosphorIconsRegular.clock;
    if (c.contains('fa-calendar')) return PhosphorIconsRegular.calendarBlank;
    if (c.contains('fa-star') || c.contains('fa-trophy')) {
      return PhosphorIconsRegular.trophy;
    }
    return PhosphorIconsRegular.cube;
  }

  /// Nested notebook (a `<notebook>` inside a page/group) rendered with
  /// the same Material tab strip as the main section. No outer padding
  /// here — callers wrap it so the tabs align with surrounding rows.
  Widget _renderNotebook(_ArchNode notebook) {
    final pages = notebook.children;
    if (pages.isEmpty) return const SizedBox.shrink();
    return _tabbedSection(
      keyId: 'n${notebook.notebookKey}',
      labels: [
        for (var i = 0; i < pages.length; i++)
          pages[i].title?.isNotEmpty == true
              ? pages[i].title!
              : 'Page ${i + 1}',
      ],
      paneBuilder: (selected) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildGroupContent(pages[selected]),
      ),
    );
  }
}

// ── Formatting helpers shared by the arch widgets ────────────────────────────

abstract class ArchFmt {
  /// Odoo float_time / timesheet_uom → "02:30" (hours:minutes).
  static String hours(num v) {
    final negative = v < 0;
    final n = v.abs();
    final h = n.floor();
    final m = ((n - h) * 60).round();
    final text =
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    return negative ? '-$text' : text;
  }

  /// Numeric display without noise: 0.0 → "0", 2.5 → "2.5".
  static String number(num v) {
    if (v == v.roundToDouble()) {
      final i = v.round();
      return i.toString();
    }
    return v.toString();
  }
}

// ── oe_button_box stat card ─────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 9.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── shared detail tab-strip style ────────────────────────────────────────────

/// The detail-screen tab strip style (bold 14pt poppins labels, red
/// label-width underline, full-width divider) — the single source for
/// the embedded strip, the pinned-sliver delegate and the app-bar
/// [OdooArchTabStrip].
Widget archStripTabBar(ThemeData theme, List<String> labels) {
  // Tabs are sized ≈ (labels.length − 1) per viewport so the row
  // always overflows and the strip is guaranteed slidable on every
  // screen width — numeric minimums (~80dp) quietly fit on wide
  // screens and leave the bar full-width / unscrollable. The cap
  // keeps desktop windows sane; the floor keeps chatty labels
  // readable. Plain inheriting Text keeps the selected/unselected
  // label + color animation from the TabBar's _TabStyle wrapper.
  return LayoutBuilder(
    builder: (context, constraints) {
      return TabBar(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: theme.dividerColor,
        labelColor: theme.colorScheme.onSurface,
        unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        tabs: [
          for (final label in labels)
            Tab(
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: 80),
                child: Center(child: Text(label)),
              ),
            ),
        ],
      );
    },
  );
}

/// Detail tab strip as a [PreferredSizeWidget] for app-bar `bottom:`
/// sections (e.g. CollapsingAppBarPage). Must live below a
/// DefaultTabController with [labels].length so the [TabBar] can
/// resolve the controller; pair it with
/// [OdooArchDetailView.computeTabLabels].
class OdooArchTabStrip extends StatelessWidget implements PreferredSizeWidget {
  final List<String> labels;

  const OdooArchTabStrip({super.key, required this.labels});

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      height: 48,
      child: archStripTabBar(theme, labels),
    );
  }
}

// ── form-header stage pipeline (statusbar) ───────────────────────────────────

/// Web form-header statusbar (`<field name="stage_id"
/// widget="statusbar"/>`): the task's stage path with the active
/// stage in the app primary color and grey chevron separators —
/// `New › Ongoing › Completed`.
class _StagePipeline extends StatelessWidget {
  final List<Map<String, dynamic>> stages;

  /// Display name of the record's current stage (matches by name, the
  /// same text the hydrated many2one carries).
  final String? currentName;

  const _StagePipeline({required this.stages, required this.currentName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A single entry is allowed: it is the degraded fallback showing the
    // record's own stage when the stage-table RPC never came back.
    if (stages.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < stages.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  PhosphorIconsRegular.caretRight,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ),
            _buildStageText(theme, stages[i]),
          ],
        ],
      ),
    );
  }

  /// Current stage = its configured stage color (or the app's brand
  /// primary when the server stage carries none) with its duration
  /// badge in the same hue; other stages are muted but keep their own
  /// badges — `New 11h › Ongoing 45m › Completed 9m`.
  /// Active detection prefers the explicit `current` flag the screen
  /// computes from the record's `stage_id` many2one id — name
  /// comparison stays as a fallback because hydrated display names
  /// may drift from the configured stage label.
  Widget _buildStageText(ThemeData theme, Map<String, dynamic> stage) {
    final name = stage['name']?.toString() ?? '';
    final active =
        stage['current'] == true || (currentName != null && name == currentName);
    final colorIndex = stage['color'] is num ? (stage['color'] as num).toInt() : 0;
    // Current stage: its configured stage color when the server sets
    // one, otherwise the app's PRIMARY brand color — the green
    // `statusDone` reads as a checkbox "done", not as the highlight.
    final activeColor =
        (colorIndex > 0 ? _stageColor(colorIndex) : AppColors.primary) ??
        AppColors.primary;
    final duration = stage['duration']?.toString();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style: GoogleFonts.poppins(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: active
                ? activeColor
                : theme.colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
        if (duration != null && duration.isNotEmpty) ...[
          const SizedBox(width: 5),
          Text(
            duration,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active
                  ? activeColor.withValues(alpha: 0.95)
                  : theme.colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ],
    );
  }

  /// Odoo's stage color palette (the `color` integer on
  /// project.task.type, mirroring the web tag colors).
  static Color? _stageColor(int index) => switch (index) {
        1 => const Color(0xFFEA3E36), // red
        2 => const Color(0xFFFF7C28), // orange
        3 => const Color(0xFFD09600), // gold/yellow
        4 => const Color(0xFF00A3A3), // teal
        5 => const Color(0xFF29B6F6), // light blue
        6 => const Color(0xFFF45B69), // pink
        7 => const Color(0xFF8B5CF6), // violet
        8 => const Color(0xFF00C853), // green
        9 => const Color(0xFFF7941D), // burnt orange
        10 => const Color(0xFF9E9E9E), // slate
        _ => null,
      };
}

// ── pinned tab-strip header (sticky mode) ────────────────────────────────────

/// Pinned [SliverPersistentHeaderDelegate] showing the same styled
/// [TabBar] as the embedded strip. The bar resolves its
/// DefaultTabController itself, so the delegate only needs the labels.
///
/// Use it wherever the strip must pin directly (CustomScrollView
/// bodies without NestedScrollView quirks):
/// ```dart
/// SliverPersistentHeader(
///   pinned: true,
///   delegate: OdooArchTabStripDelegate(labels: tabLabels),
/// )
/// ```
class OdooArchTabStripDelegate extends SliverPersistentHeaderDelegate {
  final List<String> labels;

  const OdooArchTabStripDelegate({required this.labels});

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    return Container(
      // Solid background so the scrolling pane slides under a clean,
      // opaque strip instead of behind see-through labels.
      color: theme.scaffoldBackgroundColor,
      child: archStripTabBar(theme, labels),
    );
  }

  @override
  bool shouldRebuild(covariant OdooArchTabStripDelegate oldDelegate) =>
      oldDelegate.labels.length != labels.length ||
      oldDelegate.labels.join('|') != labels.join('|');
}

// ── web_ribbon (e.g. "Archived") ────────────────────────────────────────────

class _RibbonBanner extends StatelessWidget {
  final String title;

  const _RibbonBanner(this.title);

  @override
  Widget build(BuildContext context) {
    // No outer padding here — call sites wrap it with the shared screen
    // padding so it aligns with field cards above and below.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIconsRegular.warningCircle,
            size: 16,
            color: Colors.redAccent.shade200,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.redAccent.shade200,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── one2many record mini-list (web's inline <tree>, mobile-flavoured) ───────

class _RecordList extends StatelessWidget {
  final String label;
  final dynamic records; // List<Map> from parseDetailRecord, or null
  final Map<String, String> columnHints; // tree column order + labels
  final Map<String, dynamic> fieldDefs;

  const _RecordList({
    required this.label,
    required this.records,
    required this.columnHints,
    required this.fieldDefs,
  });

  /// display value of one record map for one tree column.
  String _cell(Map rec, String key) {
    final v = rec[key];
    if (v is List) {
      return v.length == 2 ? v[1].toString() : v.join(', ');
    }
    if (v is num) {
      // Hours/duration columns render as Odoo float_time ("02:30").
      final k = key.toLowerCase();
      final isHours = k.contains('hour') || k == 'unit_amount';
      return isHours ? ArchFmt.hours(v) : ArchFmt.number(v);
    }
    final s = v?.toString() ?? '';
    return s;
  }

  String _line(Map rec) {
    final keys = columnHints.keys
        .where((k) => k != 'sequence' && rec.containsKey(k) && rec[k] != null)
        .toList();
    final cells = [
      for (final k in keys)
        if (_cell(rec, k).trim().isNotEmpty) _cell(rec, k),
    ];
    if (cells.isEmpty && rec['display_name'] != null) {
      return rec['display_name'].toString();
    }
    return cells.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = records is List ? records as List : const <dynamic>[];

    if (items.isEmpty) {
      // Empty state mirrors the record-card geometry exactly — count
      // row, same card shell and 13.5pt/12px inset as the rows below —
      // so the placeholder aligns with values in every other pane
      // instead of a bare flush-left "None".
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelRow(theme, count: 0),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              'None',
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      );
    }

    final rows = <Widget>[
      for (var i = 0; i < items.length; i++)
        if (items[i] is Map)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _line(items[i] as Map),
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  PhosphorIconsRegular.caretRight,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                ),
              ],
            ),
          ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label + record count share one row (count right-aligned).
        _labelRow(theme, count: items.length),
        const SizedBox(height: 10),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.25),
                ),
              ),
              child: r,
            ),
          ),
      ],
    );
  }

  /// Section label with the optional record count sitting on the same
  /// row (right-aligned), baseline-aligned with the label text.
  Widget _labelRow(ThemeData theme, {int? count}) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Expanded(
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (count != null)
        Text(
          '$count ${count == 1 ? 'record' : 'records'}',
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
    ],
  );
}

// ── Arch tree model + parser ─────────────────────────────────────────────────

enum _ArchKind {
  group,
  notebook,
  field,
  container,
  statButtons,
  statButton,
  ribbon,
}

/// One arch node rendered by the view: a group container, a notebook of
/// pages, a single field, a plain div/span container, a stat-info
/// button, or a stat-button box.
class _ArchNode {
  final _ArchKind kind;
  final String? name;
  final String? title;
  final Map<String, String> attrs;
  final List<_ArchNode> children = [];
  String? widget;
  int notebookKey = 0;
  bool isPage = false;

  /// Inline `<tree>`/`<list>`/`<kanban>` column order for x2many fields:
  /// column name → string label. Lets [_RecordList] render the same
  /// cells the web list shows.
  final Map<String, String> treeHints = {};

  _ArchNode(this.kind, this.name, this.title, this.attrs);
}

/// Parses a form arch into ordered top nodes, skipping chrome
/// (`header`, `footer`, `label`, `button`, `i`, `t`…) and carrying attrs
/// for visibility evaluation. Deterministic document order.
class OdooArchLayoutParser {
  final String arch;
  int _notebookSeq = 0;

  OdooArchLayoutParser(this.arch);

  List<_ArchNode> _parseNodes() {
    final doc = XmlDocument.parse(arch);
    List<XmlElement> roots;
    final form = doc.childElements.firstWhere(
      (e) => e.name.local == 'form',
      orElse: () => doc.childElements.isEmpty
          ? throw StateError('No elements in arch')
          : doc.childElements.first,
    );
    final sheet = form.getElement('sheet');
    // The form <header> (statusbar / statusbar_duration widgets — the
    // stage pipeline row) is a SIBLING of the sheet in Odoo form
    // archs. Parsing used to walk only the sheet's children, so the
    // header — and with it the stage pipeline — never reached the
    // renderer at all. Header nodes go first, like the web layout
    // (statusbar above the sheet content).
    final headers = sheet == null
        ? const <XmlElement>[]
        : form.childElements
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'header');
    final body = sheet ?? form;
    roots = [
      ...headers,
      ...body.childElements.whereType<XmlElement>().where(
            (e) => _isVisibleTopTag(e) || e.name.local == 'header',
          ),
    ].toList();

    final nodes = <_ArchNode>[];
    for (final el in roots) {
      final node = _visitElement(el);
      if (node != null) nodes.add(node);
    }
    return nodes;
  }

  /// Top-level tags that produce nodes: containers (group), the
  /// notebook, fields, and — since divs carry real fields — div/span
  /// and web_ribbon widgets too. `header`/`footer`/misc stay skipped.
  static const Set<String> _containerTags = {
    'group',
    'notebook',
    'div',
    'span',
  };
  static bool _isVisibleTopTag(XmlElement el) =>
      _containerTags.contains(el.name.local) ||
      el.name.local == 'field' ||
      el.name.local == 'widget';

  /// Generic visit used at top level AND when recursing containers.
  _ArchNode? _visitElement(XmlElement el) {
    switch (el.name.local) {
      case 'group':
        return _visitGroup(el);
      case 'notebook':
        return _visitNotebook(el);
      case 'header':
        return _visitHeader(el);
      case 'field':
        return _visitField(el);
      case 'div':
      case 'span':
        return _visitContainer(el);
      case 'widget':
        if (el.getAttribute('name') == 'web_ribbon') {
          return _ArchNode(
            _ArchKind.ribbon,
            null,
            el.getAttribute('title'),
            <String, String>{'invisible': el.getAttribute('invisible') ?? ''},
          );
        }
        return null;
      default:
        // label, button, i, t, h1, strong, template, kanban, tree…
        // — pure chrome / view-definitions, no record data to show.
        return null;
    }
  }

  /// Plain div/span subtree. Wrapper divs in Odoo archs carry real
  /// content (Allocated Time + progress inside `.text-nowrap`, the
  /// deadline row, …) — they render as flattened mobile rows. Pure
  /// chrome (`oe_title`, `oe_chatter`, `oe_button_box`) is either
  /// skipped or lifted into its own design.
  _ArchNode? _visitContainer(XmlElement el) {
    final cls = el.getAttribute('class') ?? '';
    final id = el.getAttribute('id') ?? '';
    if (el.name.local == 'div' &&
        (cls.contains('oe_title') ||
            cls.contains('oe_chatter') ||
            id == 'date_deadline_placeholder')) {
      return null;
    }
    if (el.name.local == 'div' && cls.contains('oe_button_box')) {
      return _visitStatButtons(el);
    }

    final node = _ArchNode(_ArchKind.container, null, null, _attrs(el));
    for (final child in el.childElements) {
      final childNode = _visitElement(child);
      if (childNode != null) node.children.add(childNode);
    }
    return node;
  }

  /// Form `<header>`: carries the statusbar widgets — the stage
  /// pipeline (`stage_id`) and the state switcher (`state`, whose
  /// duplicate row the renderer collapses in favour of the screen's
  /// own badge). Everything else inside is plain chrome.
  _ArchNode? _visitHeader(XmlElement el) {
    final node = _ArchNode(_ArchKind.container, null, null, _attrs(el));
    for (final child in el.childElements) {
      if (child.name.local != 'field') continue;
      // Accept both the plain statusbar and the Odoo 19
      // statusbar-with-time variant (`statusbar_duration`) — the
      // original arch's stage_id uses it, and dropping it silently
      // removed the whole stage pipeline from mobile.
      final widgetName = child.getAttribute('widget') ?? '';
      if (widgetName != 'statusbar' && widgetName != 'statusbar_duration') {
        continue;
      }
      final n = _visitField(child);
      if (n != null) node.children.add(n);
    }
    return node.children.isEmpty ? null : node;
  }

  /// `oe_button_box` → [_ArchKind.statButtons] with one statButton per
  /// button (label from `string` / the `o_stat_text` span).
  _ArchNode _visitStatButtons(XmlElement el) {
    final node = _ArchNode(_ArchKind.statButtons, null, null, _attrs(el));
    for (final button in el.childElements.whereType<XmlElement>().where(
      (e) => e.name.local == 'button',
    )) {
      final b = _visitStatButton(button);
      if (b != null) node.children.add(b);
    }
    return node;
  }

  _ArchNode? _visitStatButton(XmlElement button) {
    // First visible <field> inside the button carries the stat value
    // (e.g. subtask_count, rating_avg_text, recurring_count).
    String? fieldName;
    for (final f in button.descendantElements.whereType<XmlElement>().where(
      (e) => e.name.local == 'field',
    )) {
      final invisible = f.getAttribute('invisible');
      if (invisible == '1') continue;
      fieldName = f.getAttribute('name');
      break;
    }
    if (fieldName == null) return null;

    // Label: button string attr > o_stat_text span > field name def.
    final statText = button.descendantElements
        .whereType<XmlElement>()
        .where(
          (e) =>
              (e.getAttribute('class') ?? '').contains('o_stat_text') &&
              (e.innerText.trim().isNotEmpty),
        )
        .map((e) => e.innerText.trim())
        .toList();

    String? iconClass;
    for (final e in button.descendantElements) {
      final cls = e.getAttribute('class') ?? '';
      if (cls.contains('fa-')) {
        iconClass = cls;
        break;
      }
    }

    return _ArchNode(
      _ArchKind.statButton,
      fieldName,
      button.getAttribute('string') ??
          (statText.isNotEmpty ? statText.first : null),
      _attrs(button),
    )..widget = iconClass;
  }

  _ArchNode _visitGroup(XmlElement el) {
    final node = _ArchNode(_ArchKind.group, null, _headingOf(el), _attrs(el));
    _fill(el, node);
    return node;
  }

  _ArchNode _visitNotebook(XmlElement el) {
    final node = _ArchNode(_ArchKind.notebook, null, null, _attrs(el));
    node.notebookKey = _notebookSeq++;
    for (final page in el.findElements('page').toList()) {
      final pageNode = _ArchNode(
        _ArchKind.group,
        null,
        _headingOf(page),
        _attrs(page),
      )..isPage = true;
      _fill(page, pageNode);
      node.children.add(pageNode);
    }
    return node;
  }

  _ArchNode? _visitField(XmlElement el) {
    final name = el.getAttribute('name');
    if (name == null) return null;
    final fieldNode = _ArchNode(
      _ArchKind.field,
      name,
      el.getAttribute('string'),
      _attrs(el),
    );
    fieldNode.widget = el.getAttribute('widget');
    for (final sub in el.childElements) {
      final local = sub.name.local;
      // Inline x2many view: Odoo ≤ 17 writes <tree>, Odoo 18+ renamed
      // the same tag to <list>. Both spellings are accepted here.
      if (local == 'tree' || local == 'list' || local == 'kanban') {
        for (final tf in sub.findAllElements('field')) {
          final n = tf.getAttribute('name');
          if (n != null && !fieldNode.treeHints.containsKey(n)) {
            fieldNode.treeHints[n] = tf.getAttribute('string') ?? '';
          }
        }
        break; // first view definition wins
      }
    }
    return fieldNode;
  }

  /// Recursively fills [node] from an arbitrary container element
  /// (group root / page), recursing into divs/spans and applying the
  /// per-widget designs for the innermost visible nodes.
  void _fill(XmlElement element, _ArchNode node) {
    for (final child in element.childElements) {
      switch (child.name.local) {
        case 'field':
          final fieldNode = _visitField(child);
          if (fieldNode != null) node.children.add(fieldNode);
        case 'group':
          node.children.add(_visitGroup(child));
        case 'notebook':
          node.children.add(_visitNotebook(child));
        case 'div':
        case 'span':
          final container = _visitContainer(child);
          if (container != null) node.children.add(container);
        case 'widget':
          if (child.getAttribute('name') == 'web_ribbon') {
            node.children.add(
              _ArchNode(
                _ArchKind.ribbon,
                null,
                child.getAttribute('title'),
                <String, String>{
                  'invisible': child.getAttribute('invisible') ?? '',
                },
              ),
            );
          }
        default:
          break; // labels, buttons, imgs, t templates ignored
      }
    }
  }

  /// Element attributes as a plain string map (local names only).
  static Map<String, String> _attrs(XmlElement el) {
    return {for (final a in el.attributes) a.name.local: a.value};
  }

  /// Section heading from `string` (classic) or `title` (Odoo 17+).
  static String? _headingOf(XmlElement el) =>
      el.getAttribute('string') ?? el.getAttribute('title');
}

/// Visibility + pruning engine shared by the embedded renderer and
/// [OdooArchDetailView.computeTabLabels] — sticky screens that must
/// know the visible tab labels outside the renderer widget itself
/// (e.g. to build the strip in the app bar's `bottom:` slot).
class _ArchPruner {
  final Map<String, dynamic> defs;
  final Map<String, dynamic> values;

  const _ArchPruner(this.defs, this.values);

  /// Applies visibility rules + drops empty containers. Returns null
  /// when the node should not render at all.
  _ArchNode? prune(_ArchNode node) {
    if (isHidden(node.attrs)) {
      return null;
    }
    final copy = _ArchNode(node.kind, node.name, node.title, node.attrs)
      ..children.addAll(node.children)
      ..notebookKey = node.notebookKey
      ..widget = node.widget
      ..isPage = node.isPage
      ..treeHints.addAll(node.treeHints);

    if (node.kind == _ArchKind.field) {
      if (node.name == null || !defs.containsKey(node.name)) {
        return null;
      }
      if (OdooDetailSections.isNoiseKey(node.name!)) return null;
      // NOTE: unlike before, empty fields still render — the web client
      // shows every field in the arch (with an empty input), and pruning
      // value-less fields used to delete whole <page>/<group> containers
      // whenever the record's values happened to be empty (losing the
      // Description / Timesheets / Sub-tasks tabs, Tags, Customer…).
    } else {
      final kept = <_ArchNode>[];
      for (final c in copy.children) {
        final prunedChild = prune(c);
        if (prunedChild != null) kept.add(prunedChild);
      }
      copy.children
        ..clear()
        ..addAll(kept);
      // An empty notebook page keeps its tab — the web client shows
      // empty tabs too. Plain empty groups / containers are dropped.
      if (copy.children.isEmpty) {
        return node.isPage || node.kind == _ArchKind.statButton ? copy : null;
      }
    }
    return copy;
  }

  /// True when a node's conditions say it should not be shown.
  bool isHidden(Map<String, String> attrs) {
    // Security groups constraint (`groups="base.group_no_one"` etc):
    // nodes carrying a groups= flag are technical/admin-gated content.
    // The user's group membership isn't evaluated client-side, and the
    // CONFIRMED default is to hide them — matching a regular
    // (non-technical) account on the web. The Extra Info tab, for
    // example, stays hidden (owner confirmed 2026-10-25).
    final groups = attrs['groups']?.trim();
    if (groups != null && groups.isNotEmpty) return true;

    final expr = (attrs['invisible'] ?? attrs['column_invisible'])?.trim();
    if (expr != null && expr.isNotEmpty) {
      if (expr == '1' || expr == 'True') return true;
      if (expr != '0' && expr != 'False') {
        // Resolved true → hidden; unresolvable → visible (safe default).
        return _evalExpr(expr) == true;
      }
    }

    // Legacy attrs="{'invisible': [[cond]]}" — flat AND only; anything
    // with RPN ('|'/'&') or unknown ops falls back to visible.
    final legacy = attrs['attrs'];
    if (legacy != null) {
      final decoded = _decodeLegacyAttrs(legacy);
      if (decoded != null && decoded.containsKey('invisible')) {
        final clauses = decoded['invisible'];
        if (clauses is List && clauses.isNotEmpty) {
          if (clauses.any((c) => c is! List)) return false; // RPN — bail
          var and = true;
          for (final c in clauses.cast<List>()) {
            if (c.length != 3) {
              and = false;
              break;
            }
            if (!_evalDomainClause(c[0]?.toString(), c[1]?.toString(), c[2])) {
              and = false;
              break;
            }
          }
          return and;
        }
      }
    }
    return false;
  }

  /// Python-ish boolean expression from Odoo 17+ arch. Returns null when
  /// a part cannot be confidently resolved.
  bool? _evalExpr(String expr) {
    final orParts = expr.split(RegExp(r'\s+or\s+'));
    bool someTrue = false;
    var allKnown = true;
    for (final part in orParts) {
      final plural = _evalAndChain(part);
      if (plural == null) {
        allKnown = false;
        continue;
      }
      if (plural == true) {
        someTrue = true;
        break;
      }
    }
    if (!allKnown && !someTrue) return null;
    return someTrue;
  }

  bool? _evalAndChain(String expr) {
    final andParts = expr.split(RegExp(r'\s+and\s+'));
    var result = true;
    for (final p in andParts) {
      final v = _evalAtom(p.trim());
      if (v == null) return null;
      if (v == false) result = false;
    }
    return result;
  }

  bool? _evalAtom(String atom) {
    final s = atom.trim();
    if (s.isEmpty) return null;

    if (s.startsWith('not ')) {
      final inner = _evalAtom(s.substring(4));
      return inner == null ? null : !inner;
    }

    final inMatch = RegExp(r'^(.+?)\s+(not\s+in|in)\s+\[(.*)\]$').firstMatch(s);
    if (inMatch != null) {
      final fieldVal = _fieldString(inMatch.group(1)!.trim());
      if (fieldVal == null) return null;
      final items = RegExp("'([^']*)'|\"([^\"]*)\"")
          .allMatches(inMatch.group(3) ?? '')
          .map((m) => m.group(1) ?? m.group(2))
          .whereType<String>()
          .toList();
      final contains = items.contains(fieldVal);
      return inMatch.group(2)!.startsWith('not') ? !contains : contains;
    }

    final cmp = RegExp(r'^(.+?)\s*(==|!=)\s*(.+)$').firstMatch(s);
    if (cmp != null) {
      final fieldVal = _fieldString(cmp.group(1)!.trim());
      if (fieldVal == null) return null;
      final rhs = _literalValue(cmp.group(3)!.trim());
      if (rhs == null) return null;
      final equal = fieldVal == rhs;
      return cmp.group(2) == '==' ? equal : !equal;
    }

    // Bare field → truthiness.
    return _truthy(s);
  }

  /// Field value as normalised text for comparisons; null when the
  /// expression variable isn't a known record field.
  /// Odoo semantics: an unset / false value *is* False in arch
  /// expressions. Returning '' used to flip `X != False` comparisons
  /// to true, which silently hid fields whose value is simply empty
  /// (e.g. Allocated Time / Deadline on fresh tasks).
  String? _fieldString(String lhs) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_.]*$').hasMatch(lhs)) return null;
    if (!defs.containsKey(lhs)) return null;
    return _domainText(values[lhs]);
  }

  /// Normalises any record/server value into Python-literal text
  /// ('True' / 'False' / quoted strings / numbers) for comparisons —
  /// booleans arrive as 'true'/'false' (Dart), JSON false, or absent.
  static String _domainText(dynamic v) {
    if (v == null || v == false) return 'False';
    if (v == true) return 'True';
    final t = v.toString();
    if (t == 'true') return 'True';
    if (t == 'false' || t.isEmpty) return 'False';
    return t;
  }

  /// Quoted string / True / False / number → comparable text; else null.
  static String? _literalValue(String raw) {
    var r = raw;
    if (r.startsWith("'") && r.endsWith("'") && r.length >= 2) {
      return r.substring(1, r.length - 1);
    }
    if (r.startsWith('"') && r.endsWith('"') && r.length >= 2) {
      return r.substring(1, r.length - 1);
    }
    if (r == 'True') return 'True';
    if (r == 'False') return 'False';
    if (double.tryParse(r) != null) return r;
    return null;
  }

  /// Domain-style clause [field, op, value] against the record, with
  /// Odoo's unset-is-False semantics and case-normalised booleans.
  bool _evalDomainClause(String? field, String? op, dynamic value) {
    if (field == null || op == null) return false;
    final text = _domainText(values[field]);
    switch (op) {
      case '=':
        return text == _domainText(value);
      case '!=':
        return text != _domainText(value);
      case 'in':
        return value is List ? value.any((e) => _domainText(e) == text) : false;
      case 'not in':
        return value is List ? !value.any((e) => _domainText(e) == text) : true;
      default:
        return false;
    }
  }

  /// `{'invisible': [...]}` — python-literal dict; normalise quotes and
  /// decode defensively. Only respected when it actually matches JSON.
  static Map<String, dynamic>? _decodeLegacyAttrs(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      try {
        return jsonDecode(raw.replaceAll("'", '"'));
      } catch (_) {
        return null;
      }
    }
  }

  /// True when the record value is truthy (python-ish: False/''/0/[] →
  /// false); null when the field isn't in the record at all.
  bool? _truthy(String field) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_.]*$').hasMatch(field)) return null;
    if (!defs.containsKey(field)) return null;
    final v = values[field];
    if (v == null || v == false) return false;
    if (v is String && v.trim().isEmpty) return false;
    if (v is num && v == 0) return false;
    if (v is List && v.isEmpty) return false;
    return true;
  }
}
