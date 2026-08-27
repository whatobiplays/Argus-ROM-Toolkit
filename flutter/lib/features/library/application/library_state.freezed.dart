// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'library_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LibraryRuntimeContext {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryRuntimeContext);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LibraryRuntimeContext()';
}


}

/// @nodoc
class $LibraryRuntimeContextCopyWith<$Res>  {
$LibraryRuntimeContextCopyWith(LibraryRuntimeContext _, $Res Function(LibraryRuntimeContext) __);
}


/// Adds pattern-matching-related methods to [LibraryRuntimeContext].
extension LibraryRuntimeContextPatterns on LibraryRuntimeContext {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LibraryRuntimeContextPreReady value)?  preReady,TResult Function( LibraryRuntimeContextReady value)?  ready,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LibraryRuntimeContextPreReady() when preReady != null:
return preReady(_that);case LibraryRuntimeContextReady() when ready != null:
return ready(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LibraryRuntimeContextPreReady value)  preReady,required TResult Function( LibraryRuntimeContextReady value)  ready,}){
final _that = this;
switch (_that) {
case LibraryRuntimeContextPreReady():
return preReady(_that);case LibraryRuntimeContextReady():
return ready(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LibraryRuntimeContextPreReady value)?  preReady,TResult? Function( LibraryRuntimeContextReady value)?  ready,}){
final _that = this;
switch (_that) {
case LibraryRuntimeContextPreReady() when preReady != null:
return preReady(_that);case LibraryRuntimeContextReady() when ready != null:
return ready(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  preReady,TResult Function( RuntimeInstanceId runtimeInstanceId)?  ready,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LibraryRuntimeContextPreReady() when preReady != null:
return preReady();case LibraryRuntimeContextReady() when ready != null:
return ready(_that.runtimeInstanceId);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  preReady,required TResult Function( RuntimeInstanceId runtimeInstanceId)  ready,}) {final _that = this;
switch (_that) {
case LibraryRuntimeContextPreReady():
return preReady();case LibraryRuntimeContextReady():
return ready(_that.runtimeInstanceId);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  preReady,TResult? Function( RuntimeInstanceId runtimeInstanceId)?  ready,}) {final _that = this;
switch (_that) {
case LibraryRuntimeContextPreReady() when preReady != null:
return preReady();case LibraryRuntimeContextReady() when ready != null:
return ready(_that.runtimeInstanceId);case _:
  return null;

}
}

}

/// @nodoc


class LibraryRuntimeContextPreReady implements LibraryRuntimeContext {
  const LibraryRuntimeContextPreReady();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryRuntimeContextPreReady);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LibraryRuntimeContext.preReady()';
}


}




/// @nodoc


class LibraryRuntimeContextReady implements LibraryRuntimeContext {
  const LibraryRuntimeContextReady({required this.runtimeInstanceId});


 final  RuntimeInstanceId runtimeInstanceId;

/// Create a copy of LibraryRuntimeContext
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryRuntimeContextReadyCopyWith<LibraryRuntimeContextReady> get copyWith => _$LibraryRuntimeContextReadyCopyWithImpl<LibraryRuntimeContextReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryRuntimeContextReady&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId);

@override
String toString() {
  return 'LibraryRuntimeContext.ready(runtimeInstanceId: $runtimeInstanceId)';
}


}

/// @nodoc
abstract mixin class $LibraryRuntimeContextReadyCopyWith<$Res> implements $LibraryRuntimeContextCopyWith<$Res> {
  factory $LibraryRuntimeContextReadyCopyWith(LibraryRuntimeContextReady value, $Res Function(LibraryRuntimeContextReady) _then) = _$LibraryRuntimeContextReadyCopyWithImpl;
@useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId
});




}
/// @nodoc
class _$LibraryRuntimeContextReadyCopyWithImpl<$Res>
    implements $LibraryRuntimeContextReadyCopyWith<$Res> {
  _$LibraryRuntimeContextReadyCopyWithImpl(this._self, this._then);

  final LibraryRuntimeContextReady _self;
  final $Res Function(LibraryRuntimeContextReady) _then;

/// Create a copy of LibraryRuntimeContext
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,}) {
  return _then(LibraryRuntimeContextReady(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,
  ));
}


}

/// @nodoc
mixin _$LibraryReconciliationDemand {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryReconciliationDemand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LibraryReconciliationDemand()';
}


}

/// @nodoc
class $LibraryReconciliationDemandCopyWith<$Res>  {
$LibraryReconciliationDemandCopyWith(LibraryReconciliationDemand _, $Res Function(LibraryReconciliationDemand) __);
}


/// Adds pattern-matching-related methods to [LibraryReconciliationDemand].
extension LibraryReconciliationDemandPatterns on LibraryReconciliationDemand {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LibraryReconciliationDemandListChanged value)?  listChanged,TResult Function( LibraryReconciliationDemandDetailChanged value)?  detailChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LibraryReconciliationDemandListChanged() when listChanged != null:
return listChanged(_that);case LibraryReconciliationDemandDetailChanged() when detailChanged != null:
return detailChanged(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LibraryReconciliationDemandListChanged value)  listChanged,required TResult Function( LibraryReconciliationDemandDetailChanged value)  detailChanged,}){
final _that = this;
switch (_that) {
case LibraryReconciliationDemandListChanged():
return listChanged(_that);case LibraryReconciliationDemandDetailChanged():
return detailChanged(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LibraryReconciliationDemandListChanged value)?  listChanged,TResult? Function( LibraryReconciliationDemandDetailChanged value)?  detailChanged,}){
final _that = this;
switch (_that) {
case LibraryReconciliationDemandListChanged() when listChanged != null:
return listChanged(_that);case LibraryReconciliationDemandDetailChanged() when detailChanged != null:
return detailChanged(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  listChanged,TResult Function( GameId gameId)?  detailChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LibraryReconciliationDemandListChanged() when listChanged != null:
return listChanged();case LibraryReconciliationDemandDetailChanged() when detailChanged != null:
return detailChanged(_that.gameId);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  listChanged,required TResult Function( GameId gameId)  detailChanged,}) {final _that = this;
switch (_that) {
case LibraryReconciliationDemandListChanged():
return listChanged();case LibraryReconciliationDemandDetailChanged():
return detailChanged(_that.gameId);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  listChanged,TResult? Function( GameId gameId)?  detailChanged,}) {final _that = this;
switch (_that) {
case LibraryReconciliationDemandListChanged() when listChanged != null:
return listChanged();case LibraryReconciliationDemandDetailChanged() when detailChanged != null:
return detailChanged(_that.gameId);case _:
  return null;

}
}

}

/// @nodoc


class LibraryReconciliationDemandListChanged implements LibraryReconciliationDemand {
  const LibraryReconciliationDemandListChanged();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryReconciliationDemandListChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LibraryReconciliationDemand.listChanged()';
}


}




/// @nodoc


class LibraryReconciliationDemandDetailChanged implements LibraryReconciliationDemand {
  const LibraryReconciliationDemandDetailChanged({required this.gameId});


 final  GameId gameId;

/// Create a copy of LibraryReconciliationDemand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryReconciliationDemandDetailChangedCopyWith<LibraryReconciliationDemandDetailChanged> get copyWith => _$LibraryReconciliationDemandDetailChangedCopyWithImpl<LibraryReconciliationDemandDetailChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryReconciliationDemandDetailChanged&&(identical(other.gameId, gameId) || other.gameId == gameId));
}


@override
int get hashCode => Object.hash(runtimeType,gameId);

@override
String toString() {
  return 'LibraryReconciliationDemand.detailChanged(gameId: $gameId)';
}


}

/// @nodoc
abstract mixin class $LibraryReconciliationDemandDetailChangedCopyWith<$Res> implements $LibraryReconciliationDemandCopyWith<$Res> {
  factory $LibraryReconciliationDemandDetailChangedCopyWith(LibraryReconciliationDemandDetailChanged value, $Res Function(LibraryReconciliationDemandDetailChanged) _then) = _$LibraryReconciliationDemandDetailChangedCopyWithImpl;
@useResult
$Res call({
 GameId gameId
});




}
/// @nodoc
class _$LibraryReconciliationDemandDetailChangedCopyWithImpl<$Res>
    implements $LibraryReconciliationDemandDetailChangedCopyWith<$Res> {
  _$LibraryReconciliationDemandDetailChangedCopyWithImpl(this._self, this._then);

  final LibraryReconciliationDemandDetailChanged _self;
  final $Res Function(LibraryReconciliationDemandDetailChanged) _then;

/// Create a copy of LibraryReconciliationDemand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? gameId = null,}) {
  return _then(LibraryReconciliationDemandDetailChanged(
gameId: null == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as GameId,
  ));
}


}

/// @nodoc
mixin _$LibraryState {

 LibraryScope get scope; String? get searchText; LibraryFilter get filters; LibrarySort get sort; List<GameLibraryRow> get games; String? get nextCursor; LibraryFacets? get facets; LibraryRootPage? get roots; LibraryLoadPhase get phase; bool get refreshing; bool get loadingMore; ClientFailure? get lastFailure; Set<GameId> get selectedGameIds; LibraryViewMode get viewMode; double get gridScrollOffset; double get listScrollOffset;
/// Create a copy of LibraryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryStateCopyWith<LibraryState> get copyWith => _$LibraryStateCopyWithImpl<LibraryState>(this as LibraryState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryState&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.searchText, searchText) || other.searchText == searchText)&&(identical(other.filters, filters) || other.filters == filters)&&(identical(other.sort, sort) || other.sort == sort)&&const DeepCollectionEquality().equals(other.games, games)&&(identical(other.nextCursor, nextCursor) || other.nextCursor == nextCursor)&&(identical(other.facets, facets) || other.facets == facets)&&(identical(other.roots, roots) || other.roots == roots)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.refreshing, refreshing) || other.refreshing == refreshing)&&(identical(other.loadingMore, loadingMore) || other.loadingMore == loadingMore)&&(identical(other.lastFailure, lastFailure) || other.lastFailure == lastFailure)&&const DeepCollectionEquality().equals(other.selectedGameIds, selectedGameIds)&&(identical(other.viewMode, viewMode) || other.viewMode == viewMode)&&(identical(other.gridScrollOffset, gridScrollOffset) || other.gridScrollOffset == gridScrollOffset)&&(identical(other.listScrollOffset, listScrollOffset) || other.listScrollOffset == listScrollOffset));
}


@override
int get hashCode => Object.hash(runtimeType,scope,searchText,filters,sort,const DeepCollectionEquality().hash(games),nextCursor,facets,roots,phase,refreshing,loadingMore,lastFailure,const DeepCollectionEquality().hash(selectedGameIds),viewMode,gridScrollOffset,listScrollOffset);

@override
String toString() {
  return 'LibraryState(scope: $scope, searchText: $searchText, filters: $filters, sort: $sort, games: $games, nextCursor: $nextCursor, facets: $facets, roots: $roots, phase: $phase, refreshing: $refreshing, loadingMore: $loadingMore, lastFailure: $lastFailure, selectedGameIds: $selectedGameIds, viewMode: $viewMode, gridScrollOffset: $gridScrollOffset, listScrollOffset: $listScrollOffset)';
}


}

/// @nodoc
abstract mixin class $LibraryStateCopyWith<$Res>  {
  factory $LibraryStateCopyWith(LibraryState value, $Res Function(LibraryState) _then) = _$LibraryStateCopyWithImpl;
@useResult
$Res call({
 LibraryScope scope, String? searchText, LibraryFilter filters, LibrarySort sort, List<GameLibraryRow> games, String? nextCursor, LibraryFacets? facets, LibraryRootPage? roots, LibraryLoadPhase phase, bool refreshing, bool loadingMore, ClientFailure? lastFailure, Set<GameId> selectedGameIds, LibraryViewMode viewMode, double gridScrollOffset, double listScrollOffset
});




}
/// @nodoc
class _$LibraryStateCopyWithImpl<$Res>
    implements $LibraryStateCopyWith<$Res> {
  _$LibraryStateCopyWithImpl(this._self, this._then);

  final LibraryState _self;
  final $Res Function(LibraryState) _then;

/// Create a copy of LibraryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? searchText = freezed,Object? filters = null,Object? sort = null,Object? games = null,Object? nextCursor = freezed,Object? facets = freezed,Object? roots = freezed,Object? phase = null,Object? refreshing = null,Object? loadingMore = null,Object? lastFailure = freezed,Object? selectedGameIds = null,Object? viewMode = null,Object? gridScrollOffset = null,Object? listScrollOffset = null,}) {
  return _then(_self.copyWith(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as LibraryScope,searchText: freezed == searchText ? _self.searchText : searchText // ignore: cast_nullable_to_non_nullable
as String?,filters: null == filters ? _self.filters : filters // ignore: cast_nullable_to_non_nullable
as LibraryFilter,sort: null == sort ? _self.sort : sort // ignore: cast_nullable_to_non_nullable
as LibrarySort,games: null == games ? _self.games : games // ignore: cast_nullable_to_non_nullable
as List<GameLibraryRow>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,facets: freezed == facets ? _self.facets : facets // ignore: cast_nullable_to_non_nullable
as LibraryFacets?,roots: freezed == roots ? _self.roots : roots // ignore: cast_nullable_to_non_nullable
as LibraryRootPage?,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as LibraryLoadPhase,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as bool,loadingMore: null == loadingMore ? _self.loadingMore : loadingMore // ignore: cast_nullable_to_non_nullable
as bool,lastFailure: freezed == lastFailure ? _self.lastFailure : lastFailure // ignore: cast_nullable_to_non_nullable
as ClientFailure?,selectedGameIds: null == selectedGameIds ? _self.selectedGameIds : selectedGameIds // ignore: cast_nullable_to_non_nullable
as Set<GameId>,viewMode: null == viewMode ? _self.viewMode : viewMode // ignore: cast_nullable_to_non_nullable
as LibraryViewMode,gridScrollOffset: null == gridScrollOffset ? _self.gridScrollOffset : gridScrollOffset // ignore: cast_nullable_to_non_nullable
as double,listScrollOffset: null == listScrollOffset ? _self.listScrollOffset : listScrollOffset // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [LibraryState].
extension LibraryStatePatterns on LibraryState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LibraryState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LibraryState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LibraryState value)  $default,){
final _that = this;
switch (_that) {
case _LibraryState():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LibraryState value)?  $default,){
final _that = this;
switch (_that) {
case _LibraryState() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( LibraryScope scope,  String? searchText,  LibraryFilter filters,  LibrarySort sort,  List<GameLibraryRow> games,  String? nextCursor,  LibraryFacets? facets,  LibraryRootPage? roots,  LibraryLoadPhase phase,  bool refreshing,  bool loadingMore,  ClientFailure? lastFailure,  Set<GameId> selectedGameIds,  LibraryViewMode viewMode,  double gridScrollOffset,  double listScrollOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LibraryState() when $default != null:
return $default(_that.scope,_that.searchText,_that.filters,_that.sort,_that.games,_that.nextCursor,_that.facets,_that.roots,_that.phase,_that.refreshing,_that.loadingMore,_that.lastFailure,_that.selectedGameIds,_that.viewMode,_that.gridScrollOffset,_that.listScrollOffset);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( LibraryScope scope,  String? searchText,  LibraryFilter filters,  LibrarySort sort,  List<GameLibraryRow> games,  String? nextCursor,  LibraryFacets? facets,  LibraryRootPage? roots,  LibraryLoadPhase phase,  bool refreshing,  bool loadingMore,  ClientFailure? lastFailure,  Set<GameId> selectedGameIds,  LibraryViewMode viewMode,  double gridScrollOffset,  double listScrollOffset)  $default,) {final _that = this;
switch (_that) {
case _LibraryState():
return $default(_that.scope,_that.searchText,_that.filters,_that.sort,_that.games,_that.nextCursor,_that.facets,_that.roots,_that.phase,_that.refreshing,_that.loadingMore,_that.lastFailure,_that.selectedGameIds,_that.viewMode,_that.gridScrollOffset,_that.listScrollOffset);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( LibraryScope scope,  String? searchText,  LibraryFilter filters,  LibrarySort sort,  List<GameLibraryRow> games,  String? nextCursor,  LibraryFacets? facets,  LibraryRootPage? roots,  LibraryLoadPhase phase,  bool refreshing,  bool loadingMore,  ClientFailure? lastFailure,  Set<GameId> selectedGameIds,  LibraryViewMode viewMode,  double gridScrollOffset,  double listScrollOffset)?  $default,) {final _that = this;
switch (_that) {
case _LibraryState() when $default != null:
return $default(_that.scope,_that.searchText,_that.filters,_that.sort,_that.games,_that.nextCursor,_that.facets,_that.roots,_that.phase,_that.refreshing,_that.loadingMore,_that.lastFailure,_that.selectedGameIds,_that.viewMode,_that.gridScrollOffset,_that.listScrollOffset);case _:
  return null;

}
}

}

/// @nodoc


class _LibraryState extends LibraryState {
  const _LibraryState({required this.scope, required this.searchText, required this.filters, required this.sort, required final  List<GameLibraryRow> games, required this.nextCursor, required this.facets, required this.roots, required this.phase, required this.refreshing, required this.loadingMore, required this.lastFailure, required final  Set<GameId> selectedGameIds, required this.viewMode, required this.gridScrollOffset, required this.listScrollOffset}): _games = games,_selectedGameIds = selectedGameIds,super._();


@override final  LibraryScope scope;
@override final  String? searchText;
@override final  LibraryFilter filters;
@override final  LibrarySort sort;
 final  List<GameLibraryRow> _games;
@override List<GameLibraryRow> get games {
  if (_games is EqualUnmodifiableListView) return _games;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_games);
}

@override final  String? nextCursor;
@override final  LibraryFacets? facets;
@override final  LibraryRootPage? roots;
@override final  LibraryLoadPhase phase;
@override final  bool refreshing;
@override final  bool loadingMore;
@override final  ClientFailure? lastFailure;
 final  Set<GameId> _selectedGameIds;
@override Set<GameId> get selectedGameIds {
  if (_selectedGameIds is EqualUnmodifiableSetView) return _selectedGameIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_selectedGameIds);
}

@override final  LibraryViewMode viewMode;
@override final  double gridScrollOffset;
@override final  double listScrollOffset;

/// Create a copy of LibraryState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LibraryStateCopyWith<_LibraryState> get copyWith => __$LibraryStateCopyWithImpl<_LibraryState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LibraryState&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.searchText, searchText) || other.searchText == searchText)&&(identical(other.filters, filters) || other.filters == filters)&&(identical(other.sort, sort) || other.sort == sort)&&const DeepCollectionEquality().equals(other._games, _games)&&(identical(other.nextCursor, nextCursor) || other.nextCursor == nextCursor)&&(identical(other.facets, facets) || other.facets == facets)&&(identical(other.roots, roots) || other.roots == roots)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.refreshing, refreshing) || other.refreshing == refreshing)&&(identical(other.loadingMore, loadingMore) || other.loadingMore == loadingMore)&&(identical(other.lastFailure, lastFailure) || other.lastFailure == lastFailure)&&const DeepCollectionEquality().equals(other._selectedGameIds, _selectedGameIds)&&(identical(other.viewMode, viewMode) || other.viewMode == viewMode)&&(identical(other.gridScrollOffset, gridScrollOffset) || other.gridScrollOffset == gridScrollOffset)&&(identical(other.listScrollOffset, listScrollOffset) || other.listScrollOffset == listScrollOffset));
}


@override
int get hashCode => Object.hash(runtimeType,scope,searchText,filters,sort,const DeepCollectionEquality().hash(_games),nextCursor,facets,roots,phase,refreshing,loadingMore,lastFailure,const DeepCollectionEquality().hash(_selectedGameIds),viewMode,gridScrollOffset,listScrollOffset);

@override
String toString() {
  return 'LibraryState(scope: $scope, searchText: $searchText, filters: $filters, sort: $sort, games: $games, nextCursor: $nextCursor, facets: $facets, roots: $roots, phase: $phase, refreshing: $refreshing, loadingMore: $loadingMore, lastFailure: $lastFailure, selectedGameIds: $selectedGameIds, viewMode: $viewMode, gridScrollOffset: $gridScrollOffset, listScrollOffset: $listScrollOffset)';
}


}

/// @nodoc
abstract mixin class _$LibraryStateCopyWith<$Res> implements $LibraryStateCopyWith<$Res> {
  factory _$LibraryStateCopyWith(_LibraryState value, $Res Function(_LibraryState) _then) = __$LibraryStateCopyWithImpl;
@override @useResult
$Res call({
 LibraryScope scope, String? searchText, LibraryFilter filters, LibrarySort sort, List<GameLibraryRow> games, String? nextCursor, LibraryFacets? facets, LibraryRootPage? roots, LibraryLoadPhase phase, bool refreshing, bool loadingMore, ClientFailure? lastFailure, Set<GameId> selectedGameIds, LibraryViewMode viewMode, double gridScrollOffset, double listScrollOffset
});




}
/// @nodoc
class __$LibraryStateCopyWithImpl<$Res>
    implements _$LibraryStateCopyWith<$Res> {
  __$LibraryStateCopyWithImpl(this._self, this._then);

  final _LibraryState _self;
  final $Res Function(_LibraryState) _then;

/// Create a copy of LibraryState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? searchText = freezed,Object? filters = null,Object? sort = null,Object? games = null,Object? nextCursor = freezed,Object? facets = freezed,Object? roots = freezed,Object? phase = null,Object? refreshing = null,Object? loadingMore = null,Object? lastFailure = freezed,Object? selectedGameIds = null,Object? viewMode = null,Object? gridScrollOffset = null,Object? listScrollOffset = null,}) {
  return _then(_LibraryState(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as LibraryScope,searchText: freezed == searchText ? _self.searchText : searchText // ignore: cast_nullable_to_non_nullable
as String?,filters: null == filters ? _self.filters : filters // ignore: cast_nullable_to_non_nullable
as LibraryFilter,sort: null == sort ? _self.sort : sort // ignore: cast_nullable_to_non_nullable
as LibrarySort,games: null == games ? _self._games : games // ignore: cast_nullable_to_non_nullable
as List<GameLibraryRow>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,facets: freezed == facets ? _self.facets : facets // ignore: cast_nullable_to_non_nullable
as LibraryFacets?,roots: freezed == roots ? _self.roots : roots // ignore: cast_nullable_to_non_nullable
as LibraryRootPage?,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as LibraryLoadPhase,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as bool,loadingMore: null == loadingMore ? _self.loadingMore : loadingMore // ignore: cast_nullable_to_non_nullable
as bool,lastFailure: freezed == lastFailure ? _self.lastFailure : lastFailure // ignore: cast_nullable_to_non_nullable
as ClientFailure?,selectedGameIds: null == selectedGameIds ? _self._selectedGameIds : selectedGameIds // ignore: cast_nullable_to_non_nullable
as Set<GameId>,viewMode: null == viewMode ? _self.viewMode : viewMode // ignore: cast_nullable_to_non_nullable
as LibraryViewMode,gridScrollOffset: null == gridScrollOffset ? _self.gridScrollOffset : gridScrollOffset // ignore: cast_nullable_to_non_nullable
as double,listScrollOffset: null == listScrollOffset ? _self.listScrollOffset : listScrollOffset // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

// dart format on
