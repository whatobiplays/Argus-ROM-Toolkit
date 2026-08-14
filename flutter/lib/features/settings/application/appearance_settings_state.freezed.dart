// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'appearance_settings_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AppearanceRuntimeContext {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceRuntimeContext);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppearanceRuntimeContext()';
}


}

/// @nodoc
class $AppearanceRuntimeContextCopyWith<$Res>  {
$AppearanceRuntimeContextCopyWith(AppearanceRuntimeContext _, $Res Function(AppearanceRuntimeContext) __);
}


/// Adds pattern-matching-related methods to [AppearanceRuntimeContext].
extension AppearanceRuntimeContextPatterns on AppearanceRuntimeContext {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AppearanceRuntimeContextPreReady value)?  preReady,TResult Function( AppearanceRuntimeContextReady value)?  ready,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AppearanceRuntimeContextPreReady() when preReady != null:
return preReady(_that);case AppearanceRuntimeContextReady() when ready != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AppearanceRuntimeContextPreReady value)  preReady,required TResult Function( AppearanceRuntimeContextReady value)  ready,}){
final _that = this;
switch (_that) {
case AppearanceRuntimeContextPreReady():
return preReady(_that);case AppearanceRuntimeContextReady():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AppearanceRuntimeContextPreReady value)?  preReady,TResult? Function( AppearanceRuntimeContextReady value)?  ready,}){
final _that = this;
switch (_that) {
case AppearanceRuntimeContextPreReady() when preReady != null:
return preReady(_that);case AppearanceRuntimeContextReady() when ready != null:
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
case AppearanceRuntimeContextPreReady() when preReady != null:
return preReady();case AppearanceRuntimeContextReady() when ready != null:
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
case AppearanceRuntimeContextPreReady():
return preReady();case AppearanceRuntimeContextReady():
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
case AppearanceRuntimeContextPreReady() when preReady != null:
return preReady();case AppearanceRuntimeContextReady() when ready != null:
return ready(_that.runtimeInstanceId);case _:
  return null;

}
}

}

/// @nodoc


class AppearanceRuntimeContextPreReady implements AppearanceRuntimeContext {
  const AppearanceRuntimeContextPreReady();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceRuntimeContextPreReady);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppearanceRuntimeContext.preReady()';
}


}




/// @nodoc


class AppearanceRuntimeContextReady implements AppearanceRuntimeContext {
  const AppearanceRuntimeContextReady({required this.runtimeInstanceId});


 final  RuntimeInstanceId runtimeInstanceId;

/// Create a copy of AppearanceRuntimeContext
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppearanceRuntimeContextReadyCopyWith<AppearanceRuntimeContextReady> get copyWith => _$AppearanceRuntimeContextReadyCopyWithImpl<AppearanceRuntimeContextReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceRuntimeContextReady&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId);

@override
String toString() {
  return 'AppearanceRuntimeContext.ready(runtimeInstanceId: $runtimeInstanceId)';
}


}

/// @nodoc
abstract mixin class $AppearanceRuntimeContextReadyCopyWith<$Res> implements $AppearanceRuntimeContextCopyWith<$Res> {
  factory $AppearanceRuntimeContextReadyCopyWith(AppearanceRuntimeContextReady value, $Res Function(AppearanceRuntimeContextReady) _then) = _$AppearanceRuntimeContextReadyCopyWithImpl;
@useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId
});




}
/// @nodoc
class _$AppearanceRuntimeContextReadyCopyWithImpl<$Res>
    implements $AppearanceRuntimeContextReadyCopyWith<$Res> {
  _$AppearanceRuntimeContextReadyCopyWithImpl(this._self, this._then);

  final AppearanceRuntimeContextReady _self;
  final $Res Function(AppearanceRuntimeContextReady) _then;

/// Create a copy of AppearanceRuntimeContext
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,}) {
  return _then(AppearanceRuntimeContextReady(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,
  ));
}


}

/// @nodoc
mixin _$AppearanceSaveOperation {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceSaveOperation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppearanceSaveOperation()';
}


}

/// @nodoc
class $AppearanceSaveOperationCopyWith<$Res>  {
$AppearanceSaveOperationCopyWith(AppearanceSaveOperation _, $Res Function(AppearanceSaveOperation) __);
}


/// Adds pattern-matching-related methods to [AppearanceSaveOperation].
extension AppearanceSaveOperationPatterns on AppearanceSaveOperation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AppearanceSaveOperationIdle value)?  idle,TResult Function( AppearanceSaveOperationSaving value)?  saving,TResult Function( AppearanceSaveOperationFailed value)?  failed,TResult Function( AppearanceSaveOperationOutcomeUnknown value)?  outcomeUnknown,TResult Function( AppearanceSaveOperationCommittedButUnreconciled value)?  committedButUnreconciled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AppearanceSaveOperationIdle() when idle != null:
return idle(_that);case AppearanceSaveOperationSaving() when saving != null:
return saving(_that);case AppearanceSaveOperationFailed() when failed != null:
return failed(_that);case AppearanceSaveOperationOutcomeUnknown() when outcomeUnknown != null:
return outcomeUnknown(_that);case AppearanceSaveOperationCommittedButUnreconciled() when committedButUnreconciled != null:
return committedButUnreconciled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AppearanceSaveOperationIdle value)  idle,required TResult Function( AppearanceSaveOperationSaving value)  saving,required TResult Function( AppearanceSaveOperationFailed value)  failed,required TResult Function( AppearanceSaveOperationOutcomeUnknown value)  outcomeUnknown,required TResult Function( AppearanceSaveOperationCommittedButUnreconciled value)  committedButUnreconciled,}){
final _that = this;
switch (_that) {
case AppearanceSaveOperationIdle():
return idle(_that);case AppearanceSaveOperationSaving():
return saving(_that);case AppearanceSaveOperationFailed():
return failed(_that);case AppearanceSaveOperationOutcomeUnknown():
return outcomeUnknown(_that);case AppearanceSaveOperationCommittedButUnreconciled():
return committedButUnreconciled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AppearanceSaveOperationIdle value)?  idle,TResult? Function( AppearanceSaveOperationSaving value)?  saving,TResult? Function( AppearanceSaveOperationFailed value)?  failed,TResult? Function( AppearanceSaveOperationOutcomeUnknown value)?  outcomeUnknown,TResult? Function( AppearanceSaveOperationCommittedButUnreconciled value)?  committedButUnreconciled,}){
final _that = this;
switch (_that) {
case AppearanceSaveOperationIdle() when idle != null:
return idle(_that);case AppearanceSaveOperationSaving() when saving != null:
return saving(_that);case AppearanceSaveOperationFailed() when failed != null:
return failed(_that);case AppearanceSaveOperationOutcomeUnknown() when outcomeUnknown != null:
return outcomeUnknown(_that);case AppearanceSaveOperationCommittedButUnreconciled() when committedButUnreconciled != null:
return committedButUnreconciled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( AppearanceSettings requested)?  saving,TResult Function( ApplicationFailure failure)?  failed,TResult Function( TransportFailure failure)?  outcomeUnknown,TResult Function( ClientFailure failure)?  committedButUnreconciled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AppearanceSaveOperationIdle() when idle != null:
return idle();case AppearanceSaveOperationSaving() when saving != null:
return saving(_that.requested);case AppearanceSaveOperationFailed() when failed != null:
return failed(_that.failure);case AppearanceSaveOperationOutcomeUnknown() when outcomeUnknown != null:
return outcomeUnknown(_that.failure);case AppearanceSaveOperationCommittedButUnreconciled() when committedButUnreconciled != null:
return committedButUnreconciled(_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( AppearanceSettings requested)  saving,required TResult Function( ApplicationFailure failure)  failed,required TResult Function( TransportFailure failure)  outcomeUnknown,required TResult Function( ClientFailure failure)  committedButUnreconciled,}) {final _that = this;
switch (_that) {
case AppearanceSaveOperationIdle():
return idle();case AppearanceSaveOperationSaving():
return saving(_that.requested);case AppearanceSaveOperationFailed():
return failed(_that.failure);case AppearanceSaveOperationOutcomeUnknown():
return outcomeUnknown(_that.failure);case AppearanceSaveOperationCommittedButUnreconciled():
return committedButUnreconciled(_that.failure);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( AppearanceSettings requested)?  saving,TResult? Function( ApplicationFailure failure)?  failed,TResult? Function( TransportFailure failure)?  outcomeUnknown,TResult? Function( ClientFailure failure)?  committedButUnreconciled,}) {final _that = this;
switch (_that) {
case AppearanceSaveOperationIdle() when idle != null:
return idle();case AppearanceSaveOperationSaving() when saving != null:
return saving(_that.requested);case AppearanceSaveOperationFailed() when failed != null:
return failed(_that.failure);case AppearanceSaveOperationOutcomeUnknown() when outcomeUnknown != null:
return outcomeUnknown(_that.failure);case AppearanceSaveOperationCommittedButUnreconciled() when committedButUnreconciled != null:
return committedButUnreconciled(_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class AppearanceSaveOperationIdle implements AppearanceSaveOperation {
  const AppearanceSaveOperationIdle();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceSaveOperationIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppearanceSaveOperation.idle()';
}


}




/// @nodoc


class AppearanceSaveOperationSaving implements AppearanceSaveOperation {
  const AppearanceSaveOperationSaving({required this.requested});


 final  AppearanceSettings requested;

/// Create a copy of AppearanceSaveOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppearanceSaveOperationSavingCopyWith<AppearanceSaveOperationSaving> get copyWith => _$AppearanceSaveOperationSavingCopyWithImpl<AppearanceSaveOperationSaving>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceSaveOperationSaving&&(identical(other.requested, requested) || other.requested == requested));
}


@override
int get hashCode => Object.hash(runtimeType,requested);

@override
String toString() {
  return 'AppearanceSaveOperation.saving(requested: $requested)';
}


}

/// @nodoc
abstract mixin class $AppearanceSaveOperationSavingCopyWith<$Res> implements $AppearanceSaveOperationCopyWith<$Res> {
  factory $AppearanceSaveOperationSavingCopyWith(AppearanceSaveOperationSaving value, $Res Function(AppearanceSaveOperationSaving) _then) = _$AppearanceSaveOperationSavingCopyWithImpl;
@useResult
$Res call({
 AppearanceSettings requested
});


$AppearanceSettingsCopyWith<$Res> get requested;

}
/// @nodoc
class _$AppearanceSaveOperationSavingCopyWithImpl<$Res>
    implements $AppearanceSaveOperationSavingCopyWith<$Res> {
  _$AppearanceSaveOperationSavingCopyWithImpl(this._self, this._then);

  final AppearanceSaveOperationSaving _self;
  final $Res Function(AppearanceSaveOperationSaving) _then;

/// Create a copy of AppearanceSaveOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? requested = null,}) {
  return _then(AppearanceSaveOperationSaving(
requested: null == requested ? _self.requested : requested // ignore: cast_nullable_to_non_nullable
as AppearanceSettings,
  ));
}

/// Create a copy of AppearanceSaveOperation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AppearanceSettingsCopyWith<$Res> get requested {

  return $AppearanceSettingsCopyWith<$Res>(_self.requested, (value) {
    return _then(_self.copyWith(requested: value));
  });
}
}

/// @nodoc


class AppearanceSaveOperationFailed implements AppearanceSaveOperation {
  const AppearanceSaveOperationFailed({required this.failure});


 final  ApplicationFailure failure;

/// Create a copy of AppearanceSaveOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppearanceSaveOperationFailedCopyWith<AppearanceSaveOperationFailed> get copyWith => _$AppearanceSaveOperationFailedCopyWithImpl<AppearanceSaveOperationFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceSaveOperationFailed&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode => Object.hash(runtimeType,failure);

@override
String toString() {
  return 'AppearanceSaveOperation.failed(failure: $failure)';
}


}

/// @nodoc
abstract mixin class $AppearanceSaveOperationFailedCopyWith<$Res> implements $AppearanceSaveOperationCopyWith<$Res> {
  factory $AppearanceSaveOperationFailedCopyWith(AppearanceSaveOperationFailed value, $Res Function(AppearanceSaveOperationFailed) _then) = _$AppearanceSaveOperationFailedCopyWithImpl;
@useResult
$Res call({
 ApplicationFailure failure
});




}
/// @nodoc
class _$AppearanceSaveOperationFailedCopyWithImpl<$Res>
    implements $AppearanceSaveOperationFailedCopyWith<$Res> {
  _$AppearanceSaveOperationFailedCopyWithImpl(this._self, this._then);

  final AppearanceSaveOperationFailed _self;
  final $Res Function(AppearanceSaveOperationFailed) _then;

/// Create a copy of AppearanceSaveOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(AppearanceSaveOperationFailed(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as ApplicationFailure,
  ));
}


}

/// @nodoc


class AppearanceSaveOperationOutcomeUnknown implements AppearanceSaveOperation {
  const AppearanceSaveOperationOutcomeUnknown({required this.failure});


 final  TransportFailure failure;

/// Create a copy of AppearanceSaveOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppearanceSaveOperationOutcomeUnknownCopyWith<AppearanceSaveOperationOutcomeUnknown> get copyWith => _$AppearanceSaveOperationOutcomeUnknownCopyWithImpl<AppearanceSaveOperationOutcomeUnknown>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceSaveOperationOutcomeUnknown&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode => Object.hash(runtimeType,failure);

@override
String toString() {
  return 'AppearanceSaveOperation.outcomeUnknown(failure: $failure)';
}


}

/// @nodoc
abstract mixin class $AppearanceSaveOperationOutcomeUnknownCopyWith<$Res> implements $AppearanceSaveOperationCopyWith<$Res> {
  factory $AppearanceSaveOperationOutcomeUnknownCopyWith(AppearanceSaveOperationOutcomeUnknown value, $Res Function(AppearanceSaveOperationOutcomeUnknown) _then) = _$AppearanceSaveOperationOutcomeUnknownCopyWithImpl;
@useResult
$Res call({
 TransportFailure failure
});




}
/// @nodoc
class _$AppearanceSaveOperationOutcomeUnknownCopyWithImpl<$Res>
    implements $AppearanceSaveOperationOutcomeUnknownCopyWith<$Res> {
  _$AppearanceSaveOperationOutcomeUnknownCopyWithImpl(this._self, this._then);

  final AppearanceSaveOperationOutcomeUnknown _self;
  final $Res Function(AppearanceSaveOperationOutcomeUnknown) _then;

/// Create a copy of AppearanceSaveOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(AppearanceSaveOperationOutcomeUnknown(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as TransportFailure,
  ));
}


}

/// @nodoc


class AppearanceSaveOperationCommittedButUnreconciled implements AppearanceSaveOperation {
  const AppearanceSaveOperationCommittedButUnreconciled({required this.failure});


 final  ClientFailure failure;

/// Create a copy of AppearanceSaveOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppearanceSaveOperationCommittedButUnreconciledCopyWith<AppearanceSaveOperationCommittedButUnreconciled> get copyWith => _$AppearanceSaveOperationCommittedButUnreconciledCopyWithImpl<AppearanceSaveOperationCommittedButUnreconciled>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceSaveOperationCommittedButUnreconciled&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode => Object.hash(runtimeType,failure);

@override
String toString() {
  return 'AppearanceSaveOperation.committedButUnreconciled(failure: $failure)';
}


}

/// @nodoc
abstract mixin class $AppearanceSaveOperationCommittedButUnreconciledCopyWith<$Res> implements $AppearanceSaveOperationCopyWith<$Res> {
  factory $AppearanceSaveOperationCommittedButUnreconciledCopyWith(AppearanceSaveOperationCommittedButUnreconciled value, $Res Function(AppearanceSaveOperationCommittedButUnreconciled) _then) = _$AppearanceSaveOperationCommittedButUnreconciledCopyWithImpl;
@useResult
$Res call({
 ClientFailure failure
});




}
/// @nodoc
class _$AppearanceSaveOperationCommittedButUnreconciledCopyWithImpl<$Res>
    implements $AppearanceSaveOperationCommittedButUnreconciledCopyWith<$Res> {
  _$AppearanceSaveOperationCommittedButUnreconciledCopyWithImpl(this._self, this._then);

  final AppearanceSaveOperationCommittedButUnreconciled _self;
  final $Res Function(AppearanceSaveOperationCommittedButUnreconciled) _then;

/// Create a copy of AppearanceSaveOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(AppearanceSaveOperationCommittedButUnreconciled(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as ClientFailure,
  ));
}


}

/// @nodoc
mixin _$AppearanceSynchronization {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceSynchronization);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppearanceSynchronization()';
}


}

/// @nodoc
class $AppearanceSynchronizationCopyWith<$Res>  {
$AppearanceSynchronizationCopyWith(AppearanceSynchronization _, $Res Function(AppearanceSynchronization) __);
}


/// Adds pattern-matching-related methods to [AppearanceSynchronization].
extension AppearanceSynchronizationPatterns on AppearanceSynchronization {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AppearanceSynchronizationSynchronized value)?  synchronized,TResult Function( AppearanceSynchronizationRefreshing value)?  refreshing,TResult Function( AppearanceSynchronizationUncertain value)?  uncertain,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AppearanceSynchronizationSynchronized() when synchronized != null:
return synchronized(_that);case AppearanceSynchronizationRefreshing() when refreshing != null:
return refreshing(_that);case AppearanceSynchronizationUncertain() when uncertain != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AppearanceSynchronizationSynchronized value)  synchronized,required TResult Function( AppearanceSynchronizationRefreshing value)  refreshing,required TResult Function( AppearanceSynchronizationUncertain value)  uncertain,}){
final _that = this;
switch (_that) {
case AppearanceSynchronizationSynchronized():
return synchronized(_that);case AppearanceSynchronizationRefreshing():
return refreshing(_that);case AppearanceSynchronizationUncertain():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AppearanceSynchronizationSynchronized value)?  synchronized,TResult? Function( AppearanceSynchronizationRefreshing value)?  refreshing,TResult? Function( AppearanceSynchronizationUncertain value)?  uncertain,}){
final _that = this;
switch (_that) {
case AppearanceSynchronizationSynchronized() when synchronized != null:
return synchronized(_that);case AppearanceSynchronizationRefreshing() when refreshing != null:
return refreshing(_that);case AppearanceSynchronizationUncertain() when uncertain != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  synchronized,TResult Function()?  refreshing,TResult Function( ClientFailure failure)?  uncertain,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AppearanceSynchronizationSynchronized() when synchronized != null:
return synchronized();case AppearanceSynchronizationRefreshing() when refreshing != null:
return refreshing();case AppearanceSynchronizationUncertain() when uncertain != null:
return uncertain(_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  synchronized,required TResult Function()  refreshing,required TResult Function( ClientFailure failure)  uncertain,}) {final _that = this;
switch (_that) {
case AppearanceSynchronizationSynchronized():
return synchronized();case AppearanceSynchronizationRefreshing():
return refreshing();case AppearanceSynchronizationUncertain():
return uncertain(_that.failure);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  synchronized,TResult? Function()?  refreshing,TResult? Function( ClientFailure failure)?  uncertain,}) {final _that = this;
switch (_that) {
case AppearanceSynchronizationSynchronized() when synchronized != null:
return synchronized();case AppearanceSynchronizationRefreshing() when refreshing != null:
return refreshing();case AppearanceSynchronizationUncertain() when uncertain != null:
return uncertain(_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class AppearanceSynchronizationSynchronized implements AppearanceSynchronization {
  const AppearanceSynchronizationSynchronized();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceSynchronizationSynchronized);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppearanceSynchronization.synchronized()';
}


}




/// @nodoc


class AppearanceSynchronizationRefreshing implements AppearanceSynchronization {
  const AppearanceSynchronizationRefreshing();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceSynchronizationRefreshing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppearanceSynchronization.refreshing()';
}


}




/// @nodoc


class AppearanceSynchronizationUncertain implements AppearanceSynchronization {
  const AppearanceSynchronizationUncertain({required this.failure});


 final  ClientFailure failure;

/// Create a copy of AppearanceSynchronization
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppearanceSynchronizationUncertainCopyWith<AppearanceSynchronizationUncertain> get copyWith => _$AppearanceSynchronizationUncertainCopyWithImpl<AppearanceSynchronizationUncertain>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceSynchronizationUncertain&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode => Object.hash(runtimeType,failure);

@override
String toString() {
  return 'AppearanceSynchronization.uncertain(failure: $failure)';
}


}

/// @nodoc
abstract mixin class $AppearanceSynchronizationUncertainCopyWith<$Res> implements $AppearanceSynchronizationCopyWith<$Res> {
  factory $AppearanceSynchronizationUncertainCopyWith(AppearanceSynchronizationUncertain value, $Res Function(AppearanceSynchronizationUncertain) _then) = _$AppearanceSynchronizationUncertainCopyWithImpl;
@useResult
$Res call({
 ClientFailure failure
});




}
/// @nodoc
class _$AppearanceSynchronizationUncertainCopyWithImpl<$Res>
    implements $AppearanceSynchronizationUncertainCopyWith<$Res> {
  _$AppearanceSynchronizationUncertainCopyWithImpl(this._self, this._then);

  final AppearanceSynchronizationUncertain _self;
  final $Res Function(AppearanceSynchronizationUncertain) _then;

/// Create a copy of AppearanceSynchronization
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(AppearanceSynchronizationUncertain(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as ClientFailure,
  ));
}


}

/// @nodoc
mixin _$AppearanceSettingsState {

 AppearanceSettings get confirmed; AppearanceSettings get presented; AppearanceSaveOperation get saveOperation; AppearanceSynchronization get synchronization;
/// Create a copy of AppearanceSettingsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppearanceSettingsStateCopyWith<AppearanceSettingsState> get copyWith => _$AppearanceSettingsStateCopyWithImpl<AppearanceSettingsState>(this as AppearanceSettingsState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceSettingsState&&(identical(other.confirmed, confirmed) || other.confirmed == confirmed)&&(identical(other.presented, presented) || other.presented == presented)&&(identical(other.saveOperation, saveOperation) || other.saveOperation == saveOperation)&&(identical(other.synchronization, synchronization) || other.synchronization == synchronization));
}


@override
int get hashCode => Object.hash(runtimeType,confirmed,presented,saveOperation,synchronization);

@override
String toString() {
  return 'AppearanceSettingsState(confirmed: $confirmed, presented: $presented, saveOperation: $saveOperation, synchronization: $synchronization)';
}


}

/// @nodoc
abstract mixin class $AppearanceSettingsStateCopyWith<$Res>  {
  factory $AppearanceSettingsStateCopyWith(AppearanceSettingsState value, $Res Function(AppearanceSettingsState) _then) = _$AppearanceSettingsStateCopyWithImpl;
@useResult
$Res call({
 AppearanceSettings confirmed, AppearanceSettings presented, AppearanceSaveOperation saveOperation, AppearanceSynchronization synchronization
});


$AppearanceSettingsCopyWith<$Res> get confirmed;$AppearanceSettingsCopyWith<$Res> get presented;$AppearanceSaveOperationCopyWith<$Res> get saveOperation;$AppearanceSynchronizationCopyWith<$Res> get synchronization;

}
/// @nodoc
class _$AppearanceSettingsStateCopyWithImpl<$Res>
    implements $AppearanceSettingsStateCopyWith<$Res> {
  _$AppearanceSettingsStateCopyWithImpl(this._self, this._then);

  final AppearanceSettingsState _self;
  final $Res Function(AppearanceSettingsState) _then;

/// Create a copy of AppearanceSettingsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? confirmed = null,Object? presented = null,Object? saveOperation = null,Object? synchronization = null,}) {
  return _then(_self.copyWith(
confirmed: null == confirmed ? _self.confirmed : confirmed // ignore: cast_nullable_to_non_nullable
as AppearanceSettings,presented: null == presented ? _self.presented : presented // ignore: cast_nullable_to_non_nullable
as AppearanceSettings,saveOperation: null == saveOperation ? _self.saveOperation : saveOperation // ignore: cast_nullable_to_non_nullable
as AppearanceSaveOperation,synchronization: null == synchronization ? _self.synchronization : synchronization // ignore: cast_nullable_to_non_nullable
as AppearanceSynchronization,
  ));
}
/// Create a copy of AppearanceSettingsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AppearanceSettingsCopyWith<$Res> get confirmed {

  return $AppearanceSettingsCopyWith<$Res>(_self.confirmed, (value) {
    return _then(_self.copyWith(confirmed: value));
  });
}/// Create a copy of AppearanceSettingsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AppearanceSettingsCopyWith<$Res> get presented {

  return $AppearanceSettingsCopyWith<$Res>(_self.presented, (value) {
    return _then(_self.copyWith(presented: value));
  });
}/// Create a copy of AppearanceSettingsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AppearanceSaveOperationCopyWith<$Res> get saveOperation {

  return $AppearanceSaveOperationCopyWith<$Res>(_self.saveOperation, (value) {
    return _then(_self.copyWith(saveOperation: value));
  });
}/// Create a copy of AppearanceSettingsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AppearanceSynchronizationCopyWith<$Res> get synchronization {

  return $AppearanceSynchronizationCopyWith<$Res>(_self.synchronization, (value) {
    return _then(_self.copyWith(synchronization: value));
  });
}
}


/// Adds pattern-matching-related methods to [AppearanceSettingsState].
extension AppearanceSettingsStatePatterns on AppearanceSettingsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AppearanceSettingsStateReady value)?  ready,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AppearanceSettingsStateReady() when ready != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AppearanceSettingsStateReady value)  ready,}){
final _that = this;
switch (_that) {
case AppearanceSettingsStateReady():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AppearanceSettingsStateReady value)?  ready,}){
final _that = this;
switch (_that) {
case AppearanceSettingsStateReady() when ready != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( AppearanceSettings confirmed,  AppearanceSettings presented,  AppearanceSaveOperation saveOperation,  AppearanceSynchronization synchronization)?  ready,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AppearanceSettingsStateReady() when ready != null:
return ready(_that.confirmed,_that.presented,_that.saveOperation,_that.synchronization);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( AppearanceSettings confirmed,  AppearanceSettings presented,  AppearanceSaveOperation saveOperation,  AppearanceSynchronization synchronization)  ready,}) {final _that = this;
switch (_that) {
case AppearanceSettingsStateReady():
return ready(_that.confirmed,_that.presented,_that.saveOperation,_that.synchronization);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( AppearanceSettings confirmed,  AppearanceSettings presented,  AppearanceSaveOperation saveOperation,  AppearanceSynchronization synchronization)?  ready,}) {final _that = this;
switch (_that) {
case AppearanceSettingsStateReady() when ready != null:
return ready(_that.confirmed,_that.presented,_that.saveOperation,_that.synchronization);case _:
  return null;

}
}

}

/// @nodoc


class AppearanceSettingsStateReady implements AppearanceSettingsState {
  const AppearanceSettingsStateReady({required this.confirmed, required this.presented, required this.saveOperation, required this.synchronization});


@override final  AppearanceSettings confirmed;
@override final  AppearanceSettings presented;
@override final  AppearanceSaveOperation saveOperation;
@override final  AppearanceSynchronization synchronization;

/// Create a copy of AppearanceSettingsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppearanceSettingsStateReadyCopyWith<AppearanceSettingsStateReady> get copyWith => _$AppearanceSettingsStateReadyCopyWithImpl<AppearanceSettingsStateReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceSettingsStateReady&&(identical(other.confirmed, confirmed) || other.confirmed == confirmed)&&(identical(other.presented, presented) || other.presented == presented)&&(identical(other.saveOperation, saveOperation) || other.saveOperation == saveOperation)&&(identical(other.synchronization, synchronization) || other.synchronization == synchronization));
}


@override
int get hashCode => Object.hash(runtimeType,confirmed,presented,saveOperation,synchronization);

@override
String toString() {
  return 'AppearanceSettingsState.ready(confirmed: $confirmed, presented: $presented, saveOperation: $saveOperation, synchronization: $synchronization)';
}


}

/// @nodoc
abstract mixin class $AppearanceSettingsStateReadyCopyWith<$Res> implements $AppearanceSettingsStateCopyWith<$Res> {
  factory $AppearanceSettingsStateReadyCopyWith(AppearanceSettingsStateReady value, $Res Function(AppearanceSettingsStateReady) _then) = _$AppearanceSettingsStateReadyCopyWithImpl;
@override @useResult
$Res call({
 AppearanceSettings confirmed, AppearanceSettings presented, AppearanceSaveOperation saveOperation, AppearanceSynchronization synchronization
});


@override $AppearanceSettingsCopyWith<$Res> get confirmed;@override $AppearanceSettingsCopyWith<$Res> get presented;@override $AppearanceSaveOperationCopyWith<$Res> get saveOperation;@override $AppearanceSynchronizationCopyWith<$Res> get synchronization;

}
/// @nodoc
class _$AppearanceSettingsStateReadyCopyWithImpl<$Res>
    implements $AppearanceSettingsStateReadyCopyWith<$Res> {
  _$AppearanceSettingsStateReadyCopyWithImpl(this._self, this._then);

  final AppearanceSettingsStateReady _self;
  final $Res Function(AppearanceSettingsStateReady) _then;

/// Create a copy of AppearanceSettingsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? confirmed = null,Object? presented = null,Object? saveOperation = null,Object? synchronization = null,}) {
  return _then(AppearanceSettingsStateReady(
confirmed: null == confirmed ? _self.confirmed : confirmed // ignore: cast_nullable_to_non_nullable
as AppearanceSettings,presented: null == presented ? _self.presented : presented // ignore: cast_nullable_to_non_nullable
as AppearanceSettings,saveOperation: null == saveOperation ? _self.saveOperation : saveOperation // ignore: cast_nullable_to_non_nullable
as AppearanceSaveOperation,synchronization: null == synchronization ? _self.synchronization : synchronization // ignore: cast_nullable_to_non_nullable
as AppearanceSynchronization,
  ));
}

/// Create a copy of AppearanceSettingsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AppearanceSettingsCopyWith<$Res> get confirmed {

  return $AppearanceSettingsCopyWith<$Res>(_self.confirmed, (value) {
    return _then(_self.copyWith(confirmed: value));
  });
}/// Create a copy of AppearanceSettingsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AppearanceSettingsCopyWith<$Res> get presented {

  return $AppearanceSettingsCopyWith<$Res>(_self.presented, (value) {
    return _then(_self.copyWith(presented: value));
  });
}/// Create a copy of AppearanceSettingsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AppearanceSaveOperationCopyWith<$Res> get saveOperation {

  return $AppearanceSaveOperationCopyWith<$Res>(_self.saveOperation, (value) {
    return _then(_self.copyWith(saveOperation: value));
  });
}/// Create a copy of AppearanceSettingsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AppearanceSynchronizationCopyWith<$Res> get synchronization {

  return $AppearanceSynchronizationCopyWith<$Res>(_self.synchronization, (value) {
    return _then(_self.copyWith(synchronization: value));
  });
}
}

// dart format on
