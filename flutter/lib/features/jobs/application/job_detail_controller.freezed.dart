// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'job_detail_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$JobDetailState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobDetailState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JobDetailState()';
}


}

/// @nodoc
class $JobDetailStateCopyWith<$Res>  {
$JobDetailStateCopyWith(JobDetailState _, $Res Function(JobDetailState) __);
}


/// Adds pattern-matching-related methods to [JobDetailState].
extension JobDetailStatePatterns on JobDetailState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( JobDetailStateReady value)?  ready,TResult Function( JobDetailStateMissing value)?  missing,required TResult orElse(),}){
final _that = this;
switch (_that) {
case JobDetailStateReady() when ready != null:
return ready(_that);case JobDetailStateMissing() when missing != null:
return missing(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( JobDetailStateReady value)  ready,required TResult Function( JobDetailStateMissing value)  missing,}){
final _that = this;
switch (_that) {
case JobDetailStateReady():
return ready(_that);case JobDetailStateMissing():
return missing(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( JobDetailStateReady value)?  ready,TResult? Function( JobDetailStateMissing value)?  missing,}){
final _that = this;
switch (_that) {
case JobDetailStateReady() when ready != null:
return ready(_that);case JobDetailStateMissing() when missing != null:
return missing(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( JobDetail detail,  bool refreshing,  bool cancelling,  bool cancelAmbiguous,  bool retrying,  bool retryAmbiguous,  RetryNotAdmittedReason? retryNotAdmittedReason,  ClientFailure? lastFailure)?  ready,TResult Function()?  missing,required TResult orElse(),}) {final _that = this;
switch (_that) {
case JobDetailStateReady() when ready != null:
return ready(_that.detail,_that.refreshing,_that.cancelling,_that.cancelAmbiguous,_that.retrying,_that.retryAmbiguous,_that.retryNotAdmittedReason,_that.lastFailure);case JobDetailStateMissing() when missing != null:
return missing();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( JobDetail detail,  bool refreshing,  bool cancelling,  bool cancelAmbiguous,  bool retrying,  bool retryAmbiguous,  RetryNotAdmittedReason? retryNotAdmittedReason,  ClientFailure? lastFailure)  ready,required TResult Function()  missing,}) {final _that = this;
switch (_that) {
case JobDetailStateReady():
return ready(_that.detail,_that.refreshing,_that.cancelling,_that.cancelAmbiguous,_that.retrying,_that.retryAmbiguous,_that.retryNotAdmittedReason,_that.lastFailure);case JobDetailStateMissing():
return missing();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( JobDetail detail,  bool refreshing,  bool cancelling,  bool cancelAmbiguous,  bool retrying,  bool retryAmbiguous,  RetryNotAdmittedReason? retryNotAdmittedReason,  ClientFailure? lastFailure)?  ready,TResult? Function()?  missing,}) {final _that = this;
switch (_that) {
case JobDetailStateReady() when ready != null:
return ready(_that.detail,_that.refreshing,_that.cancelling,_that.cancelAmbiguous,_that.retrying,_that.retryAmbiguous,_that.retryNotAdmittedReason,_that.lastFailure);case JobDetailStateMissing() when missing != null:
return missing();case _:
  return null;

}
}

}

/// @nodoc


class JobDetailStateReady implements JobDetailState {
  const JobDetailStateReady({required this.detail, required this.refreshing, required this.cancelling, required this.cancelAmbiguous, required this.retrying, required this.retryAmbiguous, this.retryNotAdmittedReason, this.lastFailure});


 final  JobDetail detail;
 final  bool refreshing;
 final  bool cancelling;
 final  bool cancelAmbiguous;
 final  bool retrying;
 final  bool retryAmbiguous;
 final  RetryNotAdmittedReason? retryNotAdmittedReason;
 final  ClientFailure? lastFailure;

/// Create a copy of JobDetailState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobDetailStateReadyCopyWith<JobDetailStateReady> get copyWith => _$JobDetailStateReadyCopyWithImpl<JobDetailStateReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobDetailStateReady&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.refreshing, refreshing) || other.refreshing == refreshing)&&(identical(other.cancelling, cancelling) || other.cancelling == cancelling)&&(identical(other.cancelAmbiguous, cancelAmbiguous) || other.cancelAmbiguous == cancelAmbiguous)&&(identical(other.retrying, retrying) || other.retrying == retrying)&&(identical(other.retryAmbiguous, retryAmbiguous) || other.retryAmbiguous == retryAmbiguous)&&(identical(other.retryNotAdmittedReason, retryNotAdmittedReason) || other.retryNotAdmittedReason == retryNotAdmittedReason)&&(identical(other.lastFailure, lastFailure) || other.lastFailure == lastFailure));
}


@override
int get hashCode => Object.hash(runtimeType,detail,refreshing,cancelling,cancelAmbiguous,retrying,retryAmbiguous,retryNotAdmittedReason,lastFailure);

@override
String toString() {
  return 'JobDetailState.ready(detail: $detail, refreshing: $refreshing, cancelling: $cancelling, cancelAmbiguous: $cancelAmbiguous, retrying: $retrying, retryAmbiguous: $retryAmbiguous, retryNotAdmittedReason: $retryNotAdmittedReason, lastFailure: $lastFailure)';
}


}

/// @nodoc
abstract mixin class $JobDetailStateReadyCopyWith<$Res> implements $JobDetailStateCopyWith<$Res> {
  factory $JobDetailStateReadyCopyWith(JobDetailStateReady value, $Res Function(JobDetailStateReady) _then) = _$JobDetailStateReadyCopyWithImpl;
@useResult
$Res call({
 JobDetail detail, bool refreshing, bool cancelling, bool cancelAmbiguous, bool retrying, bool retryAmbiguous, RetryNotAdmittedReason? retryNotAdmittedReason, ClientFailure? lastFailure
});


$JobDetailCopyWith<$Res> get detail;$RetryNotAdmittedReasonCopyWith<$Res>? get retryNotAdmittedReason;

}
/// @nodoc
class _$JobDetailStateReadyCopyWithImpl<$Res>
    implements $JobDetailStateReadyCopyWith<$Res> {
  _$JobDetailStateReadyCopyWithImpl(this._self, this._then);

  final JobDetailStateReady _self;
  final $Res Function(JobDetailStateReady) _then;

/// Create a copy of JobDetailState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,Object? refreshing = null,Object? cancelling = null,Object? cancelAmbiguous = null,Object? retrying = null,Object? retryAmbiguous = null,Object? retryNotAdmittedReason = freezed,Object? lastFailure = freezed,}) {
  return _then(JobDetailStateReady(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as JobDetail,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as bool,cancelling: null == cancelling ? _self.cancelling : cancelling // ignore: cast_nullable_to_non_nullable
as bool,cancelAmbiguous: null == cancelAmbiguous ? _self.cancelAmbiguous : cancelAmbiguous // ignore: cast_nullable_to_non_nullable
as bool,retrying: null == retrying ? _self.retrying : retrying // ignore: cast_nullable_to_non_nullable
as bool,retryAmbiguous: null == retryAmbiguous ? _self.retryAmbiguous : retryAmbiguous // ignore: cast_nullable_to_non_nullable
as bool,retryNotAdmittedReason: freezed == retryNotAdmittedReason ? _self.retryNotAdmittedReason : retryNotAdmittedReason // ignore: cast_nullable_to_non_nullable
as RetryNotAdmittedReason?,lastFailure: freezed == lastFailure ? _self.lastFailure : lastFailure // ignore: cast_nullable_to_non_nullable
as ClientFailure?,
  ));
}

/// Create a copy of JobDetailState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JobDetailCopyWith<$Res> get detail {

  return $JobDetailCopyWith<$Res>(_self.detail, (value) {
    return _then(_self.copyWith(detail: value));
  });
}/// Create a copy of JobDetailState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RetryNotAdmittedReasonCopyWith<$Res>? get retryNotAdmittedReason {
    if (_self.retryNotAdmittedReason == null) {
    return null;
  }

  return $RetryNotAdmittedReasonCopyWith<$Res>(_self.retryNotAdmittedReason!, (value) {
    return _then(_self.copyWith(retryNotAdmittedReason: value));
  });
}
}

/// @nodoc


class JobDetailStateMissing implements JobDetailState {
  const JobDetailStateMissing();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobDetailStateMissing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JobDetailState.missing()';
}


}




// dart format on
