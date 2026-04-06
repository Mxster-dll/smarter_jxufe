// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ims_auth_repository_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$imsAuthRepositoryHash() => r'4d7106c5a1be2925e4316330a29b8e3d805fc0e6';

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

/// See also [imsAuthRepository].
@ProviderFor(imsAuthRepository)
const imsAuthRepositoryProvider = ImsAuthRepositoryFamily();

/// See also [imsAuthRepository].
class ImsAuthRepositoryFamily extends Family<ImsAuthRepository> {
  /// See also [imsAuthRepository].
  const ImsAuthRepositoryFamily();

  /// See also [imsAuthRepository].
  ImsAuthRepositoryProvider call(
    String account,
  ) {
    return ImsAuthRepositoryProvider(
      account,
    );
  }

  @override
  ImsAuthRepositoryProvider getProviderOverride(
    covariant ImsAuthRepositoryProvider provider,
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
  String? get name => r'imsAuthRepositoryProvider';
}

/// See also [imsAuthRepository].
class ImsAuthRepositoryProvider extends AutoDisposeProvider<ImsAuthRepository> {
  /// See also [imsAuthRepository].
  ImsAuthRepositoryProvider(
    String account,
  ) : this._internal(
          (ref) => imsAuthRepository(
            ref as ImsAuthRepositoryRef,
            account,
          ),
          from: imsAuthRepositoryProvider,
          name: r'imsAuthRepositoryProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$imsAuthRepositoryHash,
          dependencies: ImsAuthRepositoryFamily._dependencies,
          allTransitiveDependencies:
              ImsAuthRepositoryFamily._allTransitiveDependencies,
          account: account,
        );

  ImsAuthRepositoryProvider._internal(
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
    ImsAuthRepository Function(ImsAuthRepositoryRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ImsAuthRepositoryProvider._internal(
        (ref) => create(ref as ImsAuthRepositoryRef),
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
  AutoDisposeProviderElement<ImsAuthRepository> createElement() {
    return _ImsAuthRepositoryProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ImsAuthRepositoryProvider && other.account == account;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, account.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin ImsAuthRepositoryRef on AutoDisposeProviderRef<ImsAuthRepository> {
  /// The parameter `account` of this provider.
  String get account;
}

class _ImsAuthRepositoryProviderElement
    extends AutoDisposeProviderElement<ImsAuthRepository>
    with ImsAuthRepositoryRef {
  _ImsAuthRepositoryProviderElement(super.provider);

  @override
  String get account => (origin as ImsAuthRepositoryProvider).account;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
