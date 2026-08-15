import 'dart:async';

import 'package:argus/core/client/client.dart';

/// Deterministic focused Sources API fake.
final class FakeSourcesApi implements SourcesApi {
  FakeSourcesApi({List<LibraryRoot>? roots}) : roots = roots ?? [];

  List<LibraryRoot> roots;
  AddLocalLibraryRootResult Function(LocalFilesystemRootSelection selection)?
  onAdd;
  AddLocalLibraryRootAndScanResult Function(
    LocalFilesystemRootSelection selection,
  )?
  onAddAndScan;
  Object? getFailure;
  Object? listFailure;
  RemoveLibraryRootResult Function(LibraryRootId libraryRootId)? onRemove;
  StartLibraryScanResult Function(LibraryRootId libraryRootId)? onStartScan;
  StartLibraryScanAllResult Function(ScanAllRequestIdentity requestIdentity)?
  onStartScanAll;

  int listCalls = 0;
  int getCalls = 0;
  int addCalls = 0;
  int addAndScanCalls = 0;
  int removeCalls = 0;
  int startScanCalls = 0;
  int startScanAllCalls = 0;
  int listChildrenCalls = 0;
  int getEntryCalls = 0;
  final List<String> getEntryCallIds = [];

  /// Direct children by parent key (`''` = root scope) in backend order.
  final Map<String, List<SourceEntry>> childrenByParent = {};

  /// Focused details keyed by source-entry identity.
  final Map<String, SourceEntryDetail> detailsByEntry = {};

  /// Throw-once failures for hierarchy reads.
  Object? listChildrenFailure;
  Object? getDetailFailure;

  /// Deterministic gates awaited before hierarchy reads return.
  Future<void> Function()? listChildrenGate;
  Future<void> Function()? getDetailGate;
  final List<Completer<void>> listChildrenGates = [];
  final List<Completer<void>> getDetailGates = [];

  /// Deterministic precomputed child-page responses, consumed in order after
  /// any gates. Lets tests control exact old/new snapshots for supersession.
  final List<SourceEntryChildrenPage> listChildrenScripted = [];

  int getDetailInFlight = 0;
  int maxGetDetailInFlight = 0;
  int maxListChildrenInFlight = 0;
  int _listChildrenInFlight = 0;

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
  Future<AddLocalLibraryRootAndScanResult> addLocalLibraryRootAndScan(
    LocalFilesystemRootSelection selection,
  ) async {
    addAndScanCalls++;
    final handler = onAddAndScan;
    if (handler != null) return handler(selection);
    return AddLocalLibraryRootAndScanResult.addedAndScanAdmitted(
      root: LibraryRoot(
        id: const LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
        displayName: 'Added',
        safeLocationPresentation: selection.selectedFolderPath,
        availability: LibraryRootAvailability.available,
      ),
      handle: OperationHandle(
        jobRunId: const JobRunId('11111111111111111111111111111111'),
        operationType: 'library_scan',
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
    return const RemoveLibraryRootResult.removed();
  }

  @override
  Future<StartLibraryScanResult> startLibraryScan(
    LibraryRootId libraryRootId,
  ) async {
    startScanCalls++;
    final handler = onStartScan;
    if (handler != null) return handler(libraryRootId);
    return StartLibraryScanResult.admitted(
      OperationHandle(
        jobRunId: const JobRunId('11111111111111111111111111111111'),
        operationType: 'library_scan',
      ),
    );
  }

  @override
  Future<StartLibraryScanAllResult> startLibraryScanAll(
    ScanAllRequestIdentity requestIdentity,
  ) async {
    startScanAllCalls++;
    final handler = onStartScanAll;
    if (handler != null) return handler(requestIdentity);
    throw const TransportFailure('FakeSourcesApi has no Scan All handler');
  }

  @override
  Future<SourceEntryChildrenPage> listSourceEntryChildren({
    required LibraryRootId libraryRootId,
    SourceEntryId? parentSourceEntryId,
    String? cursor,
    required int pageSize,
  }) async {
    listChildrenCalls++;
    if (listChildrenGates.isNotEmpty) {
      final gate = listChildrenGates.removeAt(0);
      await gate.future;
    }
    final gate = listChildrenGate;
    if (gate != null) {
      await gate();
    }
    _listChildrenInFlight++;
    if (_listChildrenInFlight > maxListChildrenInFlight) {
      maxListChildrenInFlight = _listChildrenInFlight;
    }
    try {
      final failure = listChildrenFailure;
      if (failure != null) {
        listChildrenFailure = null;
        throw failure;
      }
      if (listChildrenScripted.isNotEmpty) {
        return listChildrenScripted.removeAt(0);
      }
      final key = parentSourceEntryId?.value ?? '';
      final all = childrenByParent[key] ?? const <SourceEntry>[];
      final offset = cursor == null ? 0 : int.parse(cursor);
      final end = (offset + pageSize).clamp(0, all.length);
      return SourceEntryChildrenPage(
        items: all.sublist(offset, end),
        nextCursor: end < all.length ? '$end' : null,
      );
    } finally {
      _listChildrenInFlight--;
    }
  }

  @override
  Future<SourceEntryDetail> getSourceEntry(SourceEntryId sourceEntryId) async {
    getEntryCalls++;
    getEntryCallIds.add(sourceEntryId.value);
    if (getDetailGates.isNotEmpty) {
      final gate = getDetailGates.removeAt(0);
      await gate.future;
    }
    final gate = getDetailGate;
    if (gate != null) {
      await gate();
    }
    getDetailInFlight++;
    if (getDetailInFlight > maxGetDetailInFlight) {
      maxGetDetailInFlight = getDetailInFlight;
    }
    try {
      final failure = getDetailFailure;
      if (failure != null) {
        getDetailFailure = null;
        throw failure;
      }
      final detail = detailsByEntry[sourceEntryId.value];
      if (detail == null) {
        throw sourceEntryNotFoundFailure();
      }
      return detail;
    } finally {
      getDetailInFlight--;
    }
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

ApplicationFailure sourceEntryNotFoundFailure() => ApplicationFailure(
  ClientApplicationError(
    code: const ErrorCode('ARGUS.V1.CONFIGURATION.SOURCE_ENTRY_NOT_FOUND'),
    category: ErrorCategory.configuration,
    severity: ApplicationSeverity.error,
    recoverability: Recoverability.userAction,
    retryPolicy: RetryPolicy.never,
    messageKey: const MessageKey('errors.configuration.source_entry_not_found'),
    traceId: const TraceId('11111111111111111111111111111111'),
    safeContext: const [],
  ),
);

SourceEntry fakeEntry({
  required String id,
  String? parentId,
  String name = 'Entry',
  SourceEntryKind kind = SourceEntryKind.file,
  SourceEntryClassification classification = SourceEntryClassification.unknown,
}) => SourceEntry(
  sourceEntryId: SourceEntryId(id),
  parentSourceEntryId: parentId == null ? null : SourceEntryId(parentId),
  displayName: name,
  displayLocation: name,
  kind: kind,
  classification: classification,
);

SourceEntryDetail fakeDetail({
  required String id,
  String? parentId,
  String name = 'Entry',
  SourceEntryKind kind = SourceEntryKind.file,
  SourceEntryClassification classification = SourceEntryClassification.unknown,
}) => SourceEntryDetail(
  sourceEntryId: SourceEntryId(id),
  parentSourceEntryId: parentId == null ? null : SourceEntryId(parentId),
  displayName: name,
  displayLocation: name,
  kind: kind,
  classification: classification,
);

TransportFailure transportFailure() =>
    const TransportFailure('fake transport failure');
