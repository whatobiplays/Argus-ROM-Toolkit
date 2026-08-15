import 'package:argus/core/client/client.dart';

/// Deterministic focused Sources API fake.
final class FakeSourcesApi implements SourcesApi {
  FakeSourcesApi({List<LibraryRoot>? roots}) : roots = roots ?? [];

  List<LibraryRoot> roots;
  AddLocalLibraryRootResult Function(LocalFilesystemRootSelection selection)?
  onAdd;
  Object? getFailure;
  Object? listFailure;
  RemoveLibraryRootResult Function(LibraryRootId libraryRootId)? onRemove;

  int listCalls = 0;
  int getCalls = 0;
  int addCalls = 0;
  int removeCalls = 0;

  @override
  Future<AddLocalLibraryRootResult> addLocalLibraryRoot(
    LocalFilesystemRootSelection selection,
  ) async {
    addCalls++;
    final handler = onAdd;
    if (handler != null) return handler(selection);
    return AddLocalLibraryRootResult.added(
      LibraryRoot(
        id: const LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
        displayName: 'Added',
        safeLocationPresentation: selection.selectedFolderPath,
        availability: LibraryRootAvailability.available,
      ),
    );
  }

  @override
  Future<LibraryRoot> getLibraryRoot(LibraryRootId libraryRootId) async {
    getCalls++;
    final failure = getFailure;
    if (failure != null) {
      getFailure = null;
      throw failure;
    }
    for (final root in roots) {
      if (root.id == libraryRootId) return root;
    }
    throw rootNotFoundFailure();
  }

  @override
  Future<LibraryRootPage> listLibraryRoots({
    required int offset,
    required int pageSize,
  }) async {
    listCalls++;
    final failure = listFailure;
    if (failure != null) {
      listFailure = null;
      throw failure;
    }
    return LibraryRootPage(
      items: roots.skip(offset).take(pageSize).toList(),
      offset: offset,
      pageSize: pageSize,
      totalCount: roots.length,
    );
  }

  @override
  Future<RemoveLibraryRootResult> removeLibraryRoot(
    LibraryRootId libraryRootId,
  ) async {
    removeCalls++;
    final handler = onRemove;
    if (handler != null) return handler(libraryRootId);
    roots = [
      for (final root in roots)
        if (root.id != libraryRootId) root,
    ];
    return RemoveLibraryRootResult.removed;
  }
}

LibraryRoot fakeRoot({
  String id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  String displayName = 'Games',
  String location = '/library/Games',
  LibraryRootAvailability availability = LibraryRootAvailability.available,
}) => LibraryRoot(
  id: LibraryRootId(id),
  displayName: displayName,
  safeLocationPresentation: location,
  availability: availability,
);

ApplicationFailure rootNotFoundFailure() => ApplicationFailure(
  ClientApplicationError(
    code: const ErrorCode('ARGUS.V1.CONFIGURATION.LIBRARY_ROOT_NOT_FOUND'),
    category: ErrorCategory.configuration,
    severity: ApplicationSeverity.error,
    recoverability: Recoverability.userAction,
    retryPolicy: RetryPolicy.never,
    messageKey: const MessageKey('errors.configuration.library_root_not_found'),
    traceId: const TraceId('11111111111111111111111111111111'),
    safeContext: const [],
  ),
);

TransportFailure transportFailure() =>
    const TransportFailure('fake transport failure');
