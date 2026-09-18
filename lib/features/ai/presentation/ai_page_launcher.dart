/// 按名字打开首页服务页（给 AI 的 `open_page` 工具收尾用）。
///
/// 页面清单**不在这里**：直接复用首页服务目录（`homeServiceEntries`）——
/// 那是宫格与侧栏共用的唯一条目表，在这里再抄一份必然漂移。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';

/// 打开标题为 [title] 的服务页；找不到就什么都不做并返回 false。
bool openHomeServiceByTitle(BuildContext context, String title) {
  final navigator = Navigator.of(context);
  for (final entry in homeServiceEntries(push: (_) {})) {
    if (entry.title == title) {
      navigator.push(MaterialPageRoute(builder: (_) => entry.builder()));
      return true;
    }
  }
  return false;
}
