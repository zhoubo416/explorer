import 'supabase_service.dart';

class InsightService {
  const InsightService();

  Future<List<Map<String, dynamic>>> listObservations({
    int limit = 20,
    bool onlyUnread = true,
  }) async {
    final client = SupabaseService.client;
    if (client == null) return [];
    var query = client.from('explore_ai_observations').select();
    if (onlyUnread) query = query.eq('status', 'new');
    final rows = await query
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> generateObservations() async {
    final client = SupabaseService.client;
    if (client == null) return;
    await SupabaseService.invokeWithRetry('explore-observations');
  }

  Future<Map<String, dynamic>?> listLatestReport() async {
    final client = SupabaseService.client;
    if (client == null) return null;
    final rows = await client
        .from('explore_weekly_reports')
        .select()
        .order('week_start', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<List<Map<String, dynamic>>> listReports() async {
    final client = SupabaseService.client;
    if (client == null) return [];
    final rows = await client
        .from('explore_weekly_reports')
        .select()
        .order('week_start', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>?> generateReport() async {
    final client = SupabaseService.client;
    if (client == null) return null;
    final res = await SupabaseService.invokeWithRetry('explore-weekly-report');
    final data = res.data;
    if (data is Map && data['report'] is Map) {
      return Map<String, dynamic>.from(data['report'] as Map);
    }
    return null;
  }

  Future<Map<String, dynamic>?> generateGoalAnalysis(String goalId) async {
    final client = SupabaseService.client;
    if (client == null) return null;
    final res = await SupabaseService.invokeWithRetry(
      'explore-goal-analysis',
      body: {'goal_id': goalId},
    );
    final data = res.data;
    if (data is Map && data['analysis'] is Map) {
      return Map<String, dynamic>.from(data['analysis'] as Map);
    }
    return null;
  }

  Future<String?> generateTimelineSummary() async {
    final client = SupabaseService.client;
    if (client == null) return null;
    final res = await SupabaseService.invokeWithRetry('explore-timeline-summary');
    final data = res.data;
    if (data is Map) return data['summary']?.toString();
    return null;
  }

  Future<List<Map<String, dynamic>>> planGoal({
    required String title,
    required String description,
    required String successDefinition,
  }) async {
    final client = SupabaseService.client;
    if (client == null) return [];
    final res = await SupabaseService.invokeWithRetry('explore-goal-plan', body: {
      'title': title,
      'description': description,
      'success_definition': successDefinition,
    });
    final data = res.data;
    if (data is Map && data['stages'] is List) {
      return List<Map<String, dynamic>>.from(data['stages']);
    }
    return [];
  }

  Future<Map<String, dynamic>?> generateProfile() async {
    final client = SupabaseService.client;
    if (client == null) return null;
    final res = await SupabaseService.invokeWithRetry('explore-profile');
    final data = res.data;
    if (data is Map && data['profile'] is Map) {
      return Map<String, dynamic>.from(data['profile']);
    }
    return null;
  }

  Future<String?> dailySuggestion() async {
    final client = SupabaseService.client;
    if (client == null) return null;
    final res = await SupabaseService.invokeWithRetry('explore-daily-suggestion');
    final data = res.data;
    if (data is Map) return data['suggestion']?.toString();
    return null;
  }
}
