/// AI 模块的网络依赖（唯一 Dio 出口）。
///
/// ⚠ **独立性是刻意的**：AI 端点（DeepSeek / 通义 / 本地 Ollama…）与教务系统
/// 毫无关系，绝不能复用 `currentImsDioProvider` —— 那个 Dio 挂着
/// `CookieManager` 与教务会话拦截器，复用它等于把学校账号的 cookie 发给第三方。
/// 这里用**裸 Dio**：无 cookie、无拦截器、无 baseUrl。
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_client.dart';

/// 裸 Dio（无 cookie / 无拦截器）。
final aiDioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 60),
      // 大模型首字延迟可能几十秒（尤其推理模型），给足
      receiveTimeout: const Duration(minutes: 5),
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});

/// OpenAI 兼容客户端。
final aiClientProvider = Provider<AiClient>(
  (ref) => AiClient(ref.watch(aiDioProvider)),
);
