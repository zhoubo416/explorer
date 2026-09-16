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
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AppHeader(store: store))),
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
  });
}
