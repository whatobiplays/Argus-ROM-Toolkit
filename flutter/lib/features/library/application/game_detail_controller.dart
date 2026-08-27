// The constructors keep public parameter names while assigning private fields.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:collection';

import 'package:argus/core/client/client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library_composition.dart';
import 'library_state.dart';

/// The authoritative state of one routed Game detail request.
enum GameDetailLoadPhase {
  /// The native runtime has not yet admitted detail reads.
  preReady,

  /// A request for the routed Game is in flight.
  loading,

  /// The routed identity resolved to a retained Game detail.
  ready,

  /// The routed identity is a redirect to another canonical Game.
  redirected,

  /// The backend published the Game-not-found application error.
  missing,

  /// A transport or non-not-found application failure occurred.
  failed,
}

/// Immutable detail state keyed by the canonical route input.
final class GameDetailState {
  const GameDetailState({
    required this.requestedGameId,
    required this.phase,
    required this.refreshing,
    this.detail,
    this.canonicalGameId,
    this.failure,
  });

  const GameDetailState.initial({required GameId requestedGameId})
    : this(
        requestedGameId: requestedGameId,
        phase: GameDetailLoadPhase.preReady,
        refreshing: false,
      );

  final GameId requestedGameId;
  final GameDetailLoadPhase phase;

  /// Whether a retained detail is being refreshed in the background.
  final bool refreshing;
  final GameDetail? detail;
  final GameId? canonicalGameId;
  final ClientFailure? failure;

  GameDetailState copyWith({
    GameDetailLoadPhase? phase,
    bool? refreshing,
    GameDetail? detail,
    GameId? canonicalGameId,
    ClientFailure? failure,
    bool clearDetail = false,
    bool clearCanonicalGameId = false,
    bool clearFailure = false,
  }) => GameDetailState(
    requestedGameId: requestedGameId,
    phase: phase ?? this.phase,
    refreshing: refreshing ?? this.refreshing,
    detail: clearDetail ? null : detail ?? this.detail,
    canonicalGameId: clearCanonicalGameId
        ? null
        : canonicalGameId ?? this.canonicalGameId,
    failure: clearFailure ? null : failure ?? this.failure,
  );
}

/// Owns one generation-safe authoritative Game detail read and refresh action.
///
/// The controller only coordinates the routed identity and backend result. It
/// does not infer grouping, availability, provider policy, or not-found state.
final class GameDetailController extends ChangeNotifier {
  GameDetailController({
    required GamesApi games,
    required GameId gameId,
    required LibraryRuntimeContext runtimeContext,
    required LibraryReconciliationDemandSource demandSource,
  }) : _games = games,
       _runtimeContext = runtimeContext,
       _state = GameDetailState.initial(requestedGameId: gameId) {
    _demandSubscription = demandSource.stream.listen(_onDemand);
  }

  static const String gameNotFoundCode =
      'ARGUS.V1.CONFIGURATION.GAME_NOT_FOUND';

  final GamesApi _games;
  final LibraryRuntimeContext _runtimeContext;
  late final StreamSubscription<LibraryReconciliationDemand>
  _demandSubscription;
  GameDetailState _state;
  int _requestToken = 0;
  bool _initialized = false;
  bool _disposed = false;

  GameDetailState get state => _state;

  /// Starts the first read once the owning runtime generation is ready.
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    _initialized = true;
    if (_runtimeContext is LibraryRuntimeContextPreReady) {
      return Future<void>.value();
    }
    return reload();
  }

  /// Re-reads the routed identity from the backend.
  Future<void> reload() async {
    if (_disposed || _runtimeContext is LibraryRuntimeContextPreReady) return;
    final token = ++_requestToken;
    final retainedDetail = _state.detail;
    _publish(
      _state.copyWith(
        phase: retainedDetail == null
            ? GameDetailLoadPhase.loading
            : GameDetailLoadPhase.ready,
        refreshing: retainedDetail != null,
        clearCanonicalGameId: true,
        clearFailure: true,
      ),
    );
    try {
      final result = await _games.getGame(_state.requestedGameId);
      if (!_canPublish(token)) return;
      _publish(switch (result) {
        GetGameFound(:final detail) => GameDetailState(
          requestedGameId: _state.requestedGameId,
          phase: GameDetailLoadPhase.ready,
          refreshing: false,
          detail: detail,
        ),
        GetGameRedirected(:final canonicalGameId) => GameDetailState(
          requestedGameId: _state.requestedGameId,
          phase: GameDetailLoadPhase.redirected,
          refreshing: false,
          canonicalGameId: canonicalGameId,
        ),
      });
    } on ClientFailure catch (failure) {
      if (!_canPublish(token)) return;
      final retainedDetail = _state.detail;
      if (retainedDetail != null && !_isGameNotFound(failure)) {
        _publish(
          _state.copyWith(
            phase: GameDetailLoadPhase.ready,
            refreshing: false,
            failure: failure,
          ),
        );
      } else {
        _publish(
          GameDetailState(
            requestedGameId: _state.requestedGameId,
            phase: _isGameNotFound(failure)
                ? GameDetailLoadPhase.missing
                : GameDetailLoadPhase.failed,
            refreshing: false,
            failure: failure,
          ),
        );
      }
    } catch (error, stackTrace) {
      if (!_canPublish(token)) return;
      final retainedDetail = _state.detail;
      final failure = TransportFailure(
        'The Game detail request failed',
        kind: TransportFailureKind.unexpectedTransportFailure,
        cause: error,
        stackTrace: stackTrace,
      );
      if (retainedDetail != null) {
        _publish(
          _state.copyWith(
            phase: GameDetailLoadPhase.ready,
            refreshing: false,
            failure: failure,
          ),
        );
      } else {
        _publish(
          GameDetailState(
            requestedGameId: _state.requestedGameId,
            phase: GameDetailLoadPhase.failed,
            refreshing: false,
            failure: failure,
          ),
        );
      }
    }
  }

  void _onDemand(LibraryReconciliationDemand demand) {
    if (_disposed) return;
    switch (demand) {
      case LibraryReconciliationDemandListChanged():
        unawaited(reload());
      case LibraryReconciliationDemandDetailChanged(:final gameId)
          when gameId == _state.requestedGameId:
        unawaited(reload());
      case LibraryReconciliationDemandDetailChanged():
        break;
    }
  }

  /// Admits one routed Game refresh through the existing Jobs-owned API.
  Future<OperationHandle> refresh(RefreshMode mode) =>
      _games.refreshGame(gameId: _state.requestedGameId, mode: mode);

  bool _isGameNotFound(ClientFailure failure) =>
      failure is ApplicationFailure &&
      failure.error.code.value == gameNotFoundCode;

  bool _canPublish(int token) =>
      !_disposed &&
      token == _requestToken &&
      _runtimeContext is LibraryRuntimeContextReady;

  void _publish(GameDetailState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _requestToken++;
    unawaited(_demandSubscription.cancel());
    super.dispose();
  }
}

/// Small bounded cache that deduplicates concurrent immutable artwork reads.
///
/// Entries are keyed only by backend-provided artwork asset identity. Failed
/// reads are never retained, so a later Refresh Game can retry the asset.
final class ArtworkBytesCache {
  ArtworkBytesCache({required ArtworkApi api, this.maxEntries = 24})
    : _api = api {
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be positive');
    }
  }

  final ArtworkApi _api;
  final int maxEntries;
  final LinkedHashMap<String, ArtworkAssetBytes> _values =
      LinkedHashMap<String, ArtworkAssetBytes>();
  final Map<String, Future<ArtworkAssetBytes>> _inFlight =
      <String, Future<ArtworkAssetBytes>>{};

  int get length => _values.length;
  int get inFlightLength => _inFlight.length;

  /// Returns cached bytes or shares the existing request for the asset.
  Future<ArtworkAssetBytes> load(String assetId) {
    final cached = _values.remove(assetId);
    if (cached != null) {
      // Reinsert to keep the bounded cache least-recently-used by access.
      _values[assetId] = cached;
      return Future<ArtworkAssetBytes>.value(cached);
    }
    final pending = _inFlight[assetId];
    if (pending != null) return pending;

    final future = _api.getArtworkAssetBytes(assetId).then((value) {
      if (value.assetId != assetId) {
        throw const TransportFailure(
          'Artwork asset identity did not match the requested asset',
          kind: TransportFailureKind.contractMismatch,
        );
      }
      _values[assetId] = value;
      while (_values.length > maxEntries) {
        _values.remove(_values.keys.first);
      }
      return value;
    });
    _inFlight[assetId] = future;
    unawaited(
      future.then<void>(
        (_) => _removePending(assetId, future),
        onError: (Object _, StackTrace _) => _removePending(assetId, future),
      ),
    );
    return future;
  }

  /// Removes one asset so the next visible request retries it.
  void evict(String assetId) {
    _values.remove(assetId);
  }

  /// Clears both completed bytes and in-flight request sharing state.
  void clear() {
    _values.clear();
    _inFlight.clear();
  }

  void _removePending(String assetId, Future<ArtworkAssetBytes> future) {
    if (identical(_inFlight[assetId], future)) _inFlight.remove(assetId);
  }
}

/// Route-scoped detail controller and artwork capability composition.
final gameDetailControllerProvider = Provider.autoDispose
    .family<GameDetailController, GameId>((ref, gameId) {
      final controller = GameDetailController(
        games: ref.watch(libraryGamesApiProvider),
        gameId: gameId,
        runtimeContext: ref.watch(libraryRuntimeContextProvider),
        demandSource: ref.watch(libraryReconciliationDemandProvider),
      );
      ref.onDispose(controller.dispose);
      unawaited(controller.initialize());
      return controller;
    });
