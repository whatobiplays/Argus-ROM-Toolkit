// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'root_detail_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SourcesRootDetailState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesRootDetailState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourcesRootDetailState()';
}


}

/// @nodoc
class $SourcesRootDetailStateCopyWith<$Res>  {
$SourcesRootDetailStateCopyWith(SourcesRootDetailState _, $Res Function(SourcesRootDetailState) __);
}


/// Adds pattern-matching-related methods to [SourcesRootDetailState].
extension SourcesRootDetailStatePatterns on SourcesRootDetailState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SourcesRootDetailStateReady value)?  ready,TResult Function( SourcesRootDetailStateMissing value)?  missing,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SourcesRootDetailStateReady() when ready != null:
return ready(_that);case SourcesRootDetailStateMissing() when missing != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SourcesRootDetailStateReady value)  ready,required TResult Function( SourcesRootDetailStateMissing value)  missing,}){
final _that = this;
switch (_that) {
case SourcesRootDetailStateReady():
return ready(_that);case SourcesRootDetailStateMissing():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SourcesRootDetailStateReady value)?  ready,TResult? Function( SourcesRootDetailStateMissing value)?  missing,}){
final _that = this;
switch (_that) {
case SourcesRootDetailStateReady() when ready != null:
return ready(_that);case SourcesRootDetailStateMissing() when missing != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( LibraryRoot root,  bool refreshing,  ClientFailure? lastFailure,  bool removing,  bool removalAmbiguous)?  ready,TResult Function()?  missing,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SourcesRootDetailStateReady() when ready != null:
return ready(_that.root,_that.refreshing,_that.lastFailure,_that.removing,_that.removalAmbiguous);case SourcesRootDetailStateMissing() when missing != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( LibraryRoot root,  bool refreshing,  ClientFailure? lastFailure,  bool removing,  bool removalAmbiguous)  ready,required TResult Function()  missing,}) {final _that = this;
switch (_that) {
case SourcesRootDetailStateReady():
return ready(_that.root,_that.refreshing,_that.lastFailure,_that.removing,_that.removalAmbiguous);case SourcesRootDetailStateMissing():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( LibraryRoot root,  bool refreshing,  ClientFailure? lastFailure,  bool removing,  bool removalAmbiguous)?  ready,TResult? Function()?  missing,}) {final _that = this;
switch (_that) {
case SourcesRootDetailStateReady() when ready != null:
return ready(_that.root,_that.refreshing,_that.lastFailure,_that.removing,_that.removalAmbiguous);case SourcesRootDetailStateMissing() when missing != null:
return missing();case _:
  return null;

}
}

}

/// @nodoc


class SourcesRootDetailStateReady implements SourcesRootDetailState {
  const SourcesRootDetailStateReady({required this.root, required this.refreshing, this.lastFailure, required this.removing, required this.removalAmbiguous});


 final  LibraryRoot root;
 final  bool refreshing;
 final  ClientFailure? lastFailure;
 final  bool removing;
 final  bool removalAmbiguous;

/// Create a copy of SourcesRootDetailState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourcesRootDetailStateReadyCopyWith<SourcesRootDetailStateReady> get copyWith => _$SourcesRootDetailStateReadyCopyWithImpl<SourcesRootDetailStateReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesRootDetailStateReady&&(identical(other.root, root) || other.root == root)&&(identical(other.refreshing, refreshing) || other.refreshing == refreshing)&&(identical(other.lastFailure, lastFailure) || other.lastFailure == lastFailure)&&(identical(other.removing, removing) || other.removing == removing)&&(identical(other.removalAmbiguous, removalAmbiguous) || other.removalAmbiguous == removalAmbiguous));
}


@override
int get hashCode => Object.hash(runtimeType,root,refreshing,lastFailure,removing,removalAmbiguous);

@override
String toString() {
  return 'SourcesRootDetailState.ready(root: $root, refreshing: $refreshing, lastFailure: $lastFailure, removing: $removing, removalAmbiguous: $removalAmbiguous)';
}


}

/// @nodoc
abstract mixin class $SourcesRootDetailStateReadyCopyWith<$Res> implements $SourcesRootDetailStateCopyWith<$Res> {
  factory $SourcesRootDetailStateReadyCopyWith(SourcesRootDetailStateReady value, $Res Function(SourcesRootDetailStateReady) _then) = _$SourcesRootDetailStateReadyCopyWithImpl;
@useResult
$Res call({
 LibraryRoot root, bool refreshing, ClientFailure? lastFailure, bool removing, bool removalAmbiguous
});


$LibraryRootCopyWith<$Res> get root;

}
/// @nodoc
class _$SourcesRootDetailStateReadyCopyWithImpl<$Res>
    implements $SourcesRootDetailStateReadyCopyWith<$Res> {
  _$SourcesRootDetailStateReadyCopyWithImpl(this._self, this._then);

  final SourcesRootDetailStateReady _self;
  final $Res Function(SourcesRootDetailStateReady) _then;

/// Create a copy of SourcesRootDetailState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? root = null,Object? refreshing = null,Object? lastFailure = freezed,Object? removing = null,Object? removalAmbiguous = null,}) {
  return _then(SourcesRootDetailStateReady(
root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as LibraryRoot,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as bool,lastFailure: freezed == lastFailure ? _self.lastFailure : lastFailure // ignore: cast_nullable_to_non_nullable
as ClientFailure?,removing: null == removing ? _self.removing : removing // ignore: cast_nullable_to_non_nullable
as bool,removalAmbiguous: null == removalAmbiguous ? _self.removalAmbiguous : removalAmbiguous // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of SourcesRootDetailState
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


class SourcesRootDetailStateMissing implements SourcesRootDetailState {
  const SourcesRootDetailStateMissing();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesRootDetailStateMissing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourcesRootDetailState.missing()';
}


}




// dart format on
