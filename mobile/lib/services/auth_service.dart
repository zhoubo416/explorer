import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class AuthService {
  const AuthService();

  SupabaseClient get _client {
    final client = SupabaseService.client;
    if (client == null) throw StateError('Supabase is not configured.');
    return client;
  }

  User? get currentUser => SupabaseService.client?.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) => _client.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? nickname,
  }) => _client.auth.signUp(
    email: email,
    password: password,
    data: nickname == null ? null : {'nickname': nickname},
  );

  Future<void> ensureExploreProfile({String? nickname}) async {
    final user = currentUser;
    if (user == null) throw StateError('Authentication required.');
    await _client.from('explore_user_profiles').upsert({
      'user_id': user.id,
      'nickname':
          nickname ??
          user.userMetadata?['nickname'] ??
          user.email?.split('@').first,
    });
  }

  Future<void> signOut() => _client.auth.signOut();
}
