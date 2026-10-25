import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double topPad = 24;
const double barH = 56;
const double bottomH = 48;
const double expanded = 120;

/// Replicates _CollapsingHeaderDelegate shape: [bar row, collapsing
/// region, bottom strip] inside a pinned SliverPersistentHeader that
/// sits in a NestedScrollView's outer header — the real task-screen
/// layout.
class TestDelegate extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => topPad + barH + bottomH;

  @override
  double get maxExtent => topPad + barH + expanded + bottomH;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final Widget strip = Container(
      height: bottomH,
      color: Colors.amber,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: Colors.red,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        tabs: [
          for (final l in const [
            'Details',
            'Description',
            'Timesheets',
            'Sub-tasks',
          ])
            Tab(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 112),
                child: Center(child: Text(l)),
              ),
            ),
        ],
      ),
    );
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          SizedBox(height: topPad, width: double.infinity),
          SizedBox(height: barH, width: double.infinity),
          const Expanded(child: SizedBox()),
          strip,
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant TestDelegate oldDelegate) => true;
}

void main() {
  testWidgets(
      'pinned outer-header bottom strip is horizontally swipeable',
      (tester) async {
    tester.view.physicalSize = const Size(400, 940);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      DefaultTabController(
        length: 4,
        child: MaterialApp(
          home: NestedScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverPersistentHeader(
                pinned: true,
                delegate: TestDelegate(),
              ),
            ],
            body: ListView(
              children: const [SizedBox(height: 1600)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scroller = tester.widget<SingleChildScrollView>(
      find
          .descendant(
            of: find.byType(TabBar),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    final position = scroller.controller!.positions.first;
    // ignore: avoid_print
    print('maxScrollExtent with overflow: ${position.maxScrollExtent}');
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.drag(
      find.byType(TabBar).first,
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();

    // ignore: avoid_print
    print('pixels after drag: ${position.pixels}');
    expect(position.pixels, greaterThan(0));
  });
}
