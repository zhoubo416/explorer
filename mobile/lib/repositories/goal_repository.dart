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
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> createGoal({
    required String title,
    String? description,
    String? targetDate,
    String? successDefinition,
    List<Map<String, dynamic>> stages = const [],
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
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row);
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
