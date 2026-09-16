/// 守卫：教务参数加密（Kingo DES）必须与教务前端 JS 逐位一致。
///
/// 期望值由**教务真实 JS 库**（`/custom/js/jkingo.des.js` + `base64.js` + `md5.js`，
/// 抓取于 2026-09-14）在 node 里跑出来（脚本 `D:\Temp\sjx_xk\gen_vectors.js`）。
/// 换实现、改表、动位序都必须先让本文件全绿。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/course_selection/domain/kingo_des.dart';

void main() {
  // 实测抓到的服务端临时密钥（/frame/homepage?method=getTempDeskey 的返回值形态）。
  const key = '52550178936240963575094';

  group('kingoStrEnc 与教务 JS 对拍', () {
    final cases = <String, String>{
      // 长度 42 → 10 整块 + 2 字符尾块
      'xn=2026&xq_m=0&xh=2000000000&kcdm=1004001943':
          'CEE49DA329830717B3B09F2FEB19AC17A98F1BA79C4733234801647DF98DE834'
              '594DA17CB4D0F6D1D66ADDF88D3494B548E6AA0A9311FF80546882C6F4735135'
              '41822BDDD25326F9BDA05DD0402D689C7B9E6ABA7F627DA6',
      // 短于 4 字符：单块 + 零填充
      'abc': 'AE6638065A31EFF5',
      'xy': 'FD127201975AFE9B',
      'a': 'C69C0CEDFFF41B52',
      // 恰好 8 字符 = 2 块
      '12345678': 'E9BEF2E5AA5603E1FC2DF47D74490DE4',
      // 非 ASCII：按 UTF-16 码元取位（JS charCodeAt 语义）
      '选课': 'F5400F6E53DCAE8E',
      'xn=2026': 'CEE49DA3298307176E533F20C159A6CB',
      // 空串
      '': '',
      // 16 个相同块 → 同一密文块重复（证明 4 字符分块语义）
      'x' * 64:
          'E0ED3DB238650B97E0ED3DB238650B97E0ED3DB238650B97E0ED3DB238650B97'
              'E0ED3DB238650B97E0ED3DB238650B97E0ED3DB238650B97E0ED3DB238650B97'
              'E0ED3DB238650B97E0ED3DB238650B97E0ED3DB238650B97E0ED3DB238650B97'
              'E0ED3DB238650B97E0ED3DB238650B97E0ED3DB238650B97E0ED3DB238650B97',
    };

    cases.forEach((plain, expected) {
      test('strEnc(${plain.length} 字符)', () {
        expect(kingoStrEnc(plain, key), expected);
      });
    });
  });

  group('getEncParams 组合式', () {
    const params = 'xn=2026&xq_m=0&xh=2000000000&kcdm=1004001943';
    const timestamp = '2026-09-14 13:06:49';

    test('token = md5(md5(params)+md5(timestamp))', () {
      expect(
        kingoEncToken(params, timestamp),
        '028a3f763c785dd76147f251118e9c43',
      );
    });

    test('请求体 = params(base64 的十六进制串) + token + timestamp', () {
      final body = kingoEncParams(
        params,
        tempDeskey: key,
        timestamp: timestamp,
      );
      expect(
        body,
        'params=Q0VFNDlEQTMyOTgzMDcxN0IzQjA5RjJGRUIxOUFDMTdBOThGMUJBNzlDNDczMzIzNDgw'
        'MTY0N0RGOThERTgzNDU5NERBMTdDQjREMEY2RDFENjZBRERGODhEMzQ5NEI1NDhFNkFBMEE5'
        'MzExRkY4MDU0Njg4MkM2RjQ3MzUxMzU0MTgyMkJEREQyNTMyNkY5QkRBMDVERDA0MDJENjg5'
        'QzdCOUU2QUJBN0Y2MjdEQTY='
        '&token=028a3f763c785dd76147f251118e9c43'
        '&timestamp=2026-09-14%2013%3A06%3A49',
      );
    });

    test('密钥短于 4 字符也能加密（单块密钥）', () {
      expect(kingoStrEnc('abcd', 'k'), isNotEmpty);
      expect(kingoStrEnc('abcd', 'k').length, 16);
    });

    test('空密钥 → 空结果（与 JS strEnc 的 null 分支一致）', () {
      expect(kingoStrEnc('abcd', ''), '');
    });
  });
}
