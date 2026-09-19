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

  /// 删除账号：由 Edge Function 删掉 auth 用户，业务数据随外键级联清空
  /// （见 supabase/functions/explore-delete-account）。失败时抛出可直接展示的中文提示。
  Future<void> deleteAccount() async {
    try {
      await _client.functions.invoke('explore-delete-account');
    } on FunctionException catch (error) {
      if (error.status == 401) {
        throw StateError('登录状态已失效，请重新登录后再试。');
      }
      if (error.status == 503) {
        throw StateError('服务暂时不可用，请稍后再试。');
      }
      throw StateError('删除失败，请稍后再试。');
    } catch (_) {
      // 请求可能已经在服务端生效，这里不能断言「没删掉」
      throw StateError('网络异常，无法确认删除结果，请重新打开 App 查看。');
    }
  }
}
