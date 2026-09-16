import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class SupabaseService {
  const SupabaseService._();

  static SupabaseClient? get client =>
      SupabaseConfig.isConfigured ? Supabase.instance.client : null;

  static Future<void> initialize() async {
    if (!SupabaseConfig.isConfigured) return;
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
  }

  static Future<FunctionResponse> invokeWithRetry(
    String functionName, {
    Map<String, dynamic>? body,
    int retries = 3,
  }) async {
    final c = client;
    if (c == null) throw StateError('Supabase is not configured.');
    Object? lastError;
    for (var attempt = 0; attempt < retries; attempt++) {
      try {
        return await c.functions.invoke(functionName, body: body);
      } catch (e) {
        lastError = e;
        if (attempt < retries - 1) {
          await Future<void>.delayed(Duration(milliseconds: 1200 * (attempt + 1)));
        }
      }
    }
    throw lastError ?? StateError('Function invoke failed: $functionName');
  }
}
