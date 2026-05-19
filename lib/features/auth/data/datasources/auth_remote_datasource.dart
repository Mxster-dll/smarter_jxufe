import 'package:dio/dio.dart';

class AuthRemoteDataSource {
  final Dio _dio;

  AuthRemoteDataSource(this._dio);

  /// 第一步：检测是否需要 MFA（多因素认证），返回 state 参数
  Future<String> detectMfa({
    required String username,
    required String password,
    required String fpVisitorId,
  }) async {
    const url = 'https://ssl.jxufe.edu.cn/cas/mfa/detect';
    final headers = {
      'Host': 'ssl.jxufe.edu.cn',
      'Connection': 'keep-alive',
      'sec-ch-ua-platform': '"Windows"',
      'X-Requested-With': 'XMLHttpRequest',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0',
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'sec-ch-ua':
          '"Chromium";v="148", "Microsoft Edge";v="148", "Not/A)Brand";v="99"',
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'sec-ch-ua-mobile': '?0',
      'Origin': 'https://ssl.jxufe.edu.cn',
      'Sec-Fetch-Site': 'same-origin',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Dest': 'empty',
      'Referer':
          'https://ssl.jxufe.edu.cn/cas/login?service=http%3A%2F%2Fehall.jxufe.edu.cn%2Famp-auth-adapter%2FloginSuccess%3FsessionToken%3D3adedcabd79f42c5a288f230ec0c2fbf',
      'Accept-Encoding': 'gzip, deflate, br, zstd',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
    };

    final body = {
      'username': username,
      'password': password,
      'fpVisitorId': fpVisitorId,
    };

    final response = await _dio.post(
      url,
      options: Options(headers: headers),
      data: body,
    );

    if (response.statusCode != 200) {
      throw Exception('MFA detection failed: ${response.statusCode}');
    }

    final json = response.data;
    if (json['code'] != 0) {
      throw Exception('MFA detection error: ${json['code']}');
    }

    final state = json['data']['state'] as String;
    return state;
  }

  /// 第二步：提交登录，返回 TGC Cookie 值
  Future<String> login({
    required String username,
    required String password,
    required String fpVisitorId,
    required String mfaState,
  }) async {
    const url =
        'https://ssl.jxufe.edu.cn/cas/login?service=http%3A%2F%2Fehall.jxufe.edu.cn%2Famp-auth-adapter%2FloginSuccess%3FsessionToken%3D3adedcabd79f42c5a288f230ec0c2fbf';
    final headers = {
      'Host': 'ssl.jxufe.edu.cn',
      'Connection': 'keep-alive',
      'Cache-Control': 'max-age=0',
      'sec-ch-ua':
          '"Chromium";v="148", "Microsoft Edge";v="148", "Not/A)Brand";v="99"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"Windows"',
      'Upgrade-Insecure-Requests': '1',
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0',
      'Origin': 'https://ssl.jxufe.edu.cn',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      'Sec-Fetch-Site': 'same-origin',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-User': '?1',
      'Sec-Fetch-Dest': 'document',
      'Referer':
          'https://ssl.jxufe.edu.cn/cas/login?service=http%3A%2F%2Fehall.jxufe.edu.cn%2Famp-auth-adapter%2FloginSuccess%3FsessionToken%3D3adedcabd79f42c5a288f230ec0c2fbf',
      'Accept-Encoding': 'gzip, deflate, br, zstd',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
    };

    // 固定参数（实际应从登录页面预请求获取，此处为示例）
    const execution =
        '5816f92e-b4de-4bc9-825a-27cab3069029_ZXlKaGJHY2lPaUpJVXpVeE1pSjkuQ2xuMW9XRmN3TmZrbjNuR0hYNC9EL0V2VUxpcy9FTDNJVlZxemxsZjRwTm1kbzZrK1RPY0IxTmErM0RKUm1xSFc3RzJ6MHNmUEE3b29yTUEzaXc5VnFSWWtnOTBJVXVNQ250L3JWcEpRUmZJN2RVQWJJSTBHN1NFNVJVK2k1eEo1RENkaGpCSUp3cS9JOEFEUUV1bk5rMk5ualN5TkNDRzEva21PK3RTN2hJZk5pNFdzaGRZVERMS2NOSWRPS2FBdGpnK3Fqb0ZjMWM0Sm8vUVZNWk1qRWkzcXFYekhka0REOFdBM21sVUkybUVqSWREa0dyVkFNZGVpSWgwTm9CZS93RzB3dFI0MldlUGd5SVdNUWx4czVCOUlYMVpidGNOcmRoSi9jVGE2SnMvKzhTWXlObS9tVEFLeGFZZFE5MHEwUTRLcm5aZHRCL2NMNER4MFdFY3NNNXdzZS9FU1JCcDVBM3R1NDRLbHY5endDWlRwTldGSWR2Y1RTa1NCVnc2R3gvRnRNcnRGN25kZkFYUEU5VkJ2Q1E0ODY0U3Q3Q1hxaFJNL2hacEhLRVpPTWFOeFRsMzdzOTV6SEovRGoyRkg0NG9obXVMaVBVVDhUU2IzVTRKRU1weWlMTmo2bnB4TmMzSkN6TVZ6QXdadzEyalpaT1RsVjJmVHJ3ZGlYTU92RFVFRUJoTUZ0L1RLcTR4SjdDK3BaZ1dhVVlRTm1JZmk2SUROUkUzbCsrYk5XY0l2ZTZzcTJhdFFIVklkZlBEVmZ2S25wWTZlTXZHa3BkL1Y4U2tGSDIvN2ozUS8xbGk1U055R1hDMWFBRHk0c00yVnNnSmFaaWhjL2JwT2lnTUV0Y1JZOEdRRWxsRzI5NWFaUTR3a1BJckM5QnM1SkNhR3hPcTZtS1hTMlhnZVZZQytNbFF5TW5ReFNSSUJMZ2w3VkhjcVBqRHQyUlFFd3VSallta3c5azAvbWs1ZTRrYzhaanZuakdGa1hPYllWMlVEOExxSHNCTnEweklkRmJJYjNBaXQwbDhkTTFuUXg2dmxaMFB1ZHhqeFJaRVQ5cEF0SVdsN1BLV1lUZ1QwRUdVY1ZPZGFYV0hjYS8yWm9PdVFQYU1mMmdsVkFWY1RheFZGTWx3TExRQVJxYXlFRHkydnhsSWd5TnZWVGtSbDFTQitaUFV1WWZUY1ZJUTdCTFB0ZTZITGFPQ0FwNGNFVDcwclZDcm9OT3AvUE9SUHgzR0pkN0FneGJPcXgwT0lZOElkL1Y4cWZUR1lzMkRXUHR4dXV5aCtyL1NmSzhyWjJoVUNsM2s4c2ovTk03M3ZMWk5vU3JZR3UwNkN6Rk1lTjRhbldLb3FMUklWYVVsY28xbGJnU2crK1hGYkprT1lHUk9kdEZsUGJLYUFwSTJiWFE3ZEpqTk9PZGtWbVY0dVRVeG1zWmZudm9rYXdWT3o3S1o5aStIbnlTVmJGcGJKTnFQY29Wd0oxdFR6WTcxMFhVUE5scVh0K1JuWm5WMjVZWVh6SG9TOUpxT3lTNVhkOG1SQ2xsNWN5Z1R4WVYvV1NJVzh2OGtFRVM2VFBOSFBRTVBwVVFOTXA3cjNPWW1OWDFkTmpUNmptekJpTkFJSDVOc1VsU2FuMmVmclBVMXFDY1oxNkVpODRxeFhZSVdoN3ZneTluVU5ScTlrcnBJY1JhSkhwM0RFWXRzZFdjQm5qcWJYUVA2WjBlcVY3RGZBU0hJblNuOHhyNHc1TERyOUpjUElVa2UvSkt1RDlMZzVQUXo3c04zcjRTdUI1WTF5UWdTczc0ZEFid0FLRGpjU2xoV0IydGt6UzlneFJETEtUYTYvMVB6THN6OUNtZVZLWTlCbG5HTll1aEFXZUcvb05MeFJZQ2xJa0l3WWFVWkVMODRnU3hrV0l3VStxblB6Y3cvRzl6R1Bhazl2K01SZmN0MmhidDNXYkMyMmMzRWJpNXZnUDYxOEI5UmJyYUo0NnBNWTZ1SmIxSEQ1MWxxN2F2S2JacWdtbDJhK3RBNTdPSldJckRxV3NPWVkxa0RRUm1oVUJYOHNMdGJHZVg5eitVa1pzaGhSV2thL3ZHelR1czdtYXlrVGd2VGNvMEVmS1JqZDRMZE9rVWxETW1LV211ano2cDJEUjFWSGQvcG9QYXdKSEwxVk1NbzlpdGRXMnRraURxOWdCbkJobSt3RFR6UWhhNEJVaWphcHFEZnQzMVBwOWxVeEppNDMvdWpkWkpSVkk0NVpFVDJNUDVVZUFvZW5LK2I0dVhMS0RlRXdjaE9zQ2dHY01PZGsrVmtEeWFjaDVaZ2dEbExnRGpXbU9WRU00dnhPZXFacFFiOUl3c01pV0x5a0JROVdQWlozdHZ2MitqL3VONHVhQmhYaXB3dG5pdVlMdDdCMUdHTSsrWXB5WmdPdHhLaFhqY1k5ZmR1UXF0am4rMVVYeVc1cjFmK2hKbTd2V3V2R2VjTndmZmlGbzl2YzZMM0pNa0tTOVl3cnhSb0NJV280bVJPU0hvSWx2UzRaNWkzamswMG5FanU0czV5bGhUSE5SVE94aDA3TmtXQnQ2Y3JENFJYTTZ1M0x3eWJxbmUvdE1hN1M5TjVwUXZMcG9maDAyU2RDZWk5Y200VHZWNlkvdHY4aHl2VFFLOHBjTVVyRCtkb1hYV2VtRzJLVW52TTN3MnZLanJVdGpsVnlKNXlOT1owNFVxV3lYdklvZUhwSTZ1WE9sYW5lL1F3cyt1c0RuZS9hQTZVeWJ6SW5PSFJBRTJkNFc0T0EyYzR3MFllQ2JLdW02U3B0SnIyU2pYOGJ1YTZNTVNBRVVOOHlpbDlVZUlzLzQvWnhlMEd4aXlOY1ByUFdKYUtoSHRrNmZaRGpCTjFHaGZjZDYwV3UyUTgvUDFLSWZUd3piMTZtZmxtc1cyVmtBQUNIVFpLNFRFajQ1K295YUo4aWk5UUlnMUtWeVVVTk5SVkxZelNDdyt1YUQ0aUpYbmZMUVlpMGtDQ21wVVNLT1ljU1ZZMUxnUjYwUTAzVS9wMnJ4dU5yd1Exd2JwN3d6NzhyMnB3LzFWL21DN1g4dTIvalBRUER6cDMwTkNac2MrOWpadlBWaEhBak4xSFYwd0J3UFZHRnpwTy95TUdEK3JNWnlRNCtHSFREZm5McDRRUiswNjFEWjNNNGExRjVER01CbHB6Zmx1T0ZFbDVQUkZQdkkxQTNpa08weUNBWmVSM1M4bHA2K1UxdEMrTWxlejBjUFdGSy9tQitsb3V5alFyWDVmUjNLQ0RrZnFBRHY4SmtpS2poYkV5S29Ob0s0SWk5RndDSEVIUHBGNys5WFRqV0ViSU1wNS8vd29yTDkwNjVXQ3JGMjBLRk43aDducEYxdms4b0xLQVFKOXRwb0FIdVVxNXF3RnpCbElaQmtiUEhWZ3JUZCtKVExuYnZCaEw1bi9tdi84MDVUckhjdWd4WXFHSDZCZTBzV1pHbEwzeHlGMWczd2hZcEtYSXM3MC91SE9LVVd0c1J5TlBsbHEwU1F1bVhTZ0tnYnFGSkswNGFaSmEyVDBYbUprZ2JTcnFia2tEeDNBWExCemdpL3lVQ2lwUnNyUXovTjFvZUltR2JlbkRVNkUvdUdGQ2Myc1JNakx4R0grMmV4TlJ4K3FleVFmNk5jZHRBQ3ZaY0lSSnp4MVNGNi9KaEYyRGlSWmlsMER2d0hFOVBXMUVuUkdYN1pkNjJRaGxOK09vVExFZkVQWGRwZUpNUEJUQU03akxxdU5ncGg1dVBzKzBmbDBJV0psOENic1BkYTdoQnk0cUdNbFd0RUIwWFkwQUExbzF5SHpLenNCdUhCRlkxa0tTall2VWZwNlh3c3c3L0xTY0pTK3VPeENoNDlOYTFUb3ZzVVBRSlBsZGh2QkNuVkErUEsrVG12aUptV0g3TVFiRTBqdzkyNkRBWmJjVWVORWc2aWk1ejVmcnVOUzhtallLZ1BZT2Y5SjRzaTAyVk9lWE9qYVdFWTFtd05nZ1A4VDJyQUE5SUdvYnhkVzZUTnpGaEpkR3lETnp3NVM0WWYwQjBneWpjbG4wcmFMcGk4MGZOWjdoUmgzdUdIcnlYUU95WGZvU2tUUEM3dlhaeU8zL0xZUkM1SGgzUEVIT2pPbnk0ODVrZlQxaG5CZkFoQnJQbGlCcStQSGhCaHR3Q3k4S2VJMmJya1BXY3RRZTJiWmQxOEMyS04ycnZGd2ZPUkl5SlRjeDBCbjgzNTJoeXBHaDcreHRNQ1djRGw5eXMzQ3Y2R3pMRDlOaDFJeHk5c1NlSkZMSWZXZmdJZ2R5M0NYVnZqM0V0NEhYTDgzd3dHYVFhWktKTU1kd0ZMaTQ3cFdlRWJseEdvYlpjYUJjSUxLZFVvNW43OUorRzdWb3EyVkFZck94Wmo5aHdoN2FCVmptQVFQWStqQlY1Q2hTK3BVdG10aUVzV1lDVksvYVJDUXFscGZjWk85VlZPci95UXdOR2tCVlp0N2dFT2dEVFFoVnlRbW5iYjVzdGc2L0V0dE9iZzZMNytnK3JJMmhmaVkzbkZtcHNEY2xxL1NPdWU2TkZYdG5CSElJb25CT3k4S21zcXp1Q3NvaU1INWM4QUZDb0VnYm1DeU5hUEFSdlRoQ2lWYWNacGJ4ODZFTDVUdVp4cDJheUYvMk9MekdUcEYrUVlvdUhZZHpQMVNVK042OGQzYllUOHVMdS8wNFVxWDAyZm5GY0xoTWNSaW93NHhUOGxXMWRSMEloeXBmTmJ0N1VxY05vbXBoalJXY1BXVkJWbGo0ZEkyaDBCMzRqNFhUQWNlOE9kTDFUMXlwb3h3c1RyaG9qYTBRTHlnT2x4OFRMYTNiY2l4cjkyRGZiYVhsR2FLYjNsQkQxUHl3dlZKUC9GTXIwc3NPVmhqYVo3VlhsRktuNnZPRDFnZ3lERGFkODREelhvZC93dG5oTWpDNFBKZXA4eGVFdEloaCt4MXBWMU1jU1ZnTVU4dmh2N01rYTNhZmM0bDlscU5hZHVLQjNxOXc5bDJOZjVBYU05NXNCZ3oyZHFNNzQ3czgvQ0ZHNjlhbklXSjJUOTRWbzIyeWxXTGkzUjRXcDhaYW5pNFR4NlNncTFMY1ZKcnNNSFN1K00yT2RXNytCd0lXMVpIVm1MYlA5V2t4RFpKYW5uOFhEQjhQdjdadWNEc2MweXYzMFJONGdHMFM2MjZ6bWZ2eitObHBMT3dFbUt3VUNmZ3pwd0lWblkvY0gwOWxUSTZPTUZDUDNySFNCZit6dlpnUmdIeDlwM2Uxc2h1Q2FEY1ZqMlUrT3czenF3dUh5dGIvV2JyY1VKQ1U2TW9LeTl1SkxDTGYxaDZvb1EraFhsT2ZBMTF3bld0WE9qTVFxUWFIenp6cHYwaGtNRGN4OVpXRFlUN3RJaHJGV2tWOUkvbHdrWC9OQzVJZXdRN3h4K0l1aldLbFhIdHlHblhmak5YaWdobUt5UHpuWEJTNEV3NlhtZEcxVjY0TmtqSFRIVGlaZzg2bFZNNkpscXZUU3lzemlmdnczbW5Ib2pzb3ZRenJETGQvYjlWNTlIY0I0cGxhcjJrdDBSNGxCQ0c1T1FUL1h6VzdWQWFDVWJZbzdDWTNnQlpNd1Q0L2Z4K3pTWXlzRDdGSVBtdStIb2NYalZ5NTBiTWRhRWsxRzJzMGhNRVE0am1SbkUvT1NQU0VlcDFTTENHMFZwamExSTJENXRKVVRUM3QrbG1yMjNKM3BLWkhnK1lYaEQvMERvc0tNL0JQU21HRnhuRWE5dHAxb3BVcS91QWN5a295WW5Cc3pHRy91VmdtWWxaK3lPMnR6NTllUWxBQWRqWGRkQi9NWUtwZzBXd04wNXN1WS9KSVhvK00xM2ZCUzFCWUI3NWU0QXNTUVFnT0pyVldDTmxrbXpWQXNVaUxOeVR5MHcveWdaMHZ1dDdFVkRuR0svWkFlQnlxbjJxMlRPWGlaRU1wLzhnYTFidnRLZG1qWSs4b2xWdHZEYkxWdFdtR0ZiZTU0S1NIYysyK1huMktFdkNWNmFReGE4M3d2QWlMMFdRYkRzVllDV3AvYlhXaUtvUlpZWVVWQ1NnSk1ySlZwSnRIRW5iUDNqbi9mM041QWRRWnJJYmxQc0tDTGhGcXhIVGFGRGtnQXdESTVJRmxRZXVvYlhabXhnKzRwSCtBMHVlQ08rMDEvc0VXRCtlTkE3MVlnVTIrOEhTSU90WnU1MzdSaUd1NWYzb0VSMjBvQ0l6V3ROWVJ3dVN3MytaY1huSzF3bXd5SFh4Um11ZGYyNW45WUtSMHA0TmdMVEoxbXpoUjZWbzZSekd5SGExbkFlS0hjNURBTUV3eWswQ0VCK01SSnhFblRDZmJjcWhFTkJOand2K1J2WkJ6bEtlVG9nYmROdmFld09qeCtuTkMydGkraHNMNXozeGpST3ljdk9pQzVPOFZyZG9rV2NlYm9jdlFYdnZZOFZqQlduUVhhWEZSRXBRSWxpVDhVMGpGNHBWNUhxSEtXdnlEbXBtUEdzcmpJRStCYTRNcUxQR285TXVVSko4Sm1yUWVYQitzeUFYTGRDMnNwZ1c0bUNENFVpNUM2djZFOFNtcGFYSGVxSXJKaEFMYkh4Nk9Pc3lzeW5oZnl3T0I5RGovb3RsZEp1Y2tGbUN6dHkwb2FFTWtja1NscFpVcXRHL0FpNEpTUk8ySHFMQitBZjF4bDJhVTlWbEM4RG4wa0hpNFlFSDVoWWx3b25jUnhmQ0FKNUtSamhDamE5TjQxUWcyRXg1RkllTXp1Z2RBcUNIZWRkbG5KekhVYmVjcFBkaHF4ZithRjdyTXdJWFRrc0I5MUJzekdVeThiSDNYVkpqQVA0V0l0VHFoSHpvQUtneVhpeisyclJoeVZ3ZzZtS01FR2FKaHlZQWl6WTVPWERJSFZaY3dRUno3ZjY0QldvdGNCSzdBTGN5NWc5VnBCNTZHditacUk1UjUwcVdpM0dnSjlUSHk3MmtKcFBFY2ZnRUxjZHZDOGRlQVhYcmttY2xVVFhpeW83aE92MURtL1MxeUEyVGhqbmhqRE8rcHI0QVhQWUhVRTRLQVZuZlY4N1FpSHArVm1sSVR5U3dGQlAwS3lUL3dwZERtQjhBbld1bUlnU1hweVlZRHl1aGQ4aXFYTFJHd0ZmS0VwZWNOQ1ppT1hvcFlsQzVwVmdHS3RwWFZ4WFlFU2RPTjl5MW55b1Ura1BWbFB3OFlXZTZ4eVR1b1dRbkcvNUpQOXR0aUdvS3JpWTVibTd3VEpJZ1VyTmlyUVJBR2ovR3o1OE1EanN6TXA2Qlc0NnJqMWV4cDBYb05JRHA5dHU1ZXAvVDExTjB5VWZJTWRER21QWUI3Vll3b2x1Q1dwR2pXTS96ckpyRkhmanBsQ2p1Y2lSSXo1NU1kKzI0ZHI2VGd2R2NFVFh0ZG5pUm8zMlRIZldnMURUNkpJaEk3Y1lrUUQ1WEp1cDQ0ekJwa3U0Zk1VdThFdGJmNXpEaldTVE5Xa0xpcmIvditWOXpQUWJ6OXNsY3JvN3M4WEVqNXNZNStRZmNabFpnTWZrSk1Lb2V2dWUzUmFyalAzcVNxVjVDNmt0ZnFPbk9Wby9vbno3UjZRNHJIbEtXYzg5OU1jYjZZY1hNdkxLcmVYQndOSlNjL3pWMmEvaUFYaWJNQUNESWszL3Ayb0hOUGgyTUFqQ1A0R3I0VnN2Qis5Rms0aDZsMGpzZkNuekp4TUtmNFNTS28wRDh2cjIvNXloWGFMNmduYWxQTHplZElyV1lPTlMyUmRFUFExZUxyKzF4WmVGdVYyNTVFamhGSWlwS3BkMm9hZEk1MFVmZXpETy9ZMEZNZjQ5S0svWUtxL25OQ2lCYVNsSFc5VVlzbW8vNkxxeGpyOUdBTHFxQ1VEZStBRTJCQy9RMm8zS3BDVFJlb1dSTmtLV0dIalBiM21EUVFtQlpGc3RsN2U0cEZyVk90am1kZ3Zld3czbWwyaVUwL1NYWXgrNTllVTdVNlZxMmovVHZJVGI3Mitia1hUR01nU0RWZUN0S0hsTjZQYzFpVm9yQWg4V28xNCt5d3FzdUxvWVBudTRjd3h0SDJERGxBN2t4MTBRMUVsc3J3Rnlpb3ZwWnVoZktvWnVwWjNWWjFrUG5rdHBkcHBCZXZqWkhra3N2ZUY5dFBQY0c2NkRzUTZmZ2lNRjQ4YTRlU2pQNjNZMDZOT1lrK2V2YTdQTjZOdmFSMEFBa01IWjRLZ1c5ZVcvUjZzN3RlaUN1R2xoMWlOVGdnQVR3U2hwT0NOVFhONHBHbDF6citWckJIbE1mRGZqdmNsZW1iTG80SytjemdPVkIzZzJtVFp3L1VieC90eklFaVI4YVpncWJiMzBsaFdzYVJJV2I3VzVROHhtR3A1Tm80MzJURWVqYlBILzBVWVpXbXh4TlY2QU4zTmdBUWxhRjNLNWcySmV0RzU3TEhEc25XN1YzdXltUlN6QjhoVDFYd0w4M1grdFFDYmpyMmhlZXlTN2twMU40OFJwSHJBZHBnUFVOaEh0MGlySG1TVlFvOUhaRUM1dy96VWs1bThsZzh4VVUxRkJ4WGJabG44T2NFbVVkeDRFOGxRQmpjR25hTGo1aTVZbnlIdktzQlM3WW9aWjFLZjFFeUtSd2s3NXpRSkhVZGpXU3hqYVRINzNiekJXUklUYjdvVXFxajYrWHEwSDBDajhsc3NWd29zNS9EVU1nRytpWGRkWldsdU5GUFFlTDkzaUNXTGpvdDkzZmljM1NDYzBrbHpHNFpwaklnYmFJdTVVNXFlQmVIWHdON1VLZ2RCMWR4N3FPaDg2RHVJZUxLSmhCM0VocnFTekJ2ZzhObVpjeURUSWhhdFlINll3Mi9vRWRpQW5sOEI3Z1BTWnZPbzExaXc0bzRMNHlEWGt3VE13djY1Z3I2VkdZZHE2L0FtdHY2NVZTbFc4NjRCZDBSVEt0bU5VMUNrc2o1ck4zckJYajFLZWw0RHJkWEJwNWVDK1kva2ZMZUIrZU5pWkR1eEIvSW9MdnNuanlqT1dFNUJOdFVVVkxlZkROMklHMTFsT0Fua3ZRSzB4Tzlaak1ZUi81ZmUvOFNoV1ZLbFh3MStFc3kwMkI4QU9WOEhsS1JrbE9Xdyt6RFVDeFBGY2JCQWQ3OWJDblVlL1M4RTFiMXV3Y0NISVkrTTYxdTdEKzdQZkpvTUFvWHg4b205NXVvOVZjZW1ZNk5DSFBJaUZEOTZmRXozOUgrejhVRTFhTmNCUnJhRGprWG9KeS96elp6UHFMVnIzRFhTcjFTOTJGcjNPOGZMZE4xbm43QjR2RTU2RjJWd2Z4YVBzd2JONkNacUM0QXV5QjgvN2UvYU9IV05pNXlPQWt3QU9GMjgzRmdyRUJKdE45RkptcisrTGxTZENFUUpkV21UN3RlazVwYzhGdVh4ZmZmOS9Jc3lRcUNocGU1UGIycTU3NTd1aytWODVNUVVnSmw1bUJSVEg5dGhFUXlqcXlJN00zYVFZRUhWRlZRVXlMMnBaUytQWU9sTUpKb0FLODVXc2RrODFGekVkTzU2WktGeStuRnNURlNnNExIWVVQb2JHV0JRVjk3SFphVStETk8xdWEwNVRRQTNoTXMvcUZzSC9FRHhFY2k3UFFNOEowWE9TK0pVUVczYjA5MGpzTGxGa2F6QVdUd2dIM0s5bmVkTTZhMkpydERsUG13UHVQcENhVUpaMXZBdis3NG45TE1PUytzVFFab0NSbmFybENudmZENmlpU0w0dEkwSFJXZFo5d0orWDRSV0NmOFZzVlM4a1kxL3VXK01lc3ZIWEsybUpXOHpnMDcvOXJMejRNMWpzWVM1YjFkbFNaTFcxUDZhTkFQWXc3TjRrM3JUcFd4ajBRU3JUenQ4cU5pK1dIbGl2Q1NYYzlmQ2RtZ0lLUEN6U1dwV2Z2MjdFYXliSWo0dWE2b21qcm5zUk5iSTRrbUtOM1EzQ29DNERNZC9Fbm5jQjJ4V0poU1lXN0NCNzJFK2h3MXNUZDkxc1JieWhmQkpValEwdml4YUkraHZJd2FEaUhCWlBxOVNWSzhScitwaWp2NUc0Mmtlb3IyRG9LMkRkMGRka3hrYzkzUytHcmVNYUVYSVV4b0dQNVZGV1RyQWJuSGg4em1WbTlEcGlTNzduTnNab2kzUGpiQkthS3dsd01WTExHelRuVGRvMlFSUVVoLzRFcEJ6UGt6MGs4NzhJTTJOUnE3RWhrSHlZQzVqTnJGZWdsQ2wxenUrNG9ST2wxYjJsR0tuNnYrTHo4ZWpKbWkyZUgzMGZrNU1zWi9QU2xxVG1PeE9FSG5ZbmQvTlpkV2V3M0dNT29UMk1FWjN3cWpONFJ3Ly9wRFplbHNOL3Ivd0ZYM0c4Tm81OTc2eE1SVXZaVDFzS1NBWWx2TS9GNHFPRE8zWElVWGF1bUVLZkQ1QklLYXRTMStYLzFiYkMrOGY2KzlOTXpDSWRrWHBPWHExbDk2N0padDh2Y05SMXRzNEJBamdTT0FrdEh2cU80NkxOSEpmVzJyUzZlMWRjeVBBWEJ1VDJMUEpYQzZJSTJXODlKUklzNFk4L0V0SldvTy8vUFdKTHcvbjlhOE5qSUFOMEUyakkzVC9LcUsrWTRqYWhaSUV0Y2FMZnFFZ3FSUnJVSjhMTTA5Wk5YYUlkeHpCbWd5SUZVeEZna0lUejl4dUFENEJQWVVxc2FycEpxOGNmVFZmUmV5QkVTbkVLd1JYcmpWeTB0QnZxZjVVdEl4bkFVWEtDTEdqb3FrNENzVVZCVHBQbnJoOHM5UHJXVHo0NlRsTnVKYnBtQmY0aU1Db281cG9HdkY0YVZXRVc4VmxIc0lKYlh6NXQ5MC8xY0lTeXVDc0RQOGh2OEFTajdncDZMZ0o2eGRqOUhZMWcvQUczUmU2MjVaQUtKQ21VbGhPekNtdjd5Rk4zc2svZTdiYkxtL2oybXNYN3RlSGtYNzdkUExTOXJBRnhnTi9xZURhRm5XcGVBNCtNVDc1RnIrN0dyaTlYd3NGNXQ4L1B4dHJnVitBWFdhbE8xZ3RrSWh3L2ZqR0dRdnZzV09NUGpobzkvOGJKMkZQNmZIYjZoVnNIdUpyaE5xY1I1c0pqeExMVS9lVGhER1o4TFBCai9lUFUvMitEQkZTM0JYcHpmeG5kbWgzSjIyTkkvTnk3UHVaNFRSRncyekRJTTROa2FtUHB5aGt2UTZ0dzVYdlpCMWs3b1d4UjVtTXdyMEhJSk5EbGt6UmtTeXZ6UWFvWGZqalFFMXhOdzVUOVV0WGxFUXhMK2FKOFpHNTQyUkZvamg2Y1FLR253Qkk0eFIxV0grY280YmZ0SWlXQXM5S2lGWEM3eTZERlRjaENIdG5tUGFRbkRBdk5ISlM1N1VlS0xOTVJnMlB5akhRbEFDT2tLMTZhMm85cERIdFNEM05PNE1MUnpma0ZwNVNOWDBYZ25Kd25ockZYT3B0MnQ1WUpoclYwZ2c3ZlZ0Vmp3UjFUMzVLeW5WdXJRZFpuVjR4K0JraHlvZGloQ2YxVVV0Qk1GYksvUk5rYlZJL0VwQlpGeHdGbjRnOFlyQVJEK3BIYWc0N3BoeTdhNU5aa2ZiRTFhOFNuazI3MitTdEthREVBNlY4U3pTMjlnUFlPdzc2Ui9PS2V0QXEyVkE3Umxhamg3OVZpNXRkelhNU0ZrWkp4Snc1SXNGRTFNdVV0dzNLak1GZHRpT1AveU13ajIydytpejB1dFhKR25iMGtOOTI2OXJUSVV6RDBEcmZyZ3I2U1M3OSt2YUpXTEZ4a1gvZjdST1JQM3g0SGdxc2JhdDdtY1lRbkpWd0JvRkw4WEgxbTZZUXRkTi5JRldiTlpxdnRyOVp6Zms5WlVVUjFkc1lFcllNbXNqLVlRWkRJMXJuR3EybkpCUFViM2h2WW9RWE5UaWNfMFJJUUw4NzdDQW8wWHJ0Yjc0aXI0eGVPZw==';
    const eventId = 'submit';
    const geolocation = '';
    const trustAgent = '';
    const submit1 = 'Login1';

    final body = {
      'username': username,
      'password': password,
      'captcha': '',
      'currentMenu': '1',
      'failN': '0',
      'mfaState': mfaState,
      'execution': execution,
      '_eventId': eventId,
      'geolocation': geolocation,
      'fpVisitorId': fpVisitorId,
      'trustAgent': trustAgent,
      'submit1': submit1,
    };

    final response = await _dio.post(
      url,
      options: Options(
        headers: headers,
        followRedirects: false, // 不自动跟随重定向，以便获取 Location 和 Set-Cookie
      ),
      data: body,
    );

    // 登录成功应返回 302 重定向
    if (response.statusCode != 302) {
      throw Exception('Login failed: expected 302, got ${response.statusCode}');
    }

    final cookies = response.headers['set-cookie'];
    if (cookies == null || cookies.isEmpty) {
      throw Exception('No Set-Cookie header found');
    }

    // 查找 TGC cookie
    for (var cookie in cookies) {
      final parts = cookie.split(';');
      for (var part in parts) {
        final trimmed = part.trim();
        if (trimmed.startsWith('TGC=')) {
          return trimmed.substring(4); // 返回 TGC 值（不含“TGC=”前缀）
        }
      }
    }

    throw Exception('TGC cookie not found in Set-Cookie');
  }
}
