
import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_support.dart';

/// `fetch*` 整组搬到了三个 extension 文件（第二阶段）：这里 export，
/// 调用方**只要 import 本文件**就仍然能用到那些方法（连 import 都不用改）。
export 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_cards.dart';
export 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_peers.dart';
export 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_pages.dart';

/// [DzjApiException] 跟着低层收发一起搬到了 `dzj_api_support.dart`；
/// 这里 re-export，既有 `import ...dzj_api_remote_datasource.dart` 的调用方不掉名字。
export 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_support.dart'
    show DzjApiException;
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_crypto.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';

/// 竹简数据中台个人首页组件接口数据源。
///
/// 每个首页卡片对应一个组件接口（data/get / dve/getSql /
/// dve/getChartSql / data/search / tsa/* / data/getDynamicTextData）。
/// 请求体与响应 data 均按 [DzjCrypto] 协议加密。
/// SQL 中的 `#{U_用户名}` 占位符**必须原样保留**，由服务端替换
/// （实测手动替换成字面值会导致 errorCode 50000）。
class DzjApiRemoteDataSource {
  final Dio dio;

  /// 应用页面地址与首页 pageKey（请求 Referer 与加密无关，但服务端校验）。
  static const String appUrl = '66eef481a9a3';
  static const String homePageKey = '82e98baafb40';

  DzjApiRemoteDataSource(this.dio);

  /// 维度的 `filterConfig`：没声明 [DzjPeerDimension.filterSql] 就是空表（原样行集）。
  ///
  /// 公开给测试（请求体形状 = 「点同班看舍友」这类事故的防线）。**留在类上**是因为
  /// `test/dzj_peer_test.dart` 按 `DzjApiRemoteDataSource.peerFilterOf(...)` 静态调用它。
  ///
  /// ⚠ 2026-10-08 拆分的连带改动：消费方 [fetchPeers] / [fetchPeerCount] 搬到了
  /// `dzj_api_peers.dart` 的 `DzjApiPeers` 扩展 —— 那**是另一个库**，原先的
  /// `@visibleForTesting` 会把自家生产代码一起拦下（`invalid_use_of_visible_for_testing_member`
  /// ×2）。注解去掉：它现在真的同时服务生产与测试，不是「只为测试存在的口子」。
  static List<Object?> peerFilterOf(DzjPeerDimension dimension) {
    final sql = dimension.filterSql;
    if (sql == null || sql.isEmpty) return const <Object?>[];
    return <Object?>[
      <String, Object?>{
        'columnName': '',
        'filterType': 'sql',
        'tableName': '',
        'type': 'VARCHAR2',
        'values': <Object?>[sql],
      },
    ];
  }
}
