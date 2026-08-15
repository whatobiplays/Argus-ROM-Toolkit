// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'add_library_folder_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SourcesAddOperation {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesAddOperation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourcesAddOperation()';
}


}

/// @nodoc
class $SourcesAddOperationCopyWith<$Res>  {
$SourcesAddOperationCopyWith(SourcesAddOperation _, $Res Function(SourcesAddOperation) __);
}


/// Adds pattern-matching-related methods to [SourcesAddOperation].
extension SourcesAddOperationPatterns on SourcesAddOperation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SourcesAddOperationIdle value)?  idle,TResult Function( SourcesAddOperationSubmitting value)?  submitting,TResult Function( SourcesAddOperationAdded value)?  added,TResult Function( SourcesAddOperationAlreadyConfigured value)?  alreadyConfigured,TResult Function( SourcesAddOperationOverlapsExisting value)?  overlapsExisting,TResult Function( SourcesAddOperationFailed value)?  failed,TResult Function( SourcesAddOperationAmbiguous value)?  ambiguous,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SourcesAddOperationIdle() when idle != null:
return idle(_that);case SourcesAddOperationSubmitting() when submitting != null:
return submitting(_that);case SourcesAddOperationAdded() when added != null:
return added(_that);case SourcesAddOperationAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that);case SourcesAddOperationOverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that);case SourcesAddOperationFailed() when failed != null:
return failed(_that);case SourcesAddOperationAmbiguous() when ambiguous != null:
return ambiguous(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SourcesAddOperationIdle value)  idle,required TResult Function( SourcesAddOperationSubmitting value)  submitting,required TResult Function( SourcesAddOperationAdded value)  added,required TResult Function( SourcesAddOperationAlreadyConfigured value)  alreadyConfigured,required TResult Function( SourcesAddOperationOverlapsExisting value)  overlapsExisting,required TResult Function( SourcesAddOperationFailed value)  failed,required TResult Function( SourcesAddOperationAmbiguous value)  ambiguous,}){
final _that = this;
switch (_that) {
case SourcesAddOperationIdle():
return idle(_that);case SourcesAddOperationSubmitting():
return submitting(_that);case SourcesAddOperationAdded():
return added(_that);case SourcesAddOperationAlreadyConfigured():
return alreadyConfigured(_that);case SourcesAddOperationOverlapsExisting():
return overlapsExisting(_that);case SourcesAddOperationFailed():
return failed(_that);case SourcesAddOperationAmbiguous():
return ambiguous(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SourcesAddOperationIdle value)?  idle,TResult? Function( SourcesAddOperationSubmitting value)?  submitting,TResult? Function( SourcesAddOperationAdded value)?  added,TResult? Function( SourcesAddOperationAlreadyConfigured value)?  alreadyConfigured,TResult? Function( SourcesAddOperationOverlapsExisting value)?  overlapsExisting,TResult? Function( SourcesAddOperationFailed value)?  failed,TResult? Function( SourcesAddOperationAmbiguous value)?  ambiguous,}){
final _that = this;
switch (_that) {
case SourcesAddOperationIdle() when idle != null:
return idle(_that);case SourcesAddOperationSubmitting() when submitting != null:
return submitting(_that);case SourcesAddOperationAdded() when added != null:
return added(_that);case SourcesAddOperationAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that);case SourcesAddOperationOverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that);case SourcesAddOperationFailed() when failed != null:
return failed(_that);case SourcesAddOperationAmbiguous() when ambiguous != null:
return ambiguous(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  submitting,TResult Function( LibraryRoot root)?  added,TResult Function( LibraryRootId existingLibraryRootId)?  alreadyConfigured,TResult Function( LibraryRootId existingLibraryRootId,  RootRelationship relationship)?  overlapsExisting,TResult Function( ClientFailure failure)?  failed,TResult Function( TransportFailure failure)?  ambiguous,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SourcesAddOperationIdle() when idle != null:
return idle();case SourcesAddOperationSubmitting() when submitting != null:
return submitting();case SourcesAddOperationAdded() when added != null:
return added(_that.root);case SourcesAddOperationAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that.existingLibraryRootId);case SourcesAddOperationOverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that.existingLibraryRootId,_that.relationship);case SourcesAddOperationFailed() when failed != null:
return failed(_that.failure);case SourcesAddOperationAmbiguous() when ambiguous != null:
return ambiguous(_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  submitting,required TResult Function( LibraryRoot root)  added,required TResult Function( LibraryRootId existingLibraryRootId)  alreadyConfigured,required TResult Function( LibraryRootId existingLibraryRootId,  RootRelationship relationship)  overlapsExisting,required TResult Function( ClientFailure failure)  failed,required TResult Function( TransportFailure failure)  ambiguous,}) {final _that = this;
switch (_that) {
case SourcesAddOperationIdle():
return idle();case SourcesAddOperationSubmitting():
return submitting();case SourcesAddOperationAdded():
return added(_that.root);case SourcesAddOperationAlreadyConfigured():
return alreadyConfigured(_that.existingLibraryRootId);case SourcesAddOperationOverlapsExisting():
return overlapsExisting(_that.existingLibraryRootId,_that.relationship);case SourcesAddOperationFailed():
return failed(_that.failure);case SourcesAddOperationAmbiguous():
return ambiguous(_that.failure);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  submitting,TResult? Function( LibraryRoot root)?  added,TResult? Function( LibraryRootId existingLibraryRootId)?  alreadyConfigured,TResult? Function( LibraryRootId existingLibraryRootId,  RootRelationship relationship)?  overlapsExisting,TResult? Function( ClientFailure failure)?  failed,TResult? Function( TransportFailure failure)?  ambiguous,}) {final _that = this;
switch (_that) {
case SourcesAddOperationIdle() when idle != null:
return idle();case SourcesAddOperationSubmitting() when submitting != null:
return submitting();case SourcesAddOperationAdded() when added != null:
return added(_that.root);case SourcesAddOperationAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that.existingLibraryRootId);case SourcesAddOperationOverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that.existingLibraryRootId,_that.relationship);case SourcesAddOperationFailed() when failed != null:
return failed(_that.failure);case SourcesAddOperationAmbiguous() when ambiguous != null:
return ambiguous(_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class SourcesAddOperationIdle implements SourcesAddOperation {
  const SourcesAddOperationIdle();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesAddOperationIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourcesAddOperation.idle()';
}


}




/// @nodoc


class SourcesAddOperationSubmitting implements SourcesAddOperation {
  const SourcesAddOperationSubmitting();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesAddOperationSubmitting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourcesAddOperation.submitting()';
}


}




/// @nodoc


class SourcesAddOperationAdded implements SourcesAddOperation {
  const SourcesAddOperationAdded(this.root);


 final  LibraryRoot root;

/// Create a copy of SourcesAddOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourcesAddOperationAddedCopyWith<SourcesAddOperationAdded> get copyWith => _$SourcesAddOperationAddedCopyWithImpl<SourcesAddOperationAdded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesAddOperationAdded&&(identical(other.root, root) || other.root == root));
}


@override
int get hashCode => Object.hash(runtimeType,root);

@override
String toString() {
  return 'SourcesAddOperation.added(root: $root)';
}


}

/// @nodoc
abstract mixin class $SourcesAddOperationAddedCopyWith<$Res> implements $SourcesAddOperationCopyWith<$Res> {
  factory $SourcesAddOperationAddedCopyWith(SourcesAddOperationAdded value, $Res Function(SourcesAddOperationAdded) _then) = _$SourcesAddOperationAddedCopyWithImpl;
@useResult
$Res call({
 LibraryRoot root
});


$LibraryRootCopyWith<$Res> get root;

}
/// @nodoc
class _$SourcesAddOperationAddedCopyWithImpl<$Res>
    implements $SourcesAddOperationAddedCopyWith<$Res> {
  _$SourcesAddOperationAddedCopyWithImpl(this._self, this._then);

  final SourcesAddOperationAdded _self;
  final $Res Function(SourcesAddOperationAdded) _then;

/// Create a copy of SourcesAddOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? root = null,}) {
  return _then(SourcesAddOperationAdded(
null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as LibraryRoot,
  ));
}

/// Create a copy of SourcesAddOperation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LibraryRootCopyWith<$Res> get root {

  return $LibraryRootCopyWith<$Res>(_self.root, (value) {
    return _then(_self.copyWith(root: value));
  });
}
}

/// @nodoc


class SourcesAddOperationAlreadyConfigured implements SourcesAddOperation {
  const SourcesAddOperationAlreadyConfigured(this.existingLibraryRootId);


 final  LibraryRootId existingLibraryRootId;

/// Create a copy of SourcesAddOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourcesAddOperationAlreadyConfiguredCopyWith<SourcesAddOperationAlreadyConfigured> get copyWith => _$SourcesAddOperationAlreadyConfiguredCopyWithImpl<SourcesAddOperationAlreadyConfigured>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesAddOperationAlreadyConfigured&&(identical(other.existingLibraryRootId, existingLibraryRootId) || other.existingLibraryRootId == existingLibraryRootId));
}


@override
int get hashCode => Object.hash(runtimeType,existingLibraryRootId);

@override
String toString() {
  return 'SourcesAddOperation.alreadyConfigured(existingLibraryRootId: $existingLibraryRootId)';
}


}

/// @nodoc
abstract mixin class $SourcesAddOperationAlreadyConfiguredCopyWith<$Res> implements $SourcesAddOperationCopyWith<$Res> {
  factory $SourcesAddOperationAlreadyConfiguredCopyWith(SourcesAddOperationAlreadyConfigured value, $Res Function(SourcesAddOperationAlreadyConfigured) _then) = _$SourcesAddOperationAlreadyConfiguredCopyWithImpl;
@useResult
$Res call({
 LibraryRootId existingLibraryRootId
});




}
/// @nodoc
class _$SourcesAddOperationAlreadyConfiguredCopyWithImpl<$Res>
    implements $SourcesAddOperationAlreadyConfiguredCopyWith<$Res> {
  _$SourcesAddOperationAlreadyConfiguredCopyWithImpl(this._self, this._then);

  final SourcesAddOperationAlreadyConfigured _self;
  final $Res Function(SourcesAddOperationAlreadyConfigured) _then;

/// Create a copy of SourcesAddOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? existingLibraryRootId = null,}) {
  return _then(SourcesAddOperationAlreadyConfigured(
null == existingLibraryRootId ? _self.existingLibraryRootId : existingLibraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,
  ));
}


}

/// @nodoc


class SourcesAddOperationOverlapsExisting implements SourcesAddOperation {
  const SourcesAddOperationOverlapsExisting({required this.existingLibraryRootId, required this.relationship});


 final  LibraryRootId existingLibraryRootId;
 final  RootRelationship relationship;

/// Create a copy of SourcesAddOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourcesAddOperationOverlapsExistingCopyWith<SourcesAddOperationOverlapsExisting> get copyWith => _$SourcesAddOperationOverlapsExistingCopyWithImpl<SourcesAddOperationOverlapsExisting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesAddOperationOverlapsExisting&&(identical(other.existingLibraryRootId, existingLibraryRootId) || other.existingLibraryRootId == existingLibraryRootId)&&(identical(other.relationship, relationship) || other.relationship == relationship));
}


@override
int get hashCode => Object.hash(runtimeType,existingLibraryRootId,relationship);

@override
String toString() {
  return 'SourcesAddOperation.overlapsExisting(existingLibraryRootId: $existingLibraryRootId, relationship: $relationship)';
}


}

/// @nodoc
abstract mixin class $SourcesAddOperationOverlapsExistingCopyWith<$Res> implements $SourcesAddOperationCopyWith<$Res> {
  factory $SourcesAddOperationOverlapsExistingCopyWith(SourcesAddOperationOverlapsExisting value, $Res Function(SourcesAddOperationOverlapsExisting) _then) = _$SourcesAddOperationOverlapsExistingCopyWithImpl;
@useResult
$Res call({
 LibraryRootId existingLibraryRootId, RootRelationship relationship
});




}
/// @nodoc
class _$SourcesAddOperationOverlapsExistingCopyWithImpl<$Res>
    implements $SourcesAddOperationOverlapsExistingCopyWith<$Res> {
  _$SourcesAddOperationOverlapsExistingCopyWithImpl(this._self, this._then);

  final SourcesAddOperationOverlapsExisting _self;
  final $Res Function(SourcesAddOperationOverlapsExisting) _then;

/// Create a copy of SourcesAddOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? existingLibraryRootId = null,Object? relationship = null,}) {
  return _then(SourcesAddOperationOverlapsExisting(
existingLibraryRootId: null == existingLibraryRootId ? _self.existingLibraryRootId : existingLibraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,relationship: null == relationship ? _self.relationship : relationship // ignore: cast_nullable_to_non_nullable
as RootRelationship,
  ));
}


}

/// @nodoc


class SourcesAddOperationFailed implements SourcesAddOperation {
  const SourcesAddOperationFailed(this.failure);


 final  ClientFailure failure;

/// Create a copy of SourcesAddOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourcesAddOperationFailedCopyWith<SourcesAddOperationFailed> get copyWith => _$SourcesAddOperationFailedCopyWithImpl<SourcesAddOperationFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesAddOperationFailed&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode => Object.hash(runtimeType,failure);

@override
String toString() {
  return 'SourcesAddOperation.failed(failure: $failure)';
}


}

/// @nodoc
abstract mixin class $SourcesAddOperationFailedCopyWith<$Res> implements $SourcesAddOperationCopyWith<$Res> {
  factory $SourcesAddOperationFailedCopyWith(SourcesAddOperationFailed value, $Res Function(SourcesAddOperationFailed) _then) = _$SourcesAddOperationFailedCopyWithImpl;
@useResult
$Res call({
 ClientFailure failure
});




}
/// @nodoc
class _$SourcesAddOperationFailedCopyWithImpl<$Res>
    implements $SourcesAddOperationFailedCopyWith<$Res> {
  _$SourcesAddOperationFailedCopyWithImpl(this._self, this._then);

  final SourcesAddOperationFailed _self;
  final $Res Function(SourcesAddOperationFailed) _then;

/// Create a copy of SourcesAddOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(SourcesAddOperationFailed(
null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as ClientFailure,
  ));
}


}

/// @nodoc


class SourcesAddOperationAmbiguous implements SourcesAddOperation {
  const SourcesAddOperationAmbiguous(this.failure);


 final  TransportFailure failure;

/// Create a copy of SourcesAddOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourcesAddOperationAmbiguousCopyWith<SourcesAddOperationAmbiguous> get copyWith => _$SourcesAddOperationAmbiguousCopyWithImpl<SourcesAddOperationAmbiguous>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesAddOperationAmbiguous&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode => Object.hash(runtimeType,failure);

@override
String toString() {
  return 'SourcesAddOperation.ambiguous(failure: $failure)';
}


}

/// @nodoc
abstract mixin class $SourcesAddOperationAmbiguousCopyWith<$Res> implements $SourcesAddOperationCopyWith<$Res> {
  factory $SourcesAddOperationAmbiguousCopyWith(SourcesAddOperationAmbiguous value, $Res Function(SourcesAddOperationAmbiguous) _then) = _$SourcesAddOperationAmbiguousCopyWithImpl;
@useResult
$Res call({
 TransportFailure failure
});




}
/// @nodoc
class _$SourcesAddOperationAmbiguousCopyWithImpl<$Res>
    implements $SourcesAddOperationAmbiguousCopyWith<$Res> {
  _$SourcesAddOperationAmbiguousCopyWithImpl(this._self, this._then);

  final SourcesAddOperationAmbiguous _self;
  final $Res Function(SourcesAddOperationAmbiguous) _then;

/// Create a copy of SourcesAddOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(SourcesAddOperationAmbiguous(
null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as TransportFailure,
  ));
}


}

// dart format on
