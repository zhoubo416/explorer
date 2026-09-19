import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 首页数据的本地缓存(stale-while-revalidate):
/// 冷启动先用上次的数据立即渲染,网络加载完成后整体覆盖。
/// 只存各表的原始行,不存密钥;按用户分 key,避免多账号串数据。
class CacheService {
  const CacheService._();

  static const _prefix = 'explore_cache_v1.';

  static Future<Map<String, dynamic>?> load(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$userId');
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String userId, Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$userId', jsonEncode(payload));
    } catch (_) {}
  }

  /// 删除账号后调用：本机不该再留着这个用户的缓存
  static Future<void> clear(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$userId');
    } catch (_) {}
  }
}