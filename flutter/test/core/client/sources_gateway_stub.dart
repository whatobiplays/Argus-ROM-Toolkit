import 'package:argus/core/client/client.dart';

/// Test-only default Sources gateway surface for unrelated client fakes.
///
/// Fakes that exercise runtime/appearance/diagnostics behavior but never
/// Sources can mix this in to satisfy the extended gateway contract without
/// duplicating stubs. Any test that actually calls a Sources operation must
/// provide its own focused fake.
mixin SourcesGatewayStub implements SourcesGateway {
  @override
  Future<LibraryRootPage> listLibraryRoots({
    required int offset,
    required int pageSize,
  }) async => LibraryRootPage(
    items: const [],
    offset: offset,
    pageSize: pageSize,
    totalCount: 0,
  );

  @override
  Future<LibraryRoot> getLibraryRoot(LibraryRootId libraryRootId) async =>
      throw const TransportFailure('Sources stub is not focused');

  @override
  Future<AddLocalLibraryRootResult> addLocalLibraryRoot(
    LocalFilesystemRootSelection selection,
  ) async => throw const TransportFailure('Sources stub is not focused');

  @override
  Future<RemoveLibraryRootResult> removeLibraryRoot(
    LibraryRootId libraryRootId,
  ) async => throw const TransportFailure('Sources stub is not focused');
}
