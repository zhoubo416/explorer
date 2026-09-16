import 'package:supabase_flutter/supabase_flutter.dart';

class MemoryRepository {
  const MemoryRepository(this.client);
  final SupabaseClient client;

  Future<List<Map<String, dynamic>>> listMemories({int limit = 50}) async {
    final rows = await client
        .from('explore_memory_items')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> addMemory({
    required String type,
    required String content,
    String? summary,
    int importance = 0,
    String? emotion,
    String? sourceConversationId,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Authentication required.');
    final row = await client
        .from('explore_memory_items')
        .insert({
          'user_id': userId,
          'type': type,
          'content': content,
          'summary': summary,
          'importance': importance.clamp(0, 100),
          'emotion': emotion,
          'source_conversation_id': sourceConversationId,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }
}
