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
      'week_start': '8/10',
      'week_end': '8/16',
    };
    for (var i = 0; i < 3; i++) {
      store.reports.add({
        'week_start': '8/${10 + i * 7}',
        'week_end': '8/${16 + i * 7}',
        'score': 4.0 + i * 0.5,
        'completed': ['完成 Agent Demo'],
        'insight': '从学习转向创造，开始用真实反馈检验想法。',
        'next_steps': ['把方向收窄到一个场景'],
      });
    }
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

  /// 渲染单个面板 / 卡片（不套 ExploreShell），用于交互流程测试
  Future<void> pumpPanel(
    WidgetTester tester,
    Widget child, {
    bool settle = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
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
      '周报列表': ExplorePage.weeklyReports,
      '周报详情': ExplorePage.weeklyReportDetail,
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

  // 陪聊不是紧急求助渠道：陪伴模式必须给出明确兜底，不能只靠模型自觉
  testWidgets('低情绪模式显示紧急求助提示', (tester) async {
    final store = seededStore();
    store.lowMood = true;
    await pumpScreen(tester, ChatScreen(store: store));
    expect(
      find.textContaining('请立即联系当地急救电话或心理援助热线'),
      findsOneWidget,
    );

    store.lowMood = false;
    await pumpScreen(tester, ChatScreen(store: store));
    expect(
      find.textContaining('请立即联系当地急救电话或心理援助热线'),
      findsNothing,
    );
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

  // App Store 审核关注点：支持注册的 App 必须能在应用内删除账号（Guideline 5.1.1(v)），
  // 且这类不可逆操作要有二次确认。这组用例钉住入口与确认流程。
  testWidgets('我的页有法务与删除账号入口', (tester) async {
    await pumpPanel(tester, AccountActionsCard(store: seededStore()));
    for (final label in ['隐私政策', '用户协议', '意见反馈 / 内容举报', '删除账号']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('删除账号需要二次确认，取消后账号仍在', (tester) async {
    await pumpPanel(tester, AccountActionsCard(store: seededStore()));
    await tester.tap(find.text('删除账号'));
    await tester.pumpAndSettle();

    expect(
      find.text('账号与全部数据（目标、记忆、对话记录）会被永久删除，无法恢复。确定要继续吗？'),
      findsOneWidget,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('确认删除'), findsNothing);
    expect(find.text('删除账号'), findsOneWidget);
  });

  testWidgets('隐私政策面板能读到随包发布的正文', (tester) async {
    await pumpPanel(
      tester,
      const LegalSheet(title: '隐私政策', asset: 'assets/legal/privacy.md'),
      settle: true,
    );
    expect(
      find.textContaining('我们收集哪些信息', findRichText: true),
      findsOneWidget,
    );
    // 第三方处理与存储地域必须在政策里写清楚
    expect(
      find.textContaining('阿里云百炼的数据处理在中国大陆', findRichText: true),
      findsOneWidget,
    );
  });

  // 「我的」页信息分工：画像置顶，账号与政策协议沉底，周报走二级页
  testWidgets('我的页画像在上、周报入口居中、账号与协议在下', (tester) async {
    final store = seededStore();
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ReportScreen(store: store))),
    );
    await tester.pump();

    expect(find.text('成长周报'), findsOneWidget);
    expect(find.text('本周成长报告'), findsNothing, reason: '周报内容应移出我的页');
    expect(find.text('历史周报'), findsNothing, reason: '选周下拉已被列表页取代');

    final profileY = tester.getRect(find.text('我的画像')).top;
    final reportsY = tester.getRect(find.text('成长周报')).top;
    expect(profileY, lessThan(reportsY), reason: '画像要在周报入口之上');
  });

  testWidgets('周报列表按周展示，点进去看当周详情', (tester) async {
    final store = seededStore();
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: store,
            builder: (_, _) => WeeklyReportsScreen(store: store),
          ),
        ),
      ),
    );
    await tester.pump();

    // 列表：三周各一行
    expect(find.text('8/10 — 8/16'), findsOneWidget);
    expect(find.text('8/17 — 8/23'), findsOneWidget);

    // 点第二周 → 进入详情，标题与内容都换成那一周
    await tester.tap(find.text('8/17 — 8/23'));
    await tester.pump();
    expect(store.page, ExplorePage.weeklyReportDetail);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: store,
            builder: (_, _) => WeeklyReportDetailScreen(store: store),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('8/17 — 8/23'), findsOneWidget);
    expect(find.text('本周评分'), findsOneWidget);
    expect(find.text('你做到了这些'), findsOneWidget);
    // 库里存的是 next_steps：下周建议必须读得到，不能是空列表
    expect(find.text('把方向收窄到一个场景'), findsOneWidget);
  });

  // 生成类操作反馈：点了要有「进行中」的样子，并且不能重复触发
  testWidgets('生成中按钮显示进行状态且点击无效', (tester) async {
    var taps = 0;
    await pumpPanel(
      tester,
      PrimaryButton(
        label: '生成画像',
        icon: Icons.auto_awesome_rounded,
        busy: true,
        busyLabel: '正在生成…',
        onTap: () => taps++,
      ),
    );

    expect(find.text('正在生成…'), findsOneWidget);
    expect(find.text('生成画像'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byType(PrimaryButton));
    await tester.pump();
    expect(taps, 0, reason: '进行中不应再触发一次生成');
  });

  testWidgets('空闲时按钮显示原文案且可点', (tester) async {
    var taps = 0;
    await pumpPanel(
      tester,
      PrimaryButton(
        label: '生成画像',
        icon: Icons.auto_awesome_rounded,
        onTap: () => taps++,
      ),
    );

    expect(find.text('生成画像'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byType(PrimaryButton));
    expect(taps, 1);
  });

  testWidgets('我的页画像重新生成时显示生成中', (tester) async {
    final store = seededStore();
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: store,
            builder: (_, _) => ReportScreen(store: store),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('重新生成'), findsOneWidget);
    store.profileLoading = true;
    store.notifyListeners();
    await tester.pump();
    expect(find.text('生成中…'), findsOneWidget);
    // AnimatedSwitcher 会短暂同时保留新旧内容，推进过动画时长再看旧文案是否移除
    // （转圈是无限动画，不能用 pumpAndSettle）
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('重新生成'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('反馈面板内容为空时不发送', (tester) async {
    await pumpPanel(tester, FeedbackSheet(store: seededStore()));
    await tester.tap(find.text('发送'));
    await tester.pump();
    expect(find.text('写点什么再发送吧。'), findsOneWidget);
  });

  // 换账号串数据：signOut 与重新登录都要清内存。以前 currentGoal 在 goals 为空时
  // 会抛 StateError，所以退出登录不敢清数据，上一位用户的目标与记忆会留在内存里。
  test('清空用户数据后不残留上一位用户的内容', () {
    final store = seededStore();
    expect(store.currentGoal, isNotNull);

    store.clearUserData();

    expect(store.goals, isEmpty);
    expect(store.memories, isEmpty);
    expect(store.conversations, isEmpty);
    expect(store.messages, isEmpty);
    expect(store.observations, isEmpty);
    expect(store.profile, isNull);
    expect(store.weeklyReport, isNull);
    expect(store.currentGoal, isNull);
    // 页面与导航回首页，登录后不会停在上一位用户的子页面
    expect(store.page, ExplorePage.home);
    expect(store.selectedNav, 0);
    // 目标共创的开场白要留着，否则共创页首屏空白
    expect(store.goalCreationMessages.length, 1);
    expect(store.goalCreationMessages.first.content, goalCreationGreeting);
  });

  // 清空后各页面必须能按空态渲染：目标详情页过去直接假设 currentGoal 非空
  testWidgets('清空数据后各页面按空态渲染不崩', (tester) async {
    final store = seededStore()..clearUserData();
    await pumpScreen(tester, HomeScreen(store: store));
    await pumpScreen(tester, GrowthScreen(store: store));
    await pumpScreen(tester, GoalDetailScreen(store: store));
    await pumpScreen(tester, GoalCreateScreen(store: store));
    expect(tester.takeException(), isNull);
  });
}
