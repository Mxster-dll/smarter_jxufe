import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/constants/hive_box_names.dart';

part 'ims_auth_jsessionid_box_provider.g.dart';

@Riverpod(keepAlive: true)
Future<Box<String>> imsAuthJsessionIdBox(ImsAuthJsessionIdBoxRef ref) =>
    Hive.openBox<String>(imsAuthBoxName);
