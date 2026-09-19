import 'package:flutter_test/flutter_test.dart';

import 'package:explore_mobile/main.dart';

void main() {
  testWidgets('renders the Explore home screen without mock data', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExploreApp());

    expect(find.text('${greetingFor(DateTime.now())} ✦'), findsOneWidget);
    expect(find.text('当前主目标'), findsWidgets);
    expect(find.text('还没有目标'), findsOneWidget);
    expect(find.text('成为 AI 时代的独立创造者'), findsNothing);
  });

  testWidgets('chat page is a first-level page without a back button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExploreApp());

    await tester.tap(find.text('对话'));
    await tester.pumpAndSettle();

    // 对话是底部导航的一级页面,回首页走底部导航,头部不放返回按钮
    expect(find.byTooltip('返回首页'), findsNothing);
    expect(find.byTooltip('历史会话'), findsOneWidget);
  });

  testWidgets('goal create back returns to the page it was opened from', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExploreApp());

    // 从首页进入：返回按钮是「返回首页」，点击回到首页
    await tester.ensureVisible(find.text('创建第一个目标'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建第一个目标'));
    await tester.pumpAndSettle();

    expect(find.text('与探境共创目标'), findsOneWidget);
    expect(find.text('返回首页'), findsOneWidget);

    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();

    expect(find.text('${greetingFor(DateTime.now())} ✦'), findsOneWidget);

    // 从成长页进入：返回按钮保持「返回目标」，点击回到成长页
    await tester.tap(find.text('成长'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('＋ 新建目标'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('＋ 新建目标'));
    await tester.pumpAndSettle();

    expect(find.text('返回目标'), findsOneWidget);

    await tester.tap(find.text('返回目标'));
    await tester.pumpAndSettle();

    // 成长页大标题页首已并入顶栏，用「当前专注」卡片锚点确认落地
    expect(find.text('当前专注'), findsOneWidget);
  });

  testWidgets('swiping from the left edge goes back on sub pages', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExploreApp());

    // 从首页进入目标创建页
    await tester.ensureVisible(find.text('创建第一个目标'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建第一个目标'));
    await tester.pumpAndSettle();

    expect(find.text('与探境共创目标'), findsOneWidget);

    // 从左边缘向右滑，应返回进入前的首页
    await tester.dragFrom(const Offset(10, 300), const Offset(220, 0));
    await tester.pumpAndSettle();

    expect(find.text('${greetingFor(DateTime.now())} ✦'), findsOneWidget);

    // 一级页面不启用边缘手势：再滑也不会离开首页
    await tester.dragFrom(const Offset(10, 300), const Offset(220, 0));
    await tester.pumpAndSettle();

    expect(find.text('${greetingFor(DateTime.now())} ✦'), findsOneWidget);
  });
}
