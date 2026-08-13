// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lib.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RuntimeEventPayloadDto {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadDto);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RuntimeEventPayloadDto()';
}


}

/// @nodoc
class $RuntimeEventPayloadDtoCopyWith<$Res>  {
$RuntimeEventPayloadDtoCopyWith(RuntimeEventPayloadDto _, $Res Function(RuntimeEventPayloadDto) __);
}


/// Adds pattern-matching-related methods to [RuntimeEventPayloadDto].
extension RuntimeEventPayloadDtoPatterns on RuntimeEventPayloadDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RuntimeEventPayloadDto_RuntimeStateChanged value)?  runtimeStateChanged,TResult Function( RuntimeEventPayloadDto_StartupFailed value)?  startupFailed,TResult Function( RuntimeEventPayloadDto_AppearanceSettingsChanged value)?  appearanceSettingsChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that);case RuntimeEventPayloadDto_StartupFailed() when startupFailed != null:
return startupFailed(_that);case RuntimeEventPayloadDto_AppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RuntimeEventPayloadDto_RuntimeStateChanged value)  runtimeStateChanged,required TResult Function( RuntimeEventPayloadDto_StartupFailed value)  startupFailed,required TResult Function( RuntimeEventPayloadDto_AppearanceSettingsChanged value)  appearanceSettingsChanged,}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged():
return runtimeStateChanged(_that);case RuntimeEventPayloadDto_StartupFailed():
return startupFailed(_that);case RuntimeEventPayloadDto_AppearanceSettingsChanged():
return appearanceSettingsChanged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RuntimeEventPayloadDto_RuntimeStateChanged value)?  runtimeStateChanged,TResult? Function( RuntimeEventPayloadDto_StartupFailed value)?  startupFailed,TResult? Function( RuntimeEventPayloadDto_AppearanceSettingsChanged value)?  appearanceSettingsChanged,}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that);case RuntimeEventPayloadDto_StartupFailed() when startupFailed != null:
return startupFailed(_that);case RuntimeEventPayloadDto_AppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( RuntimeLifecycleDto lifecycle)?  runtimeStateChanged,TResult Function( StartupPhaseDto phase)?  startupFailed,TResult Function()?  appearanceSettingsChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadDto_StartupFailed() when startupFailed != null:
return startupFailed(_that.phase);case RuntimeEventPayloadDto_AppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( RuntimeLifecycleDto lifecycle)  runtimeStateChanged,required TResult Function( StartupPhaseDto phase)  startupFailed,required TResult Function()  appearanceSettingsChanged,}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged():
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadDto_StartupFailed():
return startupFailed(_that.phase);case RuntimeEventPayloadDto_AppearanceSettingsChanged():
return appearanceSettingsChanged();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( RuntimeLifecycleDto lifecycle)?  runtimeStateChanged,TResult? Function( StartupPhaseDto phase)?  startupFailed,TResult? Function()?  appearanceSettingsChanged,}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadDto_StartupFailed() when startupFailed != null:
return startupFailed(_that.phase);case RuntimeEventPayloadDto_AppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged();case _:
  return null;

}
}

}

/// @nodoc


class RuntimeEventPayloadDto_RuntimeStateChanged extends RuntimeEventPayloadDto {
  const RuntimeEventPayloadDto_RuntimeStateChanged({required this.lifecycle}): super._();


 final  RuntimeLifecycleDto lifecycle;

/// Create a copy of RuntimeEventPayloadDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeEventPayloadDto_RuntimeStateChangedCopyWith<RuntimeEventPayloadDto_RuntimeStateChanged> get copyWith => _$RuntimeEventPayloadDto_RuntimeStateChangedCopyWithImpl<RuntimeEventPayloadDto_RuntimeStateChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadDto_RuntimeStateChanged&&(identical(other.lifecycle, lifecycle) || other.lifecycle == lifecycle));
}


@override
int get hashCode => Object.hash(runtimeType,lifecycle);

@override
String toString() {
  return 'RuntimeEventPayloadDto.runtimeStateChanged(lifecycle: $lifecycle)';
}


}

/// @nodoc
abstract mixin class $RuntimeEventPayloadDto_RuntimeStateChangedCopyWith<$Res> implements $RuntimeEventPayloadDtoCopyWith<$Res> {
  factory $RuntimeEventPayloadDto_RuntimeStateChangedCopyWith(RuntimeEventPayloadDto_RuntimeStateChanged value, $Res Function(RuntimeEventPayloadDto_RuntimeStateChanged) _then) = _$RuntimeEventPayloadDto_RuntimeStateChangedCopyWithImpl;
@useResult
$Res call({
 RuntimeLifecycleDto lifecycle
});




}
/// @nodoc
class _$RuntimeEventPayloadDto_RuntimeStateChangedCopyWithImpl<$Res>
    implements $RuntimeEventPayloadDto_RuntimeStateChangedCopyWith<$Res> {
  _$RuntimeEventPayloadDto_RuntimeStateChangedCopyWithImpl(this._self, this._then);

  final RuntimeEventPayloadDto_RuntimeStateChanged _self;
  final $Res Function(RuntimeEventPayloadDto_RuntimeStateChanged) _then;

/// Create a copy of RuntimeEventPayloadDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? lifecycle = null,}) {
  return _then(RuntimeEventPayloadDto_RuntimeStateChanged(
lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as RuntimeLifecycleDto,
  ));
}


}

/// @nodoc


class RuntimeEventPayloadDto_StartupFailed extends RuntimeEventPayloadDto {
  const RuntimeEventPayloadDto_StartupFailed({required this.phase}): super._();


 final  StartupPhaseDto phase;

/// Create a copy of RuntimeEventPayloadDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeEventPayloadDto_StartupFailedCopyWith<RuntimeEventPayloadDto_StartupFailed> get copyWith => _$RuntimeEventPayloadDto_StartupFailedCopyWithImpl<RuntimeEventPayloadDto_StartupFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadDto_StartupFailed&&(identical(other.phase, phase) || other.phase == phase));
}


@override
int get hashCode => Object.hash(runtimeType,phase);

@override
String toString() {
  return 'RuntimeEventPayloadDto.startupFailed(phase: $phase)';
}


}

/// @nodoc
abstract mixin class $RuntimeEventPayloadDto_StartupFailedCopyWith<$Res> implements $RuntimeEventPayloadDtoCopyWith<$Res> {
  factory $RuntimeEventPayloadDto_StartupFailedCopyWith(RuntimeEventPayloadDto_StartupFailed value, $Res Function(RuntimeEventPayloadDto_StartupFailed) _then) = _$RuntimeEventPayloadDto_StartupFailedCopyWithImpl;
@useResult
$Res call({
 StartupPhaseDto phase
});




}
/// @nodoc
class _$RuntimeEventPayloadDto_StartupFailedCopyWithImpl<$Res>
    implements $RuntimeEventPayloadDto_StartupFailedCopyWith<$Res> {
  _$RuntimeEventPayloadDto_StartupFailedCopyWithImpl(this._self, this._then);

  final RuntimeEventPayloadDto_StartupFailed _self;
  final $Res Function(RuntimeEventPayloadDto_StartupFailed) _then;

/// Create a copy of RuntimeEventPayloadDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? phase = null,}) {
  return _then(RuntimeEventPayloadDto_StartupFailed(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as StartupPhaseDto,
  ));
}


}

/// @nodoc


class RuntimeEventPayloadDto_AppearanceSettingsChanged extends RuntimeEventPayloadDto {
  const RuntimeEventPayloadDto_AppearanceSettingsChanged(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadDto_AppearanceSettingsChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RuntimeEventPayloadDto.appearanceSettingsChanged()';
}


}




// dart format on
