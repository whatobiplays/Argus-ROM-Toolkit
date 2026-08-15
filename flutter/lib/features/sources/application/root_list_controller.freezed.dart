// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'root_list_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SourcesRootListState {

 List<LibraryRoot> get roots; int get totalCount; bool get refreshing; ClientFailure? get lastFailure; bool get loadingMore; bool get loadMoreFailed; int get nextOffset; SourcesScanAllStatus get scanAllStatus;
/// Create a copy of SourcesRootListState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourcesRootListStateCopyWith<SourcesRootListState> get copyWith => _$SourcesRootListStateCopyWithImpl<SourcesRootListState>(this as SourcesRootListState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesRootListState&&const DeepCollectionEquality().equals(other.roots, roots)&&(identical(other.totalCount, totalCount) || other.totalCount == totalCount)&&(identical(other.refreshing, refreshing) || other.refreshing == refreshing)&&(identical(other.lastFailure, lastFailure) || other.lastFailure == lastFailure)&&(identical(other.loadingMore, loadingMore) || other.loadingMore == loadingMore)&&(identical(other.loadMoreFailed, loadMoreFailed) || other.loadMoreFailed == loadMoreFailed)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset)&&(identical(other.scanAllStatus, scanAllStatus) || other.scanAllStatus == scanAllStatus));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(roots),totalCount,refreshing,lastFailure,loadingMore,loadMoreFailed,nextOffset,scanAllStatus);

@override
String toString() {
  return 'SourcesRootListState(roots: $roots, totalCount: $totalCount, refreshing: $refreshing, lastFailure: $lastFailure, loadingMore: $loadingMore, loadMoreFailed: $loadMoreFailed, nextOffset: $nextOffset, scanAllStatus: $scanAllStatus)';
}


}

/// @nodoc
abstract mixin class $SourcesRootListStateCopyWith<$Res>  {
  factory $SourcesRootListStateCopyWith(SourcesRootListState value, $Res Function(SourcesRootListState) _then) = _$SourcesRootListStateCopyWithImpl;
@useResult
$Res call({
 List<LibraryRoot> roots, int totalCount, bool refreshing, ClientFailure? lastFailure, bool loadingMore, bool loadMoreFailed, int nextOffset, SourcesScanAllStatus scanAllStatus
});


$SourcesScanAllStatusCopyWith<$Res> get scanAllStatus;

}
/// @nodoc
class _$SourcesRootListStateCopyWithImpl<$Res>
    implements $SourcesRootListStateCopyWith<$Res> {
  _$SourcesRootListStateCopyWithImpl(this._self, this._then);

  final SourcesRootListState _self;
  final $Res Function(SourcesRootListState) _then;

/// Create a copy of SourcesRootListState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? roots = null,Object? totalCount = null,Object? refreshing = null,Object? lastFailure = freezed,Object? loadingMore = null,Object? loadMoreFailed = null,Object? nextOffset = null,Object? scanAllStatus = null,}) {
  return _then(_self.copyWith(
roots: null == roots ? _self.roots : roots // ignore: cast_nullable_to_non_nullable
as List<LibraryRoot>,totalCount: null == totalCount ? _self.totalCount : totalCount // ignore: cast_nullable_to_non_nullable
as int,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as bool,lastFailure: freezed == lastFailure ? _self.lastFailure : lastFailure // ignore: cast_nullable_to_non_nullable
as ClientFailure?,loadingMore: null == loadingMore ? _self.loadingMore : loadingMore // ignore: cast_nullable_to_non_nullable
as bool,loadMoreFailed: null == loadMoreFailed ? _self.loadMoreFailed : loadMoreFailed // ignore: cast_nullable_to_non_nullable
as bool,nextOffset: null == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int,scanAllStatus: null == scanAllStatus ? _self.scanAllStatus : scanAllStatus // ignore: cast_nullable_to_non_nullable
as SourcesScanAllStatus,
  ));
}
/// Create a copy of SourcesRootListState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourcesScanAllStatusCopyWith<$Res> get scanAllStatus {

  return $SourcesScanAllStatusCopyWith<$Res>(_self.scanAllStatus, (value) {
    return _then(_self.copyWith(scanAllStatus: value));
  });
}
}


/// Adds pattern-matching-related methods to [SourcesRootListState].
extension SourcesRootListStatePatterns on SourcesRootListState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SourcesRootListStateReady value)?  ready,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SourcesRootListStateReady() when ready != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SourcesRootListStateReady value)  ready,}){
final _that = this;
switch (_that) {
case SourcesRootListStateReady():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SourcesRootListStateReady value)?  ready,}){
final _that = this;
switch (_that) {
case SourcesRootListStateReady() when ready != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<LibraryRoot> roots,  int totalCount,  bool refreshing,  ClientFailure? lastFailure,  bool loadingMore,  bool loadMoreFailed,  int nextOffset,  SourcesScanAllStatus scanAllStatus)?  ready,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SourcesRootListStateReady() when ready != null:
return ready(_that.roots,_that.totalCount,_that.refreshing,_that.lastFailure,_that.loadingMore,_that.loadMoreFailed,_that.nextOffset,_that.scanAllStatus);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<LibraryRoot> roots,  int totalCount,  bool refreshing,  ClientFailure? lastFailure,  bool loadingMore,  bool loadMoreFailed,  int nextOffset,  SourcesScanAllStatus scanAllStatus)  ready,}) {final _that = this;
switch (_that) {
case SourcesRootListStateReady():
return ready(_that.roots,_that.totalCount,_that.refreshing,_that.lastFailure,_that.loadingMore,_that.loadMoreFailed,_that.nextOffset,_that.scanAllStatus);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<LibraryRoot> roots,  int totalCount,  bool refreshing,  ClientFailure? lastFailure,  bool loadingMore,  bool loadMoreFailed,  int nextOffset,  SourcesScanAllStatus scanAllStatus)?  ready,}) {final _that = this;
switch (_that) {
case SourcesRootListStateReady() when ready != null:
return ready(_that.roots,_that.totalCount,_that.refreshing,_that.lastFailure,_that.loadingMore,_that.loadMoreFailed,_that.nextOffset,_that.scanAllStatus);case _:
  return null;

}
}

}

/// @nodoc


class SourcesRootListStateReady implements SourcesRootListState {
  const SourcesRootListStateReady({required final  List<LibraryRoot> roots, required this.totalCount, required this.refreshing, this.lastFailure, required this.loadingMore, required this.loadMoreFailed, required this.nextOffset, required this.scanAllStatus}): _roots = roots;


 final  List<LibraryRoot> _roots;
@override List<LibraryRoot> get roots {
  if (_roots is EqualUnmodifiableListView) return _roots;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_roots);
}

@override final  int totalCount;
@override final  bool refreshing;
@override final  ClientFailure? lastFailure;
@override final  bool loadingMore;
@override final  bool loadMoreFailed;
@override final  int nextOffset;
@override final  SourcesScanAllStatus scanAllStatus;

/// Create a copy of SourcesRootListState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourcesRootListStateReadyCopyWith<SourcesRootListStateReady> get copyWith => _$SourcesRootListStateReadyCopyWithImpl<SourcesRootListStateReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesRootListStateReady&&const DeepCollectionEquality().equals(other._roots, _roots)&&(identical(other.totalCount, totalCount) || other.totalCount == totalCount)&&(identical(other.refreshing, refreshing) || other.refreshing == refreshing)&&(identical(other.lastFailure, lastFailure) || other.lastFailure == lastFailure)&&(identical(other.loadingMore, loadingMore) || other.loadingMore == loadingMore)&&(identical(other.loadMoreFailed, loadMoreFailed) || other.loadMoreFailed == loadMoreFailed)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset)&&(identical(other.scanAllStatus, scanAllStatus) || other.scanAllStatus == scanAllStatus));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_roots),totalCount,refreshing,lastFailure,loadingMore,loadMoreFailed,nextOffset,scanAllStatus);

@override
String toString() {
  return 'SourcesRootListState.ready(roots: $roots, totalCount: $totalCount, refreshing: $refreshing, lastFailure: $lastFailure, loadingMore: $loadingMore, loadMoreFailed: $loadMoreFailed, nextOffset: $nextOffset, scanAllStatus: $scanAllStatus)';
}


}

/// @nodoc
abstract mixin class $SourcesRootListStateReadyCopyWith<$Res> implements $SourcesRootListStateCopyWith<$Res> {
  factory $SourcesRootListStateReadyCopyWith(SourcesRootListStateReady value, $Res Function(SourcesRootListStateReady) _then) = _$SourcesRootListStateReadyCopyWithImpl;
@override @useResult
$Res call({
 List<LibraryRoot> roots, int totalCount, bool refreshing, ClientFailure? lastFailure, bool loadingMore, bool loadMoreFailed, int nextOffset, SourcesScanAllStatus scanAllStatus
});


@override $SourcesScanAllStatusCopyWith<$Res> get scanAllStatus;

}
/// @nodoc
class _$SourcesRootListStateReadyCopyWithImpl<$Res>
    implements $SourcesRootListStateReadyCopyWith<$Res> {
  _$SourcesRootListStateReadyCopyWithImpl(this._self, this._then);

  final SourcesRootListStateReady _self;
  final $Res Function(SourcesRootListStateReady) _then;

/// Create a copy of SourcesRootListState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roots = null,Object? totalCount = null,Object? refreshing = null,Object? lastFailure = freezed,Object? loadingMore = null,Object? loadMoreFailed = null,Object? nextOffset = null,Object? scanAllStatus = null,}) {
  return _then(SourcesRootListStateReady(
roots: null == roots ? _self._roots : roots // ignore: cast_nullable_to_non_nullable
as List<LibraryRoot>,totalCount: null == totalCount ? _self.totalCount : totalCount // ignore: cast_nullable_to_non_nullable
as int,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as bool,lastFailure: freezed == lastFailure ? _self.lastFailure : lastFailure // ignore: cast_nullable_to_non_nullable
as ClientFailure?,loadingMore: null == loadingMore ? _self.loadingMore : loadingMore // ignore: cast_nullable_to_non_nullable
as bool,loadMoreFailed: null == loadMoreFailed ? _self.loadMoreFailed : loadMoreFailed // ignore: cast_nullable_to_non_nullable
as bool,nextOffset: null == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int,scanAllStatus: null == scanAllStatus ? _self.scanAllStatus : scanAllStatus // ignore: cast_nullable_to_non_nullable
as SourcesScanAllStatus,
  ));
}

/// Create a copy of SourcesRootListState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourcesScanAllStatusCopyWith<$Res> get scanAllStatus {

  return $SourcesScanAllStatusCopyWith<$Res>(_self.scanAllStatus, (value) {
    return _then(_self.copyWith(scanAllStatus: value));
  });
}
}

/// @nodoc
mixin _$SourcesScanAllStatus {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesScanAllStatus);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourcesScanAllStatus()';
}


}

/// @nodoc
class $SourcesScanAllStatusCopyWith<$Res>  {
$SourcesScanAllStatusCopyWith(SourcesScanAllStatus _, $Res Function(SourcesScanAllStatus) __);
}


/// Adds pattern-matching-related methods to [SourcesScanAllStatus].
extension SourcesScanAllStatusPatterns on SourcesScanAllStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SourcesScanAllStatusIdle value)?  idle,TResult Function( SourcesScanAllStatusSubmitting value)?  submitting,TResult Function( SourcesScanAllStatusAdmitted value)?  admitted,TResult Function( SourcesScanAllStatusNothingEligible value)?  nothingEligible,TResult Function( SourcesScanAllStatusUncertain value)?  uncertain,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SourcesScanAllStatusIdle() when idle != null:
return idle(_that);case SourcesScanAllStatusSubmitting() when submitting != null:
return submitting(_that);case SourcesScanAllStatusAdmitted() when admitted != null:
return admitted(_that);case SourcesScanAllStatusNothingEligible() when nothingEligible != null:
return nothingEligible(_that);case SourcesScanAllStatusUncertain() when uncertain != null:
return uncertain(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SourcesScanAllStatusIdle value)  idle,required TResult Function( SourcesScanAllStatusSubmitting value)  submitting,required TResult Function( SourcesScanAllStatusAdmitted value)  admitted,required TResult Function( SourcesScanAllStatusNothingEligible value)  nothingEligible,required TResult Function( SourcesScanAllStatusUncertain value)  uncertain,}){
final _that = this;
switch (_that) {
case SourcesScanAllStatusIdle():
return idle(_that);case SourcesScanAllStatusSubmitting():
return submitting(_that);case SourcesScanAllStatusAdmitted():
return admitted(_that);case SourcesScanAllStatusNothingEligible():
return nothingEligible(_that);case SourcesScanAllStatusUncertain():
return uncertain(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SourcesScanAllStatusIdle value)?  idle,TResult? Function( SourcesScanAllStatusSubmitting value)?  submitting,TResult? Function( SourcesScanAllStatusAdmitted value)?  admitted,TResult? Function( SourcesScanAllStatusNothingEligible value)?  nothingEligible,TResult? Function( SourcesScanAllStatusUncertain value)?  uncertain,}){
final _that = this;
switch (_that) {
case SourcesScanAllStatusIdle() when idle != null:
return idle(_that);case SourcesScanAllStatusSubmitting() when submitting != null:
return submitting(_that);case SourcesScanAllStatusAdmitted() when admitted != null:
return admitted(_that);case SourcesScanAllStatusNothingEligible() when nothingEligible != null:
return nothingEligible(_that);case SourcesScanAllStatusUncertain() when uncertain != null:
return uncertain(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  submitting,TResult Function( int admittedCount,  bool hasExclusions,  JobRunId jobRunId)?  admitted,TResult Function( List<LibraryScanAdmissionExclusion> exclusions)?  nothingEligible,TResult Function()?  uncertain,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SourcesScanAllStatusIdle() when idle != null:
return idle();case SourcesScanAllStatusSubmitting() when submitting != null:
return submitting();case SourcesScanAllStatusAdmitted() when admitted != null:
return admitted(_that.admittedCount,_that.hasExclusions,_that.jobRunId);case SourcesScanAllStatusNothingEligible() when nothingEligible != null:
return nothingEligible(_that.exclusions);case SourcesScanAllStatusUncertain() when uncertain != null:
return uncertain();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  submitting,required TResult Function( int admittedCount,  bool hasExclusions,  JobRunId jobRunId)  admitted,required TResult Function( List<LibraryScanAdmissionExclusion> exclusions)  nothingEligible,required TResult Function()  uncertain,}) {final _that = this;
switch (_that) {
case SourcesScanAllStatusIdle():
return idle();case SourcesScanAllStatusSubmitting():
return submitting();case SourcesScanAllStatusAdmitted():
return admitted(_that.admittedCount,_that.hasExclusions,_that.jobRunId);case SourcesScanAllStatusNothingEligible():
return nothingEligible(_that.exclusions);case SourcesScanAllStatusUncertain():
return uncertain();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  submitting,TResult? Function( int admittedCount,  bool hasExclusions,  JobRunId jobRunId)?  admitted,TResult? Function( List<LibraryScanAdmissionExclusion> exclusions)?  nothingEligible,TResult? Function()?  uncertain,}) {final _that = this;
switch (_that) {
case SourcesScanAllStatusIdle() when idle != null:
return idle();case SourcesScanAllStatusSubmitting() when submitting != null:
return submitting();case SourcesScanAllStatusAdmitted() when admitted != null:
return admitted(_that.admittedCount,_that.hasExclusions,_that.jobRunId);case SourcesScanAllStatusNothingEligible() when nothingEligible != null:
return nothingEligible(_that.exclusions);case SourcesScanAllStatusUncertain() when uncertain != null:
return uncertain();case _:
  return null;

}
}

}

/// @nodoc


class SourcesScanAllStatusIdle implements SourcesScanAllStatus {
  const SourcesScanAllStatusIdle();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesScanAllStatusIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourcesScanAllStatus.idle()';
}


}




/// @nodoc


class SourcesScanAllStatusSubmitting implements SourcesScanAllStatus {
  const SourcesScanAllStatusSubmitting();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesScanAllStatusSubmitting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourcesScanAllStatus.submitting()';
}


}




/// @nodoc


class SourcesScanAllStatusAdmitted implements SourcesScanAllStatus {
  const SourcesScanAllStatusAdmitted({required this.admittedCount, required this.hasExclusions, required this.jobRunId});


 final  int admittedCount;
 final  bool hasExclusions;
 final  JobRunId jobRunId;

/// Create a copy of SourcesScanAllStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourcesScanAllStatusAdmittedCopyWith<SourcesScanAllStatusAdmitted> get copyWith => _$SourcesScanAllStatusAdmittedCopyWithImpl<SourcesScanAllStatusAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesScanAllStatusAdmitted&&(identical(other.admittedCount, admittedCount) || other.admittedCount == admittedCount)&&(identical(other.hasExclusions, hasExclusions) || other.hasExclusions == hasExclusions)&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,admittedCount,hasExclusions,jobRunId);

@override
String toString() {
  return 'SourcesScanAllStatus.admitted(admittedCount: $admittedCount, hasExclusions: $hasExclusions, jobRunId: $jobRunId)';
}


}

/// @nodoc
abstract mixin class $SourcesScanAllStatusAdmittedCopyWith<$Res> implements $SourcesScanAllStatusCopyWith<$Res> {
  factory $SourcesScanAllStatusAdmittedCopyWith(SourcesScanAllStatusAdmitted value, $Res Function(SourcesScanAllStatusAdmitted) _then) = _$SourcesScanAllStatusAdmittedCopyWithImpl;
@useResult
$Res call({
 int admittedCount, bool hasExclusions, JobRunId jobRunId
});




}
/// @nodoc
class _$SourcesScanAllStatusAdmittedCopyWithImpl<$Res>
    implements $SourcesScanAllStatusAdmittedCopyWith<$Res> {
  _$SourcesScanAllStatusAdmittedCopyWithImpl(this._self, this._then);

  final SourcesScanAllStatusAdmitted _self;
  final $Res Function(SourcesScanAllStatusAdmitted) _then;

/// Create a copy of SourcesScanAllStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? admittedCount = null,Object? hasExclusions = null,Object? jobRunId = null,}) {
  return _then(SourcesScanAllStatusAdmitted(
admittedCount: null == admittedCount ? _self.admittedCount : admittedCount // ignore: cast_nullable_to_non_nullable
as int,hasExclusions: null == hasExclusions ? _self.hasExclusions : hasExclusions // ignore: cast_nullable_to_non_nullable
as bool,jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,
  ));
}


}

/// @nodoc


class SourcesScanAllStatusNothingEligible implements SourcesScanAllStatus {
  const SourcesScanAllStatusNothingEligible({required final  List<LibraryScanAdmissionExclusion> exclusions}): _exclusions = exclusions;


 final  List<LibraryScanAdmissionExclusion> _exclusions;
 List<LibraryScanAdmissionExclusion> get exclusions {
  if (_exclusions is EqualUnmodifiableListView) return _exclusions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_exclusions);
}


/// Create a copy of SourcesScanAllStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourcesScanAllStatusNothingEligibleCopyWith<SourcesScanAllStatusNothingEligible> get copyWith => _$SourcesScanAllStatusNothingEligibleCopyWithImpl<SourcesScanAllStatusNothingEligible>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesScanAllStatusNothingEligible&&const DeepCollectionEquality().equals(other._exclusions, _exclusions));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_exclusions));

@override
String toString() {
  return 'SourcesScanAllStatus.nothingEligible(exclusions: $exclusions)';
}


}

/// @nodoc
abstract mixin class $SourcesScanAllStatusNothingEligibleCopyWith<$Res> implements $SourcesScanAllStatusCopyWith<$Res> {
  factory $SourcesScanAllStatusNothingEligibleCopyWith(SourcesScanAllStatusNothingEligible value, $Res Function(SourcesScanAllStatusNothingEligible) _then) = _$SourcesScanAllStatusNothingEligibleCopyWithImpl;
@useResult
$Res call({
 List<LibraryScanAdmissionExclusion> exclusions
});




}
/// @nodoc
class _$SourcesScanAllStatusNothingEligibleCopyWithImpl<$Res>
    implements $SourcesScanAllStatusNothingEligibleCopyWith<$Res> {
  _$SourcesScanAllStatusNothingEligibleCopyWithImpl(this._self, this._then);

  final SourcesScanAllStatusNothingEligible _self;
  final $Res Function(SourcesScanAllStatusNothingEligible) _then;

/// Create a copy of SourcesScanAllStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? exclusions = null,}) {
  return _then(SourcesScanAllStatusNothingEligible(
exclusions: null == exclusions ? _self._exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as List<LibraryScanAdmissionExclusion>,
  ));
}


}

/// @nodoc


class SourcesScanAllStatusUncertain implements SourcesScanAllStatus {
  const SourcesScanAllStatusUncertain();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesScanAllStatusUncertain);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourcesScanAllStatus.uncertain()';
}


}




// dart format on
