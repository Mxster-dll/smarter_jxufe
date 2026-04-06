// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_storage_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$accountStorageHash() => r'52dfa2c059b846e10dc91d6a172b9239a5e128f6';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// See also [accountStorage].
@ProviderFor(accountStorage)
const accountStorageProvider = AccountStorageFamily();

/// See also [accountStorage].
class AccountStorageFamily extends Family<GetStorage> {
  /// See also [accountStorage].
  const AccountStorageFamily();

  /// See also [accountStorage].
  AccountStorageProvider call(
    String account,
  ) {
    return AccountStorageProvider(
      account,
    );
  }

  @override
  AccountStorageProvider getProviderOverride(
    covariant AccountStorageProvider provider,
  ) {
    return call(
      provider.account,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'accountStorageProvider';
}

/// See also [accountStorage].
class AccountStorageProvider extends AutoDisposeProvider<GetStorage> {
  /// See also [accountStorage].
  AccountStorageProvider(
    String account,
  ) : this._internal(
          (ref) => accountStorage(
            ref as AccountStorageRef,
            account,
          ),
          from: accountStorageProvider,
          name: r'accountStorageProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$accountStorageHash,
          dependencies: AccountStorageFamily._dependencies,
          allTransitiveDependencies:
              AccountStorageFamily._allTransitiveDependencies,
          account: account,
        );

  AccountStorageProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.account,
  }) : super.internal();

  final String account;

  @override
  Override overrideWith(
    GetStorage Function(AccountStorageRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: AccountStorageProvider._internal(
        (ref) => create(ref as AccountStorageRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        account: account,
      ),
    );
  }

  @override
  AutoDisposeProviderElement<GetStorage> createElement() {
    return _AccountStorageProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is AccountStorageProvider && other.account == account;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, account.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin AccountStorageRef on AutoDisposeProviderRef<GetStorage> {
  /// The parameter `account` of this provider.
  String get account;
}

class _AccountStorageProviderElement
    extends AutoDisposeProviderElement<GetStorage> with AccountStorageRef {
  _AccountStorageProviderElement(super.provider);

  @override
  String get account => (origin as AccountStorageProvider).account;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
