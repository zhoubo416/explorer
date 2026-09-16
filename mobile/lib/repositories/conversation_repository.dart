import 'package:supabase_flutter/supabase_flutter.dart';

class ConversationRepository {
  const ConversationRepository(this.client);
  final SupabaseClient client;

  Future<List<Map<String, dynamic>>> listSessions() async {
    final rows = await client
        .from('explore_conversation_sessions')
        .select()
        .order('updated_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<String> createSession({
    String title = '新的对话',
    String mode = 'normal',
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Authentication required.');
    final row = await client
        .from('explore_conversation_sessions')
        .insert({'user_id': userId, 'title': title, 'mode': mode})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<List<Map<String, dynamic>>> listMessages(String sessionId) async {
    final rows = await client
        .from('explore_conversations')
        .select()
        .eq('session_id', sessionId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> addMessage({
    required String sessionId,
    required String role,
    required String content,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Authentication required.');
    final row = await client
        .from('explore_conversations')
        .insert({
          'session_id': sessionId,
          'user_id': userId,
          'role': role,
          'content': content,
        })
        .select()
        .single();
    await client
        .from('explore_conversation_sessions')
        .update({'preview': content})
        .eq('id', sessionId);
    return Map<String, dynamic>.from(row);
  }
}
