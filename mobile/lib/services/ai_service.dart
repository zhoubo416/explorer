import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';
import 'supabase_service.dart';

/// SSE 解码器：把网络分块切出来的文本还原成一条条 data 负载。
///
/// 单独拆出来是因为「事件跨块」是这类代码最容易出错的地方——
/// 一个事件可能被拆到两个 chunk 里，也可能一个 chunk 里塞了多个事件。
class SseDecoder {
  final StringBuffer _buffer = StringBuffer();

  /// 喂入一段文本，返回本次能够完整解析出的 data 负载
  List<String> add(String chunk) {
    _buffer.write(chunk.replaceAll('\r\n', '\n'));
    final frames = _buffer.toString().split('\n\n');
    // 最后一段可能还没收完，留到下一次
    final remainder = frames.removeLast();
    _buffer
      ..clear()
      ..write(remainder);

    final payloads = <String>[];
    for (final frame in frames) {
      final dataLines = <String>[];
      for (final line in frame.split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        dataLines.add(trimmed.substring(5).trim());
      }
      if (dataLines.isNotEmpty) payloads.add(dataLines.join('\n'));
    }
    return payloads;
  }
}

class AiService {
  const AiService();

  /// 流式获取回复（主对话）：模型生成过程中通过 [onDelta] 逐段回调，
  /// 全部结束后用 [onDone] 交回最终文本（服务端在副作用完成时发出）。
  Future<void> streamReply({
    required String sessionId,
    required String mode,
    required void Function(String text) onDelta,
    required Future<void> Function(String finalReply) onDone,
  }) async {
    var finalReply = '';
    await _stream(
      path: '/explore-conversation',
      body: {'session_id': sessionId, 'mode': mode},
      onDelta: onDelta,
      // done 事件带权威的最终文本；模型返回短纯文本时增量可能为空，靠它补全
      onEvent: (event) {
        if (event['done'] == true) {
          final reply = event['reply']?.toString() ?? '';
          if (reply.isNotEmpty) finalReply = reply;
        }
      },
    );
    await onDone(finalReply);
  }

  /// 目标共创的流式聊天：边生成边回调 [onDelta]，
  /// 结束时通过 [onGoal] 交回提炼出的目标（方向还不清晰时为 null）。
  Future<void> streamGoalChat({
    required List<Map<String, dynamic>> messages,
    required void Function(String text) onDelta,
    required Future<void> Function(Map<String, dynamic>? goal) onGoal,
  }) async {
    Map<String, dynamic>? goal;
    await _stream(
      path: '/explore-goal-chat',
      body: {'messages': messages},
      onDelta: onDelta,
      // 服务端在流末尾发 goal 事件（可能为 null）
      onEvent: (event) {
        final raw = event['goal'];
        if (raw is Map) goal = Map<String, dynamic>.from(raw);
      },
    );
    await onGoal(goal);
  }

  /// 两个流式接口共用的外壳：鉴权、重试与增量分发。
  /// [onEvent] 只接收收尾事件（主对话的 done、目标共创的 goal）。
  Future<void> _stream({
    required String path,
    required Map<String, dynamic> body,
    required void Function(String text) onDelta,
    required void Function(Map<String, dynamic> event) onEvent,
  }) async {
    final client = SupabaseService.client;
    if (client == null || !SupabaseConfig.isConfigured) {
      throw StateError('Supabase is not configured.');
    }
    final token = client.auth.currentSession?.accessToken;
    if (token == null) throw StateError('Not signed in.');

    var received = false;
    Object? lastError;

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _requestEvents(
          token: token,
          path: path,
          body: body,
          onEvent: (data) {
            final error = data['error'];
            if (error is String && error.isNotEmpty) throw Exception(error);
            if (data['done'] == true || data.containsKey('goal')) {
              onEvent(data);
              return;
            }
            final delta = data['reply']?.toString() ?? '';
            if (delta.isNotEmpty) {
              received = true;
              onDelta(delta);
            }
          },
        );
        return;
      } catch (error) {
        lastError = error;
        // 已经吐过内容就不能重试，否则用户会看到重复文本
        if (received) rethrow;
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 1200 * (attempt + 1)),
          );
        }
      }
    }
    throw lastError ?? StateError('AI request failed.');
  }

  /// 发起一次请求并把每个 SSE 负载交给回调。
  /// 旧版函数仍返回 JSON 时，整包解析后作为一个事件交付，
  /// 这样客户端先发、函数后部署的窗口期里对话仍然可用。
  Future<void> _requestEvents({
    required String token,
    required String path,
    required Map<String, dynamic> body,
    required void Function(Map<String, dynamic> data) onEvent,
  }) async {
    final request = http.Request(
      'POST',
      Uri.parse('${SupabaseConfig.url}/functions/v1$path'),
    )
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'apikey': SupabaseConfig.anonKey,
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode(body);

    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      throw Exception('AI 服务返回 ${response.statusCode}');
    }

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('text/event-stream')) {
      final raw = await response.stream.bytesToString();
      final data = jsonDecode(raw);
      if (data is Map) onEvent(Map<String, dynamic>.from(data));
      return;
    }

    final decoder = SseDecoder();
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      for (final payload in decoder.add(chunk)) {
        final data = jsonDecode(payload);
        if (data is Map) onEvent(Map<String, dynamic>.from(data));
      }
    }
  }
}
