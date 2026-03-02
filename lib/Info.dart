import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class FingerprintService {
  static final FingerprintService _instance = FingerprintService._internal();
  factory FingerprintService() => _instance;
  FingerprintService._internal();

  static const String _storageKey = 'fpVisitorId';
  static const String _userAgentKey = 'simulatedUserAgent';
  static const String _fingerprintComponentsKey = 'fingerprintComponents';

  // 模拟的浏览器指纹组件
  Map<String, dynamic> _fingerprintComponents = {};
  String _fpVisitorId = '';

  // 预设的浏览器特征（可根据实际情况调整）
  final Map<String, dynamic> _presetBrowserFeatures = {
    'userAgent': {
      'chrome':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'firefox':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
      'safari':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15',
    },
    'screenResolutions': [
      [1920, 1080],
      [1366, 768],
      [1536, 864],
      [1440, 900],
      [1280, 720],
      [2560, 1440],
    ],
    'timezones': [
      'Asia/Shanghai',
      'Asia/Beijing',
      'Asia/Tokyo',
      'America/New_York',
      'Europe/London',
      'Australia/Sydney',
    ],
    'languages': ['zh-CN', 'en-US', 'ja-JP', 'ko-KR', 'ru-RU', 'es-ES'],
    'colorDepth': 24,
    'deviceMemory': [4, 8, 16, 32],
    'hardwareConcurrency': [2, 4, 6, 8, 12, 16],
    'fonts': [
      'Arial',
      'Arial Black',
      'Arial Narrow',
      'Calibri',
      'Cambria',
      'Candara',
      'Comic Sans MS',
      'Courier New',
      'Georgia',
      'Impact',
      'Lucida Console',
      'Lucida Sans Unicode',
      'Microsoft Sans Serif',
      'Palatino Linotype',
      'Segoe UI',
      'Tahoma',
      'Times New Roman',
      'Trebuchet MS',
      'Verdana',
      'Symbol',
      'Webdings',
      'Wingdings',
    ],
  };

  Future<void> initialize() async {
    await _loadOrGenerateFingerprint();
  }

  Future<void> _loadOrGenerateFingerprint() async {
    final prefs = await SharedPreferences.getInstance();

    // 尝试从本地存储加载
    final storedId = prefs.getString(_storageKey);
    final storedComponents = prefs.getString(_fingerprintComponentsKey);

    if (storedId != null && storedComponents != null) {
      _fpVisitorId = storedId;
      try {
        _fingerprintComponents = Map<String, dynamic>.from(
          jsonDecode(storedComponents),
        );
      } catch (e) {
        print('解析指纹数据失败，重新生成: $e');
        await _generateFingerprint();
        await _saveToStorage();
      }
    } else {
      // 生成新的指纹
      await _generateFingerprint();
      await _saveToStorage();
    }
  }

  Future<void> _generateFingerprint() async {
    // 收集所有组件信息
    final components = await _collectFingerprintComponents();

    // 生成指纹ID
    _fpVisitorId = _generateVisitorId(components);
    _fingerprintComponents = components;
  }

  Future<Map<String, dynamic>> _collectFingerprintComponents() async {
    final Map<String, dynamic> components = {};

    // 1. 设备基本信息
    final deviceInfo = await _getDeviceInfo();
    components.addAll(deviceInfo);

    // 2. 屏幕信息
    final screenInfo = _getScreenInfo();
    components.addAll(screenInfo);

    // 3. 时区和语言
    final localeInfo = _getLocaleInfo();
    components.addAll(localeInfo);

    // 4. 浏览器模拟特征
    final browserFeatures = _getBrowserFeatures();
    components.addAll(browserFeatures);

    // 5. Canvas 指纹模拟
    final canvasFingerprint = _generateCanvasFingerprint();
    components['canvas'] = canvasFingerprint;

    // 6. WebGL 指纹模拟
    final webglFingerprint = _generateWebGLFingerprint();
    components['webgl'] = webglFingerprint;

    // 7. 音频指纹模拟
    components['audio'] = _generateAudioFingerprint();

    // 8. 插件列表模拟
    components['plugins'] = _generatePluginList();

    // 9. 添加时间戳和随机种子
    components['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    components['randomSeed'] = Random().nextInt(1000000);

    // 10. 平台信息
    components['platform'] = _getPlatformInfo();

    // 11. 确保所有值都是可编码的
    return _ensureEncodable(components);
  }

  // 确保Map中的所有值都是可编码的
  Map<String, dynamic> _ensureEncodable(Map<String, dynamic> map) {
    final result = <String, dynamic>{};

    for (final entry in map.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is Map) {
        result[key] = _ensureEncodable(value as Map<String, dynamic>);
      } else if (value is List) {
        result[key] = _ensureListEncodable(value);
      } else if (value is DateTime) {
        result[key] = value.toIso8601String();
      } else if (value is Future) {
        // Future对象不应该出现在这里，记录错误
        print('警告: 在指纹数据中发现了Future对象: $key');
        result[key] = 'ERROR: Future object';
      } else {
        // 基本类型直接赋值
        result[key] = value;
      }
    }

    return result;
  }

  // 确保List中的所有值都是可编码的
  List<dynamic> _ensureListEncodable(List<dynamic> list) {
    final result = <dynamic>[];

    for (final item in list) {
      if (item is Map) {
        result.add(_ensureEncodable(item as Map<String, dynamic>));
      } else if (item is List) {
        result.add(_ensureListEncodable(item));
      } else if (item is DateTime) {
        result.add(item.toIso8601String());
      } else if (item is Future) {
        print('警告: 在List中发现了Future对象');
        result.add('ERROR: Future object');
      } else {
        result.add(item);
      }
    }

    return result;
  }

  Future<Map<String, dynamic>> _getDeviceInfo() async {
    // 简化版本，使用模拟数据
    Map<String, dynamic> info = {};

    try {
      if (Platform.isAndroid) {
        info = {
          'platform': 'Android',
          'brand': 'Google',
          'model': 'Pixel 6',
          'device': 'oriole',
          'product': 'oriole',
          'board': 'oriole',
          'hardware': 'oriole',
          'manufacturer': 'Google',
          'version': {
            'sdkInt': 33,
            'release': '13',
            'previewSdkInt': 0,
            'incremental': '9854130',
            'codename': 'REL',
            'baseOS': '',
          },
          'isPhysicalDevice': true,
          'supportedAbis': ['arm64-v8a', 'armeabi-v7a', 'armeabi'],
          'systemFeatures': [
            'android.hardware.bluetooth',
            'android.hardware.camera',
            'android.hardware.camera.flash',
            'android.hardware.faketouch',
            'android.hardware.location',
            'android.hardware.location.gps',
            'android.hardware.location.network',
            'android.hardware.microphone',
            'android.hardware.screen.landscape',
            'android.hardware.screen.portrait',
            'android.hardware.telephony',
            'android.hardware.touchscreen',
            'android.hardware.touchscreen.multitouch',
            'android.hardware.touchscreen.multitouch.distinct',
            'android.hardware.touchscreen.multitouch.jazzhand',
            'android.hardware.wifi',
          ],
        };
      } else if (Platform.isIOS) {
        info = {
          'platform': 'iOS',
          'name': 'iPhone',
          'systemName': 'iOS',
          'systemVersion': '16.2',
          'model': 'iPhone14,5',
          'localizedModel': 'iPhone',
          'identifierForVendor': 'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX',
          'isPhysicalDevice': true,
          'utsname': {
            'sysname': 'Darwin',
            'nodename': 'iPhone',
            'release': '22.3.0',
            'version':
                'Darwin Kernel Version 22.3.0: Wed Jan  4 21:25:21 PST 2023; root:xnu-8792.81.2~2/RELEASE_ARM64_T8110',
            'machine': 'iPhone14,5',
          },
        };
      } else {
        info = {
          'platform': Platform.operatingSystem,
          'version': Platform.operatingSystemVersion,
          'localHostname': Platform.localHostname,
        };
      }

      // 模拟电池信息
      info['batteryLevel'] = Random().nextInt(100);

      // 模拟网络类型
      final networkTypes = ['wifi', 'mobile', 'none'];
      info['connectivity'] =
          networkTypes[Random().nextInt(networkTypes.length)];
    } catch (e) {
      print('获取设备信息错误: $e');
      info['error'] = e.toString();
    }

    return info;
  }

  Map<String, dynamic> _getScreenInfo() {
    try {
      final mediaQuery = MediaQueryData.fromWindow(ui.window);

      return {
        'screen': {
          'width': mediaQuery.size.width,
          'height': mediaQuery.size.height,
          'devicePixelRatio': mediaQuery.devicePixelRatio,
          'textScaleFactor': mediaQuery.textScaleFactor,
          'platformBrightness': mediaQuery.platformBrightness.toString(),
          'padding': {
            'top': mediaQuery.padding.top,
            'bottom': mediaQuery.padding.bottom,
            'left': mediaQuery.padding.left,
            'right': mediaQuery.padding.right,
          },
          'viewInsets': {
            'top': mediaQuery.viewInsets.top,
            'bottom': mediaQuery.viewInsets.bottom,
            'left': mediaQuery.viewInsets.left,
            'right': mediaQuery.viewInsets.right,
          },
        },
        'displayFeatures': [],
      };
    } catch (e) {
      print('获取屏幕信息错误: $e');
      return {
        'screen': {
          'width': 1920,
          'height': 1080,
          'devicePixelRatio': 1.0,
          'textScaleFactor': 1.0,
          'platformBrightness': 'Brightness.light',
          'padding': {'top': 0, 'bottom': 0, 'left': 0, 'right': 0},
          'viewInsets': {'top': 0, 'bottom': 0, 'left': 0, 'right': 0},
        },
        'displayFeatures': [],
      };
    }
  }

  Map<String, dynamic> _getLocaleInfo() {
    final random = Random();
    return {
      'timezone':
          _presetBrowserFeatures['timezones'][random.nextInt(
            _presetBrowserFeatures['timezones'].length,
          )],
      'locale':
          _presetBrowserFeatures['languages'][random.nextInt(
            _presetBrowserFeatures['languages'].length,
          )],
      'language': 'zh',
      'country': 'CN',
      'timezoneOffset': -480, // 中国标准时间偏移（分钟）
    };
  }

  Map<String, dynamic> _getBrowserFeatures() {
    final random = Random();
    final resolutions =
        _presetBrowserFeatures['screenResolutions'] as List<List<int>>;
    final selectedResolution = resolutions[random.nextInt(resolutions.length)];

    // 获取缓存的UserAgent
    final userAgent = _getCachedUserAgent();

    return {
      'userAgent': userAgent,
      'screenResolution': selectedResolution,
      'availableScreenResolution': [
        selectedResolution[0],
        selectedResolution[1] - 40,
      ], // 减去任务栏高度
      'colorDepth': _presetBrowserFeatures['colorDepth'],
      'pixelDepth': _presetBrowserFeatures['colorDepth'],
      'deviceMemory':
          _presetBrowserFeatures['deviceMemory'][random.nextInt(
            _presetBrowserFeatures['deviceMemory'].length,
          )],
      'hardwareConcurrency':
          _presetBrowserFeatures['hardwareConcurrency'][random.nextInt(
            _presetBrowserFeatures['hardwareConcurrency'].length,
          )],
      'maxTouchPoints': 10,
      'language':
          _presetBrowserFeatures['languages'][random.nextInt(
            _presetBrowserFeatures['languages'].length,
          )],
      'languages': [
        _presetBrowserFeatures['languages'][random.nextInt(
          _presetBrowserFeatures['languages'].length,
        )],
        'en-US',
        'en',
      ],
    };
  }

  // 同步获取缓存的UserAgent
  String? _getCachedUserAgent() {
    // 这里需要同步获取，我们可以使用一个同步的缓存
    // 在实际使用中，需要在初始化时设置这个值
    if (_fingerprintComponents.containsKey('userAgent') &&
        _fingerprintComponents['userAgent'] is String) {
      return _fingerprintComponents['userAgent'] as String;
    }

    // 如果缓存中没有，生成一个
    final random = Random();
    final userAgents =
        _presetBrowserFeatures['userAgent'] as Map<String, String>;
    final keys = userAgents.keys.toList();
    final selectedKey = keys[random.nextInt(keys.length)];
    return userAgents[selectedKey];
  }

  String _generateCanvasFingerprint() {
    // 模拟 Canvas 指纹
    final random = Random();
    final List<String> components = [];

    try {
      final pixelRatio = ui.window.devicePixelRatio;

      // 模拟不同 Canvas 渲染结果
      components.add('canvasCode:true');
      components.add('pixelRatio:$pixelRatio');
      components.add('resize:true');

      // 添加一些随机噪声
      components.add('noise:${random.nextInt(1000)}');
      components.add('gradient:${random.nextInt(100)}');
      components.add('text:${random.nextInt(50)}');
      components.add('shadow:${random.nextInt(10)}');
    } catch (e) {
      components.add('canvasCode:true');
      components.add('pixelRatio:1.0');
      components.add('resize:true');
      components.add('noise:500');
    }

    return components.join('~');
  }

  String _generateWebGLFingerprint() {
    // 模拟 WebGL 指纹
    final random = Random();
    final vendors = [
      'Google Inc.',
      'Intel Inc.',
      'NVIDIA Corporation',
      'AMD',
      'Apple Inc.',
    ];
    final renderers = [
      'ANGLE (Intel, Intel(R) UHD Graphics 630, D3D11 vs_5_0 ps_5_0)',
      'ANGLE (NVIDIA, NVIDIA GeForce RTX 3060, D3D11 vs_5_0 ps_5_0)',
      'ANGLE (AMD, AMD Radeon RX 6700 XT, D3D11 vs_5_0 ps_5_0)',
      'WebKit WebGL',
      'Mozilla WebGL',
    ];

    return 'webglCode:true~vendor:${vendors[random.nextInt(vendors.length)]}~'
        'renderer:${renderers[random.nextInt(renderers.length)]}~'
        'version:WebGL 2.0 (OpenGL ES 3.0 Chromium)~'
        'shadingLanguageVersion:WebGL GLSL ES 3.00~'
        'maxTextureSize:16384~'
        'aliasedLineWidthRange:[1, 1]~'
        'aliasedPointSizeRange:[1, 2048]~'
        'alphaBits:8~'
        'redBits:8~'
        'greenBits:8~'
        'blueBits:8~'
        'depthBits:24~'
        'stencilBits:8~'
        'maxAnisotropy:16';
  }

  String _generateAudioFingerprint() {
    // 模拟音频指纹
    final random = Random();
    return (124.0434752751601 + random.nextDouble() * 0.001).toStringAsFixed(
      16,
    );
  }

  List<String> _generatePluginList() {
    // 模拟浏览器插件列表
    final plugins = [
      'Chrome PDF Plugin',
      'Chrome PDF Viewer',
      'Native Client',
      'Widevine Content Decryption Module',
      'Shockwave Flash',
      'Microsoft Office',
      'Google Talk',
    ];

    // 随机选择一些插件
    final random = Random();
    final selectedCount = 3 + random.nextInt(3);
    final List<String> selectedPlugins = [];

    for (int i = 0; i < selectedCount; i++) {
      selectedPlugins.add(plugins[random.nextInt(plugins.length)]);
    }

    return selectedPlugins.toSet().toList(); // 去重
  }

  Map<String, dynamic> _getPlatformInfo() {
    return {
      'operatingSystem': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'numberOfProcessors': Platform.numberOfProcessors,
      'version': Platform.version,
      'localeName': Platform.localeName,
    };
  }

  String _generateVisitorId(Map<String, dynamic> components) {
    try {
      // 1. 将组件转换为排序后的JSON字符串
      final sortedKeys = components.keys.toList()..sort();
      final sortedMap = <String, dynamic>{};

      for (final key in sortedKeys) {
        final value = components[key];
        if (value is Map) {
          sortedMap[key] = _sortMap(value as Map);
        } else if (value is List) {
          sortedMap[key] = List.from(value)..sort();
        } else if (value is Future) {
          // 跳过Future对象
          print('跳过Future对象: $key');
          sortedMap[key] = 'SKIPPED_FUTURE';
        } else {
          sortedMap[key] = value;
        }
      }

      final jsonString = jsonEncode(sortedMap);

      // 2. 计算SHA256哈希
      final bytes = utf8.encode(jsonString);
      final digest = sha256.convert(bytes);

      // 3. 取前32个字符作为visitorId
      return digest.toString().substring(0, 32);
    } catch (e) {
      print('生成visitorId失败: $e');
      // 返回一个基于时间的随机ID作为回退
      final random = Random();
      return 'fallback_${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(1000000)}';
    }
  }

  Map<String, dynamic> _sortMap(Map map) {
    final sortedKeys = map.keys.toList()..sort();
    final result = <String, dynamic>{};

    for (final key in sortedKeys) {
      final value = map[key];
      if (value is Map) {
        result[key.toString()] = _sortMap(value as Map);
      } else if (value is List) {
        result[key.toString()] = List.from(value)..sort();
      } else if (value is Future) {
        result[key.toString()] = 'SKIPPED_FUTURE';
      } else {
        result[key.toString()] = value;
      }
    }

    return result;
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, _fpVisitorId);

      // 确保数据是可编码的
      final encodableComponents = _ensureEncodable(_fingerprintComponents);
      final jsonString = jsonEncode(encodableComponents);
      await prefs.setString(_fingerprintComponentsKey, jsonString);
    } catch (e) {
      print('保存指纹数据失败: $e');
    }
  }

  // 公共接口
  String get fpVisitorId => _fpVisitorId;

  Map<String, dynamic> get fingerprintComponents =>
      Map.from(_fingerprintComponents);

  Future<void> refreshFingerprint() async {
    await _generateFingerprint();
    await _saveToStorage();
  }

  Future<void> clearFingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await prefs.remove(_fingerprintComponentsKey);

    _fingerprintComponents = {};
    _fpVisitorId = '';

    await _generateFingerprint();
    await _saveToStorage();
  }

  Future<String> generateFingerprintReport() async {
    try {
      final report = {
        'visitorId': _fpVisitorId,
        'generatedAt': DateTime.now().toIso8601String(),
        'components': _ensureEncodable(_fingerprintComponents),
        'summary': {
          'platform': _fingerprintComponents['platform'] ?? 'unknown',
          'screenSize':
              '${_fingerprintComponents['screen']?['width'] ?? 0}x${_fingerprintComponents['screen']?['height'] ?? 0}',
          'timezone': _fingerprintComponents['timezone'] ?? 'unknown',
          'language': _fingerprintComponents['language'] ?? 'unknown',
        },
      };

      return jsonEncode(report);
    } catch (e) {
      print('生成指纹报告失败: $e');
      return '{"error": "${e.toString()}"}';
    }
  }
}
