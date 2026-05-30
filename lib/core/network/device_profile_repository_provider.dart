import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:smarter_jxufe/core/network/device_profile_repository.dart';

part 'device_profile_repository_provider.g.dart';

@Riverpod(keepAlive: true)
DeviceProfileRepository deviceProfileRepository(
  DeviceProfileRepositoryRef ref,
) => DeviceProfileRepository();
