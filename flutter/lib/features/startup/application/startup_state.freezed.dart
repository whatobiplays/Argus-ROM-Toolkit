// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'startup_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RecoveryOperationState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryOperationState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RecoveryOperationState()';
}


}

/// @nodoc
class $RecoveryOperationStateCopyWith<$Res>  {
$RecoveryOperationStateCopyWith(RecoveryOperationState _, $Res Function(RecoveryOperationState) __);
}


/// Adds pattern-matching-related methods to [RecoveryOperationState].
extension RecoveryOperationStatePatterns on RecoveryOperationState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RecoveryOperationStateIdle value)?  idle,TResult Function( RecoveryOperationStateRunning value)?  running,TResult Function( RecoveryOperationStateFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RecoveryOperationStateIdle() when idle != null:
return idle(_that);case RecoveryOperationStateRunning() when running != null:
return running(_that);case RecoveryOperationStateFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RecoveryOperationStateIdle value)  idle,required TResult Function( RecoveryOperationStateRunning value)  running,required TResult Function( RecoveryOperationStateFailed value)  failed,}){
final _that = this;
switch (_that) {
case RecoveryOperationStateIdle():
return idle(_that);case RecoveryOperationStateRunning():
return running(_that);case RecoveryOperationStateFailed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RecoveryOperationStateIdle value)?  idle,TResult? Function( RecoveryOperationStateRunning value)?  running,TResult? Function( RecoveryOperationStateFailed value)?  failed,}){
final _that = this;
switch (_that) {
case RecoveryOperationStateIdle() when idle != null:
return idle(_that);case RecoveryOperationStateRunning() when running != null:
return running(_that);case RecoveryOperationStateFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  running,TResult Function( ClientFailure error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RecoveryOperationStateIdle() when idle != null:
return idle();case RecoveryOperationStateRunning() when running != null:
return running();case RecoveryOperationStateFailed() when failed != null:
return failed(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  running,required TResult Function( ClientFailure error)  failed,}) {final _that = this;
switch (_that) {
case RecoveryOperationStateIdle():
return idle();case RecoveryOperationStateRunning():
return running();case RecoveryOperationStateFailed():
return failed(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  running,TResult? Function( ClientFailure error)?  failed,}) {final _that = this;
switch (_that) {
case RecoveryOperationStateIdle() when idle != null:
return idle();case RecoveryOperationStateRunning() when running != null:
return running();case RecoveryOperationStateFailed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class RecoveryOperationStateIdle implements RecoveryOperationState {
  const RecoveryOperationStateIdle();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryOperationStateIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RecoveryOperationState.idle()';
}


}




/// @nodoc


class RecoveryOperationStateRunning implements RecoveryOperationState {
  const RecoveryOperationStateRunning();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryOperationStateRunning);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RecoveryOperationState.running()';
}


}




/// @nodoc


class RecoveryOperationStateFailed implements RecoveryOperationState {
  const RecoveryOperationStateFailed(this.error);


 final  ClientFailure error;

/// Create a copy of RecoveryOperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryOperationStateFailedCopyWith<RecoveryOperationStateFailed> get copyWith => _$RecoveryOperationStateFailedCopyWithImpl<RecoveryOperationStateFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryOperationStateFailed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'RecoveryOperationState.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $RecoveryOperationStateFailedCopyWith<$Res> implements $RecoveryOperationStateCopyWith<$Res> {
  factory $RecoveryOperationStateFailedCopyWith(RecoveryOperationStateFailed value, $Res Function(RecoveryOperationStateFailed) _then) = _$RecoveryOperationStateFailedCopyWithImpl;
@useResult
$Res call({
 ClientFailure error
});




}
/// @nodoc
class _$RecoveryOperationStateFailedCopyWithImpl<$Res>
    implements $RecoveryOperationStateFailedCopyWith<$Res> {
  _$RecoveryOperationStateFailedCopyWithImpl(this._self, this._then);

  final RecoveryOperationStateFailed _self;
  final $Res Function(RecoveryOperationStateFailed) _then;

/// Create a copy of RecoveryOperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(RecoveryOperationStateFailed(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ClientFailure,
  ));
}


}

/// @nodoc
mixin _$ExportOperationState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExportOperationState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ExportOperationState()';
}


}

/// @nodoc
class $ExportOperationStateCopyWith<$Res>  {
$ExportOperationStateCopyWith(ExportOperationState _, $Res Function(ExportOperationState) __);
}


/// Adds pattern-matching-related methods to [ExportOperationState].
extension ExportOperationStatePatterns on ExportOperationState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ExportOperationStateIdle value)?  idle,TResult Function( ExportOperationStateRunning value)?  running,TResult Function( ExportOperationStateSucceeded value)?  succeeded,TResult Function( ExportOperationStateFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ExportOperationStateIdle() when idle != null:
return idle(_that);case ExportOperationStateRunning() when running != null:
return running(_that);case ExportOperationStateSucceeded() when succeeded != null:
return succeeded(_that);case ExportOperationStateFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ExportOperationStateIdle value)  idle,required TResult Function( ExportOperationStateRunning value)  running,required TResult Function( ExportOperationStateSucceeded value)  succeeded,required TResult Function( ExportOperationStateFailed value)  failed,}){
final _that = this;
switch (_that) {
case ExportOperationStateIdle():
return idle(_that);case ExportOperationStateRunning():
return running(_that);case ExportOperationStateSucceeded():
return succeeded(_that);case ExportOperationStateFailed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ExportOperationStateIdle value)?  idle,TResult? Function( ExportOperationStateRunning value)?  running,TResult? Function( ExportOperationStateSucceeded value)?  succeeded,TResult? Function( ExportOperationStateFailed value)?  failed,}){
final _that = this;
switch (_that) {
case ExportOperationStateIdle() when idle != null:
return idle(_that);case ExportOperationStateRunning() when running != null:
return running(_that);case ExportOperationStateSucceeded() when succeeded != null:
return succeeded(_that);case ExportOperationStateFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  running,TResult Function( DiagnosticsExport result)?  succeeded,TResult Function( ClientFailure error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ExportOperationStateIdle() when idle != null:
return idle();case ExportOperationStateRunning() when running != null:
return running();case ExportOperationStateSucceeded() when succeeded != null:
return succeeded(_that.result);case ExportOperationStateFailed() when failed != null:
return failed(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  running,required TResult Function( DiagnosticsExport result)  succeeded,required TResult Function( ClientFailure error)  failed,}) {final _that = this;
switch (_that) {
case ExportOperationStateIdle():
return idle();case ExportOperationStateRunning():
return running();case ExportOperationStateSucceeded():
return succeeded(_that.result);case ExportOperationStateFailed():
return failed(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  running,TResult? Function( DiagnosticsExport result)?  succeeded,TResult? Function( ClientFailure error)?  failed,}) {final _that = this;
switch (_that) {
case ExportOperationStateIdle() when idle != null:
return idle();case ExportOperationStateRunning() when running != null:
return running();case ExportOperationStateSucceeded() when succeeded != null:
return succeeded(_that.result);case ExportOperationStateFailed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class ExportOperationStateIdle implements ExportOperationState {
  const ExportOperationStateIdle();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExportOperationStateIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ExportOperationState.idle()';
}


}




/// @nodoc


class ExportOperationStateRunning implements ExportOperationState {
  const ExportOperationStateRunning();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExportOperationStateRunning);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ExportOperationState.running()';
}


}




/// @nodoc


class ExportOperationStateSucceeded implements ExportOperationState {
  const ExportOperationStateSucceeded(this.result);


 final  DiagnosticsExport result;

/// Create a copy of ExportOperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExportOperationStateSucceededCopyWith<ExportOperationStateSucceeded> get copyWith => _$ExportOperationStateSucceededCopyWithImpl<ExportOperationStateSucceeded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExportOperationStateSucceeded&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode => Object.hash(runtimeType,result);

@override
String toString() {
  return 'ExportOperationState.succeeded(result: $result)';
}


}

/// @nodoc
abstract mixin class $ExportOperationStateSucceededCopyWith<$Res> implements $ExportOperationStateCopyWith<$Res> {
  factory $ExportOperationStateSucceededCopyWith(ExportOperationStateSucceeded value, $Res Function(ExportOperationStateSucceeded) _then) = _$ExportOperationStateSucceededCopyWithImpl;
@useResult
$Res call({
 DiagnosticsExport result
});


$DiagnosticsExportCopyWith<$Res> get result;

}
/// @nodoc
class _$ExportOperationStateSucceededCopyWithImpl<$Res>
    implements $ExportOperationStateSucceededCopyWith<$Res> {
  _$ExportOperationStateSucceededCopyWithImpl(this._self, this._then);

  final ExportOperationStateSucceeded _self;
  final $Res Function(ExportOperationStateSucceeded) _then;

/// Create a copy of ExportOperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? result = null,}) {
  return _then(ExportOperationStateSucceeded(
null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as DiagnosticsExport,
  ));
}

/// Create a copy of ExportOperationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DiagnosticsExportCopyWith<$Res> get result {

  return $DiagnosticsExportCopyWith<$Res>(_self.result, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}

/// @nodoc


class ExportOperationStateFailed implements ExportOperationState {
  const ExportOperationStateFailed(this.error);


 final  ClientFailure error;

/// Create a copy of ExportOperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExportOperationStateFailedCopyWith<ExportOperationStateFailed> get copyWith => _$ExportOperationStateFailedCopyWithImpl<ExportOperationStateFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExportOperationStateFailed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'ExportOperationState.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $ExportOperationStateFailedCopyWith<$Res> implements $ExportOperationStateCopyWith<$Res> {
  factory $ExportOperationStateFailedCopyWith(ExportOperationStateFailed value, $Res Function(ExportOperationStateFailed) _then) = _$ExportOperationStateFailedCopyWithImpl;
@useResult
$Res call({
 ClientFailure error
});




}
/// @nodoc
class _$ExportOperationStateFailedCopyWithImpl<$Res>
    implements $ExportOperationStateFailedCopyWith<$Res> {
  _$ExportOperationStateFailedCopyWithImpl(this._self, this._then);

  final ExportOperationStateFailed _self;
  final $Res Function(ExportOperationStateFailed) _then;

/// Create a copy of ExportOperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(ExportOperationStateFailed(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ClientFailure,
  ));
}


}

/// @nodoc
mixin _$TechnicalDetailsOperationState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TechnicalDetailsOperationState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TechnicalDetailsOperationState()';
}


}

/// @nodoc
class $TechnicalDetailsOperationStateCopyWith<$Res>  {
$TechnicalDetailsOperationStateCopyWith(TechnicalDetailsOperationState _, $Res Function(TechnicalDetailsOperationState) __);
}


/// Adds pattern-matching-related methods to [TechnicalDetailsOperationState].
extension TechnicalDetailsOperationStatePatterns on TechnicalDetailsOperationState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TechnicalDetailsOperationStateIdle value)?  idle,TResult Function( TechnicalDetailsOperationStateLoading value)?  loading,TResult Function( TechnicalDetailsOperationStateLoaded value)?  loaded,TResult Function( TechnicalDetailsOperationStateFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TechnicalDetailsOperationStateIdle() when idle != null:
return idle(_that);case TechnicalDetailsOperationStateLoading() when loading != null:
return loading(_that);case TechnicalDetailsOperationStateLoaded() when loaded != null:
return loaded(_that);case TechnicalDetailsOperationStateFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TechnicalDetailsOperationStateIdle value)  idle,required TResult Function( TechnicalDetailsOperationStateLoading value)  loading,required TResult Function( TechnicalDetailsOperationStateLoaded value)  loaded,required TResult Function( TechnicalDetailsOperationStateFailed value)  failed,}){
final _that = this;
switch (_that) {
case TechnicalDetailsOperationStateIdle():
return idle(_that);case TechnicalDetailsOperationStateLoading():
return loading(_that);case TechnicalDetailsOperationStateLoaded():
return loaded(_that);case TechnicalDetailsOperationStateFailed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TechnicalDetailsOperationStateIdle value)?  idle,TResult? Function( TechnicalDetailsOperationStateLoading value)?  loading,TResult? Function( TechnicalDetailsOperationStateLoaded value)?  loaded,TResult? Function( TechnicalDetailsOperationStateFailed value)?  failed,}){
final _that = this;
switch (_that) {
case TechnicalDetailsOperationStateIdle() when idle != null:
return idle(_that);case TechnicalDetailsOperationStateLoading() when loading != null:
return loading(_that);case TechnicalDetailsOperationStateLoaded() when loaded != null:
return loaded(_that);case TechnicalDetailsOperationStateFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  loading,TResult Function( TechnicalDetails details)?  loaded,TResult Function( ClientFailure error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TechnicalDetailsOperationStateIdle() when idle != null:
return idle();case TechnicalDetailsOperationStateLoading() when loading != null:
return loading();case TechnicalDetailsOperationStateLoaded() when loaded != null:
return loaded(_that.details);case TechnicalDetailsOperationStateFailed() when failed != null:
return failed(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  loading,required TResult Function( TechnicalDetails details)  loaded,required TResult Function( ClientFailure error)  failed,}) {final _that = this;
switch (_that) {
case TechnicalDetailsOperationStateIdle():
return idle();case TechnicalDetailsOperationStateLoading():
return loading();case TechnicalDetailsOperationStateLoaded():
return loaded(_that.details);case TechnicalDetailsOperationStateFailed():
return failed(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  loading,TResult? Function( TechnicalDetails details)?  loaded,TResult? Function( ClientFailure error)?  failed,}) {final _that = this;
switch (_that) {
case TechnicalDetailsOperationStateIdle() when idle != null:
return idle();case TechnicalDetailsOperationStateLoading() when loading != null:
return loading();case TechnicalDetailsOperationStateLoaded() when loaded != null:
return loaded(_that.details);case TechnicalDetailsOperationStateFailed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class TechnicalDetailsOperationStateIdle implements TechnicalDetailsOperationState {
  const TechnicalDetailsOperationStateIdle();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TechnicalDetailsOperationStateIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TechnicalDetailsOperationState.idle()';
}


}




/// @nodoc


class TechnicalDetailsOperationStateLoading implements TechnicalDetailsOperationState {
  const TechnicalDetailsOperationStateLoading();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TechnicalDetailsOperationStateLoading);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TechnicalDetailsOperationState.loading()';
}


}




/// @nodoc


class TechnicalDetailsOperationStateLoaded implements TechnicalDetailsOperationState {
  const TechnicalDetailsOperationStateLoaded(this.details);


 final  TechnicalDetails details;

/// Create a copy of TechnicalDetailsOperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TechnicalDetailsOperationStateLoadedCopyWith<TechnicalDetailsOperationStateLoaded> get copyWith => _$TechnicalDetailsOperationStateLoadedCopyWithImpl<TechnicalDetailsOperationStateLoaded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TechnicalDetailsOperationStateLoaded&&(identical(other.details, details) || other.details == details));
}


@override
int get hashCode => Object.hash(runtimeType,details);

@override
String toString() {
  return 'TechnicalDetailsOperationState.loaded(details: $details)';
}


}

/// @nodoc
abstract mixin class $TechnicalDetailsOperationStateLoadedCopyWith<$Res> implements $TechnicalDetailsOperationStateCopyWith<$Res> {
  factory $TechnicalDetailsOperationStateLoadedCopyWith(TechnicalDetailsOperationStateLoaded value, $Res Function(TechnicalDetailsOperationStateLoaded) _then) = _$TechnicalDetailsOperationStateLoadedCopyWithImpl;
@useResult
$Res call({
 TechnicalDetails details
});


$TechnicalDetailsCopyWith<$Res> get details;

}
/// @nodoc
class _$TechnicalDetailsOperationStateLoadedCopyWithImpl<$Res>
    implements $TechnicalDetailsOperationStateLoadedCopyWith<$Res> {
  _$TechnicalDetailsOperationStateLoadedCopyWithImpl(this._self, this._then);

  final TechnicalDetailsOperationStateLoaded _self;
  final $Res Function(TechnicalDetailsOperationStateLoaded) _then;

/// Create a copy of TechnicalDetailsOperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? details = null,}) {
  return _then(TechnicalDetailsOperationStateLoaded(
null == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as TechnicalDetails,
  ));
}

/// Create a copy of TechnicalDetailsOperationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TechnicalDetailsCopyWith<$Res> get details {

  return $TechnicalDetailsCopyWith<$Res>(_self.details, (value) {
    return _then(_self.copyWith(details: value));
  });
}
}

/// @nodoc


class TechnicalDetailsOperationStateFailed implements TechnicalDetailsOperationState {
  const TechnicalDetailsOperationStateFailed(this.error);


 final  ClientFailure error;

/// Create a copy of TechnicalDetailsOperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TechnicalDetailsOperationStateFailedCopyWith<TechnicalDetailsOperationStateFailed> get copyWith => _$TechnicalDetailsOperationStateFailedCopyWithImpl<TechnicalDetailsOperationStateFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TechnicalDetailsOperationStateFailed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'TechnicalDetailsOperationState.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $TechnicalDetailsOperationStateFailedCopyWith<$Res> implements $TechnicalDetailsOperationStateCopyWith<$Res> {
  factory $TechnicalDetailsOperationStateFailedCopyWith(TechnicalDetailsOperationStateFailed value, $Res Function(TechnicalDetailsOperationStateFailed) _then) = _$TechnicalDetailsOperationStateFailedCopyWithImpl;
@useResult
$Res call({
 ClientFailure error
});




}
/// @nodoc
class _$TechnicalDetailsOperationStateFailedCopyWithImpl<$Res>
    implements $TechnicalDetailsOperationStateFailedCopyWith<$Res> {
  _$TechnicalDetailsOperationStateFailedCopyWithImpl(this._self, this._then);

  final TechnicalDetailsOperationStateFailed _self;
  final $Res Function(TechnicalDetailsOperationStateFailed) _then;

/// Create a copy of TechnicalDetailsOperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(TechnicalDetailsOperationStateFailed(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ClientFailure,
  ));
}


}

/// @nodoc
mixin _$OpenDirectoryOperationState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OpenDirectoryOperationState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'OpenDirectoryOperationState()';
}


}

/// @nodoc
class $OpenDirectoryOperationStateCopyWith<$Res>  {
$OpenDirectoryOperationStateCopyWith(OpenDirectoryOperationState _, $Res Function(OpenDirectoryOperationState) __);
}


/// Adds pattern-matching-related methods to [OpenDirectoryOperationState].
extension OpenDirectoryOperationStatePatterns on OpenDirectoryOperationState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( OpenDirectoryOperationStateIdle value)?  idle,TResult Function( OpenDirectoryOperationStateRunning value)?  running,TResult Function( OpenDirectoryOperationStateFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case OpenDirectoryOperationStateIdle() when idle != null:
return idle(_that);case OpenDirectoryOperationStateRunning() when running != null:
return running(_that);case OpenDirectoryOperationStateFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( OpenDirectoryOperationStateIdle value)  idle,required TResult Function( OpenDirectoryOperationStateRunning value)  running,required TResult Function( OpenDirectoryOperationStateFailed value)  failed,}){
final _that = this;
switch (_that) {
case OpenDirectoryOperationStateIdle():
return idle(_that);case OpenDirectoryOperationStateRunning():
return running(_that);case OpenDirectoryOperationStateFailed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( OpenDirectoryOperationStateIdle value)?  idle,TResult? Function( OpenDirectoryOperationStateRunning value)?  running,TResult? Function( OpenDirectoryOperationStateFailed value)?  failed,}){
final _that = this;
switch (_that) {
case OpenDirectoryOperationStateIdle() when idle != null:
return idle(_that);case OpenDirectoryOperationStateRunning() when running != null:
return running(_that);case OpenDirectoryOperationStateFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  running,TResult Function( ClientFailure error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case OpenDirectoryOperationStateIdle() when idle != null:
return idle();case OpenDirectoryOperationStateRunning() when running != null:
return running();case OpenDirectoryOperationStateFailed() when failed != null:
return failed(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  running,required TResult Function( ClientFailure error)  failed,}) {final _that = this;
switch (_that) {
case OpenDirectoryOperationStateIdle():
return idle();case OpenDirectoryOperationStateRunning():
return running();case OpenDirectoryOperationStateFailed():
return failed(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  running,TResult? Function( ClientFailure error)?  failed,}) {final _that = this;
switch (_that) {
case OpenDirectoryOperationStateIdle() when idle != null:
return idle();case OpenDirectoryOperationStateRunning() when running != null:
return running();case OpenDirectoryOperationStateFailed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class OpenDirectoryOperationStateIdle implements OpenDirectoryOperationState {
  const OpenDirectoryOperationStateIdle();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OpenDirectoryOperationStateIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'OpenDirectoryOperationState.idle()';
}


}




/// @nodoc


class OpenDirectoryOperationStateRunning implements OpenDirectoryOperationState {
  const OpenDirectoryOperationStateRunning();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OpenDirectoryOperationStateRunning);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'OpenDirectoryOperationState.running()';
}


}




/// @nodoc


class OpenDirectoryOperationStateFailed implements OpenDirectoryOperationState {
  const OpenDirectoryOperationStateFailed(this.error);


 final  ClientFailure error;

/// Create a copy of OpenDirectoryOperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OpenDirectoryOperationStateFailedCopyWith<OpenDirectoryOperationStateFailed> get copyWith => _$OpenDirectoryOperationStateFailedCopyWithImpl<OpenDirectoryOperationStateFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OpenDirectoryOperationStateFailed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'OpenDirectoryOperationState.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $OpenDirectoryOperationStateFailedCopyWith<$Res> implements $OpenDirectoryOperationStateCopyWith<$Res> {
  factory $OpenDirectoryOperationStateFailedCopyWith(OpenDirectoryOperationStateFailed value, $Res Function(OpenDirectoryOperationStateFailed) _then) = _$OpenDirectoryOperationStateFailedCopyWithImpl;
@useResult
$Res call({
 ClientFailure error
});




}
/// @nodoc
class _$OpenDirectoryOperationStateFailedCopyWithImpl<$Res>
    implements $OpenDirectoryOperationStateFailedCopyWith<$Res> {
  _$OpenDirectoryOperationStateFailedCopyWithImpl(this._self, this._then);

  final OpenDirectoryOperationStateFailed _self;
  final $Res Function(OpenDirectoryOperationStateFailed) _then;

/// Create a copy of OpenDirectoryOperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(OpenDirectoryOperationStateFailed(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ClientFailure,
  ));
}


}

/// @nodoc
mixin _$ReconciliationOperationState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReconciliationOperationState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ReconciliationOperationState()';
}


}

/// @nodoc
class $ReconciliationOperationStateCopyWith<$Res>  {
$ReconciliationOperationStateCopyWith(ReconciliationOperationState _, $Res Function(ReconciliationOperationState) __);
}


/// Adds pattern-matching-related methods to [ReconciliationOperationState].
extension ReconciliationOperationStatePatterns on ReconciliationOperationState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ReconciliationOperationStateIdle value)?  idle,TResult Function( ReconciliationOperationStateRunning value)?  running,TResult Function( ReconciliationOperationStateFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ReconciliationOperationStateIdle() when idle != null:
return idle(_that);case ReconciliationOperationStateRunning() when running != null:
return running(_that);case ReconciliationOperationStateFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ReconciliationOperationStateIdle value)  idle,required TResult Function( ReconciliationOperationStateRunning value)  running,required TResult Function( ReconciliationOperationStateFailed value)  failed,}){
final _that = this;
switch (_that) {
case ReconciliationOperationStateIdle():
return idle(_that);case ReconciliationOperationStateRunning():
return running(_that);case ReconciliationOperationStateFailed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ReconciliationOperationStateIdle value)?  idle,TResult? Function( ReconciliationOperationStateRunning value)?  running,TResult? Function( ReconciliationOperationStateFailed value)?  failed,}){
final _that = this;
switch (_that) {
case ReconciliationOperationStateIdle() when idle != null:
return idle(_that);case ReconciliationOperationStateRunning() when running != null:
return running(_that);case ReconciliationOperationStateFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  running,TResult Function( ClientFailure error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ReconciliationOperationStateIdle() when idle != null:
return idle();case ReconciliationOperationStateRunning() when running != null:
return running();case ReconciliationOperationStateFailed() when failed != null:
return failed(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  running,required TResult Function( ClientFailure error)  failed,}) {final _that = this;
switch (_that) {
case ReconciliationOperationStateIdle():
return idle();case ReconciliationOperationStateRunning():
return running();case ReconciliationOperationStateFailed():
return failed(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  running,TResult? Function( ClientFailure error)?  failed,}) {final _that = this;
switch (_that) {
case ReconciliationOperationStateIdle() when idle != null:
return idle();case ReconciliationOperationStateRunning() when running != null:
return running();case ReconciliationOperationStateFailed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class ReconciliationOperationStateIdle implements ReconciliationOperationState {
  const ReconciliationOperationStateIdle();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReconciliationOperationStateIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ReconciliationOperationState.idle()';
}


}




/// @nodoc


class ReconciliationOperationStateRunning implements ReconciliationOperationState {
  const ReconciliationOperationStateRunning();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReconciliationOperationStateRunning);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ReconciliationOperationState.running()';
}


}




/// @nodoc


class ReconciliationOperationStateFailed implements ReconciliationOperationState {
  const ReconciliationOperationStateFailed(this.error);


 final  ClientFailure error;

/// Create a copy of ReconciliationOperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReconciliationOperationStateFailedCopyWith<ReconciliationOperationStateFailed> get copyWith => _$ReconciliationOperationStateFailedCopyWithImpl<ReconciliationOperationStateFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReconciliationOperationStateFailed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'ReconciliationOperationState.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $ReconciliationOperationStateFailedCopyWith<$Res> implements $ReconciliationOperationStateCopyWith<$Res> {
  factory $ReconciliationOperationStateFailedCopyWith(ReconciliationOperationStateFailed value, $Res Function(ReconciliationOperationStateFailed) _then) = _$ReconciliationOperationStateFailedCopyWithImpl;
@useResult
$Res call({
 ClientFailure error
});




}
/// @nodoc
class _$ReconciliationOperationStateFailedCopyWithImpl<$Res>
    implements $ReconciliationOperationStateFailedCopyWith<$Res> {
  _$ReconciliationOperationStateFailedCopyWithImpl(this._self, this._then);

  final ReconciliationOperationStateFailed _self;
  final $Res Function(ReconciliationOperationStateFailed) _then;

/// Create a copy of ReconciliationOperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(ReconciliationOperationStateFailed(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ClientFailure,
  ));
}


}

/// @nodoc
mixin _$StartupRuntimeContext {

 RuntimeInstanceId get runtimeInstanceId; RuntimeLifecycle get lifecycle; StartupPhase? get phase;
/// Create a copy of StartupRuntimeContext
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupRuntimeContextCopyWith<StartupRuntimeContext> get copyWith => _$StartupRuntimeContextCopyWithImpl<StartupRuntimeContext>(this as StartupRuntimeContext, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupRuntimeContext&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId)&&(identical(other.lifecycle, lifecycle) || other.lifecycle == lifecycle)&&(identical(other.phase, phase) || other.phase == phase));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId,lifecycle,phase);

@override
String toString() {
  return 'StartupRuntimeContext(runtimeInstanceId: $runtimeInstanceId, lifecycle: $lifecycle, phase: $phase)';
}


}

/// @nodoc
abstract mixin class $StartupRuntimeContextCopyWith<$Res>  {
  factory $StartupRuntimeContextCopyWith(StartupRuntimeContext value, $Res Function(StartupRuntimeContext) _then) = _$StartupRuntimeContextCopyWithImpl;
@useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId, RuntimeLifecycle lifecycle, StartupPhase? phase
});




}
/// @nodoc
class _$StartupRuntimeContextCopyWithImpl<$Res>
    implements $StartupRuntimeContextCopyWith<$Res> {
  _$StartupRuntimeContextCopyWithImpl(this._self, this._then);

  final StartupRuntimeContext _self;
  final $Res Function(StartupRuntimeContext) _then;

/// Create a copy of StartupRuntimeContext
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? runtimeInstanceId = null,Object? lifecycle = null,Object? phase = freezed,}) {
  return _then(_self.copyWith(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as RuntimeLifecycle,phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as StartupPhase?,
  ));
}

}


/// Adds pattern-matching-related methods to [StartupRuntimeContext].
extension StartupRuntimeContextPatterns on StartupRuntimeContext {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartupRuntimeContext value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartupRuntimeContext() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartupRuntimeContext value)  $default,){
final _that = this;
switch (_that) {
case _StartupRuntimeContext():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartupRuntimeContext value)?  $default,){
final _that = this;
switch (_that) {
case _StartupRuntimeContext() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RuntimeInstanceId runtimeInstanceId,  RuntimeLifecycle lifecycle,  StartupPhase? phase)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartupRuntimeContext() when $default != null:
return $default(_that.runtimeInstanceId,_that.lifecycle,_that.phase);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RuntimeInstanceId runtimeInstanceId,  RuntimeLifecycle lifecycle,  StartupPhase? phase)  $default,) {final _that = this;
switch (_that) {
case _StartupRuntimeContext():
return $default(_that.runtimeInstanceId,_that.lifecycle,_that.phase);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RuntimeInstanceId runtimeInstanceId,  RuntimeLifecycle lifecycle,  StartupPhase? phase)?  $default,) {final _that = this;
switch (_that) {
case _StartupRuntimeContext() when $default != null:
return $default(_that.runtimeInstanceId,_that.lifecycle,_that.phase);case _:
  return null;

}
}

}

/// @nodoc


class _StartupRuntimeContext implements StartupRuntimeContext {
  const _StartupRuntimeContext({required this.runtimeInstanceId, required this.lifecycle, this.phase});


@override final  RuntimeInstanceId runtimeInstanceId;
@override final  RuntimeLifecycle lifecycle;
@override final  StartupPhase? phase;

/// Create a copy of StartupRuntimeContext
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartupRuntimeContextCopyWith<_StartupRuntimeContext> get copyWith => __$StartupRuntimeContextCopyWithImpl<_StartupRuntimeContext>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartupRuntimeContext&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId)&&(identical(other.lifecycle, lifecycle) || other.lifecycle == lifecycle)&&(identical(other.phase, phase) || other.phase == phase));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId,lifecycle,phase);

@override
String toString() {
  return 'StartupRuntimeContext(runtimeInstanceId: $runtimeInstanceId, lifecycle: $lifecycle, phase: $phase)';
}


}

/// @nodoc
abstract mixin class _$StartupRuntimeContextCopyWith<$Res> implements $StartupRuntimeContextCopyWith<$Res> {
  factory _$StartupRuntimeContextCopyWith(_StartupRuntimeContext value, $Res Function(_StartupRuntimeContext) _then) = __$StartupRuntimeContextCopyWithImpl;
@override @useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId, RuntimeLifecycle lifecycle, StartupPhase? phase
});




}
/// @nodoc
class __$StartupRuntimeContextCopyWithImpl<$Res>
    implements _$StartupRuntimeContextCopyWith<$Res> {
  __$StartupRuntimeContextCopyWithImpl(this._self, this._then);

  final _StartupRuntimeContext _self;
  final $Res Function(_StartupRuntimeContext) _then;

/// Create a copy of StartupRuntimeContext
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,Object? lifecycle = null,Object? phase = freezed,}) {
  return _then(_StartupRuntimeContext(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as RuntimeLifecycle,phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as StartupPhase?,
  ));
}


}

/// @nodoc
mixin _$StartupState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'StartupState()';
}


}

/// @nodoc
class $StartupStateCopyWith<$Res>  {
$StartupStateCopyWith(StartupState _, $Res Function(StartupState) __);
}


/// Adds pattern-matching-related methods to [StartupState].
extension StartupStatePatterns on StartupState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StartupStateUninitialized value)?  uninitialized,TResult Function( StartupStateStarting value)?  starting,TResult Function( StartupStateReady value)?  ready,TResult Function( StartupStateStartupFailed value)?  startupFailed,TResult Function( StartupStateRuntimeUnavailable value)?  runtimeUnavailable,TResult Function( StartupStateShuttingDown value)?  shuttingDown,TResult Function( StartupStateStopped value)?  stopped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StartupStateUninitialized() when uninitialized != null:
return uninitialized(_that);case StartupStateStarting() when starting != null:
return starting(_that);case StartupStateReady() when ready != null:
return ready(_that);case StartupStateStartupFailed() when startupFailed != null:
return startupFailed(_that);case StartupStateRuntimeUnavailable() when runtimeUnavailable != null:
return runtimeUnavailable(_that);case StartupStateShuttingDown() when shuttingDown != null:
return shuttingDown(_that);case StartupStateStopped() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StartupStateUninitialized value)  uninitialized,required TResult Function( StartupStateStarting value)  starting,required TResult Function( StartupStateReady value)  ready,required TResult Function( StartupStateStartupFailed value)  startupFailed,required TResult Function( StartupStateRuntimeUnavailable value)  runtimeUnavailable,required TResult Function( StartupStateShuttingDown value)  shuttingDown,required TResult Function( StartupStateStopped value)  stopped,}){
final _that = this;
switch (_that) {
case StartupStateUninitialized():
return uninitialized(_that);case StartupStateStarting():
return starting(_that);case StartupStateReady():
return ready(_that);case StartupStateStartupFailed():
return startupFailed(_that);case StartupStateRuntimeUnavailable():
return runtimeUnavailable(_that);case StartupStateShuttingDown():
return shuttingDown(_that);case StartupStateStopped():
return stopped(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StartupStateUninitialized value)?  uninitialized,TResult? Function( StartupStateStarting value)?  starting,TResult? Function( StartupStateReady value)?  ready,TResult? Function( StartupStateStartupFailed value)?  startupFailed,TResult? Function( StartupStateRuntimeUnavailable value)?  runtimeUnavailable,TResult? Function( StartupStateShuttingDown value)?  shuttingDown,TResult? Function( StartupStateStopped value)?  stopped,}){
final _that = this;
switch (_that) {
case StartupStateUninitialized() when uninitialized != null:
return uninitialized(_that);case StartupStateStarting() when starting != null:
return starting(_that);case StartupStateReady() when ready != null:
return ready(_that);case StartupStateStartupFailed() when startupFailed != null:
return startupFailed(_that);case StartupStateRuntimeUnavailable() when runtimeUnavailable != null:
return runtimeUnavailable(_that);case StartupStateShuttingDown() when shuttingDown != null:
return shuttingDown(_that);case StartupStateStopped() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( RuntimeInstanceId runtimeInstanceId)?  uninitialized,TResult Function( RuntimeInstanceId runtimeInstanceId,  StartupPhase? phase)?  starting,TResult Function( RuntimeInstanceId runtimeInstanceId)?  ready,TResult Function( RuntimeInstanceId runtimeInstanceId,  StartupFailure failure,  RecoveryOperationState recoveryOperation,  ExportOperationState exportOperation,  TechnicalDetailsOperationState technicalDetails,  OpenDirectoryOperationState openDirectoryOperation)?  startupFailed,TResult Function( ClientFailure cause,  StartupRuntimeContext? lastKnownRuntime,  ReconciliationOperationState reconciliationOperation)?  runtimeUnavailable,TResult Function( RuntimeInstanceId runtimeInstanceId)?  shuttingDown,TResult Function( RuntimeInstanceId runtimeInstanceId)?  stopped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StartupStateUninitialized() when uninitialized != null:
return uninitialized(_that.runtimeInstanceId);case StartupStateStarting() when starting != null:
return starting(_that.runtimeInstanceId,_that.phase);case StartupStateReady() when ready != null:
return ready(_that.runtimeInstanceId);case StartupStateStartupFailed() when startupFailed != null:
return startupFailed(_that.runtimeInstanceId,_that.failure,_that.recoveryOperation,_that.exportOperation,_that.technicalDetails,_that.openDirectoryOperation);case StartupStateRuntimeUnavailable() when runtimeUnavailable != null:
return runtimeUnavailable(_that.cause,_that.lastKnownRuntime,_that.reconciliationOperation);case StartupStateShuttingDown() when shuttingDown != null:
return shuttingDown(_that.runtimeInstanceId);case StartupStateStopped() when stopped != null:
return stopped(_that.runtimeInstanceId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( RuntimeInstanceId runtimeInstanceId)  uninitialized,required TResult Function( RuntimeInstanceId runtimeInstanceId,  StartupPhase? phase)  starting,required TResult Function( RuntimeInstanceId runtimeInstanceId)  ready,required TResult Function( RuntimeInstanceId runtimeInstanceId,  StartupFailure failure,  RecoveryOperationState recoveryOperation,  ExportOperationState exportOperation,  TechnicalDetailsOperationState technicalDetails,  OpenDirectoryOperationState openDirectoryOperation)  startupFailed,required TResult Function( ClientFailure cause,  StartupRuntimeContext? lastKnownRuntime,  ReconciliationOperationState reconciliationOperation)  runtimeUnavailable,required TResult Function( RuntimeInstanceId runtimeInstanceId)  shuttingDown,required TResult Function( RuntimeInstanceId runtimeInstanceId)  stopped,}) {final _that = this;
switch (_that) {
case StartupStateUninitialized():
return uninitialized(_that.runtimeInstanceId);case StartupStateStarting():
return starting(_that.runtimeInstanceId,_that.phase);case StartupStateReady():
return ready(_that.runtimeInstanceId);case StartupStateStartupFailed():
return startupFailed(_that.runtimeInstanceId,_that.failure,_that.recoveryOperation,_that.exportOperation,_that.technicalDetails,_that.openDirectoryOperation);case StartupStateRuntimeUnavailable():
return runtimeUnavailable(_that.cause,_that.lastKnownRuntime,_that.reconciliationOperation);case StartupStateShuttingDown():
return shuttingDown(_that.runtimeInstanceId);case StartupStateStopped():
return stopped(_that.runtimeInstanceId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( RuntimeInstanceId runtimeInstanceId)?  uninitialized,TResult? Function( RuntimeInstanceId runtimeInstanceId,  StartupPhase? phase)?  starting,TResult? Function( RuntimeInstanceId runtimeInstanceId)?  ready,TResult? Function( RuntimeInstanceId runtimeInstanceId,  StartupFailure failure,  RecoveryOperationState recoveryOperation,  ExportOperationState exportOperation,  TechnicalDetailsOperationState technicalDetails,  OpenDirectoryOperationState openDirectoryOperation)?  startupFailed,TResult? Function( ClientFailure cause,  StartupRuntimeContext? lastKnownRuntime,  ReconciliationOperationState reconciliationOperation)?  runtimeUnavailable,TResult? Function( RuntimeInstanceId runtimeInstanceId)?  shuttingDown,TResult? Function( RuntimeInstanceId runtimeInstanceId)?  stopped,}) {final _that = this;
switch (_that) {
case StartupStateUninitialized() when uninitialized != null:
return uninitialized(_that.runtimeInstanceId);case StartupStateStarting() when starting != null:
return starting(_that.runtimeInstanceId,_that.phase);case StartupStateReady() when ready != null:
return ready(_that.runtimeInstanceId);case StartupStateStartupFailed() when startupFailed != null:
return startupFailed(_that.runtimeInstanceId,_that.failure,_that.recoveryOperation,_that.exportOperation,_that.technicalDetails,_that.openDirectoryOperation);case StartupStateRuntimeUnavailable() when runtimeUnavailable != null:
return runtimeUnavailable(_that.cause,_that.lastKnownRuntime,_that.reconciliationOperation);case StartupStateShuttingDown() when shuttingDown != null:
return shuttingDown(_that.runtimeInstanceId);case StartupStateStopped() when stopped != null:
return stopped(_that.runtimeInstanceId);case _:
  return null;

}
}

}

/// @nodoc


class StartupStateUninitialized implements StartupState {
  const StartupStateUninitialized({required this.runtimeInstanceId});


 final  RuntimeInstanceId runtimeInstanceId;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupStateUninitializedCopyWith<StartupStateUninitialized> get copyWith => _$StartupStateUninitializedCopyWithImpl<StartupStateUninitialized>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupStateUninitialized&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId);

@override
String toString() {
  return 'StartupState.uninitialized(runtimeInstanceId: $runtimeInstanceId)';
}


}

/// @nodoc
abstract mixin class $StartupStateUninitializedCopyWith<$Res> implements $StartupStateCopyWith<$Res> {
  factory $StartupStateUninitializedCopyWith(StartupStateUninitialized value, $Res Function(StartupStateUninitialized) _then) = _$StartupStateUninitializedCopyWithImpl;
@useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId
});




}
/// @nodoc
class _$StartupStateUninitializedCopyWithImpl<$Res>
    implements $StartupStateUninitializedCopyWith<$Res> {
  _$StartupStateUninitializedCopyWithImpl(this._self, this._then);

  final StartupStateUninitialized _self;
  final $Res Function(StartupStateUninitialized) _then;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,}) {
  return _then(StartupStateUninitialized(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,
  ));
}


}

/// @nodoc


class StartupStateStarting implements StartupState {
  const StartupStateStarting({required this.runtimeInstanceId, this.phase});


 final  RuntimeInstanceId runtimeInstanceId;
 final  StartupPhase? phase;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupStateStartingCopyWith<StartupStateStarting> get copyWith => _$StartupStateStartingCopyWithImpl<StartupStateStarting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupStateStarting&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId)&&(identical(other.phase, phase) || other.phase == phase));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId,phase);

@override
String toString() {
  return 'StartupState.starting(runtimeInstanceId: $runtimeInstanceId, phase: $phase)';
}


}

/// @nodoc
abstract mixin class $StartupStateStartingCopyWith<$Res> implements $StartupStateCopyWith<$Res> {
  factory $StartupStateStartingCopyWith(StartupStateStarting value, $Res Function(StartupStateStarting) _then) = _$StartupStateStartingCopyWithImpl;
@useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId, StartupPhase? phase
});




}
/// @nodoc
class _$StartupStateStartingCopyWithImpl<$Res>
    implements $StartupStateStartingCopyWith<$Res> {
  _$StartupStateStartingCopyWithImpl(this._self, this._then);

  final StartupStateStarting _self;
  final $Res Function(StartupStateStarting) _then;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,Object? phase = freezed,}) {
  return _then(StartupStateStarting(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as StartupPhase?,
  ));
}


}

/// @nodoc


class StartupStateReady implements StartupState {
  const StartupStateReady({required this.runtimeInstanceId});


 final  RuntimeInstanceId runtimeInstanceId;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupStateReadyCopyWith<StartupStateReady> get copyWith => _$StartupStateReadyCopyWithImpl<StartupStateReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupStateReady&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId);

@override
String toString() {
  return 'StartupState.ready(runtimeInstanceId: $runtimeInstanceId)';
}


}

/// @nodoc
abstract mixin class $StartupStateReadyCopyWith<$Res> implements $StartupStateCopyWith<$Res> {
  factory $StartupStateReadyCopyWith(StartupStateReady value, $Res Function(StartupStateReady) _then) = _$StartupStateReadyCopyWithImpl;
@useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId
});




}
/// @nodoc
class _$StartupStateReadyCopyWithImpl<$Res>
    implements $StartupStateReadyCopyWith<$Res> {
  _$StartupStateReadyCopyWithImpl(this._self, this._then);

  final StartupStateReady _self;
  final $Res Function(StartupStateReady) _then;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,}) {
  return _then(StartupStateReady(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,
  ));
}


}

/// @nodoc


class StartupStateStartupFailed implements StartupState {
  const StartupStateStartupFailed({required this.runtimeInstanceId, required this.failure, required this.recoveryOperation, required this.exportOperation, required this.technicalDetails, required this.openDirectoryOperation});


 final  RuntimeInstanceId runtimeInstanceId;
 final  StartupFailure failure;
 final  RecoveryOperationState recoveryOperation;
 final  ExportOperationState exportOperation;
 final  TechnicalDetailsOperationState technicalDetails;
 final  OpenDirectoryOperationState openDirectoryOperation;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupStateStartupFailedCopyWith<StartupStateStartupFailed> get copyWith => _$StartupStateStartupFailedCopyWithImpl<StartupStateStartupFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupStateStartupFailed&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId)&&(identical(other.failure, failure) || other.failure == failure)&&(identical(other.recoveryOperation, recoveryOperation) || other.recoveryOperation == recoveryOperation)&&(identical(other.exportOperation, exportOperation) || other.exportOperation == exportOperation)&&(identical(other.technicalDetails, technicalDetails) || other.technicalDetails == technicalDetails)&&(identical(other.openDirectoryOperation, openDirectoryOperation) || other.openDirectoryOperation == openDirectoryOperation));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId,failure,recoveryOperation,exportOperation,technicalDetails,openDirectoryOperation);

@override
String toString() {
  return 'StartupState.startupFailed(runtimeInstanceId: $runtimeInstanceId, failure: $failure, recoveryOperation: $recoveryOperation, exportOperation: $exportOperation, technicalDetails: $technicalDetails, openDirectoryOperation: $openDirectoryOperation)';
}


}

/// @nodoc
abstract mixin class $StartupStateStartupFailedCopyWith<$Res> implements $StartupStateCopyWith<$Res> {
  factory $StartupStateStartupFailedCopyWith(StartupStateStartupFailed value, $Res Function(StartupStateStartupFailed) _then) = _$StartupStateStartupFailedCopyWithImpl;
@useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId, StartupFailure failure, RecoveryOperationState recoveryOperation, ExportOperationState exportOperation, TechnicalDetailsOperationState technicalDetails, OpenDirectoryOperationState openDirectoryOperation
});


$StartupFailureCopyWith<$Res> get failure;$RecoveryOperationStateCopyWith<$Res> get recoveryOperation;$ExportOperationStateCopyWith<$Res> get exportOperation;$TechnicalDetailsOperationStateCopyWith<$Res> get technicalDetails;$OpenDirectoryOperationStateCopyWith<$Res> get openDirectoryOperation;

}
/// @nodoc
class _$StartupStateStartupFailedCopyWithImpl<$Res>
    implements $StartupStateStartupFailedCopyWith<$Res> {
  _$StartupStateStartupFailedCopyWithImpl(this._self, this._then);

  final StartupStateStartupFailed _self;
  final $Res Function(StartupStateStartupFailed) _then;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,Object? failure = null,Object? recoveryOperation = null,Object? exportOperation = null,Object? technicalDetails = null,Object? openDirectoryOperation = null,}) {
  return _then(StartupStateStartupFailed(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as StartupFailure,recoveryOperation: null == recoveryOperation ? _self.recoveryOperation : recoveryOperation // ignore: cast_nullable_to_non_nullable
as RecoveryOperationState,exportOperation: null == exportOperation ? _self.exportOperation : exportOperation // ignore: cast_nullable_to_non_nullable
as ExportOperationState,technicalDetails: null == technicalDetails ? _self.technicalDetails : technicalDetails // ignore: cast_nullable_to_non_nullable
as TechnicalDetailsOperationState,openDirectoryOperation: null == openDirectoryOperation ? _self.openDirectoryOperation : openDirectoryOperation // ignore: cast_nullable_to_non_nullable
as OpenDirectoryOperationState,
  ));
}

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartupFailureCopyWith<$Res> get failure {

  return $StartupFailureCopyWith<$Res>(_self.failure, (value) {
    return _then(_self.copyWith(failure: value));
  });
}/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryOperationStateCopyWith<$Res> get recoveryOperation {

  return $RecoveryOperationStateCopyWith<$Res>(_self.recoveryOperation, (value) {
    return _then(_self.copyWith(recoveryOperation: value));
  });
}/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ExportOperationStateCopyWith<$Res> get exportOperation {

  return $ExportOperationStateCopyWith<$Res>(_self.exportOperation, (value) {
    return _then(_self.copyWith(exportOperation: value));
  });
}/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TechnicalDetailsOperationStateCopyWith<$Res> get technicalDetails {

  return $TechnicalDetailsOperationStateCopyWith<$Res>(_self.technicalDetails, (value) {
    return _then(_self.copyWith(technicalDetails: value));
  });
}/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OpenDirectoryOperationStateCopyWith<$Res> get openDirectoryOperation {

  return $OpenDirectoryOperationStateCopyWith<$Res>(_self.openDirectoryOperation, (value) {
    return _then(_self.copyWith(openDirectoryOperation: value));
  });
}
}

/// @nodoc


class StartupStateRuntimeUnavailable implements StartupState {
  const StartupStateRuntimeUnavailable({required this.cause, required this.lastKnownRuntime, required this.reconciliationOperation});


 final  ClientFailure cause;
 final  StartupRuntimeContext? lastKnownRuntime;
 final  ReconciliationOperationState reconciliationOperation;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupStateRuntimeUnavailableCopyWith<StartupStateRuntimeUnavailable> get copyWith => _$StartupStateRuntimeUnavailableCopyWithImpl<StartupStateRuntimeUnavailable>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupStateRuntimeUnavailable&&(identical(other.cause, cause) || other.cause == cause)&&(identical(other.lastKnownRuntime, lastKnownRuntime) || other.lastKnownRuntime == lastKnownRuntime)&&(identical(other.reconciliationOperation, reconciliationOperation) || other.reconciliationOperation == reconciliationOperation));
}


@override
int get hashCode => Object.hash(runtimeType,cause,lastKnownRuntime,reconciliationOperation);

@override
String toString() {
  return 'StartupState.runtimeUnavailable(cause: $cause, lastKnownRuntime: $lastKnownRuntime, reconciliationOperation: $reconciliationOperation)';
}


}

/// @nodoc
abstract mixin class $StartupStateRuntimeUnavailableCopyWith<$Res> implements $StartupStateCopyWith<$Res> {
  factory $StartupStateRuntimeUnavailableCopyWith(StartupStateRuntimeUnavailable value, $Res Function(StartupStateRuntimeUnavailable) _then) = _$StartupStateRuntimeUnavailableCopyWithImpl;
@useResult
$Res call({
 ClientFailure cause, StartupRuntimeContext? lastKnownRuntime, ReconciliationOperationState reconciliationOperation
});


$StartupRuntimeContextCopyWith<$Res>? get lastKnownRuntime;$ReconciliationOperationStateCopyWith<$Res> get reconciliationOperation;

}
/// @nodoc
class _$StartupStateRuntimeUnavailableCopyWithImpl<$Res>
    implements $StartupStateRuntimeUnavailableCopyWith<$Res> {
  _$StartupStateRuntimeUnavailableCopyWithImpl(this._self, this._then);

  final StartupStateRuntimeUnavailable _self;
  final $Res Function(StartupStateRuntimeUnavailable) _then;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cause = null,Object? lastKnownRuntime = freezed,Object? reconciliationOperation = null,}) {
  return _then(StartupStateRuntimeUnavailable(
cause: null == cause ? _self.cause : cause // ignore: cast_nullable_to_non_nullable
as ClientFailure,lastKnownRuntime: freezed == lastKnownRuntime ? _self.lastKnownRuntime : lastKnownRuntime // ignore: cast_nullable_to_non_nullable
as StartupRuntimeContext?,reconciliationOperation: null == reconciliationOperation ? _self.reconciliationOperation : reconciliationOperation // ignore: cast_nullable_to_non_nullable
as ReconciliationOperationState,
  ));
}

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartupRuntimeContextCopyWith<$Res>? get lastKnownRuntime {
    if (_self.lastKnownRuntime == null) {
    return null;
  }

  return $StartupRuntimeContextCopyWith<$Res>(_self.lastKnownRuntime!, (value) {
    return _then(_self.copyWith(lastKnownRuntime: value));
  });
}/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReconciliationOperationStateCopyWith<$Res> get reconciliationOperation {

  return $ReconciliationOperationStateCopyWith<$Res>(_self.reconciliationOperation, (value) {
    return _then(_self.copyWith(reconciliationOperation: value));
  });
}
}

/// @nodoc


class StartupStateShuttingDown implements StartupState {
  const StartupStateShuttingDown({required this.runtimeInstanceId});


 final  RuntimeInstanceId runtimeInstanceId;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupStateShuttingDownCopyWith<StartupStateShuttingDown> get copyWith => _$StartupStateShuttingDownCopyWithImpl<StartupStateShuttingDown>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupStateShuttingDown&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId);

@override
String toString() {
  return 'StartupState.shuttingDown(runtimeInstanceId: $runtimeInstanceId)';
}


}

/// @nodoc
abstract mixin class $StartupStateShuttingDownCopyWith<$Res> implements $StartupStateCopyWith<$Res> {
  factory $StartupStateShuttingDownCopyWith(StartupStateShuttingDown value, $Res Function(StartupStateShuttingDown) _then) = _$StartupStateShuttingDownCopyWithImpl;
@useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId
});




}
/// @nodoc
class _$StartupStateShuttingDownCopyWithImpl<$Res>
    implements $StartupStateShuttingDownCopyWith<$Res> {
  _$StartupStateShuttingDownCopyWithImpl(this._self, this._then);

  final StartupStateShuttingDown _self;
  final $Res Function(StartupStateShuttingDown) _then;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,}) {
  return _then(StartupStateShuttingDown(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,
  ));
}


}

/// @nodoc


class StartupStateStopped implements StartupState {
  const StartupStateStopped({required this.runtimeInstanceId});


 final  RuntimeInstanceId runtimeInstanceId;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupStateStoppedCopyWith<StartupStateStopped> get copyWith => _$StartupStateStoppedCopyWithImpl<StartupStateStopped>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupStateStopped&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId);

@override
String toString() {
  return 'StartupState.stopped(runtimeInstanceId: $runtimeInstanceId)';
}


}

/// @nodoc
abstract mixin class $StartupStateStoppedCopyWith<$Res> implements $StartupStateCopyWith<$Res> {
  factory $StartupStateStoppedCopyWith(StartupStateStopped value, $Res Function(StartupStateStopped) _then) = _$StartupStateStoppedCopyWithImpl;
@useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId
});




}
/// @nodoc
class _$StartupStateStoppedCopyWithImpl<$Res>
    implements $StartupStateStoppedCopyWith<$Res> {
  _$StartupStateStoppedCopyWithImpl(this._self, this._then);

  final StartupStateStopped _self;
  final $Res Function(StartupStateStopped) _then;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,}) {
  return _then(StartupStateStopped(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,
  ));
}


}

// dart format on
