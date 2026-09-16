import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_export_file.dart';

String read(String path) => File(path).readAsStringSync();

/// 学校服务器实际下发的中文文件名（HTTP 头按 latin1 解码后就是这串乱码）。
const _realName = '某同学青年志愿者志愿服务时长认定登记表.doc';
final String _mojibake = latin1.decode(utf8.encode(_realName));

void main() {
  group('volunteerExportFileName · Content-Disposition 解析', () {
    test('缺失 / 空 / 只有 disposition 类型 → 兜底名', () {
      expect(volunteerExportFileName(null), kVolunteerExportFallbackName);
      expect(volunteerExportFileName(''), kVolunteerExportFallbackName);
      expect(
        volunteerExportFileName('attachment'),
        kVolunteerExportFallbackName,
      );
      expect(
        volunteerExportFileName('attachment; filename='),
        kVolunteerExportFallbackName,
      );
      expect(
        volunteerExportFileName('attachment; filename=""'),
        kVolunteerExportFallbackName,
      );
    });

    test('UTF-8 字节被 latin1 误解码 → 还原中文', () {
      expect(
        volunteerExportFileName('attachment;filename=$_mojibake'),
        _realName,
      );
      // 带引号同样能还原
      expect(
        volunteerExportFileName('attachment; filename="$_mojibake"'),
        _realName,
      );
    });

    test('引号包裹的普通 ASCII 名（含空格）', () {
      expect(
        volunteerExportFileName('attachment; filename="vol work 2026.doc"'),
        'vol work 2026.doc',
      );
    });

    test('RFC 5987 的 filename*=UTF-8\'\'<pct>', () {
      final encoded = Uri.encodeComponent(_realName);
      expect(
        volunteerExportFileName("attachment; filename*=UTF-8''$encoded"),
        _realName,
      );
      // 带语言标记（UTF-8'zh'）也要能解析
      expect(
        volunteerExportFileName("attachment; filename*=UTF-8'zh'$encoded"),
        _realName,
      );
    });

    test('filename* 优先于 filename', () {
      final encoded = Uri.encodeComponent('规范名.doc');
      expect(
        volunteerExportFileName(
          "attachment; filename=\"ignored.doc\"; filename*=UTF-8''$encoded",
        ),
        '规范名.doc',
      );
    });

    test('路径穿越被剥掉（只取末段）', () {
      expect(
        volunteerExportFileName('attachment; filename="../../etc/passwd.doc"'),
        'passwd.doc',
      );
      expect(
        volunteerExportFileName(r'attachment; filename="C:\Temp\a.doc"'),
        'a.doc',
      );
    });

    test('非法字符与控制字符被清洗，隐藏名去掉前导点', () {
      expect(
        volunteerExportFileName('attachment; filename="a:b*c?.doc"'),
        'a_b_c_.doc',
      );
      expect(
        volunteerExportFileName('attachment; filename="  .hidden.doc "'),
        'hidden.doc',
      );
    });

    test('超长文件名截断但保留扩展名', () {
      final long = '${'a' * 200}.doc';
      final result = volunteerExportFileName('attachment; filename="$long"');
      expect(result.length, 120);
      expect(result.endsWith('.doc'), isTrue);
    });
  });

  group('VolunteerExportFile', () {
    test('默认 MIME 为 Word，大小取字节长度', () {
      final file = VolunteerExportFile(
        bytes: Uint8List.fromList(List<int>.filled(64, 0x50)),
        fileName: 'x.doc',
      );
      expect(file.mimeType, kVolunteerExportMimeType);
      expect(file.sizeInBytes, 64);
      expect(file.toString(), contains('x.doc'));
    });
  });

  group('漂移守卫 · 下载端点与原生分享桥', () {
    const datasourcePath =
        'lib/features/comprehensive_service/data/datasource/'
        'volunteer_hours_remote_datasource.dart';
    const repositoryPath =
        'lib/features/comprehensive_service/data/volunteer_hours_repository.dart';
    const screenPath =
        'lib/features/comprehensive_service/presentation/'
        'volunteer_hours_screen.dart';
    const dartBridgePath = 'lib/core/platform/file_share.dart';
    const ktBridgePath =
        'android/app/src/main/kotlin/com/example/smarter_jxufe/share/'
        'FileShareBridge.kt';
    const mainActivityPath =
        'android/app/src/main/kotlin/com/example/smarter_jxufe/MainActivity.kt';
    const manifestPath = 'android/app/src/main/AndroidManifest.xml';
    const filePathsPath = 'android/app/src/main/res/xml/file_paths.xml';

    test('数据源命中学校「下载时长认定登记表」端点', () {
      final source = read(datasourcePath);
      expect(source, contains("'/admin/tzz/StuVolWork/downloadInfo.do'"));
      expect(source, contains("responseType: ResponseType.bytes"));
      expect(source, contains("response.headers.value('content-disposition')"));
      // 会话失效判定与列表接口保持一致
      expect(source, contains('SspSessionExpiredException'));
    });

    test('仓库提供 exportRecognitionForm 且含会话刷新重试', () {
      final source = read(repositoryPath);
      expect(
        source,
        contains('Future<VolunteerExportFile> exportRecognitionForm'),
      );
      expect(source, contains('refreshSessionId(account)'));
    });

    test('分享桥通道名两端一致', () {
      final dart = read(dartBridgePath);
      final kotlin = read(ktBridgePath);
      final dartChannel = RegExp(
        r"MethodChannel\(\s*'([^']+)'",
      ).firstMatch(dart)?.group(1);
      final ktChannel = RegExp(
        r'CHANNEL\s*=\s*"([^"]+)"',
      ).firstMatch(kotlin)?.group(1);
      expect(dartChannel, isNotNull, reason: 'Dart 侧未定义通道名');
      expect(ktChannel, dartChannel, reason: 'Dart / Kotlin 通道名不一致');
      expect(dartChannel, 'smarter_jxufe/file_share');
      expect(kotlin, contains('ACTION_SEND'));
      expect(kotlin, contains('FLAG_GRANT_READ_URI_PERMISSION'));
    });

    test('Manifest 注册 FileProvider，且路径白名单只暴露 cache/shared', () {
      final manifest = read(manifestPath);
      expect(manifest, contains('androidx.core.content.FileProvider'));
      expect(
        manifest,
        contains(r'android:authorities="${applicationId}.fileprovider"'),
      );
      expect(manifest, contains('@xml/file_paths'));

      final paths = read(filePathsPath);
      expect(paths, contains('<cache-path'));
      expect(paths, contains('path="shared/"'));
      // 不做整盘暴露
      expect(paths.contains('<external-path'), isFalse);
      expect(paths.contains('<root-path'), isFalse);

      final kotlin = read(ktBridgePath);
      expect(
        kotlin,
        contains('.fileprovider'),
        reason: 'Kotlin 侧 authority 后缀必须与 Manifest 一致',
      );
    });

    test('MainActivity 注册并释放分享桥', () {
      final source = read(mainActivityPath);
      expect(source, contains('FileShareBridge('));
      expect(source, contains('fileShareBridge?.dispose()'));
    });

    test('志愿时长页提供导出入口（顶部按钮 + 列表行按钮）', () {
      final source = read(screenPath);
      expect(source, contains('_exportRecognitionForm'));
      expect(source, contains("tooltip: '导出时长认定登记表'"));
      expect(source, contains('FileShare.shareBytes('));
      expect(source, contains('exportRecognitionForm(account)'));
    });
  });
}
