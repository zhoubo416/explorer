import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:explore_mobile/main.dart';

/// 用有数据的 store 渲染各个页面，在真机尺寸下捕捉布局溢出。
/// 溢出会以 FlutterError 的形式让测试失败，并打印出具体组件树。
void main() {
  ExploreStore seededStore() {
    final store = ExploreStore();
    store.goals.add(
      Goal(
        id: 'g1',
        title: '成为 AI 时代的独立创造者',
        description: '用一个真实产品验证创造方向',
        phase: '验证期',
        progress: 35,
        status: '进行中',
        icon: Icons.adjust_rounded,
        accent: const Color(0xFF6658E8),
        milestone: '90 天完成一个 AI 产品 MVP 并获得 10 个用户反馈',
        rawStatus: 'active',
        stages: [
          {
            'id': 's1',
            'name': '第一阶段：用户验证',
            'description': '找到真实的用户问题，而不是自己想做的功能。',
            'status': 'active',
            'actions': [
              {'id': 'a1', 'content': '完成 10 次用户访谈', 'done': false},
              {'id': 'a2', 'content': '整理访谈结论并更新方向', 'done': true},
            ],
          },
        ],
      ),
    );
    store.selectedGoalId = 'g1';
    store.timelineSummary = '这段时间你从学习转向了创造，开始用真实反馈检验想法。';
    for (var i = 0; i < 6; i++) {
      store.memories.add(
        MemoryItem(
          date: '今天 10:0$i',
          month: '9 月',
          type: i.isEven ? '关键决定' : '反思',
          title: '决定从真实用户反馈开始验证产品方向',
          detail: '内容',
          icon: Icons.auto_awesome_rounded,
          tone: const Color(0xFF6658E8),
        ),
      );
    }
    for (var i = 0; i < 8; i++) {
      store.conversations.add(
        ConversationSummary(
          id: 'c$i',
          title: '和探境聊聊关于产品方向与长期成长的话题 $i',
          date: '9/$i',
          preview: '我最近在想，是不是应该先把方向收窄一点。',
          messages: const [],
        ),
      );
    }
    store.observations.add({
      'id': 'o1',
      'content': '最近 30 天你持续关注 AI 产品，这可能是你正在探索的新方向。',
    });
    store.actions.add({
      'id': 'act1',
      'content': '你已经有一段时间没有推进主目标了，要不要聊聊遇到的困难？',
    });
    store.dailySuggestion = '完成一次用户交流';
    store.profile = {
      'ai_summary': '你是一个愿意长期投入的创造者，正在从学习转向真实产品验证。',
      'personality': ['理性', '自驱'],
      'values': ['创造', '自由'],
      'interests': ['AI 产品', '写作'],
      'strengths': ['学习能力', '执行力'],
      'weaknesses': ['容易目标过多'],
      'growth_dimensions': [
        {'name': '技术能力', 'score': 72, 'evidence': '完成了 Agent Demo'},
        {'name': '产品能力', 'score': 45, 'evidence': '开始做用户访谈'},
        {'name': '商业能力', 'score': 28, 'evidence': '尚未验证付费意愿'},
      ],
      'growth_composition': [
        {'name': '学习', 'ratio': 55, 'insight': '投入最多'},
        {'name': '实践', 'ratio': 30, 'insight': '正在增加'},
        {'name': '连接', 'ratio': 15, 'insight': '偏少'},
      ],
    };
    store.weeklyReport = {
      'score': 4.0,
      'completed': ['完成 Agent Demo', '做了 5 次用户访谈'],
      'insight': '从学习转向创造，开始用真实反馈检验想法。',
      'next_steps': ['把方向收窄到一个场景'],
    };
    store.goalAnalysis = {
      'summary': '这个阶段你完成了从想法到 Demo 的跨越。',
      'observation': '实践比例在上升。',
      'suggestion': '下一步增加真实用户接触。',
      'actions': ['完成 10 次用户访谈'],
    };
    return store;
  }

  Future<void> pumpScreen(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump();
  }

  /// 在真实外壳（ExploreShell：根部 SafeArea + 底部导航）下渲染，并按机型注入
  /// 底部安全区高度——真机由系统给出，测试环境默认是 0，不注入就测不到安全区问题。
  Future<void> pumpShell(
    WidgetTester tester,
    ExploreStore store, {
    required Size size,
    required double safeBottom,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(bottom: safeBottom),
                viewPadding: media.viewPadding.copyWith(bottom: safeBottom),
              ),
              child: ExploreShell(store: store),
            );
          },
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('首页不溢出', (tester) async {
    await pumpScreen(tester, HomeScreen(store: seededStore()));
  });

  testWidgets('成长页-目标子页不溢出', (tester) async {
    final store = seededStore();
    store.setGrowthTab(GrowthTab.goal);
    await pumpScreen(tester, GrowthScreen(store: store));
  });

  testWidgets('成长页-记忆子页不溢出', (tester) async {
    final store = seededStore();
    store.setGrowthTab(GrowthTab.memory);
    await pumpScreen(tester, GrowthScreen(store: store));
  });

  testWidgets('记忆页不溢出', (tester) async {
    await pumpScreen(tester, MemoryScreen(store: seededStore()));
  });

  testWidgets('对话页不溢出', (tester) async {
    await pumpScreen(tester, ChatScreen(store: seededStore()));
  });

  testWidgets('会话历史面板不溢出', (tester) async {
    await pumpScreen(tester, ConversationHistorySheet(store: seededStore()));
  });

  testWidgets('我的页不溢出', (tester) async {
    await pumpScreen(tester, ReportScreen(store: seededStore()));
  });

  testWidgets('目标详情页不溢出', (tester) async {
    await pumpScreen(tester, GoalDetailScreen(store: seededStore()));
  });

  testWidgets('目标共创页不溢出', (tester) async {
    await pumpScreen(tester, GoalCreateScreen(store: seededStore()));
  });

  // 真机反馈（iPhone 15）：底部圆角与手势条下，共创目标页的输入框像被遮挡。
  // 根因是 Scaffold 的底部安全区被整页丢掉（见 _bottomNav 注释），这里在真实外壳
  // 下断言输入框仍落在安全区之上，并保留与其它页面输入框一致的 12pt 留白。
  testWidgets('目标共创页输入框在底部安全区之上留白', (tester) async {
    const size = Size(393, 852); // iPhone 15
    const safeBottom = 34.0;
    await pumpShell(tester, seededStore()..page = ExplorePage.goalCreate,
        size: size, safeBottom: safeBottom);
    final input = tester.getRect(find.byType(TextField));
    expect(
      input.bottom + 12,
      lessThanOrEqualTo(size.height - safeBottom + 0.5),
      reason: '输入框底边 ${input.bottom} 未在底部安全区（上沿 ${size.height - safeBottom}）之上留出 12pt',
    );
  });

  // 底部安全区扫描：各机型安全区高度差别很大（无手势条的 iPhone 为 0，带手势条机型 34，
  // 安卓手势导航 24，iPad 20，横屏 21），这里逐机型逐页扫一遍，任何可交互元素都不得
  // 落进底部不安全区（圆角与手势条所在的区域）。历史上共创目标页就是在这里出问题的：
  // 底部导航被换成零尺寸占位，Scaffold 因此把 body 的底部安全区一并去掉。
  // 覆盖 app 现有的可交互组件类型，新增组件类型时同步补进下面的列表。
  testWidgets('各机型下各页面都不落进底部安全区', (tester) async {
    const devices = <String, (Size, double)>{
      'iPhone SE 3（无手势条）': (Size(375, 667), 0),
      'iPhone 15': (Size(393, 852), 34),
      'iPhone 15 Pro Max': (Size(430, 932), 34),
      '安卓手势导航': (Size(412, 915), 24),
      'iPad mini': (Size(744, 1133), 20),
      'iPhone 15 横屏': (Size(852, 393), 21),
    };
    const pages = <String, ExplorePage>{
      '首页': ExplorePage.home,
      '成长': ExplorePage.growth,
      '对话': ExplorePage.chat,
      '我的': ExplorePage.report,
      '目标详情': ExplorePage.goalDetail,
      '共创目标': ExplorePage.goalCreate,
      '创建完成': ExplorePage.goalCreated,
    };
    final intrusions = <String>[];
    for (final device in devices.entries) {
      final (size, safeBottom) = device.value;
      final unsafeTop = size.height - safeBottom;
      for (final page in pages.entries) {
        await pumpShell(
          tester,
          seededStore()..page = page.value,
          size: size,
          safeBottom: safeBottom,
        );
        for (final finder in <Finder>[
          find.byType(TextField),
          find.byType(PrimaryButton),
          find.byType(CircleButton),
          find.byType(IconButton),
          find.byType(DetailTabButton),
          find.byType(InkWell),
        ]) {
          for (final element in finder.hitTestable().evaluate()) {
            final box = element.renderObject! as RenderBox;
            final rect = box.localToGlobal(Offset.zero) & box.size;
            if (rect.bottom > unsafeTop + 0.5) {
              intrusions.add(
                '${device.key} · ${page.key}：${element.widget.runtimeType} '
                '底边 ${rect.bottom.toStringAsFixed(1)} 越过不安全区上沿 $unsafeTop',
              );
            }
          }
        }
      }
    }
    expect(intrusions, isEmpty, reason: intrusions.join('\n'));
  });

  testWidgets('目标创建完成页不溢出', (tester) async {
    await pumpScreen(tester, GoalCreatedScreen(store: seededStore()));
  });

  testWidgets('低情绪对话不溢出', (tester) async {
    final store = seededStore();
    store.lowMood = true;
    await pumpScreen(tester, ChatScreen(store: store));
  });

  testWidgets('长标题不溢出', (tester) async {
    final store = seededStore();
    store.goals.first.title = '成为一个能够持续创造价值的独立开发者并影响更多人';
    store.goals.first.milestone =
        '在 90 天内完成一个可用的 AI 产品 MVP，获得至少 10 位真实用户的反馈，并据此完成一次方向调整';
    store.selectedGoalId = store.goals.first.id;
    await pumpScreen(tester, GoalDetailScreen(store: store));
  });

  // 真机曾出现 bottom overflowed by 160 pixels：消息多时面板不可滚动
  testWidgets('探境的消息面板不溢出（消息较多）', (tester) async {
    final store = seededStore();
    store.actions.clear();
    for (var i = 0; i < 12; i++) {
      store.actions.add({
        'id': 'act$i',
        'content': '你已经有一段时间没有推进主目标了，要不要聊聊遇到的困难？这是第 $i 条消息。',
      });
    }
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 铃铛在首页统一顶栏（ExploreAppBar）里，从整页进入保持真实入口
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: HomeScreen(store: store))),
    );
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();
    expect(find.text('探境的消息'), findsOneWidget);
  });

  testWidgets('对话页右上角的新增可以开启新对话', (tester) async {
    final store = seededStore();
    store.messages.add(
      ChatMessage(isUser: false, content: '上一轮对话的回复', time: '10:00'),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 真实 app 在根部用 AnimatedBuilder 监听 store，这里保持一致，否则 notifyListeners 不会触发重建
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: store,
            builder: (_, _) => ChatScreen(store: store),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('上一轮对话的回复'), findsOneWidget);

    await tester.tap(find.byTooltip('新增对话'));
    await tester.pump();

    expect(store.messages, isEmpty);
    expect(find.text('上一轮对话的回复'), findsNothing);
    // 新会话空态显示 AI 欢迎语（与目标共创的开场一致）
    expect(find.text(chatGreeting), findsOneWidget);
  });

  // 真机复现过崩溃：输入中直接切走页面，销毁时序导致
  // “TextEditingController was used after being disposed” 与
  // InheritedElement 的 _dependents.isEmpty 断言。这里用同样的
  // keyed 子树切换方式回归。
  testWidgets('输入中切换页面不崩溃', (tester) async {
    final store = seededStore();
    store.messages.addAll([
      ChatMessage(isUser: true, content: '最近有点迷茫', time: '21:30'),
      ChatMessage(
        isUser: false,
        content: '# 先聊聊方向\n\n- 你提到了迷茫\n- 我们从一件小事开始\n\n你可以**试试**这样。',
        time: '21:31',
      ),
      for (var i = 0; i < 3; i++)
        ChatMessage(
          isUser: false,
          content: '第 $i 条回复，带一段稍长的内容用来撑起列表，观察销毁是否正常。',
          time: '21:3$i',
        ),
    ]);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 复刻真实外壳：AnimatedBuilder 监听 store，KeyedSubtree 按 page 换子树
    Widget shell() => MaterialApp(
      home: Scaffold(
        body: AnimatedBuilder(
          animation: store,
          builder: (_, _) => KeyedSubtree(
            key: ValueKey(store.page),
            child: store.page == ExplorePage.chat
                ? ChatScreen(store: store)
                : HomeScreen(store: store),
          ),
        ),
      ),
    );

    store.page = ExplorePage.chat;
    await tester.pumpWidget(shell());
    await tester.pump();
    expect(find.text('可以这样开始'), findsOneWidget);

    // 聚焦并输入 → 建议区收起
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '我');
    await tester.pump();
    expect(find.text('可以这样开始'), findsNothing);

    // 从底部导航切走：keyed 子树整体替换，输入中的 TextField 一并销毁
    store.goToPage(ExplorePage.home);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // 真机反馈「最新消息显示在最上面」：验证渲染几何——进入对话页后，
  // 最新消息必须落在屏幕底部（可视区内），旧消息在上方（长列表时不可见）
  testWidgets('对话页最新消息显示在底部', (tester) async {
    final store = seededStore();
    store.messages.addAll([
      for (var i = 0; i < 30; i++)
        ChatMessage(isUser: true, content: '消息序号 $i', time: '21:30'),
    ]);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: store,
            builder: (_, _) => ChatScreen(store: store),
          ),
        ),
      ),
    );
    await tester.pump();

    // 最新消息在可视区内，且比更旧的已构建消息更靠屏幕下方
    expect(find.text('消息序号 28'), findsOneWidget);
    final newest = tester.getRect(find.text('消息序号 28'));
    final older = tester.getRect(find.text('消息序号 24'));
    expect(newest.top, greaterThan(older.top));
    // 足够旧的消息被收起在可视区上方之外（未构建）
    expect(find.text('消息序号 0'), findsNothing);
  });

  // 真机的实际时序：进入对话页时消息列表还是空/旧的，
  // refreshActiveConversation 异步完成后才填充。验证这种时序下
  // 视口仍停在最新消息处，而不是被顶到旧消息。
  testWidgets('数据异步到达时最新消息仍停在底部', (tester) async {
    final store = seededStore();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 先以空列表挂载（模拟刚进入对话页）
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: store,
            builder: (_, _) => ChatScreen(store: store),
          ),
        ),
      ),
    );
    await tester.pump();

    // 模拟刷新完成：消息一次性填充
    store.messages.addAll([
      for (var i = 0; i < 30; i++)
        ChatMessage(isUser: true, content: '消息序号 $i', time: '21:30'),
    ]);
    store.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('消息序号 28'), findsOneWidget);
    final newest = tester.getRect(find.text('消息序号 28'));
    final older = tester.getRect(find.text('消息序号 24'));
    expect(newest.top, greaterThan(older.top));
    // 视口应停在最新消息处：最旧的消息未被构建
    expect(find.text('消息序号 0'), findsNothing);
  });
}
