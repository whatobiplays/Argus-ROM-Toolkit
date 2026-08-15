// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'source_hierarchy_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ParentScopeState {

 List<SourceEntry> get children; String? get nextCursor; bool get hasLoaded; bool get loadingFirstPage; bool get loadingMore; bool get refreshing; ClientFailure? get failure;
/// Create a copy of ParentScopeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ParentScopeStateCopyWith<ParentScopeState> get copyWith => _$ParentScopeStateCopyWithImpl<ParentScopeState>(this as ParentScopeState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ParentScopeState&&const DeepCollectionEquality().equals(other.children, children)&&(identical(other.nextCursor, nextCursor) || other.nextCursor == nextCursor)&&(identical(other.hasLoaded, hasLoaded) || other.hasLoaded == hasLoaded)&&(identical(other.loadingFirstPage, loadingFirstPage) || other.loadingFirstPage == loadingFirstPage)&&(identical(other.loadingMore, loadingMore) || other.loadingMore == loadingMore)&&(identical(other.refreshing, refreshing) || other.refreshing == refreshing)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(children),nextCursor,hasLoaded,loadingFirstPage,loadingMore,refreshing,failure);

@override
String toString() {
  return 'ParentScopeState(children: $children, nextCursor: $nextCursor, hasLoaded: $hasLoaded, loadingFirstPage: $loadingFirstPage, loadingMore: $loadingMore, refreshing: $refreshing, failure: $failure)';
}


}

/// @nodoc
abstract mixin class $ParentScopeStateCopyWith<$Res>  {
  factory $ParentScopeStateCopyWith(ParentScopeState value, $Res Function(ParentScopeState) _then) = _$ParentScopeStateCopyWithImpl;
@useResult
$Res call({
 List<SourceEntry> children, String? nextCursor, bool hasLoaded, bool loadingFirstPage, bool loadingMore, bool refreshing, ClientFailure? failure
});




}
/// @nodoc
class _$ParentScopeStateCopyWithImpl<$Res>
    implements $ParentScopeStateCopyWith<$Res> {
  _$ParentScopeStateCopyWithImpl(this._self, this._then);

  final ParentScopeState _self;
  final $Res Function(ParentScopeState) _then;

/// Create a copy of ParentScopeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? children = null,Object? nextCursor = freezed,Object? hasLoaded = null,Object? loadingFirstPage = null,Object? loadingMore = null,Object? refreshing = null,Object? failure = freezed,}) {
  return _then(_self.copyWith(
children: null == children ? _self.children : children // ignore: cast_nullable_to_non_nullable
as List<SourceEntry>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,hasLoaded: null == hasLoaded ? _self.hasLoaded : hasLoaded // ignore: cast_nullable_to_non_nullable
as bool,loadingFirstPage: null == loadingFirstPage ? _self.loadingFirstPage : loadingFirstPage // ignore: cast_nullable_to_non_nullable
as bool,loadingMore: null == loadingMore ? _self.loadingMore : loadingMore // ignore: cast_nullable_to_non_nullable
as bool,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as bool,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as ClientFailure?,
  ));
}

}


/// Adds pattern-matching-related methods to [ParentScopeState].
extension ParentScopeStatePatterns on ParentScopeState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ParentScopeState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ParentScopeState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ParentScopeState value)  $default,){
final _that = this;
switch (_that) {
case _ParentScopeState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ParentScopeState value)?  $default,){
final _that = this;
switch (_that) {
case _ParentScopeState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<SourceEntry> children,  String? nextCursor,  bool hasLoaded,  bool loadingFirstPage,  bool loadingMore,  bool refreshing,  ClientFailure? failure)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ParentScopeState() when $default != null:
return $default(_that.children,_that.nextCursor,_that.hasLoaded,_that.loadingFirstPage,_that.loadingMore,_that.refreshing,_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<SourceEntry> children,  String? nextCursor,  bool hasLoaded,  bool loadingFirstPage,  bool loadingMore,  bool refreshing,  ClientFailure? failure)  $default,) {final _that = this;
switch (_that) {
case _ParentScopeState():
return $default(_that.children,_that.nextCursor,_that.hasLoaded,_that.loadingFirstPage,_that.loadingMore,_that.refreshing,_that.failure);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<SourceEntry> children,  String? nextCursor,  bool hasLoaded,  bool loadingFirstPage,  bool loadingMore,  bool refreshing,  ClientFailure? failure)?  $default,) {final _that = this;
switch (_that) {
case _ParentScopeState() when $default != null:
return $default(_that.children,_that.nextCursor,_that.hasLoaded,_that.loadingFirstPage,_that.loadingMore,_that.refreshing,_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class _ParentScopeState implements ParentScopeState {
  const _ParentScopeState({required final  List<SourceEntry> children, this.nextCursor, required this.hasLoaded, required this.loadingFirstPage, required this.loadingMore, required this.refreshing, this.failure}): _children = children;


 final  List<SourceEntry> _children;
@override List<SourceEntry> get children {
  if (_children is EqualUnmodifiableListView) return _children;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_children);
}

@override final  String? nextCursor;
@override final  bool hasLoaded;
@override final  bool loadingFirstPage;
@override final  bool loadingMore;
@override final  bool refreshing;
@override final  ClientFailure? failure;

/// Create a copy of ParentScopeState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ParentScopeStateCopyWith<_ParentScopeState> get copyWith => __$ParentScopeStateCopyWithImpl<_ParentScopeState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ParentScopeState&&const DeepCollectionEquality().equals(other._children, _children)&&(identical(other.nextCursor, nextCursor) || other.nextCursor == nextCursor)&&(identical(other.hasLoaded, hasLoaded) || other.hasLoaded == hasLoaded)&&(identical(other.loadingFirstPage, loadingFirstPage) || other.loadingFirstPage == loadingFirstPage)&&(identical(other.loadingMore, loadingMore) || other.loadingMore == loadingMore)&&(identical(other.refreshing, refreshing) || other.refreshing == refreshing)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_children),nextCursor,hasLoaded,loadingFirstPage,loadingMore,refreshing,failure);

@override
String toString() {
  return 'ParentScopeState(children: $children, nextCursor: $nextCursor, hasLoaded: $hasLoaded, loadingFirstPage: $loadingFirstPage, loadingMore: $loadingMore, refreshing: $refreshing, failure: $failure)';
}


}

/// @nodoc
abstract mixin class _$ParentScopeStateCopyWith<$Res> implements $ParentScopeStateCopyWith<$Res> {
  factory _$ParentScopeStateCopyWith(_ParentScopeState value, $Res Function(_ParentScopeState) _then) = __$ParentScopeStateCopyWithImpl;
@override @useResult
$Res call({
 List<SourceEntry> children, String? nextCursor, bool hasLoaded, bool loadingFirstPage, bool loadingMore, bool refreshing, ClientFailure? failure
});




}
/// @nodoc
class __$ParentScopeStateCopyWithImpl<$Res>
    implements _$ParentScopeStateCopyWith<$Res> {
  __$ParentScopeStateCopyWithImpl(this._self, this._then);

  final _ParentScopeState _self;
  final $Res Function(_ParentScopeState) _then;

/// Create a copy of ParentScopeState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? children = null,Object? nextCursor = freezed,Object? hasLoaded = null,Object? loadingFirstPage = null,Object? loadingMore = null,Object? refreshing = null,Object? failure = freezed,}) {
  return _then(_ParentScopeState(
children: null == children ? _self._children : children // ignore: cast_nullable_to_non_nullable
as List<SourceEntry>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,hasLoaded: null == hasLoaded ? _self.hasLoaded : hasLoaded // ignore: cast_nullable_to_non_nullable
as bool,loadingFirstPage: null == loadingFirstPage ? _self.loadingFirstPage : loadingFirstPage // ignore: cast_nullable_to_non_nullable
as bool,loadingMore: null == loadingMore ? _self.loadingMore : loadingMore // ignore: cast_nullable_to_non_nullable
as bool,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as bool,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as ClientFailure?,
  ));
}


}

/// @nodoc
mixin _$SourceHierarchyState {

 LibraryRootId get rootId;/// Parent scope key: `''` is the root scope, otherwise the parent
/// `SourceEntryId.value`.
 Map<String, ParentScopeState> get scopesByParent; Set<String> get expandedEntryIds; SourceEntryId? get selectedEntryId; List<SourceEntryId> get compactDrillDownPath; bool get reconciling;
/// Create a copy of SourceHierarchyState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourceHierarchyStateCopyWith<SourceHierarchyState> get copyWith => _$SourceHierarchyStateCopyWithImpl<SourceHierarchyState>(this as SourceHierarchyState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceHierarchyState&&(identical(other.rootId, rootId) || other.rootId == rootId)&&const DeepCollectionEquality().equals(other.scopesByParent, scopesByParent)&&const DeepCollectionEquality().equals(other.expandedEntryIds, expandedEntryIds)&&(identical(other.selectedEntryId, selectedEntryId) || other.selectedEntryId == selectedEntryId)&&const DeepCollectionEquality().equals(other.compactDrillDownPath, compactDrillDownPath)&&(identical(other.reconciling, reconciling) || other.reconciling == reconciling));
}


@override
int get hashCode => Object.hash(runtimeType,rootId,const DeepCollectionEquality().hash(scopesByParent),const DeepCollectionEquality().hash(expandedEntryIds),selectedEntryId,const DeepCollectionEquality().hash(compactDrillDownPath),reconciling);

@override
String toString() {
  return 'SourceHierarchyState(rootId: $rootId, scopesByParent: $scopesByParent, expandedEntryIds: $expandedEntryIds, selectedEntryId: $selectedEntryId, compactDrillDownPath: $compactDrillDownPath, reconciling: $reconciling)';
}


}

/// @nodoc
abstract mixin class $SourceHierarchyStateCopyWith<$Res>  {
  factory $SourceHierarchyStateCopyWith(SourceHierarchyState value, $Res Function(SourceHierarchyState) _then) = _$SourceHierarchyStateCopyWithImpl;
@useResult
$Res call({
 LibraryRootId rootId, Map<String, ParentScopeState> scopesByParent, Set<String> expandedEntryIds, SourceEntryId? selectedEntryId, List<SourceEntryId> compactDrillDownPath, bool reconciling
});




}
/// @nodoc
class _$SourceHierarchyStateCopyWithImpl<$Res>
    implements $SourceHierarchyStateCopyWith<$Res> {
  _$SourceHierarchyStateCopyWithImpl(this._self, this._then);

  final SourceHierarchyState _self;
  final $Res Function(SourceHierarchyState) _then;

/// Create a copy of SourceHierarchyState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? rootId = null,Object? scopesByParent = null,Object? expandedEntryIds = null,Object? selectedEntryId = freezed,Object? compactDrillDownPath = null,Object? reconciling = null,}) {
  return _then(_self.copyWith(
rootId: null == rootId ? _self.rootId : rootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,scopesByParent: null == scopesByParent ? _self.scopesByParent : scopesByParent // ignore: cast_nullable_to_non_nullable
as Map<String, ParentScopeState>,expandedEntryIds: null == expandedEntryIds ? _self.expandedEntryIds : expandedEntryIds // ignore: cast_nullable_to_non_nullable
as Set<String>,selectedEntryId: freezed == selectedEntryId ? _self.selectedEntryId : selectedEntryId // ignore: cast_nullable_to_non_nullable
as SourceEntryId?,compactDrillDownPath: null == compactDrillDownPath ? _self.compactDrillDownPath : compactDrillDownPath // ignore: cast_nullable_to_non_nullable
as List<SourceEntryId>,reconciling: null == reconciling ? _self.reconciling : reconciling // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [SourceHierarchyState].
extension SourceHierarchyStatePatterns on SourceHierarchyState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SourceHierarchyState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SourceHierarchyState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SourceHierarchyState value)  $default,){
final _that = this;
switch (_that) {
case _SourceHierarchyState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SourceHierarchyState value)?  $default,){
final _that = this;
switch (_that) {
case _SourceHierarchyState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( LibraryRootId rootId,  Map<String, ParentScopeState> scopesByParent,  Set<String> expandedEntryIds,  SourceEntryId? selectedEntryId,  List<SourceEntryId> compactDrillDownPath,  bool reconciling)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SourceHierarchyState() when $default != null:
return $default(_that.rootId,_that.scopesByParent,_that.expandedEntryIds,_that.selectedEntryId,_that.compactDrillDownPath,_that.reconciling);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( LibraryRootId rootId,  Map<String, ParentScopeState> scopesByParent,  Set<String> expandedEntryIds,  SourceEntryId? selectedEntryId,  List<SourceEntryId> compactDrillDownPath,  bool reconciling)  $default,) {final _that = this;
switch (_that) {
case _SourceHierarchyState():
return $default(_that.rootId,_that.scopesByParent,_that.expandedEntryIds,_that.selectedEntryId,_that.compactDrillDownPath,_that.reconciling);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( LibraryRootId rootId,  Map<String, ParentScopeState> scopesByParent,  Set<String> expandedEntryIds,  SourceEntryId? selectedEntryId,  List<SourceEntryId> compactDrillDownPath,  bool reconciling)?  $default,) {final _that = this;
switch (_that) {
case _SourceHierarchyState() when $default != null:
return $default(_that.rootId,_that.scopesByParent,_that.expandedEntryIds,_that.selectedEntryId,_that.compactDrillDownPath,_that.reconciling);case _:
  return null;

}
}

}

/// @nodoc


class _SourceHierarchyState implements SourceHierarchyState {
  const _SourceHierarchyState({required this.rootId, required final  Map<String, ParentScopeState> scopesByParent, required final  Set<String> expandedEntryIds, this.selectedEntryId, required final  List<SourceEntryId> compactDrillDownPath, required this.reconciling}): _scopesByParent = scopesByParent,_expandedEntryIds = expandedEntryIds,_compactDrillDownPath = compactDrillDownPath;


@override final  LibraryRootId rootId;
/// Parent scope key: `''` is the root scope, otherwise the parent
/// `SourceEntryId.value`.
 final  Map<String, ParentScopeState> _scopesByParent;
/// Parent scope key: `''` is the root scope, otherwise the parent
/// `SourceEntryId.value`.
@override Map<String, ParentScopeState> get scopesByParent {
  if (_scopesByParent is EqualUnmodifiableMapView) return _scopesByParent;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_scopesByParent);
}

 final  Set<String> _expandedEntryIds;
@override Set<String> get expandedEntryIds {
  if (_expandedEntryIds is EqualUnmodifiableSetView) return _expandedEntryIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_expandedEntryIds);
}

@override final  SourceEntryId? selectedEntryId;
 final  List<SourceEntryId> _compactDrillDownPath;
@override List<SourceEntryId> get compactDrillDownPath {
  if (_compactDrillDownPath is EqualUnmodifiableListView) return _compactDrillDownPath;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_compactDrillDownPath);
}

@override final  bool reconciling;

/// Create a copy of SourceHierarchyState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SourceHierarchyStateCopyWith<_SourceHierarchyState> get copyWith => __$SourceHierarchyStateCopyWithImpl<_SourceHierarchyState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SourceHierarchyState&&(identical(other.rootId, rootId) || other.rootId == rootId)&&const DeepCollectionEquality().equals(other._scopesByParent, _scopesByParent)&&const DeepCollectionEquality().equals(other._expandedEntryIds, _expandedEntryIds)&&(identical(other.selectedEntryId, selectedEntryId) || other.selectedEntryId == selectedEntryId)&&const DeepCollectionEquality().equals(other._compactDrillDownPath, _compactDrillDownPath)&&(identical(other.reconciling, reconciling) || other.reconciling == reconciling));
}


@override
int get hashCode => Object.hash(runtimeType,rootId,const DeepCollectionEquality().hash(_scopesByParent),const DeepCollectionEquality().hash(_expandedEntryIds),selectedEntryId,const DeepCollectionEquality().hash(_compactDrillDownPath),reconciling);

@override
String toString() {
  return 'SourceHierarchyState(rootId: $rootId, scopesByParent: $scopesByParent, expandedEntryIds: $expandedEntryIds, selectedEntryId: $selectedEntryId, compactDrillDownPath: $compactDrillDownPath, reconciling: $reconciling)';
}


}

/// @nodoc
abstract mixin class _$SourceHierarchyStateCopyWith<$Res> implements $SourceHierarchyStateCopyWith<$Res> {
  factory _$SourceHierarchyStateCopyWith(_SourceHierarchyState value, $Res Function(_SourceHierarchyState) _then) = __$SourceHierarchyStateCopyWithImpl;
@override @useResult
$Res call({
 LibraryRootId rootId, Map<String, ParentScopeState> scopesByParent, Set<String> expandedEntryIds, SourceEntryId? selectedEntryId, List<SourceEntryId> compactDrillDownPath, bool reconciling
});




}
/// @nodoc
class __$SourceHierarchyStateCopyWithImpl<$Res>
    implements _$SourceHierarchyStateCopyWith<$Res> {
  __$SourceHierarchyStateCopyWithImpl(this._self, this._then);

  final _SourceHierarchyState _self;
  final $Res Function(_SourceHierarchyState) _then;

/// Create a copy of SourceHierarchyState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? rootId = null,Object? scopesByParent = null,Object? expandedEntryIds = null,Object? selectedEntryId = freezed,Object? compactDrillDownPath = null,Object? reconciling = null,}) {
  return _then(_SourceHierarchyState(
rootId: null == rootId ? _self.rootId : rootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,scopesByParent: null == scopesByParent ? _self._scopesByParent : scopesByParent // ignore: cast_nullable_to_non_nullable
as Map<String, ParentScopeState>,expandedEntryIds: null == expandedEntryIds ? _self._expandedEntryIds : expandedEntryIds // ignore: cast_nullable_to_non_nullable
as Set<String>,selectedEntryId: freezed == selectedEntryId ? _self.selectedEntryId : selectedEntryId // ignore: cast_nullable_to_non_nullable
as SourceEntryId?,compactDrillDownPath: null == compactDrillDownPath ? _self._compactDrillDownPath : compactDrillDownPath // ignore: cast_nullable_to_non_nullable
as List<SourceEntryId>,reconciling: null == reconciling ? _self.reconciling : reconciling // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
