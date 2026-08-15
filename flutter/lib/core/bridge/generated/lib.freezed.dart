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
mixin _$AddLocalLibraryRootResultDto {

 Object get field0;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootResultDto&&const DeepCollectionEquality().equals(other.field0, field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(field0));

@override
String toString() {
  return 'AddLocalLibraryRootResultDto(field0: $field0)';
}


}

/// @nodoc
class $AddLocalLibraryRootResultDtoCopyWith<$Res>  {
$AddLocalLibraryRootResultDtoCopyWith(AddLocalLibraryRootResultDto _, $Res Function(AddLocalLibraryRootResultDto) __);
}


/// Adds pattern-matching-related methods to [AddLocalLibraryRootResultDto].
extension AddLocalLibraryRootResultDtoPatterns on AddLocalLibraryRootResultDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AddLocalLibraryRootResultDto_Added value)?  added,TResult Function( AddLocalLibraryRootResultDto_AlreadyConfigured value)?  alreadyConfigured,TResult Function( AddLocalLibraryRootResultDto_OverlapsExisting value)?  overlapsExisting,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AddLocalLibraryRootResultDto_Added() when added != null:
return added(_that);case AddLocalLibraryRootResultDto_AlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that);case AddLocalLibraryRootResultDto_OverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AddLocalLibraryRootResultDto_Added value)  added,required TResult Function( AddLocalLibraryRootResultDto_AlreadyConfigured value)  alreadyConfigured,required TResult Function( AddLocalLibraryRootResultDto_OverlapsExisting value)  overlapsExisting,}){
final _that = this;
switch (_that) {
case AddLocalLibraryRootResultDto_Added():
return added(_that);case AddLocalLibraryRootResultDto_AlreadyConfigured():
return alreadyConfigured(_that);case AddLocalLibraryRootResultDto_OverlapsExisting():
return overlapsExisting(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AddLocalLibraryRootResultDto_Added value)?  added,TResult? Function( AddLocalLibraryRootResultDto_AlreadyConfigured value)?  alreadyConfigured,TResult? Function( AddLocalLibraryRootResultDto_OverlapsExisting value)?  overlapsExisting,}){
final _that = this;
switch (_that) {
case AddLocalLibraryRootResultDto_Added() when added != null:
return added(_that);case AddLocalLibraryRootResultDto_AlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that);case AddLocalLibraryRootResultDto_OverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( LibraryRootDto field0)?  added,TResult Function( String field0)?  alreadyConfigured,TResult Function( String field0,  RootRelationshipDto field1)?  overlapsExisting,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AddLocalLibraryRootResultDto_Added() when added != null:
return added(_that.field0);case AddLocalLibraryRootResultDto_AlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that.field0);case AddLocalLibraryRootResultDto_OverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that.field0,_that.field1);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( LibraryRootDto field0)  added,required TResult Function( String field0)  alreadyConfigured,required TResult Function( String field0,  RootRelationshipDto field1)  overlapsExisting,}) {final _that = this;
switch (_that) {
case AddLocalLibraryRootResultDto_Added():
return added(_that.field0);case AddLocalLibraryRootResultDto_AlreadyConfigured():
return alreadyConfigured(_that.field0);case AddLocalLibraryRootResultDto_OverlapsExisting():
return overlapsExisting(_that.field0,_that.field1);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( LibraryRootDto field0)?  added,TResult? Function( String field0)?  alreadyConfigured,TResult? Function( String field0,  RootRelationshipDto field1)?  overlapsExisting,}) {final _that = this;
switch (_that) {
case AddLocalLibraryRootResultDto_Added() when added != null:
return added(_that.field0);case AddLocalLibraryRootResultDto_AlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that.field0);case AddLocalLibraryRootResultDto_OverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that.field0,_that.field1);case _:
  return null;

}
}

}

/// @nodoc


class AddLocalLibraryRootResultDto_Added extends AddLocalLibraryRootResultDto {
  const AddLocalLibraryRootResultDto_Added(this.field0): super._();


@override final  LibraryRootDto field0;

/// Create a copy of AddLocalLibraryRootResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLocalLibraryRootResultDto_AddedCopyWith<AddLocalLibraryRootResultDto_Added> get copyWith => _$AddLocalLibraryRootResultDto_AddedCopyWithImpl<AddLocalLibraryRootResultDto_Added>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootResultDto_Added&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AddLocalLibraryRootResultDto.added(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AddLocalLibraryRootResultDto_AddedCopyWith<$Res> implements $AddLocalLibraryRootResultDtoCopyWith<$Res> {
  factory $AddLocalLibraryRootResultDto_AddedCopyWith(AddLocalLibraryRootResultDto_Added value, $Res Function(AddLocalLibraryRootResultDto_Added) _then) = _$AddLocalLibraryRootResultDto_AddedCopyWithImpl;
@useResult
$Res call({
 LibraryRootDto field0
});




}
/// @nodoc
class _$AddLocalLibraryRootResultDto_AddedCopyWithImpl<$Res>
    implements $AddLocalLibraryRootResultDto_AddedCopyWith<$Res> {
  _$AddLocalLibraryRootResultDto_AddedCopyWithImpl(this._self, this._then);

  final AddLocalLibraryRootResultDto_Added _self;
  final $Res Function(AddLocalLibraryRootResultDto_Added) _then;

/// Create a copy of AddLocalLibraryRootResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AddLocalLibraryRootResultDto_Added(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as LibraryRootDto,
  ));
}


}

/// @nodoc


class AddLocalLibraryRootResultDto_AlreadyConfigured extends AddLocalLibraryRootResultDto {
  const AddLocalLibraryRootResultDto_AlreadyConfigured(this.field0): super._();


@override final  String field0;

/// Create a copy of AddLocalLibraryRootResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLocalLibraryRootResultDto_AlreadyConfiguredCopyWith<AddLocalLibraryRootResultDto_AlreadyConfigured> get copyWith => _$AddLocalLibraryRootResultDto_AlreadyConfiguredCopyWithImpl<AddLocalLibraryRootResultDto_AlreadyConfigured>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootResultDto_AlreadyConfigured&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AddLocalLibraryRootResultDto.alreadyConfigured(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AddLocalLibraryRootResultDto_AlreadyConfiguredCopyWith<$Res> implements $AddLocalLibraryRootResultDtoCopyWith<$Res> {
  factory $AddLocalLibraryRootResultDto_AlreadyConfiguredCopyWith(AddLocalLibraryRootResultDto_AlreadyConfigured value, $Res Function(AddLocalLibraryRootResultDto_AlreadyConfigured) _then) = _$AddLocalLibraryRootResultDto_AlreadyConfiguredCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$AddLocalLibraryRootResultDto_AlreadyConfiguredCopyWithImpl<$Res>
    implements $AddLocalLibraryRootResultDto_AlreadyConfiguredCopyWith<$Res> {
  _$AddLocalLibraryRootResultDto_AlreadyConfiguredCopyWithImpl(this._self, this._then);

  final AddLocalLibraryRootResultDto_AlreadyConfigured _self;
  final $Res Function(AddLocalLibraryRootResultDto_AlreadyConfigured) _then;

/// Create a copy of AddLocalLibraryRootResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AddLocalLibraryRootResultDto_AlreadyConfigured(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AddLocalLibraryRootResultDto_OverlapsExisting extends AddLocalLibraryRootResultDto {
  const AddLocalLibraryRootResultDto_OverlapsExisting(this.field0, this.field1): super._();


@override final  String field0;
 final  RootRelationshipDto field1;

/// Create a copy of AddLocalLibraryRootResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLocalLibraryRootResultDto_OverlapsExistingCopyWith<AddLocalLibraryRootResultDto_OverlapsExisting> get copyWith => _$AddLocalLibraryRootResultDto_OverlapsExistingCopyWithImpl<AddLocalLibraryRootResultDto_OverlapsExisting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootResultDto_OverlapsExisting&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1));
}


@override
int get hashCode => Object.hash(runtimeType,field0,field1);

@override
String toString() {
  return 'AddLocalLibraryRootResultDto.overlapsExisting(field0: $field0, field1: $field1)';
}


}

/// @nodoc
abstract mixin class $AddLocalLibraryRootResultDto_OverlapsExistingCopyWith<$Res> implements $AddLocalLibraryRootResultDtoCopyWith<$Res> {
  factory $AddLocalLibraryRootResultDto_OverlapsExistingCopyWith(AddLocalLibraryRootResultDto_OverlapsExisting value, $Res Function(AddLocalLibraryRootResultDto_OverlapsExisting) _then) = _$AddLocalLibraryRootResultDto_OverlapsExistingCopyWithImpl;
@useResult
$Res call({
 String field0, RootRelationshipDto field1
});




}
/// @nodoc
class _$AddLocalLibraryRootResultDto_OverlapsExistingCopyWithImpl<$Res>
    implements $AddLocalLibraryRootResultDto_OverlapsExistingCopyWith<$Res> {
  _$AddLocalLibraryRootResultDto_OverlapsExistingCopyWithImpl(this._self, this._then);

  final AddLocalLibraryRootResultDto_OverlapsExisting _self;
  final $Res Function(AddLocalLibraryRootResultDto_OverlapsExisting) _then;

/// Create a copy of AddLocalLibraryRootResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,}) {
  return _then(AddLocalLibraryRootResultDto_OverlapsExisting(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as RootRelationshipDto,
  ));
}


}

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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RuntimeEventPayloadDto_RuntimeStateChanged value)?  runtimeStateChanged,TResult Function( RuntimeEventPayloadDto_StartupFailed value)?  startupFailed,TResult Function( RuntimeEventPayloadDto_AppearanceSettingsChanged value)?  appearanceSettingsChanged,TResult Function( RuntimeEventPayloadDto_LibraryRootsChanged value)?  libraryRootsChanged,TResult Function( RuntimeEventPayloadDto_LibraryRootChanged value)?  libraryRootChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that);case RuntimeEventPayloadDto_StartupFailed() when startupFailed != null:
return startupFailed(_that);case RuntimeEventPayloadDto_AppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged(_that);case RuntimeEventPayloadDto_LibraryRootsChanged() when libraryRootsChanged != null:
return libraryRootsChanged(_that);case RuntimeEventPayloadDto_LibraryRootChanged() when libraryRootChanged != null:
return libraryRootChanged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RuntimeEventPayloadDto_RuntimeStateChanged value)  runtimeStateChanged,required TResult Function( RuntimeEventPayloadDto_StartupFailed value)  startupFailed,required TResult Function( RuntimeEventPayloadDto_AppearanceSettingsChanged value)  appearanceSettingsChanged,required TResult Function( RuntimeEventPayloadDto_LibraryRootsChanged value)  libraryRootsChanged,required TResult Function( RuntimeEventPayloadDto_LibraryRootChanged value)  libraryRootChanged,}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged():
return runtimeStateChanged(_that);case RuntimeEventPayloadDto_StartupFailed():
return startupFailed(_that);case RuntimeEventPayloadDto_AppearanceSettingsChanged():
return appearanceSettingsChanged(_that);case RuntimeEventPayloadDto_LibraryRootsChanged():
return libraryRootsChanged(_that);case RuntimeEventPayloadDto_LibraryRootChanged():
return libraryRootChanged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RuntimeEventPayloadDto_RuntimeStateChanged value)?  runtimeStateChanged,TResult? Function( RuntimeEventPayloadDto_StartupFailed value)?  startupFailed,TResult? Function( RuntimeEventPayloadDto_AppearanceSettingsChanged value)?  appearanceSettingsChanged,TResult? Function( RuntimeEventPayloadDto_LibraryRootsChanged value)?  libraryRootsChanged,TResult? Function( RuntimeEventPayloadDto_LibraryRootChanged value)?  libraryRootChanged,}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that);case RuntimeEventPayloadDto_StartupFailed() when startupFailed != null:
return startupFailed(_that);case RuntimeEventPayloadDto_AppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged(_that);case RuntimeEventPayloadDto_LibraryRootsChanged() when libraryRootsChanged != null:
return libraryRootsChanged(_that);case RuntimeEventPayloadDto_LibraryRootChanged() when libraryRootChanged != null:
return libraryRootChanged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( RuntimeLifecycleDto lifecycle)?  runtimeStateChanged,TResult Function( StartupPhaseDto phase)?  startupFailed,TResult Function()?  appearanceSettingsChanged,TResult Function()?  libraryRootsChanged,TResult Function( String libraryRootId)?  libraryRootChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadDto_StartupFailed() when startupFailed != null:
return startupFailed(_that.phase);case RuntimeEventPayloadDto_AppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged();case RuntimeEventPayloadDto_LibraryRootsChanged() when libraryRootsChanged != null:
return libraryRootsChanged();case RuntimeEventPayloadDto_LibraryRootChanged() when libraryRootChanged != null:
return libraryRootChanged(_that.libraryRootId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( RuntimeLifecycleDto lifecycle)  runtimeStateChanged,required TResult Function( StartupPhaseDto phase)  startupFailed,required TResult Function()  appearanceSettingsChanged,required TResult Function()  libraryRootsChanged,required TResult Function( String libraryRootId)  libraryRootChanged,}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged():
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadDto_StartupFailed():
return startupFailed(_that.phase);case RuntimeEventPayloadDto_AppearanceSettingsChanged():
return appearanceSettingsChanged();case RuntimeEventPayloadDto_LibraryRootsChanged():
return libraryRootsChanged();case RuntimeEventPayloadDto_LibraryRootChanged():
return libraryRootChanged(_that.libraryRootId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( RuntimeLifecycleDto lifecycle)?  runtimeStateChanged,TResult? Function( StartupPhaseDto phase)?  startupFailed,TResult? Function()?  appearanceSettingsChanged,TResult? Function()?  libraryRootsChanged,TResult? Function( String libraryRootId)?  libraryRootChanged,}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadDto_StartupFailed() when startupFailed != null:
return startupFailed(_that.phase);case RuntimeEventPayloadDto_AppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged();case RuntimeEventPayloadDto_LibraryRootsChanged() when libraryRootsChanged != null:
return libraryRootsChanged();case RuntimeEventPayloadDto_LibraryRootChanged() when libraryRootChanged != null:
return libraryRootChanged(_that.libraryRootId);case _:
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




/// @nodoc


class RuntimeEventPayloadDto_LibraryRootsChanged extends RuntimeEventPayloadDto {
  const RuntimeEventPayloadDto_LibraryRootsChanged(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadDto_LibraryRootsChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RuntimeEventPayloadDto.libraryRootsChanged()';
}


}




/// @nodoc


class RuntimeEventPayloadDto_LibraryRootChanged extends RuntimeEventPayloadDto {
  const RuntimeEventPayloadDto_LibraryRootChanged({required this.libraryRootId}): super._();


 final  String libraryRootId;

/// Create a copy of RuntimeEventPayloadDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeEventPayloadDto_LibraryRootChangedCopyWith<RuntimeEventPayloadDto_LibraryRootChanged> get copyWith => _$RuntimeEventPayloadDto_LibraryRootChangedCopyWithImpl<RuntimeEventPayloadDto_LibraryRootChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadDto_LibraryRootChanged&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId);

@override
String toString() {
  return 'RuntimeEventPayloadDto.libraryRootChanged(libraryRootId: $libraryRootId)';
}


}

/// @nodoc
abstract mixin class $RuntimeEventPayloadDto_LibraryRootChangedCopyWith<$Res> implements $RuntimeEventPayloadDtoCopyWith<$Res> {
  factory $RuntimeEventPayloadDto_LibraryRootChangedCopyWith(RuntimeEventPayloadDto_LibraryRootChanged value, $Res Function(RuntimeEventPayloadDto_LibraryRootChanged) _then) = _$RuntimeEventPayloadDto_LibraryRootChangedCopyWithImpl;
@useResult
$Res call({
 String libraryRootId
});




}
/// @nodoc
class _$RuntimeEventPayloadDto_LibraryRootChangedCopyWithImpl<$Res>
    implements $RuntimeEventPayloadDto_LibraryRootChangedCopyWith<$Res> {
  _$RuntimeEventPayloadDto_LibraryRootChangedCopyWithImpl(this._self, this._then);

  final RuntimeEventPayloadDto_LibraryRootChanged _self;
  final $Res Function(RuntimeEventPayloadDto_LibraryRootChanged) _then;

/// Create a copy of RuntimeEventPayloadDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? libraryRootId = null,}) {
  return _then(RuntimeEventPayloadDto_LibraryRootChanged(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
