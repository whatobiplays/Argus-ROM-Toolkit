// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'jobs_list_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$JobsListState {

 List<JobListItem> get activeJobs; List<JobListItem> get recentJobs; int get recentTotalCount; bool get refreshing; ClientFailure? get lastFailure; bool get loadingMore; bool get loadMoreFailed; int? get nextOffset;
/// Create a copy of JobsListState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobsListStateCopyWith<JobsListState> get copyWith => _$JobsListStateCopyWithImpl<JobsListState>(this as JobsListState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobsListState&&const DeepCollectionEquality().equals(other.activeJobs, activeJobs)&&const DeepCollectionEquality().equals(other.recentJobs, recentJobs)&&(identical(other.recentTotalCount, recentTotalCount) || other.recentTotalCount == recentTotalCount)&&(identical(other.refreshing, refreshing) || other.refreshing == refreshing)&&(identical(other.lastFailure, lastFailure) || other.lastFailure == lastFailure)&&(identical(other.loadingMore, loadingMore) || other.loadingMore == loadingMore)&&(identical(other.loadMoreFailed, loadMoreFailed) || other.loadMoreFailed == loadMoreFailed)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(activeJobs),const DeepCollectionEquality().hash(recentJobs),recentTotalCount,refreshing,lastFailure,loadingMore,loadMoreFailed,nextOffset);

@override
String toString() {
  return 'JobsListState(activeJobs: $activeJobs, recentJobs: $recentJobs, recentTotalCount: $recentTotalCount, refreshing: $refreshing, lastFailure: $lastFailure, loadingMore: $loadingMore, loadMoreFailed: $loadMoreFailed, nextOffset: $nextOffset)';
}


}

/// @nodoc
abstract mixin class $JobsListStateCopyWith<$Res>  {
  factory $JobsListStateCopyWith(JobsListState value, $Res Function(JobsListState) _then) = _$JobsListStateCopyWithImpl;
@useResult
$Res call({
 List<JobListItem> activeJobs, List<JobListItem> recentJobs, int recentTotalCount, bool refreshing, ClientFailure? lastFailure, bool loadingMore, bool loadMoreFailed, int? nextOffset
});




}
/// @nodoc
class _$JobsListStateCopyWithImpl<$Res>
    implements $JobsListStateCopyWith<$Res> {
  _$JobsListStateCopyWithImpl(this._self, this._then);

  final JobsListState _self;
  final $Res Function(JobsListState) _then;

/// Create a copy of JobsListState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? activeJobs = null,Object? recentJobs = null,Object? recentTotalCount = null,Object? refreshing = null,Object? lastFailure = freezed,Object? loadingMore = null,Object? loadMoreFailed = null,Object? nextOffset = freezed,}) {
  return _then(_self.copyWith(
activeJobs: null == activeJobs ? _self.activeJobs : activeJobs // ignore: cast_nullable_to_non_nullable
as List<JobListItem>,recentJobs: null == recentJobs ? _self.recentJobs : recentJobs // ignore: cast_nullable_to_non_nullable
as List<JobListItem>,recentTotalCount: null == recentTotalCount ? _self.recentTotalCount : recentTotalCount // ignore: cast_nullable_to_non_nullable
as int,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as bool,lastFailure: freezed == lastFailure ? _self.lastFailure : lastFailure // ignore: cast_nullable_to_non_nullable
as ClientFailure?,loadingMore: null == loadingMore ? _self.loadingMore : loadingMore // ignore: cast_nullable_to_non_nullable
as bool,loadMoreFailed: null == loadMoreFailed ? _self.loadMoreFailed : loadMoreFailed // ignore: cast_nullable_to_non_nullable
as bool,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [JobsListState].
extension JobsListStatePatterns on JobsListState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( JobsListStateReady value)?  ready,required TResult orElse(),}){
final _that = this;
switch (_that) {
case JobsListStateReady() when ready != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( JobsListStateReady value)  ready,}){
final _that = this;
switch (_that) {
case JobsListStateReady():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( JobsListStateReady value)?  ready,}){
final _that = this;
switch (_that) {
case JobsListStateReady() when ready != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<JobListItem> activeJobs,  List<JobListItem> recentJobs,  int recentTotalCount,  bool refreshing,  ClientFailure? lastFailure,  bool loadingMore,  bool loadMoreFailed,  int? nextOffset)?  ready,required TResult orElse(),}) {final _that = this;
switch (_that) {
case JobsListStateReady() when ready != null:
return ready(_that.activeJobs,_that.recentJobs,_that.recentTotalCount,_that.refreshing,_that.lastFailure,_that.loadingMore,_that.loadMoreFailed,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<JobListItem> activeJobs,  List<JobListItem> recentJobs,  int recentTotalCount,  bool refreshing,  ClientFailure? lastFailure,  bool loadingMore,  bool loadMoreFailed,  int? nextOffset)  ready,}) {final _that = this;
switch (_that) {
case JobsListStateReady():
return ready(_that.activeJobs,_that.recentJobs,_that.recentTotalCount,_that.refreshing,_that.lastFailure,_that.loadingMore,_that.loadMoreFailed,_that.nextOffset);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<JobListItem> activeJobs,  List<JobListItem> recentJobs,  int recentTotalCount,  bool refreshing,  ClientFailure? lastFailure,  bool loadingMore,  bool loadMoreFailed,  int? nextOffset)?  ready,}) {final _that = this;
switch (_that) {
case JobsListStateReady() when ready != null:
return ready(_that.activeJobs,_that.recentJobs,_that.recentTotalCount,_that.refreshing,_that.lastFailure,_that.loadingMore,_that.loadMoreFailed,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class JobsListStateReady implements JobsListState {
  const JobsListStateReady({required final  List<JobListItem> activeJobs, required final  List<JobListItem> recentJobs, required this.recentTotalCount, required this.refreshing, this.lastFailure, required this.loadingMore, required this.loadMoreFailed, this.nextOffset}): _activeJobs = activeJobs,_recentJobs = recentJobs;


 final  List<JobListItem> _activeJobs;
@override List<JobListItem> get activeJobs {
  if (_activeJobs is EqualUnmodifiableListView) return _activeJobs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_activeJobs);
}

 final  List<JobListItem> _recentJobs;
@override List<JobListItem> get recentJobs {
  if (_recentJobs is EqualUnmodifiableListView) return _recentJobs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_recentJobs);
}

@override final  int recentTotalCount;
@override final  bool refreshing;
@override final  ClientFailure? lastFailure;
@override final  bool loadingMore;
@override final  bool loadMoreFailed;
@override final  int? nextOffset;

/// Create a copy of JobsListState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobsListStateReadyCopyWith<JobsListStateReady> get copyWith => _$JobsListStateReadyCopyWithImpl<JobsListStateReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobsListStateReady&&const DeepCollectionEquality().equals(other._activeJobs, _activeJobs)&&const DeepCollectionEquality().equals(other._recentJobs, _recentJobs)&&(identical(other.recentTotalCount, recentTotalCount) || other.recentTotalCount == recentTotalCount)&&(identical(other.refreshing, refreshing) || other.refreshing == refreshing)&&(identical(other.lastFailure, lastFailure) || other.lastFailure == lastFailure)&&(identical(other.loadingMore, loadingMore) || other.loadingMore == loadingMore)&&(identical(other.loadMoreFailed, loadMoreFailed) || other.loadMoreFailed == loadMoreFailed)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_activeJobs),const DeepCollectionEquality().hash(_recentJobs),recentTotalCount,refreshing,lastFailure,loadingMore,loadMoreFailed,nextOffset);

@override
String toString() {
  return 'JobsListState.ready(activeJobs: $activeJobs, recentJobs: $recentJobs, recentTotalCount: $recentTotalCount, refreshing: $refreshing, lastFailure: $lastFailure, loadingMore: $loadingMore, loadMoreFailed: $loadMoreFailed, nextOffset: $nextOffset)';
}


}

/// @nodoc
abstract mixin class $JobsListStateReadyCopyWith<$Res> implements $JobsListStateCopyWith<$Res> {
  factory $JobsListStateReadyCopyWith(JobsListStateReady value, $Res Function(JobsListStateReady) _then) = _$JobsListStateReadyCopyWithImpl;
@override @useResult
$Res call({
 List<JobListItem> activeJobs, List<JobListItem> recentJobs, int recentTotalCount, bool refreshing, ClientFailure? lastFailure, bool loadingMore, bool loadMoreFailed, int? nextOffset
});




}
/// @nodoc
class _$JobsListStateReadyCopyWithImpl<$Res>
    implements $JobsListStateReadyCopyWith<$Res> {
  _$JobsListStateReadyCopyWithImpl(this._self, this._then);

  final JobsListStateReady _self;
  final $Res Function(JobsListStateReady) _then;

/// Create a copy of JobsListState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? activeJobs = null,Object? recentJobs = null,Object? recentTotalCount = null,Object? refreshing = null,Object? lastFailure = freezed,Object? loadingMore = null,Object? loadMoreFailed = null,Object? nextOffset = freezed,}) {
  return _then(JobsListStateReady(
activeJobs: null == activeJobs ? _self._activeJobs : activeJobs // ignore: cast_nullable_to_non_nullable
as List<JobListItem>,recentJobs: null == recentJobs ? _self._recentJobs : recentJobs // ignore: cast_nullable_to_non_nullable
as List<JobListItem>,recentTotalCount: null == recentTotalCount ? _self.recentTotalCount : recentTotalCount // ignore: cast_nullable_to_non_nullable
as int,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as bool,lastFailure: freezed == lastFailure ? _self.lastFailure : lastFailure // ignore: cast_nullable_to_non_nullable
as ClientFailure?,loadingMore: null == loadingMore ? _self.loadingMore : loadingMore // ignore: cast_nullable_to_non_nullable
as bool,loadMoreFailed: null == loadMoreFailed ? _self.loadMoreFailed : loadMoreFailed // ignore: cast_nullable_to_non_nullable
as bool,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
