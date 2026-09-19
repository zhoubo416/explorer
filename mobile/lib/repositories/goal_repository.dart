import 'package:supabase_flutter/supabase_flutter.dart';

class GoalRepository {
  const GoalRepository(this.client);
  final SupabaseClient client;

  Future<List<Map<String, dynamic>>> listGoals() async {
    final rows = await client
        .from('explore_growth_goals')
        .select()
        .neq('status', 'archived')
        .order('is_main_goal', ascending: false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> createGoal({
    required String title,
    String? description,
    String? targetDate,
    String? successDefinition,
    List<Map<String, dynamic>> stages = const [],
    bool isMainGoal = false,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Authentication required.');
    final row = await client
        .from('explore_growth_goals')
        .insert({
          'user_id': userId,
          'title': title,
          'description': description,
          'target_date': targetDate,
          'success_definition': successDefinition,
          'stages': stages,
          'is_main_goal': isMainGoal,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  /// 切换主目标。顺序不能反：先清掉旧主目标标志、再置新，
  /// 直接置新会撞 idx_explore_one_main_goal_per_user 唯一索引。
  Future<void> setMainGoal(String goalId) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Authentication required.');
    await client
        .from('explore_growth_goals')
        .update({'is_main_goal': false})
        .eq('user_id', userId)
        .eq('is_main_goal', true);
    await client
        .from('explore_growth_goals')
        .update({'is_main_goal': true})
        .eq('id', goalId)
        .eq('user_id', userId);
  }

  Future<void> updateProgress(String goalId, int progress) => client
      .from('explore_growth_goals')
      .update({'progress': progress.clamp(0, 100)})
      .eq('id', goalId);

  Future<Map<String, dynamic>> updateGoal({
    required String goalId,
    required String title,
    required String description,
    required String successDefinition,
    required String status,
  }) async {
    final row = await client
        .from('explore_growth_goals')
        .update({
          'title': title,
          'description': description,
          'success_definition': successDefinition,
          'status': status,
        })
        .eq('id', goalId)
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }
}
