import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'repositories/conversation_repository.dart';
import 'repositories/goal_repository.dart';
import 'repositories/memory_repository.dart';
import 'services/ai_service.dart';
import 'services/auth_service.dart';
import 'services/cache_service.dart';
import 'services/insight_service.dart';
import 'services/supabase_service.dart';

const ink = Color(0xFF202038);
const muted = Color(0xFF5C5C78);
const muted2 = Color(0xFF7C7C96);
const purple = Color(0xFF6658E8);
const line = Color(0xFFEDEDF5);
const pageBg = Color(0xFFF8F8FD);
const violetBg = Color(0xFFF0EFFF);
const mintBg = Color(0xFFE5F8F1);
const coralBg = Color(0xFFFFF0EC);
const amberBg = Color(0xFFFFF4D9);

/// 新会话的 AI 开场白：空会话先展示，发出第一条消息时随会话落库（见 _persistMessage）
const chatGreeting =
    '你好，我是探境。最近过得怎么样？开心的、烦心的，或者还没想明白的事，都可以随时说给我听。';

/// 目标共创的开场白：原「为什么从对话开始」说明文案并入这里
const goalCreationGreeting =
    '你好，我是探境。目标不是一开始就完美的答案，而是你愿意先靠近的一条路——不用先想清楚，我们边走边发现。最近有没有一件事，你一直想做，但还没真正开始？';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  runApp(const ExploreApp());
}

// 首页问候语按当地小时计算：11 点前早上好，18 点前下午好，其余晚上好。
// 测试通过同一函数计算期望值，避免断言依赖运行时刻。
String greetingFor(DateTime now) {
  final hour = now.hour;
  return hour < 11 ? '早上好' : hour < 18 ? '下午好' : '晚上好';
}

enum ExplorePage {
  home,
  growth,
  chat,
  report,
  goalDetail,
  goalCreate,
  goalCreated,
}

/// 「成长」页内的两个子视图：目标与记忆
enum GrowthTab { goal, memory }

enum DetailTab { overview, phase, action, records, analysis }

class Goal {
  Goal({
    required this.id,
    required this.title,
    required this.description,
    required this.phase,
    required this.progress,
    required this.status,
    required this.icon,
    required this.accent,
    required this.milestone,
    this.rawStatus = 'exploring',
    this.isMainGoal = false,
    List<Map<String, dynamic>>? stages,
  }) : stages = stages ?? [];
  final String id;
  String title;
  String description;
  String phase;
  int progress;
  String status;
  final IconData icon;
  final Color accent;
  String milestone;
  final String rawStatus;
  /// 数据库 is_main_goal：一人同时只有一个主目标，
  /// 首页「当前主目标」与对话的目标上下文、进度副作用都挂在它上面
  bool isMainGoal;
  final List<Map<String, dynamic>> stages;
}

class MemoryItem {
  MemoryItem({
    required this.date,
    required this.month,
    required this.type,
    required this.title,
    required this.detail,
    required this.icon,
    required this.tone,
  });
  final String date;
  final String month;
  final String type;
  final String title;
  final String detail;
  final IconData icon;
  final Color tone;
}

class ChatMessage {
  ChatMessage({
    required this.isUser,
    required this.content,
    required this.time,
  });
  final bool isUser;
  final String content;
  final String time;
}

class ConversationSummary {
  ConversationSummary({
    this.id,
    required this.title,
    required this.date,
    required this.preview,
    required this.messages,
  });
  final String? id;
  final String title;
  final String date;
  final String preview;
  final List<ChatMessage> messages;
}

class ExploreStore extends ChangeNotifier {
  ExploreStore();

  final List<Goal> goals = [];
  final List<MemoryItem> memories = [];
  final List<ChatMessage> messages = [];
  final List<ConversationSummary> conversations = [];
  String selectedGoalId = '';
  int selectedNav = 0;
  int activeConversationIndex = 0;
  ExplorePage page = ExplorePage.home;
  /// 目标共创页的来源页，返回时回到进入前所在页面
  ExplorePage goalCreateOrigin = ExplorePage.growth;
  GrowthTab growthTab = GrowthTab.goal;
  bool lowMood = false;
  DetailTab detailTab = DetailTab.overview;
  String memoryFilter = '全部';
  String? activeSessionId;
  bool remoteLoading = false;
  String? remoteError;
  /// 一次发送（含流式回复）是否进行中；进行中不刷新会话消息，避免和流式写入竞争
  bool chatSending = false;
  /// 「新对话」空态（手动新增或切换/新建主目标后）：进入对话页不自动恢复
  /// 最近会话，直到下一条消息归属具体会话，或用户主动选回历史会话
  bool _pendingNewChat = false;
  bool progressUpdating = false;
  bool goalUpdating = false;
  /// 主目标切换写库链：连续快速切换时按顺序排队执行，
  /// 避免两次「清旧+置新」交错撞一人一主目标的唯一索引
  Future<void>? _mainGoalWrite;
  final List<Map<String, dynamic>> observations = [];
  Map<String, dynamic>? weeklyReport;
  final List<Map<String, dynamic>> reports = [];
  Map<String, dynamic>? goalAnalysis;
  final List<MemoryItem> goalMemories = [];
  String? timelineSummary;
  Map<String, dynamic>? profile;
  String dailySuggestion = '';
  /// 快速连续切换主目标时，建议请求可能乱序返回；只认最后一次发起的
  int _suggestionRequestSeq = 0;
  bool reportLoading = false;
  bool analysisLoading = false;
  final List<ChatMessage> goalCreationMessages = [
    ChatMessage(isUser: false, content: goalCreationGreeting, time: ''),
  ];
  Map<String, dynamic>? goalDraft;
  List<Map<String, dynamic>> goalStages = [];
  bool goalChatLoading = false;
  final List<Map<String, dynamic>> actions = [];

  Goal get currentGoal => goals.firstWhere(
    (goal) => goal.id == selectedGoalId,
    orElse: () => goals.first,
  );

  /// 兜底：把选中目标重置为主目标（列表按 is_main_goal 排序时首位即主目标）
  void _resetSelectedGoalToMain() {
    if (goals.isEmpty) return;
    selectedGoalId =
        goals.firstWhere((g) => g.isMainGoal, orElse: () => goals.first).id;
  }

  List<ChatMessage> get visibleMessages => messages;

  bool get remoteEnabled => SupabaseService.client != null;

  Future<void> loadRemoteData() async {
    final client = SupabaseService.client;
    if (client == null || client.auth.currentUser == null || remoteLoading) {
      return;
    }

    remoteLoading = true;
    remoteError = null;
    notifyListeners();
    try {
      final auth = const AuthService();
      final insight = const InsightService();
      final goalsRepository = GoalRepository(client);
      final memoriesRepository = MemoryRepository(client);
      final conversationsRepository = ConversationRepository(client);

      // 单路数据失败只丢掉这一路,不让整个首页加载跟着失败
      Object? firstError;
      Future<T?> tryLoad<T>(Future<T> Function() task) async {
        try {
          return await task();
        } catch (error) {
          firstError ??= error;
          return null;
        }
      }

      // 各路读取互相独立,创建即并行发出,首页只等最慢的一路而不是逐个排队
      final goalsTask = tryLoad(goalsRepository.listGoals);
      final memoriesTask = tryLoad(memoriesRepository.listMemories);
      // 会话以「会话行 + 消息行」原始数据返回,建摘要和写缓存共用
      final conversationPairsTask = tryLoad(() async {
        final sessions = await conversationsRepository.listSessions();
        return Future.wait(
          sessions.map((session) async {
            final sessionId = session['id']?.toString();
            final rows = sessionId == null
                ? <Map<String, dynamic>>[]
                : await conversationsRepository.listMessages(sessionId);
            return <String, dynamic>{'session': session, 'messages': rows};
          }),
        );
      });
      final observationsTask = tryLoad(insight.listObservations);
      final latestReportTask = tryLoad(insight.listLatestReport);
      final reportsTask = tryLoad(insight.listReports);
      final profileTask = tryLoad(_fetchProfileRow);
      final actionsTask = tryLoad(_fetchActionRows);
      final ensureProfileTask = tryLoad(auth.ensureExploreProfile);

      // 网络请求已经发出,先用上次的本地缓存把首屏画出来(本地读,毫秒级)
      final cachedData = await _applyCachedData();

      // 任务都已经发出去了,这里按顺序 await 只是取结果,不会重新排队
      final remoteGoals = await goalsTask;
      final remoteMemories = await memoriesTask;
      final remotePairs = await conversationPairsTask;
      final remoteObservations = await observationsTask;
      final remoteReports = await reportsTask;
      final remoteProfile = await profileTask;
      final remoteActions = await actionsTask;
      weeklyReport = await latestReportTask;
      await ensureProfileTask;

      if (remoteGoals != null && remoteGoals.isNotEmpty) {
        goals
          ..clear()
          ..addAll(remoteGoals.map(_goalFromRow));
      }
      if (remoteMemories != null && remoteMemories.isNotEmpty) {
        memories
          ..clear()
          ..addAll(remoteMemories.map(_memoryFromRow));
      }
      if (remotePairs != null) {
        final remoteConversations = [
          for (final pair in remotePairs) _conversationFromPair(pair),
        ];
        if (remoteConversations.isNotEmpty) {
          conversations
            ..clear()
            ..addAll(remoteConversations);
          activeConversationIndex = 0;
          activeSessionId = conversations.first.id;
          messages
            ..clear()
            ..addAll(conversations.first.messages);
        } else {
          conversations.clear();
          messages.clear();
          activeConversationIndex = 0;
          activeSessionId = null;
        }
      }
      if (remoteObservations != null && remoteObservations.isNotEmpty) {
        observations
          ..clear()
          ..addAll(remoteObservations);
      }
      if (remoteReports != null) {
        reports
          ..clear()
          ..addAll(remoteReports);
      }
      if (remoteProfile != null) profile = remoteProfile;
      if (remoteActions != null) {
        actions
          ..clear()
          ..addAll(remoteActions);
      }

      // 只有核心数据全挂才算加载失败;部分失败时先展示已拿到的数据
      if (remoteGoals == null &&
          remoteMemories == null &&
          remotePairs == null) {
        remoteError = firstError.toString();
      }

      _resetSelectedGoalToMain();

      // 原始行写回本地缓存,供下次冷启动秒开;某一路拉取失败时保留缓存里的
      // 旧值,避免把还好的缓存清掉;会话只存最近 20 个控制体积
      final uid = client.auth.currentUser?.id;
      final cachePayload = <String, dynamic>{
        'savedAt': DateTime.now().toIso8601String(),
        'goals': remoteGoals ?? _rowsFrom(cachedData?['goals']),
        'memories': remoteMemories ?? _rowsFrom(cachedData?['memories']),
        'conversations': remotePairs != null
            ? [for (final pair in remotePairs.take(20)) pair]
            : _rowsFrom(cachedData?['conversations']),
        'observations':
            remoteObservations ?? _rowsFrom(cachedData?['observations']),
        'reports': remoteReports ?? _rowsFrom(cachedData?['reports']),
        'weeklyReport': weeklyReport ?? _mapFrom(cachedData?['weeklyReport']),
        'profile': remoteProfile ?? _mapFrom(cachedData?['profile']),
        'actions': remoteActions ?? _rowsFrom(cachedData?['actions']),
        'dailySuggestion': dailySuggestion,
      };
      if (uid != null) {
        await CacheService.save(uid, cachePayload);
      }

      // 每日建议、观察生成、主动关怀都要等 Edge Function/大模型,放到后台,
      // 完成后各自 notifyListeners,不阻塞首页首屏
      loadAiExtras(
        needObservations:
            observations.isEmpty && (goals.isNotEmpty || memories.isNotEmpty),
        cachePayload: cachePayload,
      );
      if (goals.isNotEmpty || memories.isNotEmpty) {
        runProactiveCheck();
      }
      goToPage(ExplorePage.home);
    } catch (error) {
      remoteError = error.toString();
    } finally {
      remoteLoading = false;
      notifyListeners();
    }
  }

  /// 首页核心数据就绪后在后台补齐慢的 AI 内容(每日建议、首次观察生成)。
  /// 这些调用要同步等 DeepSeek 出结果,串在 loadRemoteData 关键路径上会把
  /// 首屏拖慢好几秒;完成后自行 notifyListeners,并顺手更新本地缓存。
  Future<void> loadAiExtras({
    bool needObservations = false,
    Map<String, dynamic>? cachePayload,
  }) async {
    final uid = SupabaseService.client?.auth.currentUser?.id;
    if (needObservations) {
      try {
        await const InsightService().generateObservations();
        final rows = await const InsightService().listObservations();
        observations
          ..clear()
          ..addAll(rows);
        notifyListeners();
        if (uid != null && cachePayload != null) {
          cachePayload['observations'] = rows;
          await CacheService.save(uid, cachePayload);
        }
      } catch (_) {}
    }
    try {
      await loadDailySuggestion();
      if (uid != null && cachePayload != null && dailySuggestion.isNotEmpty) {
        cachePayload['dailySuggestion'] = dailySuggestion;
        await CacheService.save(uid, cachePayload);
      }
    } catch (_) {}
  }

  /// 冷启动先用本地缓存渲染(stale-while-revalidate),网络加载完成后覆盖。
  /// 只在本次会话还没有任何数据时生效,避免旧缓存顶掉已刷新的数据;
  /// 返回缓存原文,供网络刷新失败时兜底。
  Future<Map<String, dynamic>?> _applyCachedData() async {
    final uid = SupabaseService.client?.auth.currentUser?.id;
    if (uid == null) return null;
    if (goals.isNotEmpty ||
        memories.isNotEmpty ||
        conversations.isNotEmpty ||
        observations.isNotEmpty) {
      return null;
    }
    final cache = await CacheService.load(uid);
    if (cache == null) return null;
    final cachedGoals = _rowsFrom(cache['goals']);
    final cachedMemories = _rowsFrom(cache['memories']);
    if (cachedGoals.isNotEmpty) {
      goals
        ..clear()
        ..addAll(cachedGoals.map(_goalFromRow));
    }
    if (cachedMemories.isNotEmpty) {
      memories
        ..clear()
        ..addAll(cachedMemories.map(_memoryFromRow));
    }
    final cachedConversations = [
      for (final pair in _rowsFrom(cache['conversations']))
        _conversationFromPair(pair),
    ];
    if (cachedConversations.isNotEmpty) {
      conversations
        ..clear()
        ..addAll(cachedConversations);
      activeConversationIndex = 0;
      activeSessionId = conversations.first.id;
      messages
        ..clear()
        ..addAll(conversations.first.messages);
    }
    final cachedObservations = _rowsFrom(cache['observations']);
    if (cachedObservations.isNotEmpty) {
      observations
        ..clear()
        ..addAll(cachedObservations);
    }
    weeklyReport = _mapFrom(cache['weeklyReport']);
    final cachedReports = _rowsFrom(cache['reports']);
    if (cachedReports.isNotEmpty) {
      reports
        ..clear()
        ..addAll(cachedReports);
    }
    profile = _mapFrom(cache['profile']);
    final cachedActions = _rowsFrom(cache['actions']);
    if (cachedActions.isNotEmpty) {
      actions
        ..clear()
        ..addAll(cachedActions);
    }
    // 每日建议只认当天的缓存,隔天直接空着等网络
    if (_isSameLocalDay(cache['savedAt']?.toString())) {
      final suggestion = cache['dailySuggestion']?.toString();
      if (suggestion != null && suggestion.isNotEmpty) {
        dailySuggestion = suggestion;
      }
    }
    _resetSelectedGoalToMain();
    notifyListeners();
    return cache;
  }

  /// 由「会话行 + 消息行」构造 ConversationSummary,网络加载和缓存读取共用
  ConversationSummary _conversationFromPair(Map<String, dynamic> pair) {
    final session = pair['session'] is Map
        ? Map<String, dynamic>.from(pair['session'] as Map)
        : <String, dynamic>{};
    // 消息一律按时间正序，本地缓存里存的旧数据可能是倒序（排序方向修复前落盘的）
    final rows = _rowsFrom(pair['messages'])..sort(_byCreatedAt);
    final mappedMessages = rows.map(_messageFromRow).toList();
    return ConversationSummary(
      id: session['id']?.toString(),
      title: session['title']?.toString() ?? '新的对话',
      date: _dateLabel(session['updated_at'] ?? session['created_at']),
      preview:
          session['preview']?.toString() ??
          (mappedMessages.isEmpty
              ? '还没有消息'
              : mappedMessages.last.content),
      messages: mappedMessages,
    );
  }

  /// JSON 解出来的 List 还原成行列表,类型不符的元素直接丢弃
  List<Map<String, dynamic>> _rowsFrom(dynamic value) => [
        for (final row in value is List ? value : const [])
          if (row is Map) Map<String, dynamic>.from(row),
      ];

  /// 行按 created_at 从旧到新排；解析失败的时间排最前
  int _byCreatedAt(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = DateTime.tryParse(a['created_at']?.toString() ?? '');
    final tb = DateTime.tryParse(b['created_at']?.toString() ?? '');
    return (ta ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(tb ?? DateTime.fromMillisecondsSinceEpoch(0));
  }

  Map<String, dynamic>? _mapFrom(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  bool _isSameLocalDay(String? iso) {
    final saved = iso == null ? null : DateTime.tryParse(iso);
    if (saved == null) return false;
    final local = saved.toLocal();
    final now = DateTime.now();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  Future<void> generateWeeklyReport() async {
    if (SupabaseService.client == null) return;
    reportLoading = true;
    notifyListeners();
    try {
      final report = await const InsightService().generateReport();
      if (report != null) weeklyReport = report;
    } catch (error) {
      remoteError = error.toString();
    } finally {
      reportLoading = false;
      notifyListeners();
    }
  }

  Future<void> generateTimelineSummary() async {
    final summary = await const InsightService().generateTimelineSummary();
    if (summary != null) {
      timelineSummary = summary;
      notifyListeners();
    }
  }

  /// 当前用户的画像行,还没有画像或读取失败时返回 null
  Future<Map<String, dynamic>?> _fetchProfileRow() async {
    final client = SupabaseService.client;
    if (client == null || client.auth.currentUser == null) return null;
    try {
      final row = await client
          .from('explore_user_profiles')
          .select()
          .eq('user_id', client.auth.currentUser!.id)
          .single();
      return Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  Future<void> generateProfile() async {
    final p = await const InsightService().generateProfile();
    if (p != null) {
      profile = p;
      notifyListeners();
    }
  }

  Future<void> loadDailySuggestion() async {
    final request = ++_suggestionRequestSeq;
    final s = await const InsightService().dailySuggestion();
    if (request != _suggestionRequestSeq) return;
    if (s != null) dailySuggestion = s;
    notifyListeners();
  }

  /// 主目标切换/新建/归档后重新取每日建议（按「目标+天」缓存，当天该目标
  /// 首次会生成一次）。失败静默：建议丢了不影响目标操作本身。
  Future<void> refreshDailySuggestionQuietly() async {
    try {
      await loadDailySuggestion();
    } catch (_) {}
  }

  void selectReport(Map<String, dynamic> row) {
    weeklyReport = Map<String, dynamic>.from(row);
    notifyListeners();
  }

  Future<void> generateGoalAnalysis(Goal goal) async {
    if (SupabaseService.client == null) return;
    analysisLoading = true;
    notifyListeners();
    try {
      final analysis = await const InsightService().generateGoalAnalysis(
        goal.id,
      );
      if (analysis != null) goalAnalysis = analysis;
    } catch (error) {
      remoteError = error.toString();
    } finally {
      analysisLoading = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchActionRows() async {
    final client = SupabaseService.client;
    if (client == null || client.auth.currentUser == null) return const [];
    final rows = await client
        .from('explore_ai_actions')
        .select()
        .eq('user_id', client.auth.currentUser!.id)
        .order('created_at', ascending: false)
        .limit(20);
    return List<Map<String, dynamic>>.from(
      rows,
    ).where((a) => a['status'] == 'pending' || a['status'] == 'sent').toList();
  }

  Future<void> loadActions() async {
    actions
      ..clear()
      ..addAll(await _fetchActionRows());
  }

  Future<void> runProactiveCheck() async {
    final client = SupabaseService.client;
    if (client == null || client.auth.currentUser == null) return;
    try {
      await client.functions.invoke('explore-proactive');
      await loadActions();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> dismissAction(String id) async {
    final client = SupabaseService.client;
    if (client == null) return;
    await client
        .from('explore_ai_actions')
        .update({'status': 'read'})
        .eq('id', id);
    actions.removeWhere((a) => a['id'] == id);
    notifyListeners();
  }

  Future<void> markObservationRead(String id) async {
    final client = SupabaseService.client;
    if (client == null || id.isEmpty) return;
    await client
        .from('explore_ai_observations')
        .update({'status': 'read'})
        .eq('id', id);
    observations.removeWhere((o) => o['id'] == id);
    notifyListeners();
  }

  // 底部导航的页面，顺序与 NavigationBar 的 items 一一对应
  static const List<ExplorePage> navPages = [
    ExplorePage.home,
    ExplorePage.growth,
    ExplorePage.chat,
    ExplorePage.report,
  ];

  /// 跳转到指定页面。目标页之外的都会同步底部导航选中态。
  /// [resetChat] 只在进入对话页时生效：把活跃会话重置为最近一次会话。
  void goToPage(ExplorePage target, {GrowthTab? tab, bool resetChat = false}) {
    // 切页前先收起键盘：销毁「还持有焦点的输入框」会留下未关闭的输入连接，
    // iOS 输入法的飞行中消息会继续写已销毁的 controller，进而破坏 element 树
    if (target != page) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    page = target;
    final index = navPages.indexOf(target);
    if (index >= 0) {
      selectedNav = index;
      lowMood = false;
    }
    if (tab != null) growthTab = tab;
    // 每次进对话页都从库里刷新会话消息，避免展示登录那一刻的旧快照；
    // 重置入口（导航栏、首页快捷入口）直接定位到最近一次会话
    if (target == ExplorePage.chat) {
      refreshActiveConversation(toLatest: resetChat);
    }
    notifyListeners();
  }

  void setGrowthTab(GrowthTab tab) {
    growthTab = tab;
    notifyListeners();
  }

  // 覆盖在底部导航之上、带「返回」语义的子页面
  static const Set<ExplorePage> subPages = {
    ExplorePage.goalDetail,
    ExplorePage.goalCreate,
    ExplorePage.goalCreated,
  };

  bool get isSubPage => subPages.contains(page);

  /// 子页面返回上级：详情与创建完成回成长方向页，创建页回到进入前的页面。
  /// 与各子页面顶栏返回按钮的目的地保持一致。
  void goBack() {
    switch (page) {
      case ExplorePage.goalCreate:
        goToPage(goalCreateOrigin);
      case ExplorePage.goalDetail || ExplorePage.goalCreated:
        goToPage(ExplorePage.growth);
      default:
        break;
    }
  }

  void openGoal(Goal goal) {
    selectedGoalId = goal.id;
    goalAnalysis = null;
    // 与 Web 端 selectGoal 对齐：点开非主目标即切换主目标，
    // 首页「当前主目标」与对话的目标上下文、进度副作用随之切换
    if (!goal.isMainGoal) unawaited(makeMainGoal(goal));
    loadGoalMemories(goal.id);
    detailTab = DetailTab.overview;
    goToPage(ExplorePage.goalDetail);
  }

  /// 把某个目标设为主目标：先乐观翻转本地标志，再两步写库（先清旧、再置新），
  /// 失败回滚并报错。连续切换时排队串行执行，见 _mainGoalWrite。
  Future<void> makeMainGoal(Goal goal) async {
    final client = SupabaseService.client;
    if (client == null || client.auth.currentUser == null) return;
    final pending = _mainGoalWrite;
    _mainGoalWrite = (pending ?? Future.value()).then((_) async {
      if (goal.isMainGoal) return;
      final previousFlags = {
        for (final item in goals) item.id: item.isMainGoal,
      };
      for (final item in goals) {
        item.isMainGoal = item.id == goal.id;
      }
      notifyListeners();
      try {
        await GoalRepository(client).setMainGoal(goal.id);
        // 新目标配新对话：进对话页保持空态，而不是接着旧会话聊
        _startNewChatForGoalSwitch();
        // 每日建议按「目标+天」缓存：主目标换了重新取，不阻塞切换本身
        unawaited(refreshDailySuggestionQuietly());
      } catch (error) {
        for (final item in goals) {
          item.isMainGoal = previousFlags[item.id] ?? false;
        }
        remoteError = error.toString();
        notifyListeners();
      }
    });
    await _mainGoalWrite;
  }

  /// 切换/新建主目标后开启新对话。若还有流式回复在途则只记下标志，
  /// 等发送结束再清（见 sendMessage 收尾）。
  void _startNewChatForGoalSwitch() {
    if (chatSending) {
      _pendingNewChat = true;
    } else {
      startNewConversation();
    }
  }

  Future<void> loadGoalMemories(String goalId) async {
    final client = SupabaseService.client;
    goalMemories.clear();
    if (client == null || client.auth.currentUser == null) return;
    final events = await client
        .from('explore_growth_events')
        .select('memory_id')
        .eq('goal_id', goalId)
        .eq('user_id', client.auth.currentUser!.id);
    final ids = events
        .map((e) => e['memory_id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    final rows = await client
        .from('explore_memory_items')
        .select()
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    goalMemories
      ..clear()
      ..addAll(rows.map(_memoryFromRow));
  }

  void openGoalCreate() {
    goalCreateOrigin = page;
    goToPage(ExplorePage.goalCreate);
  }

  void createGoal() {
    final draft = goalDraft;
    final isFirstGoal = goals.isEmpty;
    final goal = Goal(
      id: 'goal-${DateTime.now().millisecondsSinceEpoch}',
      title: draft?['title']?.toString() ?? '未命名目标',
      description: draft?['description']?.toString() ?? '',
      phase: '验证期',
      progress: 0,
      status: '进行中',
      icon: Icons.adjust_rounded,
      accent: purple,
      milestone: draft?['success_definition']?.toString() ?? '完成第一次真实行动',
      stages: goalStages,
    );
    for (final item in goals) {
      if (item.status == '进行中') item.status = '探索中';
    }
    goals.insert(0, goal);
    selectedGoalId = goal.id;
    goToPage(ExplorePage.goalCreated);
    goalDraft = null;
    goalStages = [];
    if (goals.length == 1) generateProfile();
    goalCreationMessages
      ..clear()
      ..add(ChatMessage(isUser: false, content: goalCreationGreeting, time: ''));
    notifyListeners();
    unawaited(_persistGoal(goal, isFirstGoal: isFirstGoal));
  }

  Future<void> sendGoalCreationMessage(String content) async {
    final text = content.trim();
    if (text.isEmpty || goalChatLoading) return;
    goalCreationMessages.add(
      ChatMessage(isUser: true, content: text, time: timeNow()),
    );
    goalChatLoading = true;
    notifyListeners();
    // 请求体要在加占位之前取好，免得把空占位当成历史发给服务端
    final payload = goalCreationMessages
        .map(
          (m) => {
            'role': m.isUser ? 'user' : 'assistant',
            'content': m.content,
          },
        )
        .toList();
    // 占位消息：随流式增量不断替换，等待期间也有反馈
    final replyTime = timeNow();
    var reply = '';
    goalCreationMessages.add(
      ChatMessage(isUser: false, content: '', time: replyTime),
    );
    final placeholderIndex = goalCreationMessages.length - 1;
    var lastPaintedAt = DateTime.now();
    try {
      await const AiService().streamGoalChat(
        messages: payload,
        onDelta: (delta) {
          reply += delta;
          // 增量很碎（一秒可达几十段），节流重绘避免整帧重建过于频繁
          final now = DateTime.now();
          if (now.difference(lastPaintedAt).inMilliseconds < 60) return;
          lastPaintedAt = now;
          _replaceMessage(
            goalCreationMessages,
            placeholderIndex,
            reply,
            replyTime,
          );
        },
        onGoal: (goal) async {
          // 没收到任何内容时撤掉占位，不留一条「正在思考…」
          if (reply.isEmpty && goal == null) {
            goalCreationMessages.removeAt(placeholderIndex);
            remoteError = 'AI 暂时没有回复，请稍后重试。';
            notifyListeners();
            return;
          }
          // 补画节流期间的最后一段
          _replaceMessage(
            goalCreationMessages,
            placeholderIndex,
            reply,
            replyTime,
          );
          if (goal != null && goal['title']?.toString().isNotEmpty == true) {
            goalDraft = goal;
            await planGoalStages(
              goal['title']?.toString() ?? '',
              goal['description']?.toString() ?? '',
              goal['success_definition']?.toString() ?? '',
            );
          }
        },
      );
    } catch (error) {
      if (reply.isEmpty && placeholderIndex < goalCreationMessages.length) {
        goalCreationMessages.removeAt(placeholderIndex);
      }
      remoteError = error.toString();
    } finally {
      goalChatLoading = false;
      notifyListeners();
    }
  }

  Future<void> planGoalStages(
    String title,
    String description,
    String successDefinition,
  ) async {
    final raw = await const InsightService().planGoal(
      title: title,
      description: description,
      successDefinition: successDefinition,
    );
    final ts = DateTime.now().millisecondsSinceEpoch;
    goalStages = raw.asMap().entries.map((e) {
      final i = e.key;
      final s = e.value;
      return {
        'id': 's-$ts-$i',
        'name': s['name']?.toString() ?? '阶段 ${i + 1}',
        'description': s['description']?.toString() ?? '',
        'status': i == 0 ? 'active' : 'not_started',
        'actions': ((s['actions'] as List?) ?? []).asMap().entries.map((ae) {
          final j = ae.key;
          final a = ae.value;
          return {
            'id': 'a-$ts-$i-$j',
            'content': a['content']?.toString() ?? '',
            'done': false,
          };
        }).toList(),
      };
    }).toList();
    notifyListeners();
  }

  Future<void> toggleAction(String stageId, String actionId) async {
    final goal = goals.firstWhere(
      (g) => g.id == selectedGoalId,
      orElse: () => goals.first,
    );
    for (final stage in goal.stages) {
      if (stage['id'] == stageId) {
        for (final action in ((stage['actions'] as List?) ?? [])) {
          if (action['id'] == actionId) {
            action['done'] = !(action['done'] == true);
          }
        }
      }
    }
    final client = SupabaseService.client;
    if (client != null) {
      await client
          .from('explore_growth_goals')
          .update({'stages': goal.stages})
          .eq('id', goal.id);
    }
    notifyListeners();
  }

  Future<void> updateGoalStatus(String goalId, String status) async {
    final client = SupabaseService.client;
    if (client == null || client.auth.currentUser == null) return;
    // _refreshMemoriesAndGoals 会把选中目标重置回主目标，先记下归档的是不是主目标
    final wasMainGoal = goals.any((g) => g.id == goalId && g.isMainGoal);
    final goal = goals.firstWhere(
      (g) => g.id == goalId,
      orElse: () => goals.first,
    );
    final patch = <String, dynamic>{'status': status};
    if (status == 'completed') {
      patch['progress'] = 100;
      if (goal.stages.isNotEmpty) {
        patch['stages'] = [
          for (final s in goal.stages) {...s, 'status': 'completed'},
        ];
      }
    }
    try {
      await client
          .from('explore_growth_goals')
          .update(patch)
          .eq('id', goalId)
          .eq('user_id', client.auth.currentUser!.id);
      await _refreshMemoriesAndGoals();
      // 归档的是主目标时，主目标落到其它目标上，建议跟着重新取
      if (wasMainGoal && status == 'archived') {
        unawaited(refreshDailySuggestionQuietly());
      }
    } catch (error) {
      remoteError = error.toString();
      notifyListeners();
    }
  }

  Future<void> _persistGoal(
    Goal goal, {
    required bool isFirstGoal,
  }) async {
    final client = SupabaseService.client;
    if (client == null || client.auth.currentUser == null) return;
    try {
      // 首个目标直接带主目标标志落库；非首个目标插入后再切换主目标，
      // 与「新建目标即当前专注」的页面展示语义保持一致
      final row = await GoalRepository(client).createGoal(
        title: goal.title,
        description: goal.description,
        successDefinition: goal.milestone,
        stages: goal.stages,
        isMainGoal: isFirstGoal,
      );
      final remoteId = row['id']?.toString();
      if (remoteId != null) {
        final saved = _goalFromRow(row);
        final localIndex = goals.indexWhere((item) => item.id == goal.id);
        if (localIndex >= 0) {
          goals[localIndex] = saved;
          selectedGoalId = saved.id;
          notifyListeners();
        }
        if (!isFirstGoal) {
          // 非首个目标：切换主目标（makeMainGoal 内部会顺带开启新对话）
          await makeMainGoal(saved);
        } else {
          // 首个目标：没有旧主目标要清，但同样开启新对话
          _startNewChatForGoalSwitch();
          // 首个目标即主目标：建议从静态引导切换为按目标生成
          unawaited(refreshDailySuggestionQuietly());
        }
      }
    } catch (error) {
      remoteError = error.toString();
      notifyListeners();
    }
  }

  void openChat({bool withLowMood = false}) {
    goToPage(ExplorePage.chat, resetChat: true);
    lowMood = withLowMood;
    notifyListeners();
  }

  void loadConversation(int index) {
    if (index < 0 || index >= conversations.length) return;
    messages
      ..clear()
      ..addAll(conversations[index].messages);
    activeConversationIndex = index;
    activeSessionId = conversations[index].id;
    // 用户主动翻回历史会话：切换目标带来的新对话空态就此解除
    _pendingNewChat = false;
    goToPage(ExplorePage.chat);
  }

  void exitLowMood() {
    lowMood = false;
    notifyListeners();
  }

  /// 开始新对话：清空当前消息，下一条消息会创建一个新会话。
  /// 空态会一直保持，期间进入对话页不会自动恢复最近会话（见 refreshActiveConversation）。
  void startNewConversation() {
    _pendingNewChat = true;
    activeSessionId = null;
    messages.clear();
    notifyListeners();
  }

  /// 进入对话页时刷新当前会话的消息；[toLatest] 或没有活跃会话时定位到最近一次会话。
  /// 发送中或首次全量加载进行中都不刷新，避免和流式写入、loadRemoteData 竞争。
  Future<void> refreshActiveConversation({bool toLatest = false}) async {
    final client = SupabaseService.client;
    if (client == null ||
        client.auth.currentUser == null ||
        chatSending ||
        remoteLoading) {
      return;
    }
    final repository = ConversationRepository(client);
    try {
      // 「新增对话」空态：不自动恢复最近会话，保持空态等第一条消息
      if (_pendingNewChat && activeSessionId == null) return;
      var sessionId = activeSessionId;
      // 重置到最近一次（导航栏、首页快捷入口），或没有活跃会话（「新增对话」后的空态）
      Map<String, dynamic>? latestSession;
      if (toLatest || sessionId == null) {
        final sessions = await repository.listSessions();
        if (sessions.isEmpty) return;
        latestSession = sessions.first;
        // 最近一次会话已隔天：进入对话页时开启新会话，旧话题从历史面板进入
        if (!_isSameLocalDay(
          latestSession['updated_at']?.toString() ??
              latestSession['created_at']?.toString(),
        )) {
          startNewConversation();
          return;
        }
        sessionId = latestSession['id']?.toString();
        if (sessionId == null) return;
        if (conversations.indexWhere((c) => c.id == sessionId) < 0) {
          conversations.insert(
            0,
            _conversationFromPair({
              'session': latestSession,
              'messages': const [],
            }),
          );
        }
      }
      final rows = await repository.listMessages(sessionId);
      final fresh = [for (final row in rows) _messageFromRow(row)];
      messages
        ..clear()
        ..addAll(fresh);
      activeSessionId = sessionId;
      final summaryIndex = conversations.indexWhere((c) => c.id == sessionId);
      if (summaryIndex >= 0) {
        activeConversationIndex = summaryIndex;
        // 历史列表里同一条会话的消息与预览也换成刚拉到的；
        // 定位到最近一次会话时顺带把时间也换成会话行的最新值
        final conversation = conversations[summaryIndex];
        conversation.messages
          ..clear()
          ..addAll(fresh);
        conversations[summaryIndex] = ConversationSummary(
          id: conversation.id,
          title: conversation.title,
          date: latestSession == null
              ? conversation.date
              : _dateLabel(
                  latestSession['updated_at'] ?? latestSession['created_at'],
                ),
          preview: fresh.isEmpty ? conversation.preview : fresh.last.content,
          messages: conversation.messages,
        );
      }
      notifyListeners();
    } catch (_) {
      // 拉取失败保持现状，不打断用户
    }
  }

  void showGoalDetail() {
    goToPage(ExplorePage.goalDetail);
  }

  void setDetailTab(DetailTab tab) {
    detailTab = tab;
    notifyListeners();
  }

  Future<void> changeGoalProgress(int delta) async {
    if (progressUpdating) return;
    final goal = currentGoal;
    final nextProgress = (goal.progress + delta).clamp(0, 100);
    if (nextProgress == goal.progress) return;

    final previousProgress = goal.progress;
    goal.progress = nextProgress;
    progressUpdating = true;
    notifyListeners();

    final client = SupabaseService.client;
    if (client == null || client.auth.currentUser == null) {
      progressUpdating = false;
      notifyListeners();
      return;
    }
    try {
      await GoalRepository(client).updateProgress(goal.id, nextProgress);
    } catch (error) {
      goal.progress = previousProgress;
      remoteError = error.toString();
    } finally {
      progressUpdating = false;
      notifyListeners();
    }
  }

  Future<bool> updateGoal({
    required String title,
    required String description,
    required String milestone,
    required String status,
  }) async {
    if (goalUpdating) return false;
    final goal = currentGoal;
    final previous = (
      title: goal.title,
      description: goal.description,
      milestone: goal.milestone,
      status: goal.status,
      phase: goal.phase,
    );
    goal
      ..title = title
      ..description = description
      ..milestone = milestone
      ..status = status
      ..phase = _goalPhase(_databaseGoalStatus(status));
    goalUpdating = true;
    notifyListeners();

    final client = SupabaseService.client;
    if (client == null || client.auth.currentUser == null) {
      goalUpdating = false;
      notifyListeners();
      return true;
    }
    try {
      final row = await GoalRepository(client).updateGoal(
        goalId: goal.id,
        title: title,
        description: description,
        successDefinition: milestone,
        status: _databaseGoalStatus(status),
      );
      final index = goals.indexWhere((item) => item.id == goal.id);
      if (index >= 0) goals[index] = _goalFromRow(row);
      return true;
    } catch (error) {
      goal
        ..title = previous.title
        ..description = previous.description
        ..milestone = previous.milestone
        ..status = previous.status
        ..phase = previous.phase;
      remoteError = error.toString();
      return false;
    } finally {
      goalUpdating = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    final client = SupabaseService.client;
    if (client == null) return;
    await const AuthService().signOut();
    activeSessionId = null;
    _pendingNewChat = false;
    remoteError = null;
    notifyListeners();
  }

  /// 删除账号：服务端删掉 auth 用户（业务数据随外键级联清空），
  /// 本机再清掉该用户的本地缓存并登出。
  /// 不重试：删除不可逆，失败时交给用户自己决定要不要再试。
  Future<void> deleteAccount() async {
    final userId = SupabaseService.client?.auth.currentUser?.id;
    if (userId == null) return;
    await const AuthService().deleteAccount();
    await CacheService.clear(userId);
    await signOut();
  }

  /// 意见反馈 / 内容举报：写进 explore_feedback，只有本人能写、本人能读
  Future<void> submitFeedback({
    required String category,
    required String content,
  }) async {
    final client = SupabaseService.client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) {
      throw StateError('请先登录。');
    }
    await client.from('explore_feedback').insert({
      'user_id': userId,
      'category': category,
      'content': content,
      'platform': defaultTargetPlatform.name,
    });
  }

  Future<void> sendMessage(String value) async {
    final content = value.trim();
    if (content.isEmpty) return;
    // 从落库用户消息到流式回复结束都算「发送中」，期间进入对话页不刷新消息
    chatSending = true;
    try {
      final isLowMood = lowMood;
      final target = messages;
      target.add(ChatMessage(isUser: true, content: content, time: timeNow()));
      notifyListeners();
      await _persistMessage(
        role: 'user',
        content: content,
        mode: isLowMood ? 'low_mood' : 'normal',
      );
      if (!remoteEnabled || activeSessionId == null) {
        remoteError = 'Supabase 未配置或未登录，无法获取 AI 回复。';
        notifyListeners();
        return;
      }
      // 占位消息：随流式增量不断替换，避免等待期间界面毫无反馈
      var reply = '';
      final replyTime = timeNow();
      target.add(ChatMessage(isUser: false, content: '', time: replyTime));
      final placeholderIndex = target.length - 1;
      notifyListeners();
      var lastPaintedAt = DateTime.now();
      try {
        await const AiService().streamReply(
          sessionId: activeSessionId!,
          mode: isLowMood ? 'low_mood' : 'normal',
          onDelta: (delta) {
            reply += delta;
            // 增量很碎（一秒可达几十段），节流重绘避免整帧重建过于频繁
            final now = DateTime.now();
            if (now.difference(lastPaintedAt).inMilliseconds < 60) return;
            lastPaintedAt = now;
            _replaceMessage(target, placeholderIndex, reply, replyTime);
          },
          onDone: (finalReply) async {
            // 服务端交回的最终文本是权威版本（模型返回短纯文本时不会有增量），
            // 顺带补画节流期间的最后一段
            if (finalReply.isNotEmpty) reply = finalReply;
            _replaceMessage(target, placeholderIndex, reply, replyTime);
            _refreshActiveConversationPreview();
            // 助手回复、记忆落库、向量化、目标阶段更新均由后端 explore-conversation 完成
            await _refreshMemoriesAndGoals();
          },
        );
      } catch (error) {
        if (reply.isEmpty && placeholderIndex < target.length) {
          target.removeAt(placeholderIndex);
        }
        remoteError = error.toString();
        notifyListeners();
      }
    } finally {
      // 切换目标时若这条消息的流式回复还在途，等结束后再清空会话，开启新对话
      if (_pendingNewChat) startNewConversation();
      chatSending = false;
    }
  }

  /// ChatMessage.content 是 final，流式更新只能整体替换这一条
  void _replaceMessage(
    List<ChatMessage> target,
    int index,
    String content,
    String time,
  ) {
    if (index < 0 || index >= target.length) return;
    target[index] = ChatMessage(isUser: false, content: content, time: time);
    notifyListeners();
  }

  Future<void> _refreshMemoriesAndGoals() async {
    final client = SupabaseService.client;
    if (client == null || client.auth.currentUser == null) return;
    try {
      final remoteGoals = await GoalRepository(client).listGoals();
      if (remoteGoals.isNotEmpty) {
        goals
          ..clear()
          ..addAll(remoteGoals.map(_goalFromRow));
      }
      final remoteMemories = await MemoryRepository(client).listMemories();
      if (remoteMemories.isNotEmpty) {
        memories
          ..clear()
          ..addAll(remoteMemories.map(_memoryFromRow));
      }
      if (goals.isNotEmpty &&
          (selectedGoalId.isEmpty ||
              !goals.any((g) => g.id == selectedGoalId))) {
        _resetSelectedGoalToMain();
      }
      notifyListeners();
    } catch (error) {
      remoteError = error.toString();
      notifyListeners();
    }
  }

  void _refreshActiveConversationPreview() {
    if (activeConversationIndex < 0 ||
        activeConversationIndex >= conversations.length) {
      return;
    }
    final conversation = conversations[activeConversationIndex];
    conversation.messages
      ..clear()
      ..addAll(messages);
    conversations[activeConversationIndex] = ConversationSummary(
      id: conversation.id,
      title: conversation.title,
      date: '刚刚',
      preview: messages.isEmpty ? conversation.preview : messages.last.content,
      messages: conversation.messages,
    );
    notifyListeners();
  }

  Future<void> _persistMessage({
    required String role,
    required String content,
    String mode = 'normal',
  }) async {
    final client = SupabaseService.client;
    if (client == null || client.auth.currentUser == null) return;
    try {
      final repository = ConversationRepository(client);
      final shouldCreateSummary = activeSessionId == null;
      activeSessionId ??= await repository.createSession(
        title: '新的对话',
        mode: mode,
      );
      // 消息已归属具体会话：切换目标带来的新对话空态就此解除
      _pendingNewChat = false;
      if (shouldCreateSummary) {
        // 新会话先落一条 AI 欢迎语（与目标共创的开场一致），失败不阻塞消息发送；
        // 本地同步补上，避免发送后欢迎语凭空消失
        try {
          await repository.addMessage(
            sessionId: activeSessionId!,
            role: 'assistant',
            content: chatGreeting,
          );
          messages.insert(
            0,
            ChatMessage(isUser: false, content: chatGreeting, time: ''),
          );
        } catch (_) {}
        conversations.insert(
          0,
          ConversationSummary(
            id: activeSessionId,
            title: '新的对话',
            date: '刚刚',
            preview: content,
            messages: List<ChatMessage>.from(messages),
          ),
        );
        activeConversationIndex = 0;
      }
      await repository.addMessage(
        sessionId: activeSessionId!,
        role: role,
        content: content,
      );
    } catch (error) {
      remoteError = error.toString();
      notifyListeners();
    }
  }

  Goal _goalFromRow(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? 'exploring';
    return Goal(
      id:
          row['id']?.toString() ??
          'goal-${DateTime.now().microsecondsSinceEpoch}',
      title: row['title']?.toString() ?? '未命名目标',
      description: row['description']?.toString() ?? '',
      phase: _goalPhase(status),
      progress: _intValue(row['progress']),
      status: _goalStatus(status),
      rawStatus: status,
      icon: Icons.adjust_rounded,
      accent: purple,
      milestone: row['success_definition']?.toString() ?? '持续完成下一步行动',
      isMainGoal: row['is_main_goal'] == true,
      stages: (row['stages'] is List)
          ? List<Map<String, dynamic>>.from(row['stages'])
          : [],
    );
  }

  MemoryItem _memoryFromRow(Map<String, dynamic> row) {
    final type = row['type']?.toString() ?? 'thought';
    final createdAt = row['created_at'];
    return MemoryItem(
      date: _dateLabel(createdAt),
      month: _monthLabel(createdAt),
      type: _memoryType(type),
      title: row['summary']?.toString() ?? row['content']?.toString() ?? '',
      detail: row['content']?.toString() ?? '',
      icon: _memoryIcon(type),
      tone: _memoryTone(type),
    );
  }

  ChatMessage _messageFromRow(Map<String, dynamic> row) {
    return ChatMessage(
      isUser: row['role']?.toString() == 'user',
      content: row['content']?.toString() ?? '',
      time: _timeLabel(row['created_at']),
    );
  }

  int _intValue(dynamic value) {
    if (value is int) return value.clamp(0, 100);
    return int.tryParse(value?.toString() ?? '')?.clamp(0, 100) ?? 0;
  }

  String _goalPhase(String status) {
    switch (status) {
      case 'active':
        return '进行期';
      case 'paused':
        return '暂停期';
      case 'blocked':
        return '受阻期';
      case 'completed':
        return '完成期';
      case 'archived':
        return '归档';
      default:
        return '探索期';
    }
  }

  String _goalStatus(String status) {
    switch (status) {
      case 'active':
        return '进行中';
      case 'paused':
        return '暂停中';
      case 'blocked':
        return '受阻';
      case 'completed':
        return '已完成';
      case 'archived':
        return '已归档';
      default:
        return '探索中';
    }
  }

  String _databaseGoalStatus(String status) {
    switch (status) {
      case '进行中':
        return 'active';
      case '暂停中':
        return 'paused';
      case '已完成':
        return 'completed';
      default:
        return 'exploring';
    }
  }

  String _memoryType(String type) {
    const labels = {
      'event': '成长事件',
      'decision': '关键决定',
      'reflection': '反思',
      'achievement': '成就',
      'failure': '挫折',
      'emotion': '情绪',
      'thought': '想法',
    };
    return labels[type] ?? '成长记录';
  }

  IconData _memoryIcon(String type) {
    switch (type) {
      case 'decision':
        return Icons.edit_note_rounded;
      case 'reflection':
        return Icons.chat_bubble_outline_rounded;
      case 'achievement':
        return Icons.auto_awesome_rounded;
      case 'emotion':
        return Icons.favorite_border_rounded;
      default:
        return Icons.check_rounded;
    }
  }

  Color _memoryTone(String type) {
    switch (type) {
      case 'decision':
      case 'failure':
        return const Color(0xFFE58370);
      case 'reflection':
      case 'emotion':
        return const Color(0xFF43A98A);
      case 'achievement':
        return const Color(0xFFD9962B);
      default:
        return purple;
    }
  }

  String _dateLabel(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '刚刚';
    return '${date.month} 月 ${date.day} 日 ${_timeLabel(date)}';
  }

  String _monthLabel(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '最近';
    return '${date.month} 月';
  }

  String _timeLabel(dynamic value) {
    final date = value is DateTime
        ? value.toLocal()
        : DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return timeNow();
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void setFilter(String value) {
    memoryFilter = value;
    notifyListeners();
  }

  List<MemoryItem> get filteredMemories => memoryFilter == '全部'
      ? memories
      : memories.where((memory) => memory.type.contains(memoryFilter)).toList();

  String timeNow() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

class ExploreApp extends StatefulWidget {
  const ExploreApp({super.key});

  @override
  State<ExploreApp> createState() => _ExploreAppState();
}

class _ExploreAppState extends State<ExploreApp> {
  final store = ExploreStore();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '探境 · Explore',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: pageBg,
          colorScheme: ColorScheme.fromSeed(seedColor: purple),
          fontFamily: 'Avenir',
          textTheme: const TextTheme(bodyMedium: TextStyle(color: ink)),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.12)),
          child: child!,
        ),
        home: AuthGate(store: store),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.store});
  final ExploreStore store;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription? _authSubscription;
  bool _authenticated = false;

  @override
  void initState() {
    super.initState();
    _authenticated = const AuthService().currentUser != null;
    final client = SupabaseService.client;
    if (client != null) {
      _authSubscription = const AuthService().authStateChanges.listen((state) {
        if (!mounted) return;
        setState(() => _authenticated = state.session != null);
        if (state.session != null) widget.store.loadRemoteData();
      });
      if (_authenticated) widget.store.loadRemoteData();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (SupabaseService.client == null || _authenticated) {
      return ExploreShell(store: widget.store);
    }
    return AuthScreen(store: widget.store);
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.store});
  final ExploreStore store;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nicknameController = TextEditingController();
  bool isSignUp = false;
  bool submitting = false;
  String? errorMessage;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nicknameController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    if (email.isEmpty || password.length < 6) {
      setState(() => errorMessage = '请输入邮箱和至少 6 位密码。');
      return;
    }
    setState(() {
      submitting = true;
      errorMessage = null;
    });
    try {
      final auth = const AuthService();
      final response = isSignUp
          ? await auth.signUp(
              email: email,
              password: password,
              nickname: nicknameController.text.trim(),
            )
          : await auth.signIn(email: email, password: password);
      if (!mounted) return;
      if (response.session == null && isSignUp) {
        setState(() {
          submitting = false;
          errorMessage = '注册成功，请先完成邮箱确认，再回来登录。';
        });
      } else if (response.session != null) {
        setState(() => submitting = false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        errorMessage = _authError(error);
      });
    }
  }

  String _authError(Object error) {
    final message = error.toString();
    if (message.contains('Invalid login credentials')) return '邮箱或密码不正确。';
    if (message.contains('User already registered')) return '这个邮箱已经注册过了。';
    return '操作失败，请检查 Supabase 配置后重试。';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: purple,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.explore_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    isSignUp ? '开始你的探境' : '欢迎回来',
                    style: const TextStyle(
                      color: ink,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isSignUp ? '创建账号，保存你的成长轨迹。' : '登录后继续你的成长探索。',
                    style: const TextStyle(color: muted, fontSize: 17),
                  ),
                  const SizedBox(height: 28),
                  if (isSignUp) ...[
                    _authField(
                      nicknameController,
                      '昵称（可选）',
                      Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 14),
                  ],
                  _authField(emailController, '邮箱', Icons.mail_outline_rounded),
                  const SizedBox(height: 14),
                  _authField(
                    passwordController,
                    '密码',
                    Icons.lock_outline_rounded,
                    obscure: true,
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: Color(0xFFD75B50)),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: submitting ? null : submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: purple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: submitting
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(isSignUp ? '注册' : '登录'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() {
                        isSignUp = !isSignUp;
                        errorMessage = null;
                      }),
                      child: Text(isSignUp ? '已有账号？去登录' : '还没有账号？去注册'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _authField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: hint == '邮箱'
          ? TextInputType.emailAddress
          : TextInputType.text,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: line),
        ),
      ),
    );
  }
}

class ExploreShell extends StatelessWidget {
  const ExploreShell({super.key, required this.store});
  final ExploreStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PopScope(
        // 安卓系统返回：子页面先回上级，一级页面才允许退出应用
        canPop: !store.isSubPage,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) store.goBack();
        },
        child: _EdgeSwipeBack(
          enabled: store.isSubPage,
          onBack: store.goBack,
          child: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              reverseDuration: const Duration(milliseconds: 140),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                final offset =
                    Tween<Offset>(
                      begin: const Offset(0.012, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(store.page),
                child: _page(context),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  Widget _page(BuildContext context) {
    switch (store.page) {
      case ExplorePage.home:
        return HomeScreen(store: store);
      case ExplorePage.growth:
        return GrowthScreen(store: store);
      case ExplorePage.chat:
        return ChatScreen(store: store);
      case ExplorePage.report:
        return ReportScreen(store: store);
      case ExplorePage.goalDetail:
        return GoalDetailScreen(store: store);
      case ExplorePage.goalCreate:
        return GoalCreateScreen(store: store);
      case ExplorePage.goalCreated:
        return GoalCreatedScreen(store: store);
    }
  }

  /// 共创目标页不显示底部导航。这里必须返回 null，不能用 `SizedBox.shrink()` 占位：
  /// Scaffold 只要发现 bottomNavigationBar 非空，就会把 body 的底部安全区一起去掉
  /// （它假定底栏自己消费了这段安全区，见 Scaffold 源码里的 removeBottomPadding），
  /// 而零尺寸占位并不消费安全区，页面会连安全区一并丢掉、输入框贴到屏幕底边。
  Widget? _bottomNav() {
    const items = [
      (Icons.home_rounded, '首页'),
      (Icons.insights_rounded, '成长'),
      (Icons.chat_bubble_outline_rounded, '对话'),
      (Icons.person_outline_rounded, '我的'),
    ];
    if (store.page == ExplorePage.goalCreate) return null;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: line)),
      ),
      child: NavigationBar(
        height: 68,
        selectedIndex: store.selectedNav,
        backgroundColor: Colors.white,
        indicatorColor: violetBg,
        onDestinationSelected: (index) => store.goToPage(
          ExploreStore.navPages[index],
          // 从底部导航进对话页回到最近一次会话（resetChat 对其它页面无效）
          resetChat: true,
        ),
        destinations: [
          for (final item in items)
            NavigationDestination(
              icon: Icon(item.$1, size: 20),
              selectedIcon: Icon(item.$1, size: 20),
              label: item.$2,
            ),
        ],
      ),
    );
  }
}

/// 「左滑返回」的轻量实现：整个应用是单路由状态切页、没有路由栈，
/// 系统的边缘返回手势不会触发，于是在子页面里识别左边缘右滑来补齐。
class _EdgeSwipeBack extends StatefulWidget {
  const _EdgeSwipeBack({
    required this.enabled,
    required this.onBack,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onBack;
  final Widget child;

  @override
  State<_EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<_EdgeSwipeBack> {
  // 起点须落在左边缘区域内；滑出该距离或快速右甩时触发返回
  static const double _edgeWidth = 24;
  static const double _triggerDistance = 56;
  static const double _flingVelocity = 500;

  double _distance = 0;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    // 手势条单独占左缘一条竖带、处于命中测试最上层：真机上手指滑动多是斜向，
    // 若把识别器包在整页外层，它在手势竞技场里排在正文之后、斜向滑动会输给滚动；
    // 独立竖带让边缘滑动稳定获胜，也不影响正文区域的任何手势。
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _edgeWidth,
          child: SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _distance = 0,
              onHorizontalDragUpdate: (details) =>
                  _distance += details.primaryDelta ?? 0,
              onHorizontalDragEnd: (details) {
                final flingRight =
                    details.velocity.pixelsPerSecond.dx >= _flingVelocity;
                if (_distance >= _triggerDistance || flingRight) {
                  widget.onBack();
                }
                _distance = 0;
              },
            ),
          ),
        ),
      ],
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});
  final ExploreStore store;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ExploreAppBar(
        leading: const Brand(),
        actions: [_NotificationButton(store: store)],
      ),
      Expanded(child: _content()),
    ],
  );

  Widget _content() {
    final greeting = greetingFor(DateTime.now());
    return AppScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (store.actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ProactiveBanner(
              action: store.actions.first,
              onDismiss: () => store.dismissAction(
                store.actions.first['id']?.toString() ?? '',
              ),
            ),
          ],
          const SizedBox(height: 24),
          Eyebrow('${DateTime.now().month} 月 ${DateTime.now().day} 日'),
          const SizedBox(height: 7),
          Text(
            '$greeting ✦',
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '今天也和自己靠近一点。',
            style: TextStyle(color: muted, fontSize: 14.5),
          ),
          const SizedBox(height: 25),
          _HeroCard(store: store),
          const SizedBox(height: 27),
          SectionTitle(
            eyebrow: 'AI 今日观察',
            title: '给你的一个发现',
            action: '查看周报',
            onTap: () => store.goToPage(ExplorePage.report),
          ),
          const SizedBox(height: 13),
          if (store.observations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  '还没有新的观察。',
                  style: TextStyle(color: muted, fontSize: 14),
                ),
              ),
            )
          else
            for (final observation in store.observations.take(3))
              _ObservationCard(store: store, observation: observation),
          const SizedBox(height: 27),
          SectionTitle(
            eyebrow: '正在靠近',
            title: '当前主目标',
            action: '切换',
            onTap: () => store.goToPage(ExplorePage.growth),
          ),
          const SizedBox(height: 13),
          if (store.goals.isEmpty)
            _EmptyGoalCard(store: store)
          else
            GoalTile(
              goal: store.currentGoal,
              featured: true,
              onTap: () => store.openGoal(store.currentGoal),
            ),
          const SizedBox(height: 28),
          SectionTitle(
            eyebrow: '留下来的痕迹',
            title: '最近成长记录',
            action: '查看全部',
            onTap: () =>
                store.goToPage(ExplorePage.growth, tab: GrowthTab.memory),
          ),
          const SizedBox(height: 8),
          for (final memory in store.memories.take(3))
            MemoryTile(memory: memory),
        ],
      ),
    );
  }
}

/// 统一顶栏：所有页面共用同一套高度、间距与排版，固定在滚动区之上。
class ExploreAppBar extends StatelessWidget {
  const ExploreAppBar({
    super.key,
    this.onBack,
    this.backLabel = '返回',
    this.leading,
    this.title,
    this.subtitle,
    this.actions = const <Widget>[],
  });

  final VoidCallback? onBack;
  final String backLabel;
  final Widget? leading;
  final String? title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    color: pageBg,
    padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
    child: Row(
      children: [
        if (onBack != null)
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
            label: Text(backLabel, style: const TextStyle(fontSize: 13)),
            style: TextButton.styleFrom(
              foregroundColor: muted,
              padding: EdgeInsets.zero,
            ),
          ),
        if (leading != null) ...[
          if (onBack != null) const SizedBox(width: 14),
          leading!,
        ],
        if (title != null || subtitle != null) ...[
          if (onBack != null || leading != null) const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 13),
                  ),
              ],
            ),
          ),
        ] else
          const Spacer(),
        ...actions,
      ],
    ),
  );
}

/// 首页顶栏的铃铛按钮，打开「探境的消息」面板
class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.store});
  final ExploreStore store;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '探境的消息',
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '探境的消息',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (store.actions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            '暂时没有新的消息。',
                            style: TextStyle(color: muted, fontSize: 14),
                          ),
                        ),
                      )
                    else
                      for (final action in store.actions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                color: purple,
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  action['content']?.toString() ?? '',
                                  style: const TextStyle(
                                    color: Color(0xFF5C55A2),
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => store.dismissAction(
                                  action['id']?.toString() ?? '',
                                ),
                                child: const Text(
                                  '知道了',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      icon: const Icon(
        Icons.notifications_none_rounded,
        color: muted,
        size: 21,
      ),
    );
  }
}

class Brand extends StatelessWidget {
  const Brand({super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          'assets/logo.png',
          width: 30,
          height: 30,
          fit: BoxFit.cover,
        ),
      ),
      const SizedBox(width: 9),
      const Text(
        '探境',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
      ),
    ],
  );
}

class _GrowthComposition extends StatelessWidget {
  const _GrowthComposition({required this.profile});
  final Map<String, dynamic>? profile;

  List<Map<String, dynamic>> _items(String key) {
    final raw = profile?[key];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  int _value(dynamic v) {
    final n = int.tryParse(v?.toString() ?? '');
    return n == null ? 0 : n.clamp(0, 100);
  }

  Widget _bar(String name, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              name,
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: value / 100,
                minHeight: 6,
                color: color,
                backgroundColor: const Color(0xFFEEEEF7),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(
              '$value%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: purple,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final composition = _items('growth_composition');
    final dimensions = _items('growth_dimensions');
    if (composition.isEmpty && dimensions.isEmpty) {
      return const SizedBox.shrink();
    }
    return WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(eyebrow: '成长路径', title: '多维成长构成'),
          const SizedBox(height: 14),
          for (final d in composition)
            _bar(d['name']?.toString() ?? '', _value(d['ratio']), purple),
          if (dimensions.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final d in dimensions)
              _bar(
                d['name']?.toString() ?? '',
                _value(d['score']),
                const Color(0xFFE6A04E),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.onRegenerate});
  final Map<String, dynamic> profile;
  final VoidCallback onRegenerate;

  Widget _tags(String key) {
    final v = profile[key];
    if (v is! List || v.isEmpty) {
      return const Text('暂无', style: TextStyle(color: muted, fontSize: 13));
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in v)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: violetBg,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              t.toString(),
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => WhiteCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Eyebrow('你的画像'),
            TextButton(
              onPressed: onRegenerate,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: purple,
              ),
              child: const Text(
                '重新生成',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          profile['ai_summary']?.toString() ?? '',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        for (final g in [
          ['personality', '性格'],
          ['values', '价值观'],
          ['interests', '兴趣'],
          ['strengths', '优势'],
          ['weaknesses', '待改进'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    g[1],
                    style: const TextStyle(color: muted, fontSize: 13),
                  ),
                ),
                Expanded(child: _tags(g[0])),
              ],
            ),
          ),
      ],
    ),
  );
}

class _ProactiveBanner extends StatelessWidget {
  const _ProactiveBanner({required this.action, required this.onDismiss});
  final Map<String, dynamic> action;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: violetBg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE5E2FF)),
    ),
    child: Row(
      children: [
        const Icon(Icons.auto_awesome_rounded, color: purple, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            action['content']?.toString() ?? '',
            style: const TextStyle(
              color: Color(0xFF5C55A2),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
        TextButton(
          onPressed: onDismiss,
          style: TextButton.styleFrom(
            foregroundColor: purple,
            padding: EdgeInsets.zero,
          ),
          child: const Text(
            '知道了',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _EmptyGoalCard extends StatelessWidget {
  const _EmptyGoalCard({required this.store});
  final ExploreStore store;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: violetBg,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '还没有目标',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '和探境聊聊你想成为的样子，一起找到第一个方向。',
          style: TextStyle(color: muted, fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () => store.openGoalCreate(),
          icon: const Icon(Icons.add_rounded, size: 14),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
            foregroundColor: purple,
            visualDensity: VisualDensity.compact,
          ),
          label: const Text(
            '创建第一个目标',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.store});
  final ExploreStore store;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(23),
      gradient: const LinearGradient(
        colors: [Color(0xFFECEBFF), Color(0xFFF2F8FF)],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('今天，探境观察到'),
        const SizedBox(height: 11),
        Text(
          store.goals.isEmpty
              ? '你正在靠近\n「一个属于你的方向」。'
              : '你正在靠近\n「${store.currentGoal.title}」。',
          style: const TextStyle(
            fontSize: 22,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          store.goals.isEmpty
              ? '还没有目标。先和探境聊聊，一起找到第一步。'
              : '下一步：${store.dailySuggestion.isNotEmpty ? store.dailySuggestion : (store.currentGoal.milestone.isEmpty ? '从一个小行动开始' : store.currentGoal.milestone)}。',
          style: const TextStyle(
            color: muted,
            fontSize: 14,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 18),
        PrimaryButton(
          label: '和我聊聊',
          icon: Icons.arrow_forward_rounded,
          onTap: () => store.openChat(),
        ),
      ],
    ),
  );
}

class _ObservationCard extends StatelessWidget {
  const _ObservationCard({required this.store, required this.observation});
  final ExploreStore store;
  final Map<String, dynamic> observation;

  @override
  Widget build(BuildContext context) {
    final content = observation['content']?.toString() ?? '';
    final title = content.isEmpty
        ? '新的观察'
        : (content.length > 24 ? content.substring(0, 24) : content);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 29,
            height: 29,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: violetBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: purple,
              size: 16,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            content.isEmpty ? '开始一次对话，让探境更了解你。' : content,
            style: const TextStyle(
              color: muted,
              fontSize: 13,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () => store.markObservationRead(
              observation['id']?.toString() ?? '',
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: purple,
            ),
            child: const Text(
              '标记已读  →',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class GrowthScreen extends StatelessWidget {
  const GrowthScreen({super.key, required this.store});
  final ExploreStore store;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const ExploreAppBar(title: '成长'),
      _GrowthTabBar(store: store),
      Expanded(
        child: store.growthTab == GrowthTab.memory
            ? MemoryScreen(store: store)
            : _GrowthGoalView(store: store),
      ),
    ],
  );
}

class _GrowthTabBar extends StatelessWidget {
  const _GrowthTabBar({required this.store});
  final ExploreStore store;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
    child: Row(
      children: [
        for (final (tab, label) in const [
          (GrowthTab.goal, '成长目标'),
          (GrowthTab.memory, '记忆时间线'),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: store.growthTab == tab ? purple : muted,
                ),
              ),
              selected: store.growthTab == tab,
              onSelected: (_) => store.setGrowthTab(tab),
              showCheckmark: false,
              side: BorderSide.none,
              backgroundColor: const Color(0xFFF0EFF8),
              selectedColor: violetBg,
            ),
          ),
      ],
    ),
  );
}

class _GrowthGoalView extends StatelessWidget {
  const _GrowthGoalView({required this.store});
  final ExploreStore store;

  @override
  Widget build(BuildContext context) => AppScroll(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: violetBg,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow('当前专注'),
                    SizedBox(height: 8),
                    Text(
                      '一条路，也可以走得很深。',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '此刻只需要把注意力交给最重要的一个。',
                      style: TextStyle(color: muted, fontSize: 13, height: 1.6),
                    ),
                  ],
                ),
              ),
              _Stat(number: '${store.goals.length}', label: '个方向'),
            ],
          ),
        ),
        const SizedBox(height: 27),
        SectionTitle(
          eyebrow: '你的方向',
          title: '全部目标',
          action: '＋ 新建目标',
          onTap: store.openGoalCreate,
        ),
        const SizedBox(height: 13),
        if (store.goals.isEmpty)
          _EmptyGoalCard(store: store)
        else
          for (final goal in store.goals)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GoalTile(
                goal: goal,
                featured: goal.id == store.currentGoal.id,
                onTap: () => store.openGoal(goal),
              ),
            ),
        const SizedBox(height: 10),
        const TipCard(),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.number, required this.label});
  final String number;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        number,
        style: const TextStyle(
          color: purple,
          fontWeight: FontWeight.w700,
          fontSize: 26,
        ),
      ),
      Text(label, style: const TextStyle(color: muted, fontSize: 11)),
    ],
  );
}

class GoalTile extends StatelessWidget {
  const GoalTile({
    super.key,
    required this.goal,
    required this.onTap,
    this.featured = false,
  });
  final Goal goal;
  final VoidCallback onTap;
  final bool featured;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: featured ? const Color(0xFF8278EF) : line,
          width: featured ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .03),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 33,
                height: 33,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: goal.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(goal.icon, color: goal.accent, size: 19),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  featured ? '当前主目标' : goal.status,
                  style: TextStyle(
                    color: featured ? purple : goal.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFB5B5C7),
                size: 19,
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            goal.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            goal.description,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 15),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: goal.progress / 100,
              minHeight: 5,
              backgroundColor: const Color(0xFFF0EFF7),
              color: purple,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                goal.phase,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
              Text(
                '${goal.progress}%',
                style: const TextStyle(
                  color: purple,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key, required this.store});
  final ExploreStore store;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<MemoryItem>>{};
    for (final memory in store.filteredMemories) {
      groups.putIfAbsent(memory.month, () => []).add(memory);
    }
    final timeline = <Widget>[];
    if (store.filteredMemories.isEmpty) {
      final hasAnyMemory = store.memories.isNotEmpty;
      timeline.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            children: [
              Text(
                hasAnyMemory ? '这个分类还没有记忆。' : '还没有成长记录。',
                style: const TextStyle(color: muted, fontSize: 14),
              ),
              if (!hasAnyMemory) ...[
                const SizedBox(height: 8),
                const Text(
                  '记忆来自对话：当你说出决定、情绪、反思或成果时，探境会把它留下来。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 13, height: 1.7),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () =>
                      store.goToPage(ExplorePage.chat, resetChat: true),
                  style: TextButton.styleFrom(
                    foregroundColor: purple,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text(
                    '去和探境聊聊  →',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    } else {
      for (final entry in groups.entries) {
        timeline.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.key,
                style: const TextStyle(
                  color: muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              for (final memory in entry.value) MemoryTile(memory: memory),
              const SizedBox(height: 16),
            ],
          ),
        );
      }
    }
    return AppScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF252544),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '“ 每一次诚实的表达，\n都在帮我更了解你。 ”',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                height: 1.5,
              ),
            ),
          ),
          if (store.timelineSummary != null || store.memories.length >= 3) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('成长阶段总结'),
                  const SizedBox(height: 8),
                  Text(
                    store.timelineSummary ?? '让探境帮你回顾这段成长轨迹。',
                    style: const TextStyle(
                      color: Color(0xFF4A4A63),
                      fontSize: 14,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: store.generateTimelineSummary,
                    style: TextButton.styleFrom(
                      foregroundColor: purple,
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(
                      store.timelineSummary != null ? '重新生成' : '生成总结',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 27),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Eyebrow('成长时间线'),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final filter in ['全部', '事件', '决定', '反思', '成就'])
                        Padding(
                          padding: const EdgeInsets.only(left: 5),
                          child: FilterChip(
                            label: Text(
                              filter,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: store.memoryFilter == filter
                                    ? purple
                                    : muted,
                              ),
                            ),
                            selected: store.memoryFilter == filter,
                            onSelected: (_) => store.setFilter(filter),
                            showCheckmark: false,
                            side: BorderSide.none,
                            backgroundColor: const Color(0xFFF0EFF8),
                            selectedColor: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ...timeline,
        ],
      ),
    );
  }
}

class MemoryTile extends StatelessWidget {
  const MemoryTile({super.key, required this.memory});
  final MemoryItem memory;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 13),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: memory.tone.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(memory.icon, size: 16, color: memory.tone),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    memory.type,
                    style: const TextStyle(color: muted2, fontSize: 11.5),
                  ),
                  const Spacer(),
                  Text(
                    memory.date,
                    style: const TextStyle(color: muted2, fontSize: 11.5),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                memory.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                memory.detail,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.store});
  final ExploreStore store;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final controller = TextEditingController();
  final inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 开始输入（键盘弹起或输入了文字）时收起建议区，避免它挤压、遮挡消息
    inputFocus.addListener(_refreshTypingState);
    controller.addListener(_refreshTypingState);
  }

  @override
  void dispose() {
    inputFocus.removeListener(_refreshTypingState);
    controller.removeListener(_refreshTypingState);
    inputFocus.dispose();
    controller.dispose();
    super.dispose();
  }

  void _refreshTypingState() {
    if (!mounted) return;
    setState(() {});
  }

  bool get typing => inputFocus.hasFocus || controller.text.isNotEmpty;

  void send() {
    widget.store.sendMessage(controller.text);
    controller.clear();
  }

  void showHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ConversationHistorySheet(store: widget.store),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ExploreAppBar(
        title: '对话',
        actions: [
          if (!widget.store.lowMood)
            IconButton(
              tooltip: '新增对话',
              onPressed: widget.store.startNewConversation,
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.add_comment_outlined,
                color: muted,
                size: 20,
              ),
            ),
          IconButton(
            tooltip: '历史会话',
            onPressed: showHistory,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.history_rounded, color: muted, size: 20),
          ),
          if (widget.store.lowMood)
            TextButton(
              onPressed: () {
                widget.store.exitLowMood();
              },
              child: const Text(
                '返回日常',
                style: TextStyle(color: purple, fontSize: 13),
              ),
            ),
        ],
      ),
      Expanded(
        child: GestureDetector(
          // 点按消息区域任意位置收起键盘
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Column(
            children: [
              // 空会话：AI 欢迎语固定在消息区顶部（与目标共创的开场一致）；
              // 发出第一条消息时由 _persistMessage 落库，此后保留在会话历史里
              if (widget.store.messages.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 11, 20, 0),
                  child: ChatBubble(
                    key: const ValueKey('chat-greeting'),
                    message: ChatMessage(
                      isUser: false,
                      content: chatGreeting,
                      time: '',
                    ),
                  ),
                ),
              Expanded(
                // reverse: true 让列表默认停在最新消息处（视觉底部），新消息和流式回复也自动贴底
                child: ListView(
                  reverse: true,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
                  children: [
                    if (!typing) ...[
                      _ChatSuggestions(store: widget.store, controller: controller),
                      const SizedBox(height: 12),
                    ],
                    for (final message in widget.store.visibleMessages.reversed)
                      // key 让消息在建议区收起/展开（列表头部增删）时保持元素对位，
                      // 否则 MarkdownBody 会按索引错位复用，销毁时可能触发断言
                      ChatBubble(key: ValueKey(message), message: message),
                    const SizedBox(height: 20),
                    if (widget.store.lowMood)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 18),
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: violetBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded, size: 15, color: purple),
                            SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                '你不用现在就解决所有问题，我们先一起理解它。',
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Center(
                      child: Text(
                        '今天 · 8 月 9 日',
                        style: const TextStyle(color: muted2, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 7, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: inputFocus,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: widget.store.lowMood ? '把此刻的感受告诉我……' : '写下你的想法……',
                  hintStyle: const TextStyle(
                    color: muted2,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: line),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleButton(icon: Icons.arrow_upward_rounded, onTap: send),
          ],
        ),
      ),
    ],
  );
}

class ConversationHistorySheet extends StatelessWidget {
  const ConversationHistorySheet({super.key, required this.store});
  final ExploreStore store;

  @override
  Widget build(BuildContext context) => Container(
    height: MediaQuery.of(context).size.height * .72,
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
    ),
    child: SafeArea(
      child: Column(
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: line,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow('CONVERSATION OS'),
                    SizedBox(height: 6),
                    Text(
                      '历史会话',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '每一次对话，都是理解你的一个入口。',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: ListView.separated(
              itemCount: store.conversations.length,
              separatorBuilder: (_, _) => const Divider(color: line, height: 1),
              itemBuilder: (context, index) {
                final conversation = store.conversations[index];
                final active = index == store.activeConversationIndex;
                // 外层白色 Container 会挡住 ListTile 的水波纹，这里补一层 Material
                return Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    leading: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? violetBg : const Color(0xFFF6F6FB),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        active
                            ? Icons.chat_rounded
                            : Icons.chat_bubble_outline_rounded,
                        color: active ? purple : muted,
                        size: 19,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.title,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (active)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: mintBg,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Text(
                              '当前',
                              style: TextStyle(
                                color: Color(0xFF43A98A),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        conversation.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 13),
                      ),
                    ),
                    trailing: Text(
                      conversation.date,
                      style: const TextStyle(
                        color: muted2,
                        fontSize: 11,
                      ),
                    ),
                    onTap: () {
                      store.loadConversation(index);
                      Navigator.of(context).pop();
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChatSuggestions extends StatelessWidget {
  const _ChatSuggestions({required this.store, required this.controller});
  final ExploreStore store;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final suggestions = store.lowMood
        ? ['把目标拆小一点', '重新看看为什么出发']
        : ['我不知道下一步做什么', '帮我回顾最近的成长', '我有点累，想放弃'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('可以这样开始'),
        const SizedBox(height: 9),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final suggestion in suggestions)
              ActionChip(
                label: Text(
                  suggestion,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 13,
                  ),
                ),
                side: const BorderSide(color: Color(0xFFECEBFA)),
                backgroundColor: const Color(0xFFFAF9FF),
                onPressed: () {
                  if (suggestion.contains('放弃')) {
                    store.openChat(withLowMood: true);
                  } else {
                    controller.text = suggestion;
                  }
                },
              ),
          ],
        ),
      ],
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});
  final ChatMessage message;

  // 助手回复是 Markdown（与 Web 端 MarkdownText 的渲染对齐），
  // 样式尽量贴近气泡里普通文本的观感
  static final MarkdownStyleSheet _assistantStyle = MarkdownStyleSheet(
    p: const TextStyle(color: Color(0xFF4A4A63), fontSize: 14, height: 1.65),
    h1: const TextStyle(
      color: Color(0xFF4A4A63),
      fontSize: 14.5,
      fontWeight: FontWeight.w700,
    ),
    h2: const TextStyle(
      color: Color(0xFF4A4A63),
      fontSize: 14.5,
      fontWeight: FontWeight.w700,
    ),
    h3: const TextStyle(
      color: Color(0xFF4A4A63),
      fontSize: 14.5,
      fontWeight: FontWeight.w700,
    ),
    listBullet: const TextStyle(color: Color(0xFF4A4A63), fontSize: 14),
    a: const TextStyle(color: Color(0xFF5C55A2)),
    code: const TextStyle(
      color: Color(0xFF5C55A2),
      fontSize: 13,
      backgroundColor: Color(0x145C55A2),
    ),
    blockquote: const TextStyle(
      color: muted,
      fontSize: 13,
      height: 1.6,
    ),
    blockquoteDecoration: const BoxDecoration(
      border: Border(left: BorderSide(color: Color(0xFFD5D2F2), width: 2)),
    ),
  );

  @override
  Widget build(BuildContext context) => Align(
    alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) const AgentAvatar(small: true),
          if (!message.isUser) const SizedBox(width: 8),
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 285),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: message.isUser
                    ? const Color(0xFFE5E2FF)
                    : const Color(0xFFF5F5FB),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(15),
                  topRight: const Radius.circular(15),
                  bottomLeft: Radius.circular(message.isUser ? 15 : 5),
                  bottomRight: Radius.circular(message.isUser ? 5 : 15),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Align(alignment: Alignment.centerLeft, child: _content()),
                  const SizedBox(height: 5),
                  Text(
                    message.time,
                    style: const TextStyle(
                      color: muted2,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _content() {
    if (message.isUser) {
      return Text(
        message.content,
        style: const TextStyle(
          color: Color(0xFF5C55A2),
          fontSize: 14,
          height: 1.65,
        ),
      );
    }
    // 流式回复开始时内容为空，先给一个占位提示
    if (message.content.isEmpty) {
      return const Text(
        '正在思考…',
        style: TextStyle(color: Color(0xFF4A4A63), fontSize: 14, height: 1.65),
      );
    }
    return MarkdownBody(data: message.content, styleSheet: _assistantStyle);
  }
}

class AgentAvatar extends StatelessWidget {
  const AgentAvatar({super.key, this.small = false});
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    width: small ? 29 : 38,
    height: small ? 29 : 38,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(small ? 10 : 13),
      gradient: const LinearGradient(
        colors: [Color(0xFF8CDBF5), Color(0xFF6C5BE8)],
      ),
    ),
    child: Icon(
      Icons.smart_toy_rounded,
      color: const Color(0xFF171940),
      size: small ? 17 : 23,
    ),
  );
}

class GoalCreateScreen extends StatefulWidget {
  const GoalCreateScreen({super.key, required this.store});
  final ExploreStore store;

  @override
  State<GoalCreateScreen> createState() => _GoalCreateScreenState();
}

class _GoalCreateScreenState extends State<GoalCreateScreen> {
  final controller = TextEditingController();
  final _scrollController = ScrollController();
  int _lastMessageCount = 0;
  bool _lastHadDraft = false;

  @override
  void initState() {
    super.initState();
    _lastMessageCount = widget.store.goalCreationMessages.length;
    _lastHadDraft = widget.store.goalDraft != null;
    widget.store.addListener(_onStoreChanged);
    // 进入页面时定位到对话最下方，不用手动滚过历史消息
    _jumpToBottom();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _scrollController.dispose();
    controller.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    final count = widget.store.goalCreationMessages.length;
    final hasDraft = widget.store.goalDraft != null;
    final changed = count != _lastMessageCount || hasDraft != _lastHadDraft;
    _lastMessageCount = count;
    _lastHadDraft = hasDraft;
    if (!changed) return;
    // 发送、收到新消息或目标草稿出现时保持在最下方
    _jumpToBottom();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ExploreAppBar(
        onBack: () => widget.store.goToPage(widget.store.goalCreateOrigin),
        backLabel: widget.store.goalCreateOrigin == ExplorePage.home
            ? '返回首页'
            : '返回目标',
        title: '与探境共创目标',
      ),
      Expanded(child: _body()),
      _composer(),
    ],
  );

  Widget _body() => AppScroll(
    controller: _scrollController,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final message in widget.store.goalCreationMessages)
          ChatBubble(message: message),
        if (widget.store.goalChatLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (widget.store.goalDraft != null) _GoalPreview(store: widget.store),
      ],
    ),
  );

  // 底部导航在本页返回 null，body 因此保留底部安全区（见 _bottomNav），
  // 输入框与其它页面的输入框一样，只需在安全区之上留一段常规留白
  Widget _composer() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 7, 14, 12),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: '输入你的想法……',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: line),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        CircleButton(
          icon: Icons.arrow_upward_rounded,
          onTap: () {
            final text = controller.text.trim();
            if (text.isNotEmpty) {
              controller.clear();
              widget.store.sendGoalCreationMessage(text);
            }
          },
        ),
      ],
    ),
  );
}

class _GoalPreview extends StatelessWidget {
  const _GoalPreview({required this.store});
  final ExploreStore store;

  @override
  Widget build(BuildContext context) {
    final draft = store.goalDraft;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: violetBg,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE5E2FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('我帮你整理成了一个方向'),
          const SizedBox(height: 8),
          Text(
            draft?['title']?.toString() ?? '未命名目标',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
          ),
          const SizedBox(height: 6),
          Text(
            draft?['description']?.toString() ?? '',
            style: const TextStyle(color: muted, fontSize: 13, height: 1.6),
          ),
          if (draft?['success_definition']?.toString().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              '成功标准：${draft?['success_definition']}',
              style: const TextStyle(
                color: purple,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (store.goalStages.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Eyebrow('拆解后的成长路径'),
            const SizedBox(height: 8),
            for (final stage in store.goalStages)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '· ${stage['name']}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${((stage['actions'] as List?) ?? []).length} 个行动',
                      style: const TextStyle(color: muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 17),
          PrimaryButton(
            label: '创建这个目标',
            icon: Icons.arrow_forward_rounded,
            onTap: store.createGoal,
          ),
        ],
      ),
    );
  }
}

class GoalCreatedScreen extends StatelessWidget {
  const GoalCreatedScreen({super.key, required this.store});
  final ExploreStore store;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ExploreAppBar(
          onBack: () => store.goToPage(ExplorePage.growth),
          backLabel: '返回成长方向',
        ),
        Expanded(child: _content()),
      ],
    );
  }

  Widget _content() {
    final goal = store.goals.isEmpty ? null : store.currentGoal;
    return AppScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 35),
          Container(
            width: 90,
            height: 90,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.celebration_rounded,
              color: Color(0xFFE4A24F),
              size: 38,
            ),
          ),
          const SizedBox(height: 22),
          const Eyebrow('A NEW DIRECTION BEGINS'),
          const SizedBox(height: 10),
          const Text(
            '目标创建！',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            '我们将一起努力，把它变成现实。✦',
            style: TextStyle(color: muted, fontSize: 14),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: coralBg,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.adjust_rounded,
                    color: purple,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal?.title ?? '未命名目标',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '主目标 · ${goal == null ? '探索中' : goal.status}',
                        style: const TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF55B892),
                  size: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('成功标准'),
                const SizedBox(height: 8),
                Text(
                  goal?.milestone ?? '持续完成下一步行动',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if ((goal?.stages.length ?? 0) > 0) ...[
                  const SizedBox(height: 17),
                  const Text(
                    '阶段路径',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  for (final stage in goal!.stages)
                    CheckLine(label: stage['name']?.toString() ?? ''),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          PrimaryButton(
            label: '开始探索之旅',
            icon: Icons.arrow_forward_rounded,
            onTap: () {
              store.showGoalDetail();
            },
          ),
          const SizedBox(height: 11),
          TextButton(
            onPressed: () => store.goToPage(ExplorePage.growth),
            child: const Text(
              '稍后再看',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class GoalDetailScreen extends StatefulWidget {
  const GoalDetailScreen({super.key, required this.store});
  final ExploreStore store;

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  List<(String, String)> _statusActions(Goal goal) {
    final s = goal.rawStatus;
    if (s == 'exploring') {
      return [('开始', 'active'), ('归档', 'archived')];
    }
    if (s == 'active') {
      return [('暂停', 'paused'), ('标记完成', 'completed'), ('归档', 'archived')];
    }
    if (s == 'paused' || s == 'blocked') {
      return [('恢复进行', 'active'), ('标记完成', 'completed'), ('归档', 'archived')];
    }
    if (s == 'completed') {
      return [('重新开始', 'active'), ('归档', 'archived')];
    }
    if (s == 'archived') {
      return [('恢复', 'active')];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ExploreAppBar(
          onBack: () => widget.store.goToPage(ExplorePage.growth),
          backLabel: '返回成长方向',
          actions: [
            IconButton(
              tooltip: '编辑目标',
              visualDensity: VisualDensity.compact,
              onPressed: widget.store.goalUpdating
                  ? null
                  : _showEditGoalSheet,
              icon: const Icon(Icons.edit_outlined, color: muted, size: 20),
            ),
          ],
        ),
        Expanded(child: _scroll()),
      ],
    );
  }

  Widget _scroll() {
    final goal = widget.store.currentGoal;
    return AppScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusLabel(status: goal.status),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  goal.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                '${goal.progress}%',
                style: const TextStyle(
                  color: purple,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            goal.description,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tab in DetailTab.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: GestureDetector(
                      onTap: () {
                        widget.store.setDetailTab(tab);
                      },
                      child: DetailTabButton(
                        label: tabLabel(tab),
                        active: widget.store.detailTab == tab,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(color: line),
          const SizedBox(height: 17),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: KeyedSubtree(
              key: ValueKey(widget.store.detailTab),
              child: _detailContent(goal),
            ),
          ),
        ],
      ),
    );
  }

  String tabLabel(DetailTab tab) => switch (tab) {
    DetailTab.overview => '概览',
    DetailTab.phase => '阶段',
    DetailTab.action => '行动',
    DetailTab.records => '记录',
    DetailTab.analysis => '分析',
  };

  Future<void> _showEditGoalSheet() async {
    final goal = widget.store.currentGoal;
    final titleController = TextEditingController(text: goal.title);
    final descriptionController = TextEditingController(text: goal.description);
    final milestoneController = TextEditingController(text: goal.milestone);
    var status = goal.status;
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: line,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '编辑目标',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      '让目标保持真实，也保持可行动。',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    _goalField(titleController, '目标名称'),
                    const SizedBox(height: 12),
                    _goalField(descriptionController, '目标描述', maxLines: 2),
                    const SizedBox(height: 12),
                    _goalField(milestoneController, '下一里程碑'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: _goalDecoration('当前状态'),
                      items: const [
                        DropdownMenuItem(value: '探索中', child: Text('探索中')),
                        DropdownMenuItem(value: '进行中', child: Text('进行中')),
                        DropdownMenuItem(value: '暂停中', child: Text('暂停中')),
                        DropdownMenuItem(value: '已完成', child: Text('已完成')),
                      ],
                      onChanged: saving
                          ? null
                          : (value) =>
                                setSheetState(() => status = value ?? status),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final title = titleController.text.trim();
                                if (title.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('请填写目标名称。')),
                                  );
                                  return;
                                }
                                setSheetState(() => saving = true);
                                final saved = await widget.store.updateGoal(
                                  title: title,
                                  description: descriptionController.text
                                      .trim(),
                                  milestone: milestoneController.text.trim(),
                                  status: status,
                                );
                                if (!context.mounted) return;
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      saved ? '目标已更新' : '保存失败，请稍后重试',
                                    ),
                                  ),
                                );
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: purple,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('保存修改'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    titleController.dispose();
    descriptionController.dispose();
    milestoneController.dispose();
  }

  Widget _goalField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) => TextField(
    controller: controller,
    maxLines: maxLines,
    decoration: _goalDecoration(label),
  );

  InputDecoration _goalDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: muted, fontSize: 14),
    filled: true,
    fillColor: const Color(0xFFF9F9FD),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
  );

  Widget _detailContent(Goal goal) => switch (widget.store.detailTab) {
    DetailTab.overview => _overview(goal),
    DetailTab.phase => _phase(goal),
    DetailTab.action => _action(goal),
    DetailTab.records => _records(),
    DetailTab.analysis => _analysis(),
  };

  Widget _overview(Goal goal) => Column(
    children: [
      WhiteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(
              eyebrow: '整体进度',
              title: '正在把想法变成现实',
              action: goal.phase,
              onTap: () {},
            ),
            const SizedBox(height: 22),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: goal.progress / 100,
                minHeight: 8,
                color: purple,
                backgroundColor: const Color(0xFFEEEEF7),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('起点', style: TextStyle(color: muted, fontSize: 13)),
                Row(
                  children: [
                    IconButton(
                      tooltip: '减少 5%',
                      visualDensity: VisualDensity.compact,
                      onPressed:
                          goal.progress == 0 || widget.store.progressUpdating
                          ? null
                          : () => widget.store.changeGoalProgress(-5),
                      icon: const Icon(
                        Icons.remove_circle_outline_rounded,
                        size: 20,
                      ),
                    ),
                    Text(
                      widget.store.progressUpdating ? '保存中' : '调整进度',
                      style: const TextStyle(
                        color: purple,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      tooltip: '增加 5%',
                      visualDensity: VisualDensity.compact,
                      onPressed:
                          goal.progress == 100 || widget.store.progressUpdating
                          ? null
                          : () => widget.store.changeGoalProgress(5),
                      icon: const Icon(
                        Icons.add_circle_outline_rounded,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(color: line, height: 30),
            DetailPair(label: '当前阶段', value: goal.phase),
            const SizedBox(height: 13),
            DetailPair(
              label: '阶段目标',
              value: goal.milestone.isEmpty ? '尚未设定' : goal.milestone,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in _statusActions(goal))
                  TextButton(
                    onPressed: () =>
                        widget.store.updateGoalStatus(goal.id, a.$2),
                    style: TextButton.styleFrom(
                      foregroundColor: purple,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      a.$1,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 13),
      _GrowthComposition(profile: widget.store.profile),
      const SizedBox(height: 13),
      WhiteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(eyebrow: '里程碑', title: '成长路径'),
            const SizedBox(height: 15),
            if (goal.milestone.isNotEmpty)
              Milestone(title: goal.milestone, date: goal.status, state: 1),
          ],
        ),
      ),
      const SizedBox(height: 13),
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: violetBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AgentAvatar(small: true),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                goal.description.isEmpty ? '继续前进，下一步会逐渐清晰。' : goal.description,
                style: const TextStyle(
                  color: muted,
                  fontSize: 13,
                  height: 1.7,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _phase(Goal goal) => Column(
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF252544),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('当前阶段', light: true),
            const SizedBox(height: 10),
            Text(
              goal.phase,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 29,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              goal.description.isEmpty
                  ? '把方向交给行动，在行动中让答案出现。'
                  : goal.description,
              style: const TextStyle(color: Color(0xFFC3C2D9), fontSize: 13),
            ),
            const SizedBox(height: 25),
            LinearProgressIndicator(
              value: goal.progress / 100,
              minHeight: 5,
              color: const Color(0xFFA59FFF),
              backgroundColor: const Color(0xFF5E5B83),
            ),
          ],
        ),
      ),
      if (goal.milestone.isNotEmpty) ...[
        const SizedBox(height: 13),
        WhiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(eyebrow: '里程碑', title: '成长路径'),
              const SizedBox(height: 15),
              Milestone(title: goal.milestone, date: goal.status, state: 1),
            ],
          ),
        ),
      ],
      if (goal.stages.isNotEmpty) ...[
        const SizedBox(height: 13),
        for (final stage in goal.stages)
          WhiteCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      stage['name']?.toString() ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      stage['status'] == 'completed'
                          ? '已完成'
                          : stage['status'] == 'active'
                          ? '进行中'
                          : '未开始',
                      style: TextStyle(
                        color: stage['status'] == 'active' ? purple : muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
                if (stage['description']?.toString().isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text(
                    stage['description']?.toString() ?? '',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
                if ((stage['actions'] as List?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  for (final action in (stage['actions'] as List? ?? []))
                    CheckboxListTile(
                      value: action['done'] == true,
                      onChanged: stage['status'] == 'active'
                          ? (v) => widget.store.toggleAction(
                              stage['id']?.toString() ?? '',
                              action['id']?.toString() ?? '',
                            )
                          : null,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: purple,
                      dense: true,
                      title: Text(
                        action['content']?.toString() ?? '',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                ],
              ],
            ),
          ),
      ],
    ],
  );

  Widget _action(Goal goal) {
    final activeStage = goal.stages.isNotEmpty
        ? goal.stages.firstWhere(
            (s) => s['status'] == 'active',
            orElse: () => goal.stages.first,
          )
        : null;
    if (activeStage == null) {
      return const WhiteCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              '这个目标还没有拆解阶段。',
              style: TextStyle(color: muted, fontSize: 14),
            ),
          ),
        ),
      );
    }
    final stageActions = ((activeStage['actions'] as List?) ?? []);
    return WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('当前阶段行动'),
          const SizedBox(height: 8),
          Text(
            '${activeStage['name']} · 让下一步变得足够小',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 15),
          if (stageActions.isEmpty)
            const Text(
              '这个阶段还没有行动项。',
              style: TextStyle(color: muted, fontSize: 14),
            )
          else
            for (final action in stageActions)
              CheckboxListTile(
                value: action['done'] == true,
                onChanged: (value) => widget.store.toggleAction(
                  activeStage['id']?.toString() ?? '',
                  action['id']?.toString() ?? '',
                ),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: purple,
                dense: true,
                title: Text(
                  action['content']?.toString() ?? '',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
          const SizedBox(height: 9),
          PrimaryButton(
            label: '和探境一起拆解',
            icon: Icons.arrow_forward_rounded,
            onTap: () => widget.store.openChat(),
          ),
        ],
      ),
    );
  }

  Widget _records() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Eyebrow('与目标有关的记忆'),
      const SizedBox(height: 8),
      const Text(
        '这些时刻，正在推动你',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 14),
      if (widget.store.goalMemories.isEmpty)
        const Text(
          '还没有与该目标相关的记忆。',
          style: TextStyle(color: muted, fontSize: 14),
        )
      else
        for (final memory in widget.store.goalMemories.take(10))
          MemoryTile(memory: memory),
    ],
  );

  Widget _analysis() {
    final goal = widget.store.currentGoal;
    if (widget.store.analysisLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final analysis = widget.store.goalAnalysis;
    if (analysis == null) {
      return WhiteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(eyebrow: '目标分析', title: '让探境帮你梳理方向'),
            const SizedBox(height: 10),
            const Text(
              '基于目标、记忆和对话，生成阶段总结与行动建议。',
              style: TextStyle(color: muted, fontSize: 14),
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              label: '生成分析',
              icon: Icons.auto_awesome_rounded,
              onTap: () => widget.store.generateGoalAnalysis(goal),
            ),
          ],
        ),
      );
    }
    final summary = analysis['summary']?.toString() ?? '';
    final observation = analysis['observation']?.toString() ?? '';
    final suggestion = analysis['suggestion']?.toString() ?? '';
    return Column(
      children: [
        WhiteCard(
          child: AnalysisCard(
            number: '01',
            eyebrow: '阶段总结',
            title: summary,
            body: observation,
          ),
        ),
        const SizedBox(height: 13),
        WhiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnalysisCard(
                number: '02',
                eyebrow: '我的建议',
                title: suggestion,
                body: '',
              ),
              const SizedBox(height: 15),
              PrimaryButton(
                label: '重新生成分析',
                icon: Icons.auto_awesome_rounded,
                onTap: () => widget.store.generateGoalAnalysis(goal),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key, required this.store});
  final ExploreStore store;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const ExploreAppBar(title: '本周成长报告'),
      Expanded(child: _body()),
    ],
  );

  Widget _body() => AppScroll(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        if (store.reports.isNotEmpty) ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: store.weeklyReport?['week_start']?.toString(),
            decoration: InputDecoration(
              labelText: '历史周报',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: line),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            items: [
              for (final r in store.reports)
                DropdownMenuItem(
                  value: r['week_start']?.toString(),
                  child: Text(
                    '${r['week_start']} — ${r['week_end']}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              final row = store.reports.firstWhere(
                (r) => r['week_start']?.toString() == value,
              );
              store.selectReport(row);
            },
          ),
        ],
        if (SupabaseService.client != null) ...[
          const SizedBox(height: 18),
          WhiteCard(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: violetBg,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: purple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '当前账号',
                        style: TextStyle(color: muted, fontSize: 11.5),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        const AuthService().currentUser?.email ?? '未登录',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await store.signOut();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFD75B50),
                  ),
                  child: const Text('退出', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
        if (SupabaseService.client != null) ...[
          const SizedBox(height: 14),
          AccountActionsCard(store: store),
        ],
        const SizedBox(height: 16),
        if (store.profile != null)
          _ProfileCard(
            profile: store.profile!,
            onRegenerate: () => store.generateProfile(),
          )
        else
          WhiteCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(eyebrow: '你的画像', title: '让探境更了解你'),
                const SizedBox(height: 8),
                const Text(
                  '从你的记忆里提炼出性格、价值观与兴趣。',
                  style: TextStyle(color: muted, fontSize: 14),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: '生成画像',
                  icon: Icons.auto_awesome_rounded,
                  onTap: () => store.generateProfile(),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: violetBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('本周评分'),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    store.weeklyReport?['score']?.toString() ?? '—',
                    style: const TextStyle(
                      color: purple,
                      fontSize: 46,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -2,
                    ),
                  ),
                  const Text(
                    ' / 10',
                    style: TextStyle(color: muted, fontSize: 14.5),
                  ),
                ],
              ),
              Text(
                store.weeklyReport?['insight']?.toString() ?? '',
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        WhiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(eyebrow: '本周完成', title: '你做到了这些'),
              const SizedBox(height: 14),
              for (final item
                  in (store.weeklyReport?['completed'] as List? ?? const []))
                CheckLine(label: item.toString()),
            ],
          ),
        ),
        const SizedBox(height: 13),
        WhiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(eyebrow: '我的发现', title: '一个重要变化'),
              const SizedBox(height: 14),
              Text(
                store.weeklyReport?['insight']?.toString() ?? '继续积累，变化会逐渐显现。',
                style: const TextStyle(
                  color: Color(0xFF4A4A63),
                  fontSize: 14,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF252544),
            borderRadius: BorderRadius.circular(19),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('下周建议', light: true),
              const SizedBox(height: 8),
              const Text(
                '把方向，再往前推一步',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              for (final item
                  in (store.weeklyReport?['nextSteps'] as List? ?? const []))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Color(0xFF9D96FC),
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              Center(
                child: TextButton(
                  onPressed: store.reportLoading
                      ? null
                      : () => store.generateWeeklyReport(),
                  style: TextButton.styleFrom(foregroundColor: purple),
                  child: const Text(
                    '重新生成周报',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class AppScroll extends StatelessWidget {
  const AppScroll({super.key, required this.child, this.controller});
  final Widget child;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => GestureDetector(
    // 点按空白处收起键盘（iOS 没有系统返回键可用来关键盘）
    behavior: HitTestBehavior.opaque,
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: SingleChildScrollView(
      controller: controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      child: child,
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.eyebrow,
    required this.title,
    this.action,
    this.onTap,
  });
  final String eyebrow;
  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(eyebrow),
            const SizedBox(height: 5),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: purple,
          ),
          child: Text(
            action!,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
    ],
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.light = false});
  final String text;
  final bool light;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: light ? const Color(0xFFA5A3C8) : muted2,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 15),
    label: Text(
      label,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    style: FilledButton.styleFrom(
      backgroundColor: purple,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    ),
  );
}

class WhiteCard extends StatelessWidget {
  const WhiteCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: line),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .025),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: child,
  );
}

class TipCard extends StatelessWidget {
  const TipCard({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: line),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.auto_awesome_rounded, color: Color(0xFFE6A04E), size: 19),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            '目标可以调整，方向也可以重新选择。重要的是，你始终知道自己为什么出发。',
            style: TextStyle(
              color: muted,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ),
      ],
    ),
  );
}

class CircleButton extends StatelessWidget {
  const CircleButton({super.key, required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    icon: Icon(icon, color: Colors.white, size: 17),
    style: IconButton.styleFrom(
      backgroundColor: purple,
      fixedSize: const Size(34, 34),
    ),
  );
}

class StatusLabel extends StatelessWidget {
  const StatusLabel({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF48B48D),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        status,
        style: const TextStyle(color: Color(0xFF48B48D), fontSize: 11.5),
      ),
    ],
  );
}

class DetailTabButton extends StatelessWidget {
  const DetailTabButton({super.key, required this.label, required this.active});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      color: active ? purple : muted,
      fontSize: 13,
      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
    ),
  );
}

class DetailPair extends StatelessWidget {
  const DetailPair({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 11.5)),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ],
  );
}

class Milestone extends StatelessWidget {
  const Milestone({
    super.key,
    required this.title,
    required this.date,
    required this.state,
  });
  final String title;
  final String date;
  final int state;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Container(
          width: 19,
          height: 19,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: state == 2
                ? const Color(0xFF57BD99)
                : state == 1
                ? purple
                : const Color(0xFFDEDEE9),
            shape: BoxShape.circle,
          ),
          child: state == 2
              ? const Icon(Icons.check, color: Colors.white, size: 11)
              : null,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                date,
                style: const TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class AnalysisCard extends StatelessWidget {
  const AnalysisCard({
    super.key,
    required this.number,
    required this.eyebrow,
    required this.title,
    required this.body,
  });
  final String number;
  final String eyebrow;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 29,
        height: 29,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: violetBg,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          number,
          style: const TextStyle(
            color: purple,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(eyebrow),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: const TextStyle(color: muted, fontSize: 13, height: 1.7),
            ),
          ],
        ),
      ),
    ],
  );
}

class CheckLine extends StatelessWidget {
  const CheckLine({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF58BB96),
          ),
          child: const Icon(Icons.check, color: Colors.white, size: 12),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: muted, fontSize: 13),
        ),
      ],
    ),
  );
}

/// 「我的」页的功能入口：隐私政策 / 用户协议 / 意见反馈 / 删除账号。
/// 删除账号不可逆，这里持有 deleting 状态避免重复点击。
class AccountActionsCard extends StatefulWidget {
  const AccountActionsCard({super.key, required this.store});
  final ExploreStore store;

  @override
  State<AccountActionsCard> createState() => _AccountActionsCardState();
}

class _AccountActionsCardState extends State<AccountActionsCard> {
  bool deleting = false;

  Future<void> _openLegal(String title, String asset) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LegalSheet(title: title, asset: asset),
  );

  Future<void> _openFeedback() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FeedbackSheet(store: widget.store),
  );

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除账号'),
        content: const Text('账号与全部数据（目标、记忆、对话记录）会被永久删除，无法恢复。确定要继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFD75B50)),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => deleting = true);
    try {
      await widget.store.deleteAccount();
      // 成功后 AuthGate 会切回登录页，这里不再跳转
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError ? error.message : '删除失败，请稍后再试。',
          ),
        ),
      );
    }
  }

  Widget _row({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool danger = false,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 19, color: danger ? const Color(0xFFD75B50) : purple),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: danger ? const Color(0xFFD75B50) : ink,
              ),
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right_rounded, size: 18, color: muted2),
        ],
      ),
    ),
  );

  Widget _divider() => const Divider(height: 1, thickness: 1, color: line);

  @override
  Widget build(BuildContext context) => WhiteCard(
    child: Column(
      children: [
        _row(
          icon: Icons.privacy_tip_outlined,
          label: '隐私政策',
          onTap: () => _openLegal('隐私政策', 'assets/legal/privacy.md'),
        ),
        _divider(),
        _row(
          icon: Icons.description_outlined,
          label: '用户协议',
          onTap: () => _openLegal('用户协议', 'assets/legal/terms.md'),
        ),
        _divider(),
        _row(
          icon: Icons.forum_outlined,
          label: '意见反馈 / 内容举报',
          onTap: _openFeedback,
        ),
        _divider(),
        _row(
          icon: Icons.delete_outline_rounded,
          label: deleting ? '正在删除…' : '删除账号',
          danger: true,
          onTap: deleting ? null : _confirmDelete,
        ),
      ],
    ),
  );
}

/// 隐私政策 / 用户协议的阅读面板：直接渲染随 App 打包的同一份 markdown
/// （发布用的 HTML 由 scripts/build-legal.mjs 从同一份文件生成，避免两处维护）
class LegalSheet extends StatelessWidget {
  const LegalSheet({super.key, required this.title, required this.asset});
  final String title;
  final String asset;

  @override
  Widget build(BuildContext context) => Container(
    height: MediaQuery.of(context).size.height * .82,
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: line,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: FutureBuilder<String>(
              future: DefaultAssetBundle.of(context).loadString(asset),
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (snapshot.hasError || (snapshot.hasData && data == null)) {
                  return const Center(
                    child: Text(
                      '内容加载失败，请稍后再试。',
                      style: TextStyle(color: muted2, fontSize: 13),
                    ),
                  );
                }
                if (data == null) {
                  return const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                // MarkdownBody 自身不滚动，长文必须套一层滚动容器
                return SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: MarkdownBody(data: data, styleSheet: _legalStyle),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

final MarkdownStyleSheet _legalStyle = MarkdownStyleSheet(
  h1: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: ink),
  h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
  h3: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: ink),
  p: const TextStyle(fontSize: 14, height: 1.75, color: Color(0xFF4A4A63)),
  listBullet: const TextStyle(fontSize: 14, height: 1.75, color: Color(0xFF4A4A63)),
  a: const TextStyle(color: purple),
);

/// 意见反馈 / 内容举报：写进 explore_feedback，只有本人能写、本人能读
class FeedbackSheet extends StatefulWidget {
  const FeedbackSheet({super.key, required this.store});
  final ExploreStore store;

  @override
  State<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<FeedbackSheet> {
  final controller = TextEditingController();
  String category = 'feedback';
  bool submitting = false;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (submitting) return;
    final content = controller.text.trim();
    if (content.isEmpty) {
      setState(() => error = '写点什么再发送吧。');
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await widget.store.submitFeedback(category: category, content: content);
      if (!mounted) return;
      // 面板关掉之后还要用 ScaffoldMessenger，先取出来再 pop
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('已经收到，谢谢你的反馈。')));
    } on Object catch (_) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        error = '提交失败，请检查网络后再试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '让探境知道哪里不对',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              '内容举报会优先处理：如果 AI 回复让你不适，选「内容举报」并说明是哪一段。',
              style: TextStyle(color: muted, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'feedback', label: Text('意见反馈')),
                ButtonSegment(value: 'content_report', label: Text('内容举报')),
              ],
              selected: {category},
              showSelectedIcon: false,
              onSelectionChanged: submitting
                  ? null
                  : (selection) => setState(() => category = selection.first),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 4,
              maxLines: 8,
              enabled: !submitting,
              decoration: InputDecoration(
                hintText: category == 'content_report' ? '哪一条回复、哪里不合适？' : '说说你的想法或遇到的问题……',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: line),
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: const TextStyle(color: Color(0xFFD75B50), fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 16),
            PrimaryButton(
              label: submitting ? '发送中…' : '发送',
              icon: Icons.send_rounded,
              onTap: submit,
            ),
          ],
        ),
      ),
    ),
  );
}
