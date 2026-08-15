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
mixin _$AddLocalLibraryRootAndScanResultDto {

 Object get field0;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootAndScanResultDto&&const DeepCollectionEquality().equals(other.field0, field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(field0));

@override
String toString() {
  return 'AddLocalLibraryRootAndScanResultDto(field0: $field0)';
}


}

/// @nodoc
class $AddLocalLibraryRootAndScanResultDtoCopyWith<$Res>  {
$AddLocalLibraryRootAndScanResultDtoCopyWith(AddLocalLibraryRootAndScanResultDto _, $Res Function(AddLocalLibraryRootAndScanResultDto) __);
}


/// Adds pattern-matching-related methods to [AddLocalLibraryRootAndScanResultDto].
extension AddLocalLibraryRootAndScanResultDtoPatterns on AddLocalLibraryRootAndScanResultDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted value)?  addedAndScanAdmitted,TResult Function( AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted value)?  addedButScanNotAdmitted,TResult Function( AddLocalLibraryRootAndScanResultDto_AlreadyConfigured value)?  alreadyConfigured,TResult Function( AddLocalLibraryRootAndScanResultDto_OverlapsExisting value)?  overlapsExisting,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted() when addedAndScanAdmitted != null:
return addedAndScanAdmitted(_that);case AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted() when addedButScanNotAdmitted != null:
return addedButScanNotAdmitted(_that);case AddLocalLibraryRootAndScanResultDto_AlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that);case AddLocalLibraryRootAndScanResultDto_OverlapsExisting() when overlapsExisting != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted value)  addedAndScanAdmitted,required TResult Function( AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted value)  addedButScanNotAdmitted,required TResult Function( AddLocalLibraryRootAndScanResultDto_AlreadyConfigured value)  alreadyConfigured,required TResult Function( AddLocalLibraryRootAndScanResultDto_OverlapsExisting value)  overlapsExisting,}){
final _that = this;
switch (_that) {
case AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted():
return addedAndScanAdmitted(_that);case AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted():
return addedButScanNotAdmitted(_that);case AddLocalLibraryRootAndScanResultDto_AlreadyConfigured():
return alreadyConfigured(_that);case AddLocalLibraryRootAndScanResultDto_OverlapsExisting():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted value)?  addedAndScanAdmitted,TResult? Function( AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted value)?  addedButScanNotAdmitted,TResult? Function( AddLocalLibraryRootAndScanResultDto_AlreadyConfigured value)?  alreadyConfigured,TResult? Function( AddLocalLibraryRootAndScanResultDto_OverlapsExisting value)?  overlapsExisting,}){
final _that = this;
switch (_that) {
case AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted() when addedAndScanAdmitted != null:
return addedAndScanAdmitted(_that);case AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted() when addedButScanNotAdmitted != null:
return addedButScanNotAdmitted(_that);case AddLocalLibraryRootAndScanResultDto_AlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that);case AddLocalLibraryRootAndScanResultDto_OverlapsExisting() when overlapsExisting != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( LibraryRootDto field0,  OperationHandleDto field1)?  addedAndScanAdmitted,TResult Function( LibraryRootDto field0,  LibraryScanChildAdmissionIssueDto field1)?  addedButScanNotAdmitted,TResult Function( String field0)?  alreadyConfigured,TResult Function( String field0,  RootRelationshipDto field1)?  overlapsExisting,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted() when addedAndScanAdmitted != null:
return addedAndScanAdmitted(_that.field0,_that.field1);case AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted() when addedButScanNotAdmitted != null:
return addedButScanNotAdmitted(_that.field0,_that.field1);case AddLocalLibraryRootAndScanResultDto_AlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that.field0);case AddLocalLibraryRootAndScanResultDto_OverlapsExisting() when overlapsExisting != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( LibraryRootDto field0,  OperationHandleDto field1)  addedAndScanAdmitted,required TResult Function( LibraryRootDto field0,  LibraryScanChildAdmissionIssueDto field1)  addedButScanNotAdmitted,required TResult Function( String field0)  alreadyConfigured,required TResult Function( String field0,  RootRelationshipDto field1)  overlapsExisting,}) {final _that = this;
switch (_that) {
case AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted():
return addedAndScanAdmitted(_that.field0,_that.field1);case AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted():
return addedButScanNotAdmitted(_that.field0,_that.field1);case AddLocalLibraryRootAndScanResultDto_AlreadyConfigured():
return alreadyConfigured(_that.field0);case AddLocalLibraryRootAndScanResultDto_OverlapsExisting():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( LibraryRootDto field0,  OperationHandleDto field1)?  addedAndScanAdmitted,TResult? Function( LibraryRootDto field0,  LibraryScanChildAdmissionIssueDto field1)?  addedButScanNotAdmitted,TResult? Function( String field0)?  alreadyConfigured,TResult? Function( String field0,  RootRelationshipDto field1)?  overlapsExisting,}) {final _that = this;
switch (_that) {
case AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted() when addedAndScanAdmitted != null:
return addedAndScanAdmitted(_that.field0,_that.field1);case AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted() when addedButScanNotAdmitted != null:
return addedButScanNotAdmitted(_that.field0,_that.field1);case AddLocalLibraryRootAndScanResultDto_AlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that.field0);case AddLocalLibraryRootAndScanResultDto_OverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that.field0,_that.field1);case _:
  return null;

}
}

}

/// @nodoc


class AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted extends AddLocalLibraryRootAndScanResultDto {
  const AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted(this.field0, this.field1): super._();


@override final  LibraryRootDto field0;
 final  OperationHandleDto field1;

/// Create a copy of AddLocalLibraryRootAndScanResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmittedCopyWith<AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted> get copyWith => _$AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmittedCopyWithImpl<AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1));
}


@override
int get hashCode => Object.hash(runtimeType,field0,field1);

@override
String toString() {
  return 'AddLocalLibraryRootAndScanResultDto.addedAndScanAdmitted(field0: $field0, field1: $field1)';
}


}

/// @nodoc
abstract mixin class $AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmittedCopyWith<$Res> implements $AddLocalLibraryRootAndScanResultDtoCopyWith<$Res> {
  factory $AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmittedCopyWith(AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted value, $Res Function(AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted) _then) = _$AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmittedCopyWithImpl;
@useResult
$Res call({
 LibraryRootDto field0, OperationHandleDto field1
});




}
/// @nodoc
class _$AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmittedCopyWithImpl<$Res>
    implements $AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmittedCopyWith<$Res> {
  _$AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmittedCopyWithImpl(this._self, this._then);

  final AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted _self;
  final $Res Function(AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted) _then;

/// Create a copy of AddLocalLibraryRootAndScanResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,}) {
  return _then(AddLocalLibraryRootAndScanResultDto_AddedAndScanAdmitted(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as LibraryRootDto,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as OperationHandleDto,
  ));
}


}

/// @nodoc


class AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted extends AddLocalLibraryRootAndScanResultDto {
  const AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted(this.field0, this.field1): super._();


@override final  LibraryRootDto field0;
 final  LibraryScanChildAdmissionIssueDto field1;

/// Create a copy of AddLocalLibraryRootAndScanResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmittedCopyWith<AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted> get copyWith => _$AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmittedCopyWithImpl<AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1));
}


@override
int get hashCode => Object.hash(runtimeType,field0,field1);

@override
String toString() {
  return 'AddLocalLibraryRootAndScanResultDto.addedButScanNotAdmitted(field0: $field0, field1: $field1)';
}


}

/// @nodoc
abstract mixin class $AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmittedCopyWith<$Res> implements $AddLocalLibraryRootAndScanResultDtoCopyWith<$Res> {
  factory $AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmittedCopyWith(AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted value, $Res Function(AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted) _then) = _$AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmittedCopyWithImpl;
@useResult
$Res call({
 LibraryRootDto field0, LibraryScanChildAdmissionIssueDto field1
});


$LibraryScanChildAdmissionIssueDtoCopyWith<$Res> get field1;

}
/// @nodoc
class _$AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmittedCopyWithImpl<$Res>
    implements $AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmittedCopyWith<$Res> {
  _$AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmittedCopyWithImpl(this._self, this._then);

  final AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted _self;
  final $Res Function(AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted) _then;

/// Create a copy of AddLocalLibraryRootAndScanResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,}) {
  return _then(AddLocalLibraryRootAndScanResultDto_AddedButScanNotAdmitted(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as LibraryRootDto,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as LibraryScanChildAdmissionIssueDto,
  ));
}

/// Create a copy of AddLocalLibraryRootAndScanResultDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LibraryScanChildAdmissionIssueDtoCopyWith<$Res> get field1 {

  return $LibraryScanChildAdmissionIssueDtoCopyWith<$Res>(_self.field1, (value) {
    return _then(_self.copyWith(field1: value));
  });
}
}

/// @nodoc


class AddLocalLibraryRootAndScanResultDto_AlreadyConfigured extends AddLocalLibraryRootAndScanResultDto {
  const AddLocalLibraryRootAndScanResultDto_AlreadyConfigured(this.field0): super._();


@override final  String field0;

/// Create a copy of AddLocalLibraryRootAndScanResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLocalLibraryRootAndScanResultDto_AlreadyConfiguredCopyWith<AddLocalLibraryRootAndScanResultDto_AlreadyConfigured> get copyWith => _$AddLocalLibraryRootAndScanResultDto_AlreadyConfiguredCopyWithImpl<AddLocalLibraryRootAndScanResultDto_AlreadyConfigured>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootAndScanResultDto_AlreadyConfigured&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AddLocalLibraryRootAndScanResultDto.alreadyConfigured(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AddLocalLibraryRootAndScanResultDto_AlreadyConfiguredCopyWith<$Res> implements $AddLocalLibraryRootAndScanResultDtoCopyWith<$Res> {
  factory $AddLocalLibraryRootAndScanResultDto_AlreadyConfiguredCopyWith(AddLocalLibraryRootAndScanResultDto_AlreadyConfigured value, $Res Function(AddLocalLibraryRootAndScanResultDto_AlreadyConfigured) _then) = _$AddLocalLibraryRootAndScanResultDto_AlreadyConfiguredCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$AddLocalLibraryRootAndScanResultDto_AlreadyConfiguredCopyWithImpl<$Res>
    implements $AddLocalLibraryRootAndScanResultDto_AlreadyConfiguredCopyWith<$Res> {
  _$AddLocalLibraryRootAndScanResultDto_AlreadyConfiguredCopyWithImpl(this._self, this._then);

  final AddLocalLibraryRootAndScanResultDto_AlreadyConfigured _self;
  final $Res Function(AddLocalLibraryRootAndScanResultDto_AlreadyConfigured) _then;

/// Create a copy of AddLocalLibraryRootAndScanResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AddLocalLibraryRootAndScanResultDto_AlreadyConfigured(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AddLocalLibraryRootAndScanResultDto_OverlapsExisting extends AddLocalLibraryRootAndScanResultDto {
  const AddLocalLibraryRootAndScanResultDto_OverlapsExisting(this.field0, this.field1): super._();


@override final  String field0;
 final  RootRelationshipDto field1;

/// Create a copy of AddLocalLibraryRootAndScanResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLocalLibraryRootAndScanResultDto_OverlapsExistingCopyWith<AddLocalLibraryRootAndScanResultDto_OverlapsExisting> get copyWith => _$AddLocalLibraryRootAndScanResultDto_OverlapsExistingCopyWithImpl<AddLocalLibraryRootAndScanResultDto_OverlapsExisting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootAndScanResultDto_OverlapsExisting&&(identical(other.field0, field0) || other.field0 == field0)&&(identical(other.field1, field1) || other.field1 == field1));
}


@override
int get hashCode => Object.hash(runtimeType,field0,field1);

@override
String toString() {
  return 'AddLocalLibraryRootAndScanResultDto.overlapsExisting(field0: $field0, field1: $field1)';
}


}

/// @nodoc
abstract mixin class $AddLocalLibraryRootAndScanResultDto_OverlapsExistingCopyWith<$Res> implements $AddLocalLibraryRootAndScanResultDtoCopyWith<$Res> {
  factory $AddLocalLibraryRootAndScanResultDto_OverlapsExistingCopyWith(AddLocalLibraryRootAndScanResultDto_OverlapsExisting value, $Res Function(AddLocalLibraryRootAndScanResultDto_OverlapsExisting) _then) = _$AddLocalLibraryRootAndScanResultDto_OverlapsExistingCopyWithImpl;
@useResult
$Res call({
 String field0, RootRelationshipDto field1
});




}
/// @nodoc
class _$AddLocalLibraryRootAndScanResultDto_OverlapsExistingCopyWithImpl<$Res>
    implements $AddLocalLibraryRootAndScanResultDto_OverlapsExistingCopyWith<$Res> {
  _$AddLocalLibraryRootAndScanResultDto_OverlapsExistingCopyWithImpl(this._self, this._then);

  final AddLocalLibraryRootAndScanResultDto_OverlapsExisting _self;
  final $Res Function(AddLocalLibraryRootAndScanResultDto_OverlapsExisting) _then;

/// Create a copy of AddLocalLibraryRootAndScanResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,Object? field1 = null,}) {
  return _then(AddLocalLibraryRootAndScanResultDto_OverlapsExisting(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,null == field1 ? _self.field1 : field1 // ignore: cast_nullable_to_non_nullable
as RootRelationshipDto,
  ));
}


}

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
mixin _$LibraryScanAllRequestResolutionDto {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanAllRequestResolutionDto);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LibraryScanAllRequestResolutionDto()';
}


}

/// @nodoc
class $LibraryScanAllRequestResolutionDtoCopyWith<$Res>  {
$LibraryScanAllRequestResolutionDtoCopyWith(LibraryScanAllRequestResolutionDto _, $Res Function(LibraryScanAllRequestResolutionDto) __);
}


/// Adds pattern-matching-related methods to [LibraryScanAllRequestResolutionDto].
extension LibraryScanAllRequestResolutionDtoPatterns on LibraryScanAllRequestResolutionDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LibraryScanAllRequestResolutionDto_Admitted value)?  admitted,TResult Function( LibraryScanAllRequestResolutionDto_NothingAdmitted value)?  nothingAdmitted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LibraryScanAllRequestResolutionDto_Admitted() when admitted != null:
return admitted(_that);case LibraryScanAllRequestResolutionDto_NothingAdmitted() when nothingAdmitted != null:
return nothingAdmitted(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LibraryScanAllRequestResolutionDto_Admitted value)  admitted,required TResult Function( LibraryScanAllRequestResolutionDto_NothingAdmitted value)  nothingAdmitted,}){
final _that = this;
switch (_that) {
case LibraryScanAllRequestResolutionDto_Admitted():
return admitted(_that);case LibraryScanAllRequestResolutionDto_NothingAdmitted():
return nothingAdmitted(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LibraryScanAllRequestResolutionDto_Admitted value)?  admitted,TResult? Function( LibraryScanAllRequestResolutionDto_NothingAdmitted value)?  nothingAdmitted,}){
final _that = this;
switch (_that) {
case LibraryScanAllRequestResolutionDto_Admitted() when admitted != null:
return admitted(_that);case LibraryScanAllRequestResolutionDto_NothingAdmitted() when nothingAdmitted != null:
return nothingAdmitted(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OperationHandleDto operationHandle,  List<String> admittedRoots,  List<LibraryScanAdmissionExclusionDto> exclusions)?  admitted,TResult Function()?  nothingAdmitted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LibraryScanAllRequestResolutionDto_Admitted() when admitted != null:
return admitted(_that.operationHandle,_that.admittedRoots,_that.exclusions);case LibraryScanAllRequestResolutionDto_NothingAdmitted() when nothingAdmitted != null:
return nothingAdmitted();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OperationHandleDto operationHandle,  List<String> admittedRoots,  List<LibraryScanAdmissionExclusionDto> exclusions)  admitted,required TResult Function()  nothingAdmitted,}) {final _that = this;
switch (_that) {
case LibraryScanAllRequestResolutionDto_Admitted():
return admitted(_that.operationHandle,_that.admittedRoots,_that.exclusions);case LibraryScanAllRequestResolutionDto_NothingAdmitted():
return nothingAdmitted();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OperationHandleDto operationHandle,  List<String> admittedRoots,  List<LibraryScanAdmissionExclusionDto> exclusions)?  admitted,TResult? Function()?  nothingAdmitted,}) {final _that = this;
switch (_that) {
case LibraryScanAllRequestResolutionDto_Admitted() when admitted != null:
return admitted(_that.operationHandle,_that.admittedRoots,_that.exclusions);case LibraryScanAllRequestResolutionDto_NothingAdmitted() when nothingAdmitted != null:
return nothingAdmitted();case _:
  return null;

}
}

}

/// @nodoc


class LibraryScanAllRequestResolutionDto_Admitted extends LibraryScanAllRequestResolutionDto {
  const LibraryScanAllRequestResolutionDto_Admitted({required this.operationHandle, required final  List<String> admittedRoots, required final  List<LibraryScanAdmissionExclusionDto> exclusions}): _admittedRoots = admittedRoots,_exclusions = exclusions,super._();


 final  OperationHandleDto operationHandle;
 final  List<String> _admittedRoots;
 List<String> get admittedRoots {
  if (_admittedRoots is EqualUnmodifiableListView) return _admittedRoots;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_admittedRoots);
}

 final  List<LibraryScanAdmissionExclusionDto> _exclusions;
 List<LibraryScanAdmissionExclusionDto> get exclusions {
  if (_exclusions is EqualUnmodifiableListView) return _exclusions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_exclusions);
}


/// Create a copy of LibraryScanAllRequestResolutionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryScanAllRequestResolutionDto_AdmittedCopyWith<LibraryScanAllRequestResolutionDto_Admitted> get copyWith => _$LibraryScanAllRequestResolutionDto_AdmittedCopyWithImpl<LibraryScanAllRequestResolutionDto_Admitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanAllRequestResolutionDto_Admitted&&(identical(other.operationHandle, operationHandle) || other.operationHandle == operationHandle)&&const DeepCollectionEquality().equals(other._admittedRoots, _admittedRoots)&&const DeepCollectionEquality().equals(other._exclusions, _exclusions));
}


@override
int get hashCode => Object.hash(runtimeType,operationHandle,const DeepCollectionEquality().hash(_admittedRoots),const DeepCollectionEquality().hash(_exclusions));

@override
String toString() {
  return 'LibraryScanAllRequestResolutionDto.admitted(operationHandle: $operationHandle, admittedRoots: $admittedRoots, exclusions: $exclusions)';
}


}

/// @nodoc
abstract mixin class $LibraryScanAllRequestResolutionDto_AdmittedCopyWith<$Res> implements $LibraryScanAllRequestResolutionDtoCopyWith<$Res> {
  factory $LibraryScanAllRequestResolutionDto_AdmittedCopyWith(LibraryScanAllRequestResolutionDto_Admitted value, $Res Function(LibraryScanAllRequestResolutionDto_Admitted) _then) = _$LibraryScanAllRequestResolutionDto_AdmittedCopyWithImpl;
@useResult
$Res call({
 OperationHandleDto operationHandle, List<String> admittedRoots, List<LibraryScanAdmissionExclusionDto> exclusions
});




}
/// @nodoc
class _$LibraryScanAllRequestResolutionDto_AdmittedCopyWithImpl<$Res>
    implements $LibraryScanAllRequestResolutionDto_AdmittedCopyWith<$Res> {
  _$LibraryScanAllRequestResolutionDto_AdmittedCopyWithImpl(this._self, this._then);

  final LibraryScanAllRequestResolutionDto_Admitted _self;
  final $Res Function(LibraryScanAllRequestResolutionDto_Admitted) _then;

/// Create a copy of LibraryScanAllRequestResolutionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationHandle = null,Object? admittedRoots = null,Object? exclusions = null,}) {
  return _then(LibraryScanAllRequestResolutionDto_Admitted(
operationHandle: null == operationHandle ? _self.operationHandle : operationHandle // ignore: cast_nullable_to_non_nullable
as OperationHandleDto,admittedRoots: null == admittedRoots ? _self._admittedRoots : admittedRoots // ignore: cast_nullable_to_non_nullable
as List<String>,exclusions: null == exclusions ? _self._exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as List<LibraryScanAdmissionExclusionDto>,
  ));
}


}

/// @nodoc


class LibraryScanAllRequestResolutionDto_NothingAdmitted extends LibraryScanAllRequestResolutionDto {
  const LibraryScanAllRequestResolutionDto_NothingAdmitted(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanAllRequestResolutionDto_NothingAdmitted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LibraryScanAllRequestResolutionDto.nothingAdmitted()';
}


}




/// @nodoc
mixin _$LibraryScanChildAdmissionIssueDto {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanChildAdmissionIssueDto);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LibraryScanChildAdmissionIssueDto()';
}


}

/// @nodoc
class $LibraryScanChildAdmissionIssueDtoCopyWith<$Res>  {
$LibraryScanChildAdmissionIssueDtoCopyWith(LibraryScanChildAdmissionIssueDto _, $Res Function(LibraryScanChildAdmissionIssueDto) __);
}


/// Adds pattern-matching-related methods to [LibraryScanChildAdmissionIssueDto].
extension LibraryScanChildAdmissionIssueDtoPatterns on LibraryScanChildAdmissionIssueDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LibraryScanChildAdmissionIssueDto_AlreadyScanning value)?  alreadyScanning,TResult Function( LibraryScanChildAdmissionIssueDto_AdmissionFailure value)?  admissionFailure,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LibraryScanChildAdmissionIssueDto_AlreadyScanning() when alreadyScanning != null:
return alreadyScanning(_that);case LibraryScanChildAdmissionIssueDto_AdmissionFailure() when admissionFailure != null:
return admissionFailure(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LibraryScanChildAdmissionIssueDto_AlreadyScanning value)  alreadyScanning,required TResult Function( LibraryScanChildAdmissionIssueDto_AdmissionFailure value)  admissionFailure,}){
final _that = this;
switch (_that) {
case LibraryScanChildAdmissionIssueDto_AlreadyScanning():
return alreadyScanning(_that);case LibraryScanChildAdmissionIssueDto_AdmissionFailure():
return admissionFailure(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LibraryScanChildAdmissionIssueDto_AlreadyScanning value)?  alreadyScanning,TResult? Function( LibraryScanChildAdmissionIssueDto_AdmissionFailure value)?  admissionFailure,}){
final _that = this;
switch (_that) {
case LibraryScanChildAdmissionIssueDto_AlreadyScanning() when alreadyScanning != null:
return alreadyScanning(_that);case LibraryScanChildAdmissionIssueDto_AdmissionFailure() when admissionFailure != null:
return admissionFailure(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String libraryRootId,  String activeJobRunId,  String activeScanRunId)?  alreadyScanning,TResult Function( ApplicationErrorDto field0)?  admissionFailure,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LibraryScanChildAdmissionIssueDto_AlreadyScanning() when alreadyScanning != null:
return alreadyScanning(_that.libraryRootId,_that.activeJobRunId,_that.activeScanRunId);case LibraryScanChildAdmissionIssueDto_AdmissionFailure() when admissionFailure != null:
return admissionFailure(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String libraryRootId,  String activeJobRunId,  String activeScanRunId)  alreadyScanning,required TResult Function( ApplicationErrorDto field0)  admissionFailure,}) {final _that = this;
switch (_that) {
case LibraryScanChildAdmissionIssueDto_AlreadyScanning():
return alreadyScanning(_that.libraryRootId,_that.activeJobRunId,_that.activeScanRunId);case LibraryScanChildAdmissionIssueDto_AdmissionFailure():
return admissionFailure(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String libraryRootId,  String activeJobRunId,  String activeScanRunId)?  alreadyScanning,TResult? Function( ApplicationErrorDto field0)?  admissionFailure,}) {final _that = this;
switch (_that) {
case LibraryScanChildAdmissionIssueDto_AlreadyScanning() when alreadyScanning != null:
return alreadyScanning(_that.libraryRootId,_that.activeJobRunId,_that.activeScanRunId);case LibraryScanChildAdmissionIssueDto_AdmissionFailure() when admissionFailure != null:
return admissionFailure(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class LibraryScanChildAdmissionIssueDto_AlreadyScanning extends LibraryScanChildAdmissionIssueDto {
  const LibraryScanChildAdmissionIssueDto_AlreadyScanning({required this.libraryRootId, required this.activeJobRunId, required this.activeScanRunId}): super._();


 final  String libraryRootId;
 final  String activeJobRunId;
 final  String activeScanRunId;

/// Create a copy of LibraryScanChildAdmissionIssueDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryScanChildAdmissionIssueDto_AlreadyScanningCopyWith<LibraryScanChildAdmissionIssueDto_AlreadyScanning> get copyWith => _$LibraryScanChildAdmissionIssueDto_AlreadyScanningCopyWithImpl<LibraryScanChildAdmissionIssueDto_AlreadyScanning>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanChildAdmissionIssueDto_AlreadyScanning&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId)&&(identical(other.activeJobRunId, activeJobRunId) || other.activeJobRunId == activeJobRunId)&&(identical(other.activeScanRunId, activeScanRunId) || other.activeScanRunId == activeScanRunId));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId,activeJobRunId,activeScanRunId);

@override
String toString() {
  return 'LibraryScanChildAdmissionIssueDto.alreadyScanning(libraryRootId: $libraryRootId, activeJobRunId: $activeJobRunId, activeScanRunId: $activeScanRunId)';
}


}

/// @nodoc
abstract mixin class $LibraryScanChildAdmissionIssueDto_AlreadyScanningCopyWith<$Res> implements $LibraryScanChildAdmissionIssueDtoCopyWith<$Res> {
  factory $LibraryScanChildAdmissionIssueDto_AlreadyScanningCopyWith(LibraryScanChildAdmissionIssueDto_AlreadyScanning value, $Res Function(LibraryScanChildAdmissionIssueDto_AlreadyScanning) _then) = _$LibraryScanChildAdmissionIssueDto_AlreadyScanningCopyWithImpl;
@useResult
$Res call({
 String libraryRootId, String activeJobRunId, String activeScanRunId
});




}
/// @nodoc
class _$LibraryScanChildAdmissionIssueDto_AlreadyScanningCopyWithImpl<$Res>
    implements $LibraryScanChildAdmissionIssueDto_AlreadyScanningCopyWith<$Res> {
  _$LibraryScanChildAdmissionIssueDto_AlreadyScanningCopyWithImpl(this._self, this._then);

  final LibraryScanChildAdmissionIssueDto_AlreadyScanning _self;
  final $Res Function(LibraryScanChildAdmissionIssueDto_AlreadyScanning) _then;

/// Create a copy of LibraryScanChildAdmissionIssueDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? libraryRootId = null,Object? activeJobRunId = null,Object? activeScanRunId = null,}) {
  return _then(LibraryScanChildAdmissionIssueDto_AlreadyScanning(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as String,activeJobRunId: null == activeJobRunId ? _self.activeJobRunId : activeJobRunId // ignore: cast_nullable_to_non_nullable
as String,activeScanRunId: null == activeScanRunId ? _self.activeScanRunId : activeScanRunId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class LibraryScanChildAdmissionIssueDto_AdmissionFailure extends LibraryScanChildAdmissionIssueDto {
  const LibraryScanChildAdmissionIssueDto_AdmissionFailure(this.field0): super._();


 final  ApplicationErrorDto field0;

/// Create a copy of LibraryScanChildAdmissionIssueDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryScanChildAdmissionIssueDto_AdmissionFailureCopyWith<LibraryScanChildAdmissionIssueDto_AdmissionFailure> get copyWith => _$LibraryScanChildAdmissionIssueDto_AdmissionFailureCopyWithImpl<LibraryScanChildAdmissionIssueDto_AdmissionFailure>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanChildAdmissionIssueDto_AdmissionFailure&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'LibraryScanChildAdmissionIssueDto.admissionFailure(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $LibraryScanChildAdmissionIssueDto_AdmissionFailureCopyWith<$Res> implements $LibraryScanChildAdmissionIssueDtoCopyWith<$Res> {
  factory $LibraryScanChildAdmissionIssueDto_AdmissionFailureCopyWith(LibraryScanChildAdmissionIssueDto_AdmissionFailure value, $Res Function(LibraryScanChildAdmissionIssueDto_AdmissionFailure) _then) = _$LibraryScanChildAdmissionIssueDto_AdmissionFailureCopyWithImpl;
@useResult
$Res call({
 ApplicationErrorDto field0
});




}
/// @nodoc
class _$LibraryScanChildAdmissionIssueDto_AdmissionFailureCopyWithImpl<$Res>
    implements $LibraryScanChildAdmissionIssueDto_AdmissionFailureCopyWith<$Res> {
  _$LibraryScanChildAdmissionIssueDto_AdmissionFailureCopyWithImpl(this._self, this._then);

  final LibraryScanChildAdmissionIssueDto_AdmissionFailure _self;
  final $Res Function(LibraryScanChildAdmissionIssueDto_AdmissionFailure) _then;

/// Create a copy of LibraryScanChildAdmissionIssueDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(LibraryScanChildAdmissionIssueDto_AdmissionFailure(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as ApplicationErrorDto,
  ));
}


}

/// @nodoc
mixin _$ListJobsScopeDto {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ListJobsScopeDto);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ListJobsScopeDto()';
}


}

/// @nodoc
class $ListJobsScopeDtoCopyWith<$Res>  {
$ListJobsScopeDtoCopyWith(ListJobsScopeDto _, $Res Function(ListJobsScopeDto) __);
}


/// Adds pattern-matching-related methods to [ListJobsScopeDto].
extension ListJobsScopeDtoPatterns on ListJobsScopeDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ListJobsScopeDto_Active value)?  active,TResult Function( ListJobsScopeDto_RecentTerminal value)?  recentTerminal,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ListJobsScopeDto_Active() when active != null:
return active(_that);case ListJobsScopeDto_RecentTerminal() when recentTerminal != null:
return recentTerminal(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ListJobsScopeDto_Active value)  active,required TResult Function( ListJobsScopeDto_RecentTerminal value)  recentTerminal,}){
final _that = this;
switch (_that) {
case ListJobsScopeDto_Active():
return active(_that);case ListJobsScopeDto_RecentTerminal():
return recentTerminal(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ListJobsScopeDto_Active value)?  active,TResult? Function( ListJobsScopeDto_RecentTerminal value)?  recentTerminal,}){
final _that = this;
switch (_that) {
case ListJobsScopeDto_Active() when active != null:
return active(_that);case ListJobsScopeDto_RecentTerminal() when recentTerminal != null:
return recentTerminal(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  active,TResult Function( int offset,  int pageSize)?  recentTerminal,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ListJobsScopeDto_Active() when active != null:
return active();case ListJobsScopeDto_RecentTerminal() when recentTerminal != null:
return recentTerminal(_that.offset,_that.pageSize);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  active,required TResult Function( int offset,  int pageSize)  recentTerminal,}) {final _that = this;
switch (_that) {
case ListJobsScopeDto_Active():
return active();case ListJobsScopeDto_RecentTerminal():
return recentTerminal(_that.offset,_that.pageSize);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  active,TResult? Function( int offset,  int pageSize)?  recentTerminal,}) {final _that = this;
switch (_that) {
case ListJobsScopeDto_Active() when active != null:
return active();case ListJobsScopeDto_RecentTerminal() when recentTerminal != null:
return recentTerminal(_that.offset,_that.pageSize);case _:
  return null;

}
}

}

/// @nodoc


class ListJobsScopeDto_Active extends ListJobsScopeDto {
  const ListJobsScopeDto_Active(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ListJobsScopeDto_Active);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ListJobsScopeDto.active()';
}


}




/// @nodoc


class ListJobsScopeDto_RecentTerminal extends ListJobsScopeDto {
  const ListJobsScopeDto_RecentTerminal({required this.offset, required this.pageSize}): super._();


 final  int offset;
 final  int pageSize;

/// Create a copy of ListJobsScopeDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ListJobsScopeDto_RecentTerminalCopyWith<ListJobsScopeDto_RecentTerminal> get copyWith => _$ListJobsScopeDto_RecentTerminalCopyWithImpl<ListJobsScopeDto_RecentTerminal>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ListJobsScopeDto_RecentTerminal&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.pageSize, pageSize) || other.pageSize == pageSize));
}


@override
int get hashCode => Object.hash(runtimeType,offset,pageSize);

@override
String toString() {
  return 'ListJobsScopeDto.recentTerminal(offset: $offset, pageSize: $pageSize)';
}


}

/// @nodoc
abstract mixin class $ListJobsScopeDto_RecentTerminalCopyWith<$Res> implements $ListJobsScopeDtoCopyWith<$Res> {
  factory $ListJobsScopeDto_RecentTerminalCopyWith(ListJobsScopeDto_RecentTerminal value, $Res Function(ListJobsScopeDto_RecentTerminal) _then) = _$ListJobsScopeDto_RecentTerminalCopyWithImpl;
@useResult
$Res call({
 int offset, int pageSize
});




}
/// @nodoc
class _$ListJobsScopeDto_RecentTerminalCopyWithImpl<$Res>
    implements $ListJobsScopeDto_RecentTerminalCopyWith<$Res> {
  _$ListJobsScopeDto_RecentTerminalCopyWithImpl(this._self, this._then);

  final ListJobsScopeDto_RecentTerminal _self;
  final $Res Function(ListJobsScopeDto_RecentTerminal) _then;

/// Create a copy of ListJobsScopeDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? offset = null,Object? pageSize = null,}) {
  return _then(ListJobsScopeDto_RecentTerminal(
offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,pageSize: null == pageSize ? _self.pageSize : pageSize // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$OperationDetailDto {

 LibraryScanJobDetailDto get field0;
/// Create a copy of OperationDetailDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperationDetailDtoCopyWith<OperationDetailDto> get copyWith => _$OperationDetailDtoCopyWithImpl<OperationDetailDto>(this as OperationDetailDto, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationDetailDto&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'OperationDetailDto(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $OperationDetailDtoCopyWith<$Res>  {
  factory $OperationDetailDtoCopyWith(OperationDetailDto value, $Res Function(OperationDetailDto) _then) = _$OperationDetailDtoCopyWithImpl;
@useResult
$Res call({
 LibraryScanJobDetailDto field0
});




}
/// @nodoc
class _$OperationDetailDtoCopyWithImpl<$Res>
    implements $OperationDetailDtoCopyWith<$Res> {
  _$OperationDetailDtoCopyWithImpl(this._self, this._then);

  final OperationDetailDto _self;
  final $Res Function(OperationDetailDto) _then;

/// Create a copy of OperationDetailDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? field0 = null,}) {
  return _then(_self.copyWith(
field0: null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as LibraryScanJobDetailDto,
  ));
}

}


/// Adds pattern-matching-related methods to [OperationDetailDto].
extension OperationDetailDtoPatterns on OperationDetailDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( OperationDetailDto_LibraryScan value)?  libraryScan,required TResult orElse(),}){
final _that = this;
switch (_that) {
case OperationDetailDto_LibraryScan() when libraryScan != null:
return libraryScan(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( OperationDetailDto_LibraryScan value)  libraryScan,}){
final _that = this;
switch (_that) {
case OperationDetailDto_LibraryScan():
return libraryScan(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( OperationDetailDto_LibraryScan value)?  libraryScan,}){
final _that = this;
switch (_that) {
case OperationDetailDto_LibraryScan() when libraryScan != null:
return libraryScan(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( LibraryScanJobDetailDto field0)?  libraryScan,required TResult orElse(),}) {final _that = this;
switch (_that) {
case OperationDetailDto_LibraryScan() when libraryScan != null:
return libraryScan(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( LibraryScanJobDetailDto field0)  libraryScan,}) {final _that = this;
switch (_that) {
case OperationDetailDto_LibraryScan():
return libraryScan(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( LibraryScanJobDetailDto field0)?  libraryScan,}) {final _that = this;
switch (_that) {
case OperationDetailDto_LibraryScan() when libraryScan != null:
return libraryScan(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class OperationDetailDto_LibraryScan extends OperationDetailDto {
  const OperationDetailDto_LibraryScan(this.field0): super._();


@override final  LibraryScanJobDetailDto field0;

/// Create a copy of OperationDetailDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperationDetailDto_LibraryScanCopyWith<OperationDetailDto_LibraryScan> get copyWith => _$OperationDetailDto_LibraryScanCopyWithImpl<OperationDetailDto_LibraryScan>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationDetailDto_LibraryScan&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'OperationDetailDto.libraryScan(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $OperationDetailDto_LibraryScanCopyWith<$Res> implements $OperationDetailDtoCopyWith<$Res> {
  factory $OperationDetailDto_LibraryScanCopyWith(OperationDetailDto_LibraryScan value, $Res Function(OperationDetailDto_LibraryScan) _then) = _$OperationDetailDto_LibraryScanCopyWithImpl;
@override @useResult
$Res call({
 LibraryScanJobDetailDto field0
});




}
/// @nodoc
class _$OperationDetailDto_LibraryScanCopyWithImpl<$Res>
    implements $OperationDetailDto_LibraryScanCopyWith<$Res> {
  _$OperationDetailDto_LibraryScanCopyWithImpl(this._self, this._then);

  final OperationDetailDto_LibraryScan _self;
  final $Res Function(OperationDetailDto_LibraryScan) _then;

/// Create a copy of OperationDetailDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(OperationDetailDto_LibraryScan(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as LibraryScanJobDetailDto,
  ));
}


}

/// @nodoc
mixin _$RemoveLibraryRootResultDto {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoveLibraryRootResultDto);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RemoveLibraryRootResultDto()';
}


}

/// @nodoc
class $RemoveLibraryRootResultDtoCopyWith<$Res>  {
$RemoveLibraryRootResultDtoCopyWith(RemoveLibraryRootResultDto _, $Res Function(RemoveLibraryRootResultDto) __);
}


/// Adds pattern-matching-related methods to [RemoveLibraryRootResultDto].
extension RemoveLibraryRootResultDtoPatterns on RemoveLibraryRootResultDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RemoveLibraryRootResultDto_Removed value)?  removed,TResult Function( RemoveLibraryRootResultDto_RootHasActiveScan value)?  rootHasActiveScan,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RemoveLibraryRootResultDto_Removed() when removed != null:
return removed(_that);case RemoveLibraryRootResultDto_RootHasActiveScan() when rootHasActiveScan != null:
return rootHasActiveScan(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RemoveLibraryRootResultDto_Removed value)  removed,required TResult Function( RemoveLibraryRootResultDto_RootHasActiveScan value)  rootHasActiveScan,}){
final _that = this;
switch (_that) {
case RemoveLibraryRootResultDto_Removed():
return removed(_that);case RemoveLibraryRootResultDto_RootHasActiveScan():
return rootHasActiveScan(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RemoveLibraryRootResultDto_Removed value)?  removed,TResult? Function( RemoveLibraryRootResultDto_RootHasActiveScan value)?  rootHasActiveScan,}){
final _that = this;
switch (_that) {
case RemoveLibraryRootResultDto_Removed() when removed != null:
return removed(_that);case RemoveLibraryRootResultDto_RootHasActiveScan() when rootHasActiveScan != null:
return rootHasActiveScan(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  removed,TResult Function( String libraryRootId,  String jobRunId,  String scanRunId,  int owningJobRootCount)?  rootHasActiveScan,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RemoveLibraryRootResultDto_Removed() when removed != null:
return removed();case RemoveLibraryRootResultDto_RootHasActiveScan() when rootHasActiveScan != null:
return rootHasActiveScan(_that.libraryRootId,_that.jobRunId,_that.scanRunId,_that.owningJobRootCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  removed,required TResult Function( String libraryRootId,  String jobRunId,  String scanRunId,  int owningJobRootCount)  rootHasActiveScan,}) {final _that = this;
switch (_that) {
case RemoveLibraryRootResultDto_Removed():
return removed();case RemoveLibraryRootResultDto_RootHasActiveScan():
return rootHasActiveScan(_that.libraryRootId,_that.jobRunId,_that.scanRunId,_that.owningJobRootCount);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  removed,TResult? Function( String libraryRootId,  String jobRunId,  String scanRunId,  int owningJobRootCount)?  rootHasActiveScan,}) {final _that = this;
switch (_that) {
case RemoveLibraryRootResultDto_Removed() when removed != null:
return removed();case RemoveLibraryRootResultDto_RootHasActiveScan() when rootHasActiveScan != null:
return rootHasActiveScan(_that.libraryRootId,_that.jobRunId,_that.scanRunId,_that.owningJobRootCount);case _:
  return null;

}
}

}

/// @nodoc


class RemoveLibraryRootResultDto_Removed extends RemoveLibraryRootResultDto {
  const RemoveLibraryRootResultDto_Removed(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoveLibraryRootResultDto_Removed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RemoveLibraryRootResultDto.removed()';
}


}




/// @nodoc


class RemoveLibraryRootResultDto_RootHasActiveScan extends RemoveLibraryRootResultDto {
  const RemoveLibraryRootResultDto_RootHasActiveScan({required this.libraryRootId, required this.jobRunId, required this.scanRunId, required this.owningJobRootCount}): super._();


 final  String libraryRootId;
 final  String jobRunId;
 final  String scanRunId;
 final  int owningJobRootCount;

/// Create a copy of RemoveLibraryRootResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoveLibraryRootResultDto_RootHasActiveScanCopyWith<RemoveLibraryRootResultDto_RootHasActiveScan> get copyWith => _$RemoveLibraryRootResultDto_RootHasActiveScanCopyWithImpl<RemoveLibraryRootResultDto_RootHasActiveScan>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoveLibraryRootResultDto_RootHasActiveScan&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId)&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId)&&(identical(other.scanRunId, scanRunId) || other.scanRunId == scanRunId)&&(identical(other.owningJobRootCount, owningJobRootCount) || other.owningJobRootCount == owningJobRootCount));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId,jobRunId,scanRunId,owningJobRootCount);

@override
String toString() {
  return 'RemoveLibraryRootResultDto.rootHasActiveScan(libraryRootId: $libraryRootId, jobRunId: $jobRunId, scanRunId: $scanRunId, owningJobRootCount: $owningJobRootCount)';
}


}

/// @nodoc
abstract mixin class $RemoveLibraryRootResultDto_RootHasActiveScanCopyWith<$Res> implements $RemoveLibraryRootResultDtoCopyWith<$Res> {
  factory $RemoveLibraryRootResultDto_RootHasActiveScanCopyWith(RemoveLibraryRootResultDto_RootHasActiveScan value, $Res Function(RemoveLibraryRootResultDto_RootHasActiveScan) _then) = _$RemoveLibraryRootResultDto_RootHasActiveScanCopyWithImpl;
@useResult
$Res call({
 String libraryRootId, String jobRunId, String scanRunId, int owningJobRootCount
});




}
/// @nodoc
class _$RemoveLibraryRootResultDto_RootHasActiveScanCopyWithImpl<$Res>
    implements $RemoveLibraryRootResultDto_RootHasActiveScanCopyWith<$Res> {
  _$RemoveLibraryRootResultDto_RootHasActiveScanCopyWithImpl(this._self, this._then);

  final RemoveLibraryRootResultDto_RootHasActiveScan _self;
  final $Res Function(RemoveLibraryRootResultDto_RootHasActiveScan) _then;

/// Create a copy of RemoveLibraryRootResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? libraryRootId = null,Object? jobRunId = null,Object? scanRunId = null,Object? owningJobRootCount = null,}) {
  return _then(RemoveLibraryRootResultDto_RootHasActiveScan(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as String,jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as String,scanRunId: null == scanRunId ? _self.scanRunId : scanRunId // ignore: cast_nullable_to_non_nullable
as String,owningJobRootCount: null == owningJobRootCount ? _self.owningJobRootCount : owningJobRootCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$RetryJobResultDto {

 Object get field0;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryJobResultDto&&const DeepCollectionEquality().equals(other.field0, field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(field0));

@override
String toString() {
  return 'RetryJobResultDto(field0: $field0)';
}


}

/// @nodoc
class $RetryJobResultDtoCopyWith<$Res>  {
$RetryJobResultDtoCopyWith(RetryJobResultDto _, $Res Function(RetryJobResultDto) __);
}


/// Adds pattern-matching-related methods to [RetryJobResultDto].
extension RetryJobResultDtoPatterns on RetryJobResultDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RetryJobResultDto_Admitted value)?  admitted,TResult Function( RetryJobResultDto_AlreadyRetried value)?  alreadyRetried,TResult Function( RetryJobResultDto_NotAdmitted value)?  notAdmitted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RetryJobResultDto_Admitted() when admitted != null:
return admitted(_that);case RetryJobResultDto_AlreadyRetried() when alreadyRetried != null:
return alreadyRetried(_that);case RetryJobResultDto_NotAdmitted() when notAdmitted != null:
return notAdmitted(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RetryJobResultDto_Admitted value)  admitted,required TResult Function( RetryJobResultDto_AlreadyRetried value)  alreadyRetried,required TResult Function( RetryJobResultDto_NotAdmitted value)  notAdmitted,}){
final _that = this;
switch (_that) {
case RetryJobResultDto_Admitted():
return admitted(_that);case RetryJobResultDto_AlreadyRetried():
return alreadyRetried(_that);case RetryJobResultDto_NotAdmitted():
return notAdmitted(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RetryJobResultDto_Admitted value)?  admitted,TResult? Function( RetryJobResultDto_AlreadyRetried value)?  alreadyRetried,TResult? Function( RetryJobResultDto_NotAdmitted value)?  notAdmitted,}){
final _that = this;
switch (_that) {
case RetryJobResultDto_Admitted() when admitted != null:
return admitted(_that);case RetryJobResultDto_AlreadyRetried() when alreadyRetried != null:
return alreadyRetried(_that);case RetryJobResultDto_NotAdmitted() when notAdmitted != null:
return notAdmitted(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OperationHandleDto field0)?  admitted,TResult Function( String field0)?  alreadyRetried,TResult Function( RetryNotAdmittedReasonDto field0)?  notAdmitted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RetryJobResultDto_Admitted() when admitted != null:
return admitted(_that.field0);case RetryJobResultDto_AlreadyRetried() when alreadyRetried != null:
return alreadyRetried(_that.field0);case RetryJobResultDto_NotAdmitted() when notAdmitted != null:
return notAdmitted(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OperationHandleDto field0)  admitted,required TResult Function( String field0)  alreadyRetried,required TResult Function( RetryNotAdmittedReasonDto field0)  notAdmitted,}) {final _that = this;
switch (_that) {
case RetryJobResultDto_Admitted():
return admitted(_that.field0);case RetryJobResultDto_AlreadyRetried():
return alreadyRetried(_that.field0);case RetryJobResultDto_NotAdmitted():
return notAdmitted(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OperationHandleDto field0)?  admitted,TResult? Function( String field0)?  alreadyRetried,TResult? Function( RetryNotAdmittedReasonDto field0)?  notAdmitted,}) {final _that = this;
switch (_that) {
case RetryJobResultDto_Admitted() when admitted != null:
return admitted(_that.field0);case RetryJobResultDto_AlreadyRetried() when alreadyRetried != null:
return alreadyRetried(_that.field0);case RetryJobResultDto_NotAdmitted() when notAdmitted != null:
return notAdmitted(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class RetryJobResultDto_Admitted extends RetryJobResultDto {
  const RetryJobResultDto_Admitted(this.field0): super._();


@override final  OperationHandleDto field0;

/// Create a copy of RetryJobResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RetryJobResultDto_AdmittedCopyWith<RetryJobResultDto_Admitted> get copyWith => _$RetryJobResultDto_AdmittedCopyWithImpl<RetryJobResultDto_Admitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryJobResultDto_Admitted&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RetryJobResultDto.admitted(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RetryJobResultDto_AdmittedCopyWith<$Res> implements $RetryJobResultDtoCopyWith<$Res> {
  factory $RetryJobResultDto_AdmittedCopyWith(RetryJobResultDto_Admitted value, $Res Function(RetryJobResultDto_Admitted) _then) = _$RetryJobResultDto_AdmittedCopyWithImpl;
@useResult
$Res call({
 OperationHandleDto field0
});




}
/// @nodoc
class _$RetryJobResultDto_AdmittedCopyWithImpl<$Res>
    implements $RetryJobResultDto_AdmittedCopyWith<$Res> {
  _$RetryJobResultDto_AdmittedCopyWithImpl(this._self, this._then);

  final RetryJobResultDto_Admitted _self;
  final $Res Function(RetryJobResultDto_Admitted) _then;

/// Create a copy of RetryJobResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RetryJobResultDto_Admitted(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as OperationHandleDto,
  ));
}


}

/// @nodoc


class RetryJobResultDto_AlreadyRetried extends RetryJobResultDto {
  const RetryJobResultDto_AlreadyRetried(this.field0): super._();


@override final  String field0;

/// Create a copy of RetryJobResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RetryJobResultDto_AlreadyRetriedCopyWith<RetryJobResultDto_AlreadyRetried> get copyWith => _$RetryJobResultDto_AlreadyRetriedCopyWithImpl<RetryJobResultDto_AlreadyRetried>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryJobResultDto_AlreadyRetried&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RetryJobResultDto.alreadyRetried(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RetryJobResultDto_AlreadyRetriedCopyWith<$Res> implements $RetryJobResultDtoCopyWith<$Res> {
  factory $RetryJobResultDto_AlreadyRetriedCopyWith(RetryJobResultDto_AlreadyRetried value, $Res Function(RetryJobResultDto_AlreadyRetried) _then) = _$RetryJobResultDto_AlreadyRetriedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RetryJobResultDto_AlreadyRetriedCopyWithImpl<$Res>
    implements $RetryJobResultDto_AlreadyRetriedCopyWith<$Res> {
  _$RetryJobResultDto_AlreadyRetriedCopyWithImpl(this._self, this._then);

  final RetryJobResultDto_AlreadyRetried _self;
  final $Res Function(RetryJobResultDto_AlreadyRetried) _then;

/// Create a copy of RetryJobResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RetryJobResultDto_AlreadyRetried(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RetryJobResultDto_NotAdmitted extends RetryJobResultDto {
  const RetryJobResultDto_NotAdmitted(this.field0): super._();


@override final  RetryNotAdmittedReasonDto field0;

/// Create a copy of RetryJobResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RetryJobResultDto_NotAdmittedCopyWith<RetryJobResultDto_NotAdmitted> get copyWith => _$RetryJobResultDto_NotAdmittedCopyWithImpl<RetryJobResultDto_NotAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryJobResultDto_NotAdmitted&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RetryJobResultDto.notAdmitted(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RetryJobResultDto_NotAdmittedCopyWith<$Res> implements $RetryJobResultDtoCopyWith<$Res> {
  factory $RetryJobResultDto_NotAdmittedCopyWith(RetryJobResultDto_NotAdmitted value, $Res Function(RetryJobResultDto_NotAdmitted) _then) = _$RetryJobResultDto_NotAdmittedCopyWithImpl;
@useResult
$Res call({
 RetryNotAdmittedReasonDto field0
});


$RetryNotAdmittedReasonDtoCopyWith<$Res> get field0;

}
/// @nodoc
class _$RetryJobResultDto_NotAdmittedCopyWithImpl<$Res>
    implements $RetryJobResultDto_NotAdmittedCopyWith<$Res> {
  _$RetryJobResultDto_NotAdmittedCopyWithImpl(this._self, this._then);

  final RetryJobResultDto_NotAdmitted _self;
  final $Res Function(RetryJobResultDto_NotAdmitted) _then;

/// Create a copy of RetryJobResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RetryJobResultDto_NotAdmitted(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as RetryNotAdmittedReasonDto,
  ));
}

/// Create a copy of RetryJobResultDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RetryNotAdmittedReasonDtoCopyWith<$Res> get field0 {

  return $RetryNotAdmittedReasonDtoCopyWith<$Res>(_self.field0, (value) {
    return _then(_self.copyWith(field0: value));
  });
}
}

/// @nodoc
mixin _$RetryNotAdmittedReasonDto {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryNotAdmittedReasonDto);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RetryNotAdmittedReasonDto()';
}


}

/// @nodoc
class $RetryNotAdmittedReasonDtoCopyWith<$Res>  {
$RetryNotAdmittedReasonDtoCopyWith(RetryNotAdmittedReasonDto _, $Res Function(RetryNotAdmittedReasonDto) __);
}


/// Adds pattern-matching-related methods to [RetryNotAdmittedReasonDto].
extension RetryNotAdmittedReasonDtoPatterns on RetryNotAdmittedReasonDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RetryNotAdmittedReasonDto_SourceRunNotTerminal value)?  sourceRunNotTerminal,TResult Function( RetryNotAdmittedReasonDto_OperationNotRetryable value)?  operationNotRetryable,TResult Function( RetryNotAdmittedReasonDto_NoEligibleTargets value)?  noEligibleTargets,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RetryNotAdmittedReasonDto_SourceRunNotTerminal() when sourceRunNotTerminal != null:
return sourceRunNotTerminal(_that);case RetryNotAdmittedReasonDto_OperationNotRetryable() when operationNotRetryable != null:
return operationNotRetryable(_that);case RetryNotAdmittedReasonDto_NoEligibleTargets() when noEligibleTargets != null:
return noEligibleTargets(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RetryNotAdmittedReasonDto_SourceRunNotTerminal value)  sourceRunNotTerminal,required TResult Function( RetryNotAdmittedReasonDto_OperationNotRetryable value)  operationNotRetryable,required TResult Function( RetryNotAdmittedReasonDto_NoEligibleTargets value)  noEligibleTargets,}){
final _that = this;
switch (_that) {
case RetryNotAdmittedReasonDto_SourceRunNotTerminal():
return sourceRunNotTerminal(_that);case RetryNotAdmittedReasonDto_OperationNotRetryable():
return operationNotRetryable(_that);case RetryNotAdmittedReasonDto_NoEligibleTargets():
return noEligibleTargets(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RetryNotAdmittedReasonDto_SourceRunNotTerminal value)?  sourceRunNotTerminal,TResult? Function( RetryNotAdmittedReasonDto_OperationNotRetryable value)?  operationNotRetryable,TResult? Function( RetryNotAdmittedReasonDto_NoEligibleTargets value)?  noEligibleTargets,}){
final _that = this;
switch (_that) {
case RetryNotAdmittedReasonDto_SourceRunNotTerminal() when sourceRunNotTerminal != null:
return sourceRunNotTerminal(_that);case RetryNotAdmittedReasonDto_OperationNotRetryable() when operationNotRetryable != null:
return operationNotRetryable(_that);case RetryNotAdmittedReasonDto_NoEligibleTargets() when noEligibleTargets != null:
return noEligibleTargets(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  sourceRunNotTerminal,TResult Function()?  operationNotRetryable,TResult Function( List<LibraryScanAdmissionExclusionDto> field0)?  noEligibleTargets,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RetryNotAdmittedReasonDto_SourceRunNotTerminal() when sourceRunNotTerminal != null:
return sourceRunNotTerminal();case RetryNotAdmittedReasonDto_OperationNotRetryable() when operationNotRetryable != null:
return operationNotRetryable();case RetryNotAdmittedReasonDto_NoEligibleTargets() when noEligibleTargets != null:
return noEligibleTargets(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  sourceRunNotTerminal,required TResult Function()  operationNotRetryable,required TResult Function( List<LibraryScanAdmissionExclusionDto> field0)  noEligibleTargets,}) {final _that = this;
switch (_that) {
case RetryNotAdmittedReasonDto_SourceRunNotTerminal():
return sourceRunNotTerminal();case RetryNotAdmittedReasonDto_OperationNotRetryable():
return operationNotRetryable();case RetryNotAdmittedReasonDto_NoEligibleTargets():
return noEligibleTargets(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  sourceRunNotTerminal,TResult? Function()?  operationNotRetryable,TResult? Function( List<LibraryScanAdmissionExclusionDto> field0)?  noEligibleTargets,}) {final _that = this;
switch (_that) {
case RetryNotAdmittedReasonDto_SourceRunNotTerminal() when sourceRunNotTerminal != null:
return sourceRunNotTerminal();case RetryNotAdmittedReasonDto_OperationNotRetryable() when operationNotRetryable != null:
return operationNotRetryable();case RetryNotAdmittedReasonDto_NoEligibleTargets() when noEligibleTargets != null:
return noEligibleTargets(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class RetryNotAdmittedReasonDto_SourceRunNotTerminal extends RetryNotAdmittedReasonDto {
  const RetryNotAdmittedReasonDto_SourceRunNotTerminal(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryNotAdmittedReasonDto_SourceRunNotTerminal);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RetryNotAdmittedReasonDto.sourceRunNotTerminal()';
}


}




/// @nodoc


class RetryNotAdmittedReasonDto_OperationNotRetryable extends RetryNotAdmittedReasonDto {
  const RetryNotAdmittedReasonDto_OperationNotRetryable(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryNotAdmittedReasonDto_OperationNotRetryable);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RetryNotAdmittedReasonDto.operationNotRetryable()';
}


}




/// @nodoc


class RetryNotAdmittedReasonDto_NoEligibleTargets extends RetryNotAdmittedReasonDto {
  const RetryNotAdmittedReasonDto_NoEligibleTargets(final  List<LibraryScanAdmissionExclusionDto> field0): _field0 = field0,super._();


 final  List<LibraryScanAdmissionExclusionDto> _field0;
 List<LibraryScanAdmissionExclusionDto> get field0 {
  if (_field0 is EqualUnmodifiableListView) return _field0;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_field0);
}


/// Create a copy of RetryNotAdmittedReasonDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RetryNotAdmittedReasonDto_NoEligibleTargetsCopyWith<RetryNotAdmittedReasonDto_NoEligibleTargets> get copyWith => _$RetryNotAdmittedReasonDto_NoEligibleTargetsCopyWithImpl<RetryNotAdmittedReasonDto_NoEligibleTargets>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryNotAdmittedReasonDto_NoEligibleTargets&&const DeepCollectionEquality().equals(other._field0, _field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_field0));

@override
String toString() {
  return 'RetryNotAdmittedReasonDto.noEligibleTargets(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RetryNotAdmittedReasonDto_NoEligibleTargetsCopyWith<$Res> implements $RetryNotAdmittedReasonDtoCopyWith<$Res> {
  factory $RetryNotAdmittedReasonDto_NoEligibleTargetsCopyWith(RetryNotAdmittedReasonDto_NoEligibleTargets value, $Res Function(RetryNotAdmittedReasonDto_NoEligibleTargets) _then) = _$RetryNotAdmittedReasonDto_NoEligibleTargetsCopyWithImpl;
@useResult
$Res call({
 List<LibraryScanAdmissionExclusionDto> field0
});




}
/// @nodoc
class _$RetryNotAdmittedReasonDto_NoEligibleTargetsCopyWithImpl<$Res>
    implements $RetryNotAdmittedReasonDto_NoEligibleTargetsCopyWith<$Res> {
  _$RetryNotAdmittedReasonDto_NoEligibleTargetsCopyWithImpl(this._self, this._then);

  final RetryNotAdmittedReasonDto_NoEligibleTargets _self;
  final $Res Function(RetryNotAdmittedReasonDto_NoEligibleTargets) _then;

/// Create a copy of RetryNotAdmittedReasonDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RetryNotAdmittedReasonDto_NoEligibleTargets(
null == field0 ? _self._field0 : field0 // ignore: cast_nullable_to_non_nullable
as List<LibraryScanAdmissionExclusionDto>,
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RuntimeEventPayloadDto_RuntimeStateChanged value)?  runtimeStateChanged,TResult Function( RuntimeEventPayloadDto_StartupFailed value)?  startupFailed,TResult Function( RuntimeEventPayloadDto_AppearanceSettingsChanged value)?  appearanceSettingsChanged,TResult Function( RuntimeEventPayloadDto_LibraryRootsChanged value)?  libraryRootsChanged,TResult Function( RuntimeEventPayloadDto_LibraryRootChanged value)?  libraryRootChanged,TResult Function( RuntimeEventPayloadDto_JobStateChanged value)?  jobStateChanged,TResult Function( RuntimeEventPayloadDto_JobProgress value)?  jobProgress,TResult Function( RuntimeEventPayloadDto_SourceEntriesChanged value)?  sourceEntriesChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that);case RuntimeEventPayloadDto_StartupFailed() when startupFailed != null:
return startupFailed(_that);case RuntimeEventPayloadDto_AppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged(_that);case RuntimeEventPayloadDto_LibraryRootsChanged() when libraryRootsChanged != null:
return libraryRootsChanged(_that);case RuntimeEventPayloadDto_LibraryRootChanged() when libraryRootChanged != null:
return libraryRootChanged(_that);case RuntimeEventPayloadDto_JobStateChanged() when jobStateChanged != null:
return jobStateChanged(_that);case RuntimeEventPayloadDto_JobProgress() when jobProgress != null:
return jobProgress(_that);case RuntimeEventPayloadDto_SourceEntriesChanged() when sourceEntriesChanged != null:
return sourceEntriesChanged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RuntimeEventPayloadDto_RuntimeStateChanged value)  runtimeStateChanged,required TResult Function( RuntimeEventPayloadDto_StartupFailed value)  startupFailed,required TResult Function( RuntimeEventPayloadDto_AppearanceSettingsChanged value)  appearanceSettingsChanged,required TResult Function( RuntimeEventPayloadDto_LibraryRootsChanged value)  libraryRootsChanged,required TResult Function( RuntimeEventPayloadDto_LibraryRootChanged value)  libraryRootChanged,required TResult Function( RuntimeEventPayloadDto_JobStateChanged value)  jobStateChanged,required TResult Function( RuntimeEventPayloadDto_JobProgress value)  jobProgress,required TResult Function( RuntimeEventPayloadDto_SourceEntriesChanged value)  sourceEntriesChanged,}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged():
return runtimeStateChanged(_that);case RuntimeEventPayloadDto_StartupFailed():
return startupFailed(_that);case RuntimeEventPayloadDto_AppearanceSettingsChanged():
return appearanceSettingsChanged(_that);case RuntimeEventPayloadDto_LibraryRootsChanged():
return libraryRootsChanged(_that);case RuntimeEventPayloadDto_LibraryRootChanged():
return libraryRootChanged(_that);case RuntimeEventPayloadDto_JobStateChanged():
return jobStateChanged(_that);case RuntimeEventPayloadDto_JobProgress():
return jobProgress(_that);case RuntimeEventPayloadDto_SourceEntriesChanged():
return sourceEntriesChanged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RuntimeEventPayloadDto_RuntimeStateChanged value)?  runtimeStateChanged,TResult? Function( RuntimeEventPayloadDto_StartupFailed value)?  startupFailed,TResult? Function( RuntimeEventPayloadDto_AppearanceSettingsChanged value)?  appearanceSettingsChanged,TResult? Function( RuntimeEventPayloadDto_LibraryRootsChanged value)?  libraryRootsChanged,TResult? Function( RuntimeEventPayloadDto_LibraryRootChanged value)?  libraryRootChanged,TResult? Function( RuntimeEventPayloadDto_JobStateChanged value)?  jobStateChanged,TResult? Function( RuntimeEventPayloadDto_JobProgress value)?  jobProgress,TResult? Function( RuntimeEventPayloadDto_SourceEntriesChanged value)?  sourceEntriesChanged,}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that);case RuntimeEventPayloadDto_StartupFailed() when startupFailed != null:
return startupFailed(_that);case RuntimeEventPayloadDto_AppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged(_that);case RuntimeEventPayloadDto_LibraryRootsChanged() when libraryRootsChanged != null:
return libraryRootsChanged(_that);case RuntimeEventPayloadDto_LibraryRootChanged() when libraryRootChanged != null:
return libraryRootChanged(_that);case RuntimeEventPayloadDto_JobStateChanged() when jobStateChanged != null:
return jobStateChanged(_that);case RuntimeEventPayloadDto_JobProgress() when jobProgress != null:
return jobProgress(_that);case RuntimeEventPayloadDto_SourceEntriesChanged() when sourceEntriesChanged != null:
return sourceEntriesChanged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( RuntimeLifecycleDto lifecycle)?  runtimeStateChanged,TResult Function( StartupPhaseDto phase)?  startupFailed,TResult Function()?  appearanceSettingsChanged,TResult Function()?  libraryRootsChanged,TResult Function( String libraryRootId)?  libraryRootChanged,TResult Function( String jobRunId)?  jobStateChanged,TResult Function( String jobRunId,  String phase,  BigInt? completedUnits,  BigInt? totalUnits,  String? statusKey)?  jobProgress,TResult Function( String libraryRootId,  SourceEntriesChangeScopeDto scope)?  sourceEntriesChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadDto_StartupFailed() when startupFailed != null:
return startupFailed(_that.phase);case RuntimeEventPayloadDto_AppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged();case RuntimeEventPayloadDto_LibraryRootsChanged() when libraryRootsChanged != null:
return libraryRootsChanged();case RuntimeEventPayloadDto_LibraryRootChanged() when libraryRootChanged != null:
return libraryRootChanged(_that.libraryRootId);case RuntimeEventPayloadDto_JobStateChanged() when jobStateChanged != null:
return jobStateChanged(_that.jobRunId);case RuntimeEventPayloadDto_JobProgress() when jobProgress != null:
return jobProgress(_that.jobRunId,_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey);case RuntimeEventPayloadDto_SourceEntriesChanged() when sourceEntriesChanged != null:
return sourceEntriesChanged(_that.libraryRootId,_that.scope);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( RuntimeLifecycleDto lifecycle)  runtimeStateChanged,required TResult Function( StartupPhaseDto phase)  startupFailed,required TResult Function()  appearanceSettingsChanged,required TResult Function()  libraryRootsChanged,required TResult Function( String libraryRootId)  libraryRootChanged,required TResult Function( String jobRunId)  jobStateChanged,required TResult Function( String jobRunId,  String phase,  BigInt? completedUnits,  BigInt? totalUnits,  String? statusKey)  jobProgress,required TResult Function( String libraryRootId,  SourceEntriesChangeScopeDto scope)  sourceEntriesChanged,}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged():
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadDto_StartupFailed():
return startupFailed(_that.phase);case RuntimeEventPayloadDto_AppearanceSettingsChanged():
return appearanceSettingsChanged();case RuntimeEventPayloadDto_LibraryRootsChanged():
return libraryRootsChanged();case RuntimeEventPayloadDto_LibraryRootChanged():
return libraryRootChanged(_that.libraryRootId);case RuntimeEventPayloadDto_JobStateChanged():
return jobStateChanged(_that.jobRunId);case RuntimeEventPayloadDto_JobProgress():
return jobProgress(_that.jobRunId,_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey);case RuntimeEventPayloadDto_SourceEntriesChanged():
return sourceEntriesChanged(_that.libraryRootId,_that.scope);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( RuntimeLifecycleDto lifecycle)?  runtimeStateChanged,TResult? Function( StartupPhaseDto phase)?  startupFailed,TResult? Function()?  appearanceSettingsChanged,TResult? Function()?  libraryRootsChanged,TResult? Function( String libraryRootId)?  libraryRootChanged,TResult? Function( String jobRunId)?  jobStateChanged,TResult? Function( String jobRunId,  String phase,  BigInt? completedUnits,  BigInt? totalUnits,  String? statusKey)?  jobProgress,TResult? Function( String libraryRootId,  SourceEntriesChangeScopeDto scope)?  sourceEntriesChanged,}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadDto_RuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadDto_StartupFailed() when startupFailed != null:
return startupFailed(_that.phase);case RuntimeEventPayloadDto_AppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged();case RuntimeEventPayloadDto_LibraryRootsChanged() when libraryRootsChanged != null:
return libraryRootsChanged();case RuntimeEventPayloadDto_LibraryRootChanged() when libraryRootChanged != null:
return libraryRootChanged(_that.libraryRootId);case RuntimeEventPayloadDto_JobStateChanged() when jobStateChanged != null:
return jobStateChanged(_that.jobRunId);case RuntimeEventPayloadDto_JobProgress() when jobProgress != null:
return jobProgress(_that.jobRunId,_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey);case RuntimeEventPayloadDto_SourceEntriesChanged() when sourceEntriesChanged != null:
return sourceEntriesChanged(_that.libraryRootId,_that.scope);case _:
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

/// @nodoc


class RuntimeEventPayloadDto_JobStateChanged extends RuntimeEventPayloadDto {
  const RuntimeEventPayloadDto_JobStateChanged({required this.jobRunId}): super._();


 final  String jobRunId;

/// Create a copy of RuntimeEventPayloadDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeEventPayloadDto_JobStateChangedCopyWith<RuntimeEventPayloadDto_JobStateChanged> get copyWith => _$RuntimeEventPayloadDto_JobStateChangedCopyWithImpl<RuntimeEventPayloadDto_JobStateChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadDto_JobStateChanged&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,jobRunId);

@override
String toString() {
  return 'RuntimeEventPayloadDto.jobStateChanged(jobRunId: $jobRunId)';
}


}

/// @nodoc
abstract mixin class $RuntimeEventPayloadDto_JobStateChangedCopyWith<$Res> implements $RuntimeEventPayloadDtoCopyWith<$Res> {
  factory $RuntimeEventPayloadDto_JobStateChangedCopyWith(RuntimeEventPayloadDto_JobStateChanged value, $Res Function(RuntimeEventPayloadDto_JobStateChanged) _then) = _$RuntimeEventPayloadDto_JobStateChangedCopyWithImpl;
@useResult
$Res call({
 String jobRunId
});




}
/// @nodoc
class _$RuntimeEventPayloadDto_JobStateChangedCopyWithImpl<$Res>
    implements $RuntimeEventPayloadDto_JobStateChangedCopyWith<$Res> {
  _$RuntimeEventPayloadDto_JobStateChangedCopyWithImpl(this._self, this._then);

  final RuntimeEventPayloadDto_JobStateChanged _self;
  final $Res Function(RuntimeEventPayloadDto_JobStateChanged) _then;

/// Create a copy of RuntimeEventPayloadDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? jobRunId = null,}) {
  return _then(RuntimeEventPayloadDto_JobStateChanged(
jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RuntimeEventPayloadDto_JobProgress extends RuntimeEventPayloadDto {
  const RuntimeEventPayloadDto_JobProgress({required this.jobRunId, required this.phase, this.completedUnits, this.totalUnits, this.statusKey}): super._();


 final  String jobRunId;
 final  String phase;
 final  BigInt? completedUnits;
 final  BigInt? totalUnits;
 final  String? statusKey;

/// Create a copy of RuntimeEventPayloadDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeEventPayloadDto_JobProgressCopyWith<RuntimeEventPayloadDto_JobProgress> get copyWith => _$RuntimeEventPayloadDto_JobProgressCopyWithImpl<RuntimeEventPayloadDto_JobProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadDto_JobProgress&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.completedUnits, completedUnits) || other.completedUnits == completedUnits)&&(identical(other.totalUnits, totalUnits) || other.totalUnits == totalUnits)&&(identical(other.statusKey, statusKey) || other.statusKey == statusKey));
}


@override
int get hashCode => Object.hash(runtimeType,jobRunId,phase,completedUnits,totalUnits,statusKey);

@override
String toString() {
  return 'RuntimeEventPayloadDto.jobProgress(jobRunId: $jobRunId, phase: $phase, completedUnits: $completedUnits, totalUnits: $totalUnits, statusKey: $statusKey)';
}


}

/// @nodoc
abstract mixin class $RuntimeEventPayloadDto_JobProgressCopyWith<$Res> implements $RuntimeEventPayloadDtoCopyWith<$Res> {
  factory $RuntimeEventPayloadDto_JobProgressCopyWith(RuntimeEventPayloadDto_JobProgress value, $Res Function(RuntimeEventPayloadDto_JobProgress) _then) = _$RuntimeEventPayloadDto_JobProgressCopyWithImpl;
@useResult
$Res call({
 String jobRunId, String phase, BigInt? completedUnits, BigInt? totalUnits, String? statusKey
});




}
/// @nodoc
class _$RuntimeEventPayloadDto_JobProgressCopyWithImpl<$Res>
    implements $RuntimeEventPayloadDto_JobProgressCopyWith<$Res> {
  _$RuntimeEventPayloadDto_JobProgressCopyWithImpl(this._self, this._then);

  final RuntimeEventPayloadDto_JobProgress _self;
  final $Res Function(RuntimeEventPayloadDto_JobProgress) _then;

/// Create a copy of RuntimeEventPayloadDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? jobRunId = null,Object? phase = null,Object? completedUnits = freezed,Object? totalUnits = freezed,Object? statusKey = freezed,}) {
  return _then(RuntimeEventPayloadDto_JobProgress(
jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as String,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String,completedUnits: freezed == completedUnits ? _self.completedUnits : completedUnits // ignore: cast_nullable_to_non_nullable
as BigInt?,totalUnits: freezed == totalUnits ? _self.totalUnits : totalUnits // ignore: cast_nullable_to_non_nullable
as BigInt?,statusKey: freezed == statusKey ? _self.statusKey : statusKey // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class RuntimeEventPayloadDto_SourceEntriesChanged extends RuntimeEventPayloadDto {
  const RuntimeEventPayloadDto_SourceEntriesChanged({required this.libraryRootId, required this.scope}): super._();


 final  String libraryRootId;
 final  SourceEntriesChangeScopeDto scope;

/// Create a copy of RuntimeEventPayloadDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeEventPayloadDto_SourceEntriesChangedCopyWith<RuntimeEventPayloadDto_SourceEntriesChanged> get copyWith => _$RuntimeEventPayloadDto_SourceEntriesChangedCopyWithImpl<RuntimeEventPayloadDto_SourceEntriesChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadDto_SourceEntriesChanged&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId)&&(identical(other.scope, scope) || other.scope == scope));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId,scope);

@override
String toString() {
  return 'RuntimeEventPayloadDto.sourceEntriesChanged(libraryRootId: $libraryRootId, scope: $scope)';
}


}

/// @nodoc
abstract mixin class $RuntimeEventPayloadDto_SourceEntriesChangedCopyWith<$Res> implements $RuntimeEventPayloadDtoCopyWith<$Res> {
  factory $RuntimeEventPayloadDto_SourceEntriesChangedCopyWith(RuntimeEventPayloadDto_SourceEntriesChanged value, $Res Function(RuntimeEventPayloadDto_SourceEntriesChanged) _then) = _$RuntimeEventPayloadDto_SourceEntriesChangedCopyWithImpl;
@useResult
$Res call({
 String libraryRootId, SourceEntriesChangeScopeDto scope
});


$SourceEntriesChangeScopeDtoCopyWith<$Res> get scope;

}
/// @nodoc
class _$RuntimeEventPayloadDto_SourceEntriesChangedCopyWithImpl<$Res>
    implements $RuntimeEventPayloadDto_SourceEntriesChangedCopyWith<$Res> {
  _$RuntimeEventPayloadDto_SourceEntriesChangedCopyWithImpl(this._self, this._then);

  final RuntimeEventPayloadDto_SourceEntriesChanged _self;
  final $Res Function(RuntimeEventPayloadDto_SourceEntriesChanged) _then;

/// Create a copy of RuntimeEventPayloadDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? libraryRootId = null,Object? scope = null,}) {
  return _then(RuntimeEventPayloadDto_SourceEntriesChanged(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as String,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as SourceEntriesChangeScopeDto,
  ));
}

/// Create a copy of RuntimeEventPayloadDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceEntriesChangeScopeDtoCopyWith<$Res> get scope {

  return $SourceEntriesChangeScopeDtoCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}

/// @nodoc
mixin _$SourceEntriesChangeScopeDto {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceEntriesChangeScopeDto);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourceEntriesChangeScopeDto()';
}


}

/// @nodoc
class $SourceEntriesChangeScopeDtoCopyWith<$Res>  {
$SourceEntriesChangeScopeDtoCopyWith(SourceEntriesChangeScopeDto _, $Res Function(SourceEntriesChangeScopeDto) __);
}


/// Adds pattern-matching-related methods to [SourceEntriesChangeScopeDto].
extension SourceEntriesChangeScopeDtoPatterns on SourceEntriesChangeScopeDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SourceEntriesChangeScopeDto_RootChildren value)?  rootChildren,TResult Function( SourceEntriesChangeScopeDto_EntryChildren value)?  entryChildren,TResult Function( SourceEntriesChangeScopeDto_EntireRootHierarchy value)?  entireRootHierarchy,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SourceEntriesChangeScopeDto_RootChildren() when rootChildren != null:
return rootChildren(_that);case SourceEntriesChangeScopeDto_EntryChildren() when entryChildren != null:
return entryChildren(_that);case SourceEntriesChangeScopeDto_EntireRootHierarchy() when entireRootHierarchy != null:
return entireRootHierarchy(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SourceEntriesChangeScopeDto_RootChildren value)  rootChildren,required TResult Function( SourceEntriesChangeScopeDto_EntryChildren value)  entryChildren,required TResult Function( SourceEntriesChangeScopeDto_EntireRootHierarchy value)  entireRootHierarchy,}){
final _that = this;
switch (_that) {
case SourceEntriesChangeScopeDto_RootChildren():
return rootChildren(_that);case SourceEntriesChangeScopeDto_EntryChildren():
return entryChildren(_that);case SourceEntriesChangeScopeDto_EntireRootHierarchy():
return entireRootHierarchy(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SourceEntriesChangeScopeDto_RootChildren value)?  rootChildren,TResult? Function( SourceEntriesChangeScopeDto_EntryChildren value)?  entryChildren,TResult? Function( SourceEntriesChangeScopeDto_EntireRootHierarchy value)?  entireRootHierarchy,}){
final _that = this;
switch (_that) {
case SourceEntriesChangeScopeDto_RootChildren() when rootChildren != null:
return rootChildren(_that);case SourceEntriesChangeScopeDto_EntryChildren() when entryChildren != null:
return entryChildren(_that);case SourceEntriesChangeScopeDto_EntireRootHierarchy() when entireRootHierarchy != null:
return entireRootHierarchy(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  rootChildren,TResult Function( String field0)?  entryChildren,TResult Function()?  entireRootHierarchy,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SourceEntriesChangeScopeDto_RootChildren() when rootChildren != null:
return rootChildren();case SourceEntriesChangeScopeDto_EntryChildren() when entryChildren != null:
return entryChildren(_that.field0);case SourceEntriesChangeScopeDto_EntireRootHierarchy() when entireRootHierarchy != null:
return entireRootHierarchy();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  rootChildren,required TResult Function( String field0)  entryChildren,required TResult Function()  entireRootHierarchy,}) {final _that = this;
switch (_that) {
case SourceEntriesChangeScopeDto_RootChildren():
return rootChildren();case SourceEntriesChangeScopeDto_EntryChildren():
return entryChildren(_that.field0);case SourceEntriesChangeScopeDto_EntireRootHierarchy():
return entireRootHierarchy();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  rootChildren,TResult? Function( String field0)?  entryChildren,TResult? Function()?  entireRootHierarchy,}) {final _that = this;
switch (_that) {
case SourceEntriesChangeScopeDto_RootChildren() when rootChildren != null:
return rootChildren();case SourceEntriesChangeScopeDto_EntryChildren() when entryChildren != null:
return entryChildren(_that.field0);case SourceEntriesChangeScopeDto_EntireRootHierarchy() when entireRootHierarchy != null:
return entireRootHierarchy();case _:
  return null;

}
}

}

/// @nodoc


class SourceEntriesChangeScopeDto_RootChildren extends SourceEntriesChangeScopeDto {
  const SourceEntriesChangeScopeDto_RootChildren(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceEntriesChangeScopeDto_RootChildren);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourceEntriesChangeScopeDto.rootChildren()';
}


}




/// @nodoc


class SourceEntriesChangeScopeDto_EntryChildren extends SourceEntriesChangeScopeDto {
  const SourceEntriesChangeScopeDto_EntryChildren(this.field0): super._();


 final  String field0;

/// Create a copy of SourceEntriesChangeScopeDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourceEntriesChangeScopeDto_EntryChildrenCopyWith<SourceEntriesChangeScopeDto_EntryChildren> get copyWith => _$SourceEntriesChangeScopeDto_EntryChildrenCopyWithImpl<SourceEntriesChangeScopeDto_EntryChildren>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceEntriesChangeScopeDto_EntryChildren&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'SourceEntriesChangeScopeDto.entryChildren(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $SourceEntriesChangeScopeDto_EntryChildrenCopyWith<$Res> implements $SourceEntriesChangeScopeDtoCopyWith<$Res> {
  factory $SourceEntriesChangeScopeDto_EntryChildrenCopyWith(SourceEntriesChangeScopeDto_EntryChildren value, $Res Function(SourceEntriesChangeScopeDto_EntryChildren) _then) = _$SourceEntriesChangeScopeDto_EntryChildrenCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$SourceEntriesChangeScopeDto_EntryChildrenCopyWithImpl<$Res>
    implements $SourceEntriesChangeScopeDto_EntryChildrenCopyWith<$Res> {
  _$SourceEntriesChangeScopeDto_EntryChildrenCopyWithImpl(this._self, this._then);

  final SourceEntriesChangeScopeDto_EntryChildren _self;
  final $Res Function(SourceEntriesChangeScopeDto_EntryChildren) _then;

/// Create a copy of SourceEntriesChangeScopeDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(SourceEntriesChangeScopeDto_EntryChildren(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SourceEntriesChangeScopeDto_EntireRootHierarchy extends SourceEntriesChangeScopeDto {
  const SourceEntriesChangeScopeDto_EntireRootHierarchy(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceEntriesChangeScopeDto_EntireRootHierarchy);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourceEntriesChangeScopeDto.entireRootHierarchy()';
}


}




/// @nodoc
mixin _$StartLibraryScanAllResultDto {

 List<LibraryScanAdmissionExclusionDto> get exclusions;
/// Create a copy of StartLibraryScanAllResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartLibraryScanAllResultDtoCopyWith<StartLibraryScanAllResultDto> get copyWith => _$StartLibraryScanAllResultDtoCopyWithImpl<StartLibraryScanAllResultDto>(this as StartLibraryScanAllResultDto, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartLibraryScanAllResultDto&&const DeepCollectionEquality().equals(other.exclusions, exclusions));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(exclusions));

@override
String toString() {
  return 'StartLibraryScanAllResultDto(exclusions: $exclusions)';
}


}

/// @nodoc
abstract mixin class $StartLibraryScanAllResultDtoCopyWith<$Res>  {
  factory $StartLibraryScanAllResultDtoCopyWith(StartLibraryScanAllResultDto value, $Res Function(StartLibraryScanAllResultDto) _then) = _$StartLibraryScanAllResultDtoCopyWithImpl;
@useResult
$Res call({
 List<LibraryScanAdmissionExclusionDto> exclusions
});




}
/// @nodoc
class _$StartLibraryScanAllResultDtoCopyWithImpl<$Res>
    implements $StartLibraryScanAllResultDtoCopyWith<$Res> {
  _$StartLibraryScanAllResultDtoCopyWithImpl(this._self, this._then);

  final StartLibraryScanAllResultDto _self;
  final $Res Function(StartLibraryScanAllResultDto) _then;

/// Create a copy of StartLibraryScanAllResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? exclusions = null,}) {
  return _then(_self.copyWith(
exclusions: null == exclusions ? _self.exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as List<LibraryScanAdmissionExclusionDto>,
  ));
}

}


/// Adds pattern-matching-related methods to [StartLibraryScanAllResultDto].
extension StartLibraryScanAllResultDtoPatterns on StartLibraryScanAllResultDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StartLibraryScanAllResultDto_Admitted value)?  admitted,TResult Function( StartLibraryScanAllResultDto_NothingEligible value)?  nothingEligible,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StartLibraryScanAllResultDto_Admitted() when admitted != null:
return admitted(_that);case StartLibraryScanAllResultDto_NothingEligible() when nothingEligible != null:
return nothingEligible(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StartLibraryScanAllResultDto_Admitted value)  admitted,required TResult Function( StartLibraryScanAllResultDto_NothingEligible value)  nothingEligible,}){
final _that = this;
switch (_that) {
case StartLibraryScanAllResultDto_Admitted():
return admitted(_that);case StartLibraryScanAllResultDto_NothingEligible():
return nothingEligible(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StartLibraryScanAllResultDto_Admitted value)?  admitted,TResult? Function( StartLibraryScanAllResultDto_NothingEligible value)?  nothingEligible,}){
final _that = this;
switch (_that) {
case StartLibraryScanAllResultDto_Admitted() when admitted != null:
return admitted(_that);case StartLibraryScanAllResultDto_NothingEligible() when nothingEligible != null:
return nothingEligible(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OperationHandleDto operationHandle,  List<String> admittedRoots,  List<LibraryScanAdmissionExclusionDto> exclusions)?  admitted,TResult Function( List<LibraryScanAdmissionExclusionDto> exclusions)?  nothingEligible,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StartLibraryScanAllResultDto_Admitted() when admitted != null:
return admitted(_that.operationHandle,_that.admittedRoots,_that.exclusions);case StartLibraryScanAllResultDto_NothingEligible() when nothingEligible != null:
return nothingEligible(_that.exclusions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OperationHandleDto operationHandle,  List<String> admittedRoots,  List<LibraryScanAdmissionExclusionDto> exclusions)  admitted,required TResult Function( List<LibraryScanAdmissionExclusionDto> exclusions)  nothingEligible,}) {final _that = this;
switch (_that) {
case StartLibraryScanAllResultDto_Admitted():
return admitted(_that.operationHandle,_that.admittedRoots,_that.exclusions);case StartLibraryScanAllResultDto_NothingEligible():
return nothingEligible(_that.exclusions);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OperationHandleDto operationHandle,  List<String> admittedRoots,  List<LibraryScanAdmissionExclusionDto> exclusions)?  admitted,TResult? Function( List<LibraryScanAdmissionExclusionDto> exclusions)?  nothingEligible,}) {final _that = this;
switch (_that) {
case StartLibraryScanAllResultDto_Admitted() when admitted != null:
return admitted(_that.operationHandle,_that.admittedRoots,_that.exclusions);case StartLibraryScanAllResultDto_NothingEligible() when nothingEligible != null:
return nothingEligible(_that.exclusions);case _:
  return null;

}
}

}

/// @nodoc


class StartLibraryScanAllResultDto_Admitted extends StartLibraryScanAllResultDto {
  const StartLibraryScanAllResultDto_Admitted({required this.operationHandle, required final  List<String> admittedRoots, required final  List<LibraryScanAdmissionExclusionDto> exclusions}): _admittedRoots = admittedRoots,_exclusions = exclusions,super._();


 final  OperationHandleDto operationHandle;
 final  List<String> _admittedRoots;
 List<String> get admittedRoots {
  if (_admittedRoots is EqualUnmodifiableListView) return _admittedRoots;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_admittedRoots);
}

 final  List<LibraryScanAdmissionExclusionDto> _exclusions;
@override List<LibraryScanAdmissionExclusionDto> get exclusions {
  if (_exclusions is EqualUnmodifiableListView) return _exclusions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_exclusions);
}


/// Create a copy of StartLibraryScanAllResultDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartLibraryScanAllResultDto_AdmittedCopyWith<StartLibraryScanAllResultDto_Admitted> get copyWith => _$StartLibraryScanAllResultDto_AdmittedCopyWithImpl<StartLibraryScanAllResultDto_Admitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartLibraryScanAllResultDto_Admitted&&(identical(other.operationHandle, operationHandle) || other.operationHandle == operationHandle)&&const DeepCollectionEquality().equals(other._admittedRoots, _admittedRoots)&&const DeepCollectionEquality().equals(other._exclusions, _exclusions));
}


@override
int get hashCode => Object.hash(runtimeType,operationHandle,const DeepCollectionEquality().hash(_admittedRoots),const DeepCollectionEquality().hash(_exclusions));

@override
String toString() {
  return 'StartLibraryScanAllResultDto.admitted(operationHandle: $operationHandle, admittedRoots: $admittedRoots, exclusions: $exclusions)';
}


}

/// @nodoc
abstract mixin class $StartLibraryScanAllResultDto_AdmittedCopyWith<$Res> implements $StartLibraryScanAllResultDtoCopyWith<$Res> {
  factory $StartLibraryScanAllResultDto_AdmittedCopyWith(StartLibraryScanAllResultDto_Admitted value, $Res Function(StartLibraryScanAllResultDto_Admitted) _then) = _$StartLibraryScanAllResultDto_AdmittedCopyWithImpl;
@override @useResult
$Res call({
 OperationHandleDto operationHandle, List<String> admittedRoots, List<LibraryScanAdmissionExclusionDto> exclusions
});




}
/// @nodoc
class _$StartLibraryScanAllResultDto_AdmittedCopyWithImpl<$Res>
    implements $StartLibraryScanAllResultDto_AdmittedCopyWith<$Res> {
  _$StartLibraryScanAllResultDto_AdmittedCopyWithImpl(this._self, this._then);

  final StartLibraryScanAllResultDto_Admitted _self;
  final $Res Function(StartLibraryScanAllResultDto_Admitted) _then;

/// Create a copy of StartLibraryScanAllResultDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationHandle = null,Object? admittedRoots = null,Object? exclusions = null,}) {
  return _then(StartLibraryScanAllResultDto_Admitted(
operationHandle: null == operationHandle ? _self.operationHandle : operationHandle // ignore: cast_nullable_to_non_nullable
as OperationHandleDto,admittedRoots: null == admittedRoots ? _self._admittedRoots : admittedRoots // ignore: cast_nullable_to_non_nullable
as List<String>,exclusions: null == exclusions ? _self._exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as List<LibraryScanAdmissionExclusionDto>,
  ));
}


}

/// @nodoc


class StartLibraryScanAllResultDto_NothingEligible extends StartLibraryScanAllResultDto {
  const StartLibraryScanAllResultDto_NothingEligible({required final  List<LibraryScanAdmissionExclusionDto> exclusions}): _exclusions = exclusions,super._();


 final  List<LibraryScanAdmissionExclusionDto> _exclusions;
@override List<LibraryScanAdmissionExclusionDto> get exclusions {
  if (_exclusions is EqualUnmodifiableListView) return _exclusions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_exclusions);
}


/// Create a copy of StartLibraryScanAllResultDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartLibraryScanAllResultDto_NothingEligibleCopyWith<StartLibraryScanAllResultDto_NothingEligible> get copyWith => _$StartLibraryScanAllResultDto_NothingEligibleCopyWithImpl<StartLibraryScanAllResultDto_NothingEligible>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartLibraryScanAllResultDto_NothingEligible&&const DeepCollectionEquality().equals(other._exclusions, _exclusions));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_exclusions));

@override
String toString() {
  return 'StartLibraryScanAllResultDto.nothingEligible(exclusions: $exclusions)';
}


}

/// @nodoc
abstract mixin class $StartLibraryScanAllResultDto_NothingEligibleCopyWith<$Res> implements $StartLibraryScanAllResultDtoCopyWith<$Res> {
  factory $StartLibraryScanAllResultDto_NothingEligibleCopyWith(StartLibraryScanAllResultDto_NothingEligible value, $Res Function(StartLibraryScanAllResultDto_NothingEligible) _then) = _$StartLibraryScanAllResultDto_NothingEligibleCopyWithImpl;
@override @useResult
$Res call({
 List<LibraryScanAdmissionExclusionDto> exclusions
});




}
/// @nodoc
class _$StartLibraryScanAllResultDto_NothingEligibleCopyWithImpl<$Res>
    implements $StartLibraryScanAllResultDto_NothingEligibleCopyWith<$Res> {
  _$StartLibraryScanAllResultDto_NothingEligibleCopyWithImpl(this._self, this._then);

  final StartLibraryScanAllResultDto_NothingEligible _self;
  final $Res Function(StartLibraryScanAllResultDto_NothingEligible) _then;

/// Create a copy of StartLibraryScanAllResultDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? exclusions = null,}) {
  return _then(StartLibraryScanAllResultDto_NothingEligible(
exclusions: null == exclusions ? _self._exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as List<LibraryScanAdmissionExclusionDto>,
  ));
}


}

/// @nodoc
mixin _$StartLibraryScanResultDto {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartLibraryScanResultDto);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'StartLibraryScanResultDto()';
}


}

/// @nodoc
class $StartLibraryScanResultDtoCopyWith<$Res>  {
$StartLibraryScanResultDtoCopyWith(StartLibraryScanResultDto _, $Res Function(StartLibraryScanResultDto) __);
}


/// Adds pattern-matching-related methods to [StartLibraryScanResultDto].
extension StartLibraryScanResultDtoPatterns on StartLibraryScanResultDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StartLibraryScanResultDto_Admitted value)?  admitted,TResult Function( StartLibraryScanResultDto_AlreadyScanning value)?  alreadyScanning,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StartLibraryScanResultDto_Admitted() when admitted != null:
return admitted(_that);case StartLibraryScanResultDto_AlreadyScanning() when alreadyScanning != null:
return alreadyScanning(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StartLibraryScanResultDto_Admitted value)  admitted,required TResult Function( StartLibraryScanResultDto_AlreadyScanning value)  alreadyScanning,}){
final _that = this;
switch (_that) {
case StartLibraryScanResultDto_Admitted():
return admitted(_that);case StartLibraryScanResultDto_AlreadyScanning():
return alreadyScanning(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StartLibraryScanResultDto_Admitted value)?  admitted,TResult? Function( StartLibraryScanResultDto_AlreadyScanning value)?  alreadyScanning,}){
final _that = this;
switch (_that) {
case StartLibraryScanResultDto_Admitted() when admitted != null:
return admitted(_that);case StartLibraryScanResultDto_AlreadyScanning() when alreadyScanning != null:
return alreadyScanning(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OperationHandleDto field0)?  admitted,TResult Function( String libraryRootId,  String activeJobRunId,  String activeScanRunId)?  alreadyScanning,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StartLibraryScanResultDto_Admitted() when admitted != null:
return admitted(_that.field0);case StartLibraryScanResultDto_AlreadyScanning() when alreadyScanning != null:
return alreadyScanning(_that.libraryRootId,_that.activeJobRunId,_that.activeScanRunId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OperationHandleDto field0)  admitted,required TResult Function( String libraryRootId,  String activeJobRunId,  String activeScanRunId)  alreadyScanning,}) {final _that = this;
switch (_that) {
case StartLibraryScanResultDto_Admitted():
return admitted(_that.field0);case StartLibraryScanResultDto_AlreadyScanning():
return alreadyScanning(_that.libraryRootId,_that.activeJobRunId,_that.activeScanRunId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OperationHandleDto field0)?  admitted,TResult? Function( String libraryRootId,  String activeJobRunId,  String activeScanRunId)?  alreadyScanning,}) {final _that = this;
switch (_that) {
case StartLibraryScanResultDto_Admitted() when admitted != null:
return admitted(_that.field0);case StartLibraryScanResultDto_AlreadyScanning() when alreadyScanning != null:
return alreadyScanning(_that.libraryRootId,_that.activeJobRunId,_that.activeScanRunId);case _:
  return null;

}
}

}

/// @nodoc


class StartLibraryScanResultDto_Admitted extends StartLibraryScanResultDto {
  const StartLibraryScanResultDto_Admitted(this.field0): super._();


 final  OperationHandleDto field0;

/// Create a copy of StartLibraryScanResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartLibraryScanResultDto_AdmittedCopyWith<StartLibraryScanResultDto_Admitted> get copyWith => _$StartLibraryScanResultDto_AdmittedCopyWithImpl<StartLibraryScanResultDto_Admitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartLibraryScanResultDto_Admitted&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'StartLibraryScanResultDto.admitted(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $StartLibraryScanResultDto_AdmittedCopyWith<$Res> implements $StartLibraryScanResultDtoCopyWith<$Res> {
  factory $StartLibraryScanResultDto_AdmittedCopyWith(StartLibraryScanResultDto_Admitted value, $Res Function(StartLibraryScanResultDto_Admitted) _then) = _$StartLibraryScanResultDto_AdmittedCopyWithImpl;
@useResult
$Res call({
 OperationHandleDto field0
});




}
/// @nodoc
class _$StartLibraryScanResultDto_AdmittedCopyWithImpl<$Res>
    implements $StartLibraryScanResultDto_AdmittedCopyWith<$Res> {
  _$StartLibraryScanResultDto_AdmittedCopyWithImpl(this._self, this._then);

  final StartLibraryScanResultDto_Admitted _self;
  final $Res Function(StartLibraryScanResultDto_Admitted) _then;

/// Create a copy of StartLibraryScanResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(StartLibraryScanResultDto_Admitted(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as OperationHandleDto,
  ));
}


}

/// @nodoc


class StartLibraryScanResultDto_AlreadyScanning extends StartLibraryScanResultDto {
  const StartLibraryScanResultDto_AlreadyScanning({required this.libraryRootId, required this.activeJobRunId, required this.activeScanRunId}): super._();


 final  String libraryRootId;
 final  String activeJobRunId;
 final  String activeScanRunId;

/// Create a copy of StartLibraryScanResultDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartLibraryScanResultDto_AlreadyScanningCopyWith<StartLibraryScanResultDto_AlreadyScanning> get copyWith => _$StartLibraryScanResultDto_AlreadyScanningCopyWithImpl<StartLibraryScanResultDto_AlreadyScanning>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartLibraryScanResultDto_AlreadyScanning&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId)&&(identical(other.activeJobRunId, activeJobRunId) || other.activeJobRunId == activeJobRunId)&&(identical(other.activeScanRunId, activeScanRunId) || other.activeScanRunId == activeScanRunId));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId,activeJobRunId,activeScanRunId);

@override
String toString() {
  return 'StartLibraryScanResultDto.alreadyScanning(libraryRootId: $libraryRootId, activeJobRunId: $activeJobRunId, activeScanRunId: $activeScanRunId)';
}


}

/// @nodoc
abstract mixin class $StartLibraryScanResultDto_AlreadyScanningCopyWith<$Res> implements $StartLibraryScanResultDtoCopyWith<$Res> {
  factory $StartLibraryScanResultDto_AlreadyScanningCopyWith(StartLibraryScanResultDto_AlreadyScanning value, $Res Function(StartLibraryScanResultDto_AlreadyScanning) _then) = _$StartLibraryScanResultDto_AlreadyScanningCopyWithImpl;
@useResult
$Res call({
 String libraryRootId, String activeJobRunId, String activeScanRunId
});




}
/// @nodoc
class _$StartLibraryScanResultDto_AlreadyScanningCopyWithImpl<$Res>
    implements $StartLibraryScanResultDto_AlreadyScanningCopyWith<$Res> {
  _$StartLibraryScanResultDto_AlreadyScanningCopyWithImpl(this._self, this._then);

  final StartLibraryScanResultDto_AlreadyScanning _self;
  final $Res Function(StartLibraryScanResultDto_AlreadyScanning) _then;

/// Create a copy of StartLibraryScanResultDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? libraryRootId = null,Object? activeJobRunId = null,Object? activeScanRunId = null,}) {
  return _then(StartLibraryScanResultDto_AlreadyScanning(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as String,activeJobRunId: null == activeJobRunId ? _self.activeJobRunId : activeJobRunId // ignore: cast_nullable_to_non_nullable
as String,activeScanRunId: null == activeScanRunId ? _self.activeScanRunId : activeScanRunId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
