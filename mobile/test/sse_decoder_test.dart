import 'package:flutter_test/flutter_test.dart';

import 'package:explore_mobile/services/ai_service.dart';

void main() {
  group('SseDecoder', () {
    test('解析单个完整事件', () {
      final decoder = SseDecoder();
      expect(decoder.add('data: {"reply":"你好"}\n\n'), ['{"reply":"你好"}']);
    });

    test('事件被拆到两个 chunk 时不丢不重', () {
      final decoder = SseDecoder();
      // 这是最容易出错的场景：负载被网络分块切断，且 JSON 本身也是断的
      expect(decoder.add('data: {"rep'), isEmpty);
      expect(decoder.add('ly":"你好"}\n\n'), ['{"reply":"你好"}']);
    });

    test('一个 chunk 里塞多个事件时全部解析出来', () {
      final decoder = SseDecoder();
      expect(
        decoder.add('data: {"a":1}\n\ndata: {"b":2}\n\ndata: {"c":3}\n\n'),
        ['{"a":1}', '{"b":2}', '{"c":3}'],
      );
    });

    test('末尾不完整的事件留到下一次', () {
      final decoder = SseDecoder();
      expect(decoder.add('data: {"a":1}\n\ndata: {"b"'), ['{"a":1}']);
      expect(decoder.add(':2}\n\n'), ['{"b":2}']);
    });

    test('兼容 CRLF 换行', () {
      final decoder = SseDecoder();
      expect(decoder.add('data: {"a":1}\r\n\r\n'), ['{"a":1}']);
    });

    test('忽略没有 data 行的心跳/空帧', () {
      final decoder = SseDecoder();
      expect(decoder.add(': keep-alive\n\n'), isEmpty);
      expect(decoder.add('\n\n'), isEmpty);
    });

    test('多行 data 按换行拼接', () {
      final decoder = SseDecoder();
      expect(decoder.add('data: a\ndata: b\n\n'), ['a\nb']);
    });

    test('连续喂入零散字符也能还原出事件', () {
      final decoder = SseDecoder();
      final payloads = <String>[];
      const raw = 'data: {"reply":"逐字到达"}\n\n';
      for (final ch in raw.split('')) {
        payloads.addAll(decoder.add(ch));
      }
      expect(payloads, ['{"reply":"逐字到达"}']);
    });
  });
}
