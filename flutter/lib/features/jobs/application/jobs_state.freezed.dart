// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'jobs_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$JobsRuntimeContext {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobsRuntimeContext);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JobsRuntimeContext()';
}


}

/// @nodoc
class $JobsRuntimeContextCopyWith<$Res>  {
$JobsRuntimeContextCopyWith(JobsRuntimeContext _, $Res Function(JobsRuntimeContext) __);
}


/// Adds pattern-matching-related methods to [JobsRuntimeContext].
extension JobsRuntimeContextPatterns on JobsRuntimeContext {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( JobsRuntimeContextPreReady value)?  preReady,TResult Function( JobsRuntimeContextReady value)?  ready,required TResult orElse(),}){
final _that = this;
switch (_that) {
case JobsRuntimeContextPreReady() when preReady != null:
return preReady(_that);case JobsRuntimeContextReady() when ready != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( JobsRuntimeContextPreReady value)  preReady,required TResult Function( JobsRuntimeContextReady value)  ready,}){
final _that = this;
switch (_that) {
case JobsRuntimeContextPreReady():
return preReady(_that);case JobsRuntimeContextReady():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( JobsRuntimeContextPreReady value)?  preReady,TResult? Function( JobsRuntimeContextReady value)?  ready,}){
final _that = this;
switch (_that) {
case JobsRuntimeContextPreReady() when preReady != null:
return preReady(_that);case JobsRuntimeContextReady() when ready != null:
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
case JobsRuntimeContextPreReady() when preReady != null:
return preReady();case JobsRuntimeContextReady() when ready != null:
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
case JobsRuntimeContextPreReady():
return preReady();case JobsRuntimeContextReady():
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
case JobsRuntimeContextPreReady() when preReady != null:
return preReady();case JobsRuntimeContextReady() when ready != null:
return ready(_that.runtimeInstanceId);case _:
  return null;

}
}

}

/// @nodoc


class JobsRuntimeContextPreReady implements JobsRuntimeContext {
  const JobsRuntimeContextPreReady();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobsRuntimeContextPreReady);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JobsRuntimeContext.preReady()';
}


}




/// @nodoc


class JobsRuntimeContextReady implements JobsRuntimeContext {
  const JobsRuntimeContextReady({required this.runtimeInstanceId});


 final  RuntimeInstanceId runtimeInstanceId;

/// Create a copy of JobsRuntimeContext
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobsRuntimeContextReadyCopyWith<JobsRuntimeContextReady> get copyWith => _$JobsRuntimeContextReadyCopyWithImpl<JobsRuntimeContextReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobsRuntimeContextReady&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId);

@override
String toString() {
  return 'JobsRuntimeContext.ready(runtimeInstanceId: $runtimeInstanceId)';
}


}

/// @nodoc
abstract mixin class $JobsRuntimeContextReadyCopyWith<$Res> implements $JobsRuntimeContextCopyWith<$Res> {
  factory $JobsRuntimeContextReadyCopyWith(JobsRuntimeContextReady value, $Res Function(JobsRuntimeContextReady) _then) = _$JobsRuntimeContextReadyCopyWithImpl;
@useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId
});




}
/// @nodoc
class _$JobsRuntimeContextReadyCopyWithImpl<$Res>
    implements $JobsRuntimeContextReadyCopyWith<$Res> {
  _$JobsRuntimeContextReadyCopyWithImpl(this._self, this._then);

  final JobsRuntimeContextReady _self;
  final $Res Function(JobsRuntimeContextReady) _then;

/// Create a copy of JobsRuntimeContext
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,}) {
  return _then(JobsRuntimeContextReady(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,
  ));
}


}

/// @nodoc
mixin _$JobsReconciliationDemand {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobsReconciliationDemand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JobsReconciliationDemand()';
}


}

/// @nodoc
class $JobsReconciliationDemandCopyWith<$Res>  {
$JobsReconciliationDemandCopyWith(JobsReconciliationDemand _, $Res Function(JobsReconciliationDemand) __);
}


/// Adds pattern-matching-related methods to [JobsReconciliationDemand].
extension JobsReconciliationDemandPatterns on JobsReconciliationDemand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( JobsReconciliationDemandListChanged value)?  listChanged,TResult Function( JobsReconciliationDemandDetailChanged value)?  detailChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case JobsReconciliationDemandListChanged() when listChanged != null:
return listChanged(_that);case JobsReconciliationDemandDetailChanged() when detailChanged != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( JobsReconciliationDemandListChanged value)  listChanged,required TResult Function( JobsReconciliationDemandDetailChanged value)  detailChanged,}){
final _that = this;
switch (_that) {
case JobsReconciliationDemandListChanged():
return listChanged(_that);case JobsReconciliationDemandDetailChanged():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( JobsReconciliationDemandListChanged value)?  listChanged,TResult? Function( JobsReconciliationDemandDetailChanged value)?  detailChanged,}){
final _that = this;
switch (_that) {
case JobsReconciliationDemandListChanged() when listChanged != null:
return listChanged(_that);case JobsReconciliationDemandDetailChanged() when detailChanged != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  listChanged,TResult Function( JobRunId jobRunId)?  detailChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case JobsReconciliationDemandListChanged() when listChanged != null:
return listChanged();case JobsReconciliationDemandDetailChanged() when detailChanged != null:
return detailChanged(_that.jobRunId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  listChanged,required TResult Function( JobRunId jobRunId)  detailChanged,}) {final _that = this;
switch (_that) {
case JobsReconciliationDemandListChanged():
return listChanged();case JobsReconciliationDemandDetailChanged():
return detailChanged(_that.jobRunId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  listChanged,TResult? Function( JobRunId jobRunId)?  detailChanged,}) {final _that = this;
switch (_that) {
case JobsReconciliationDemandListChanged() when listChanged != null:
return listChanged();case JobsReconciliationDemandDetailChanged() when detailChanged != null:
return detailChanged(_that.jobRunId);case _:
  return null;

}
}

}

/// @nodoc


class JobsReconciliationDemandListChanged implements JobsReconciliationDemand {
  const JobsReconciliationDemandListChanged();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobsReconciliationDemandListChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JobsReconciliationDemand.listChanged()';
}


}




/// @nodoc


class JobsReconciliationDemandDetailChanged implements JobsReconciliationDemand {
  const JobsReconciliationDemandDetailChanged({required this.jobRunId});


 final  JobRunId jobRunId;

/// Create a copy of JobsReconciliationDemand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobsReconciliationDemandDetailChangedCopyWith<JobsReconciliationDemandDetailChanged> get copyWith => _$JobsReconciliationDemandDetailChangedCopyWithImpl<JobsReconciliationDemandDetailChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobsReconciliationDemandDetailChanged&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,jobRunId);

@override
String toString() {
  return 'JobsReconciliationDemand.detailChanged(jobRunId: $jobRunId)';
}


}

/// @nodoc
abstract mixin class $JobsReconciliationDemandDetailChangedCopyWith<$Res> implements $JobsReconciliationDemandCopyWith<$Res> {
  factory $JobsReconciliationDemandDetailChangedCopyWith(JobsReconciliationDemandDetailChanged value, $Res Function(JobsReconciliationDemandDetailChanged) _then) = _$JobsReconciliationDemandDetailChangedCopyWithImpl;
@useResult
$Res call({
 JobRunId jobRunId
});




}
/// @nodoc
class _$JobsReconciliationDemandDetailChangedCopyWithImpl<$Res>
    implements $JobsReconciliationDemandDetailChangedCopyWith<$Res> {
  _$JobsReconciliationDemandDetailChangedCopyWithImpl(this._self, this._then);

  final JobsReconciliationDemandDetailChanged _self;
  final $Res Function(JobsReconciliationDemandDetailChanged) _then;

/// Create a copy of JobsReconciliationDemand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? jobRunId = null,}) {
  return _then(JobsReconciliationDemandDetailChanged(
jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,
  ));
}


}

// dart format on
