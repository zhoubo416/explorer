import 'package:flutter_test/flutter_test.dart';

import 'package:explore_mobile/main.dart';

/// 会话现场的归属规则：activeSessionId / messages /「新增对话」空态只由
/// 「进入对话页」和用户操作写，加载路径只维护 conversations 这份数据。
///
/// 测试环境没有传 dart-define，SupabaseService.client 为 null，
/// 所以这里覆盖的是「本地先行」那一段；网络校准那段需要真机验证。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChatMessage msg(String content) =>
      ChatMessage(isUser: true, content: content, time: '10:00');

  /// updatedAt 缺省即「刚刚」，也就是最近一次会话发生在今天
  ConversationSummary summary(
    String? id, {
    String? updatedAt,
    List<ChatMessage> messages = const [],
  }) => ConversationSummary(
    id: id,
    title: '会话 $id',
    date: '9/21',
    preview: '预览',
    messages: messages,
    updatedAt: updatedAt ?? DateTime.now().toIso8601String(),
  );

  ExploreStore storeWith(List<ConversationSummary> conversations) =>
      ExploreStore()..conversations.addAll(conversations);

  group('进入对话页', () {
    test('用内存里的历史列表立即定位到最近一次会话', () {
      final store = storeWith([
        summary('c2', messages: [msg('今天这句')]),
        summary('c1', messages: [msg('更早那句')]),
      ]);

      store.goToPage(ExplorePage.chat, resetChat: true);

      expect(store.activeSessionId, 'c2');
      expect(store.messages.map((m) => m.content).toList(), ['今天这句']);
    });

    test('最近一次会话是更早的某天：当场开新会话，不留旧话题', () {
      final store = storeWith([
        summary(
          'c1',
          updatedAt: DateTime.now()
              .subtract(const Duration(days: 1))
              .toIso8601String(),
          messages: [msg('昨天这句')],
        ),
      ]);

      store.goToPage(ExplorePage.chat, resetChat: true);

      expect(store.activeSessionId, isNull);
      expect(store.messages, isEmpty);
    });

    test('时间未知的历史会话按同一天处理，不擅自清掉', () {
      final store = storeWith([
        ConversationSummary(
          id: 'c1',
          title: '会话 c1',
          date: '9/21',
          preview: '预览',
          messages: [msg('老缓存那句')],
          // updatedAt 缺省：更早版本落的缓存没有这个字段
        ),
      ]);

      store.goToPage(ExplorePage.chat, resetChat: true);

      expect(store.activeSessionId, 'c1');
      expect(store.messages.map((m) => m.content).toList(), ['老缓存那句']);
    });

    test('「新增对话」空态在再次进入对话页时保持', () {
      final store = storeWith([
        summary('c1', messages: [msg('上一轮会话')]),
      ]);
      store.startNewConversation();

      store.goToPage(ExplorePage.chat, resetChat: true);

      expect(store.page, ExplorePage.chat);
      expect(store.activeSessionId, isNull);
      expect(store.messages, isEmpty);
    });

    test('流式回复进行中时不重画消息', () {
      final store = storeWith([
        summary('c2', messages: [msg('库里那条')]),
      ]);
      store.activeSessionId = 'c2';
      store.messages.add(msg('正在流式写入的那条'));
      store.chatSending = true;

      store.goToPage(ExplorePage.chat, resetChat: true);

      expect(store.messages.map((m) => m.content).toList(), ['正在流式写入的那条']);
    });

    test('从历史面板选回某条：停在选中的那条，不被最近会话顶掉', () {
      final store = storeWith([
        summary('c2', messages: [msg('最近的')]),
        summary('c1', messages: [msg('更早的')]),
      ]);

      store.loadConversation(1);

      expect(store.activeSessionId, 'c1');
      expect(store.messages.map((m) => m.content).toList(), ['更早的']);
      expect(store.activeConversationIndex, 1);
    });
  });

  group('当前会话的位置', () {
    test('由 activeSessionId 推导，历史列表合并后不错位', () {
      final store = storeWith([summary('c1'), summary('c2')]);
      // 模拟加载期间用户发出第一句：新建的会话插在最前，随后远端历史并进来
      store.conversations.insert(0, summary('cNew'));
      store.activeSessionId = 'cNew';

      final merged = mergeConversationSummaries(store.conversations, [
        summary('c1'),
        summary('c2'),
      ]);
      store.conversations
        ..clear()
        ..addAll(merged);

      expect(store.conversations.map((c) => c.id).toList(), [
        'cNew',
        'c1',
        'c2',
      ]);
      expect(store.activeSessionId, 'cNew');
      expect(store.activeConversationIndex, 0);
    });

    test('没有当前会话、或当前会话不在列表里时是 -1', () {
      final store = storeWith([summary('c1')]);
      expect(store.activeConversationIndex, -1);

      store.activeSessionId = 'c9';
      expect(store.activeConversationIndex, -1);
    });

    test('没有当前会话时，id 为空的会话不会冒充当前会话', () {
      // 没有这层保护的话 indexWhere 会按 c.id == null 命中它，返回 0
      final store = storeWith([summary(null)]);
      expect(store.activeConversationIndex, -1);
    });
  });

  group('历史列表合并', () {
    test('保留本地新建、这次没拉到的会话，排在最前', () {
      final merged = mergeConversationSummaries([
        summary('cNew'),
      ], [summary('c2'), summary('c1')]);

      expect(merged.map((c) => c.id).toList(), ['cNew', 'c2', 'c1']);
    });

    test('同 id 用拉到的版本，不出现重复', () {
      final remote = summary('c1', messages: [msg('远端的新消息')]);
      final merged = mergeConversationSummaries([
        summary('c1', messages: [msg('本地的旧消息')]),
      ], [remote, summary('c2')]);

      expect(merged.map((c) => c.id).toList(), ['c1', 'c2']);
      expect(merged.first.messages.map((m) => m.content).toList(), ['远端的新消息']);
      expect(identical(merged.first, remote), isTrue);
    });

    test('拉到的为空时保持本地不变', () {
      final local = [summary('c1'), summary('c2')];
      expect(mergeConversationSummaries(local, const []), local);
    });
  });

  group('对话页顶部日期条', () {
    final now = DateTime(2026, 9, 21, 15, 0);

    test('当天的会话带「今天 ·」前缀', () {
      expect(
        chatDateLabelFor(DateTime(2026, 9, 21, 9, 30), now),
        '今天 · 9 月 21 日',
      );
    });

    test('昨天的会话带「昨天 ·」前缀', () {
      expect(
        chatDateLabelFor(DateTime(2026, 9, 20, 23, 59), now),
        '昨天 · 9 月 20 日',
      );
    });

    test('更早的会话只写日期', () {
      expect(chatDateLabelFor(DateTime(2026, 8, 9, 10, 0), now), '8 月 9 日');
    });
  });
}
