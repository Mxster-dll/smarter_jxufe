/// 网络服务写操作的统一执行外壳（确认 → 执行 → 提示 → 对账刷新）。
///
/// 口径与选课写操作一致（AGENTS.md §15.5）：**写后一律重新拉一次数据对账**，
/// 不靠返回文案断定成败；返回文案只用于给用户一句即时反馈。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/network_service/data/datasources/network_service_remote_datasource.dart';
import 'package:smarter_jxufe/features/network_service/data/providers/network_service_providers.dart';
import 'package:smarter_jxufe/features/network_service/domain/network_service_models.dart';

/// 取当前平台 GUID；未配置抛 [NetworkServiceException]（`needGuid == true`）。
Future<String> requireGuidForAction(WidgetRef ref) async {
  final guid = await ref.read(networkServiceGuidProvider.future);
  if (guid == null || guid.isEmpty) {
    throw const NetworkServiceException(
      kNetworkServiceNeedGuid,
      needGuid: true,
    );
  }
  return guid;
}

/// 执行一次网络服务写操作。
///
/// - [action] 拿到 GUID（写操作都要先按 GUID 取页面 token）返回服务端结果；
/// - [invalidate] 成功后调用，用于失效相关 provider 做**写后对账**；
/// - 失败（抛异常或 `success == false`）只提示，不刷新。
Future<NetworkActionResult?> runNetworkAction(
  BuildContext context,
  WidgetRef ref, {
  required Future<NetworkActionResult> Function(String guid) action,
  String? successFallback,
  VoidCallback? invalidate,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  var dialogOpen = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
    ).then((_) => dialogOpen = false),
  );

  void closeDialog() {
    if (dialogOpen) {
      dialogOpen = false;
      navigator.pop();
    }
  }

  void toast(String message) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
      );
  }

  try {
    final guid = await requireGuidForAction(ref);
    final result = await action(guid);
    closeDialog();
    if (result.success) {
      invalidate?.call();
      toast(
        result.message.isNotEmpty
            ? result.message
            : (successFallback ?? '操作成功'),
      );
      return result;
    }
    toast(result.message.isEmpty ? '操作失败' : result.message);
    return result;
  } catch (error) {
    closeDialog();
    toast(error.toString().replaceFirst('Exception: ', ''));
    return null;
  }
}

/// 直接取数据源（写操作闭包内用）。
NetworkServiceRemoteDataSource networkSourceOf(WidgetRef ref) =>
    ref.read(networkServiceDataSourceProvider);
