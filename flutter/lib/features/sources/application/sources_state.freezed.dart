// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sources_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SourcesRuntimeContext {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesRuntimeContext);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourcesRuntimeContext()';
}


}

/// @nodoc
class $SourcesRuntimeContextCopyWith<$Res>  {
$SourcesRuntimeContextCopyWith(SourcesRuntimeContext _, $Res Function(SourcesRuntimeContext) __);
}


/// Adds pattern-matching-related methods to [SourcesRuntimeContext].
extension SourcesRuntimeContextPatterns on SourcesRuntimeContext {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SourcesRuntimeContextPreReady value)?  preReady,TResult Function( SourcesRuntimeContextReady value)?  ready,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SourcesRuntimeContextPreReady() when preReady != null:
return preReady(_that);case SourcesRuntimeContextReady() when ready != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SourcesRuntimeContextPreReady value)  preReady,required TResult Function( SourcesRuntimeContextReady value)  ready,}){
final _that = this;
switch (_that) {
case SourcesRuntimeContextPreReady():
return preReady(_that);case SourcesRuntimeContextReady():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SourcesRuntimeContextPreReady value)?  preReady,TResult? Function( SourcesRuntimeContextReady value)?  ready,}){
final _that = this;
switch (_that) {
case SourcesRuntimeContextPreReady() when preReady != null:
return preReady(_that);case SourcesRuntimeContextReady() when ready != null:
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
case SourcesRuntimeContextPreReady() when preReady != null:
return preReady();case SourcesRuntimeContextReady() when ready != null:
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
case SourcesRuntimeContextPreReady():
return preReady();case SourcesRuntimeContextReady():
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
case SourcesRuntimeContextPreReady() when preReady != null:
return preReady();case SourcesRuntimeContextReady() when ready != null:
return ready(_that.runtimeInstanceId);case _:
  return null;

}
}

}

/// @nodoc


class SourcesRuntimeContextPreReady implements SourcesRuntimeContext {
  const SourcesRuntimeContextPreReady();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesRuntimeContextPreReady);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourcesRuntimeContext.preReady()';
}


}




/// @nodoc


class SourcesRuntimeContextReady implements SourcesRuntimeContext {
  const SourcesRuntimeContextReady({required this.runtimeInstanceId});


 final  RuntimeInstanceId runtimeInstanceId;

/// Create a copy of SourcesRuntimeContext
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourcesRuntimeContextReadyCopyWith<SourcesRuntimeContextReady> get copyWith => _$SourcesRuntimeContextReadyCopyWithImpl<SourcesRuntimeContextReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesRuntimeContextReady&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId);

@override
String toString() {
  return 'SourcesRuntimeContext.ready(runtimeInstanceId: $runtimeInstanceId)';
}


}

/// @nodoc
abstract mixin class $SourcesRuntimeContextReadyCopyWith<$Res> implements $SourcesRuntimeContextCopyWith<$Res> {
  factory $SourcesRuntimeContextReadyCopyWith(SourcesRuntimeContextReady value, $Res Function(SourcesRuntimeContextReady) _then) = _$SourcesRuntimeContextReadyCopyWithImpl;
@useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId
});




}
/// @nodoc
class _$SourcesRuntimeContextReadyCopyWithImpl<$Res>
    implements $SourcesRuntimeContextReadyCopyWith<$Res> {
  _$SourcesRuntimeContextReadyCopyWithImpl(this._self, this._then);

  final SourcesRuntimeContextReady _self;
  final $Res Function(SourcesRuntimeContextReady) _then;

/// Create a copy of SourcesRuntimeContext
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,}) {
  return _then(SourcesRuntimeContextReady(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,
  ));
}


}

/// @nodoc
mixin _$SourcesReconciliationDemand {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesReconciliationDemand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourcesReconciliationDemand()';
}


}

/// @nodoc
class $SourcesReconciliationDemandCopyWith<$Res>  {
$SourcesReconciliationDemandCopyWith(SourcesReconciliationDemand _, $Res Function(SourcesReconciliationDemand) __);
}


/// Adds pattern-matching-related methods to [SourcesReconciliationDemand].
extension SourcesReconciliationDemandPatterns on SourcesReconciliationDemand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SourcesReconciliationDemandRootsChanged value)?  rootsChanged,TResult Function( SourcesReconciliationDemandRootChanged value)?  rootChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SourcesReconciliationDemandRootsChanged() when rootsChanged != null:
return rootsChanged(_that);case SourcesReconciliationDemandRootChanged() when rootChanged != null:
return rootChanged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SourcesReconciliationDemandRootsChanged value)  rootsChanged,required TResult Function( SourcesReconciliationDemandRootChanged value)  rootChanged,}){
final _that = this;
switch (_that) {
case SourcesReconciliationDemandRootsChanged():
return rootsChanged(_that);case SourcesReconciliationDemandRootChanged():
return rootChanged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SourcesReconciliationDemandRootsChanged value)?  rootsChanged,TResult? Function( SourcesReconciliationDemandRootChanged value)?  rootChanged,}){
final _that = this;
switch (_that) {
case SourcesReconciliationDemandRootsChanged() when rootsChanged != null:
return rootsChanged(_that);case SourcesReconciliationDemandRootChanged() when rootChanged != null:
return rootChanged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  rootsChanged,TResult Function( LibraryRootId libraryRootId)?  rootChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SourcesReconciliationDemandRootsChanged() when rootsChanged != null:
return rootsChanged();case SourcesReconciliationDemandRootChanged() when rootChanged != null:
return rootChanged(_that.libraryRootId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  rootsChanged,required TResult Function( LibraryRootId libraryRootId)  rootChanged,}) {final _that = this;
switch (_that) {
case SourcesReconciliationDemandRootsChanged():
return rootsChanged();case SourcesReconciliationDemandRootChanged():
return rootChanged(_that.libraryRootId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  rootsChanged,TResult? Function( LibraryRootId libraryRootId)?  rootChanged,}) {final _that = this;
switch (_that) {
case SourcesReconciliationDemandRootsChanged() when rootsChanged != null:
return rootsChanged();case SourcesReconciliationDemandRootChanged() when rootChanged != null:
return rootChanged(_that.libraryRootId);case _:
  return null;

}
}

}

/// @nodoc


class SourcesReconciliationDemandRootsChanged implements SourcesReconciliationDemand {
  const SourcesReconciliationDemandRootsChanged();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesReconciliationDemandRootsChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourcesReconciliationDemand.rootsChanged()';
}


}




/// @nodoc


class SourcesReconciliationDemandRootChanged implements SourcesReconciliationDemand {
  const SourcesReconciliationDemandRootChanged({required this.libraryRootId});


 final  LibraryRootId libraryRootId;

/// Create a copy of SourcesReconciliationDemand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourcesReconciliationDemandRootChangedCopyWith<SourcesReconciliationDemandRootChanged> get copyWith => _$SourcesReconciliationDemandRootChangedCopyWithImpl<SourcesReconciliationDemandRootChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourcesReconciliationDemandRootChanged&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId);

@override
String toString() {
  return 'SourcesReconciliationDemand.rootChanged(libraryRootId: $libraryRootId)';
}


}

/// @nodoc
abstract mixin class $SourcesReconciliationDemandRootChangedCopyWith<$Res> implements $SourcesReconciliationDemandCopyWith<$Res> {
  factory $SourcesReconciliationDemandRootChangedCopyWith(SourcesReconciliationDemandRootChanged value, $Res Function(SourcesReconciliationDemandRootChanged) _then) = _$SourcesReconciliationDemandRootChangedCopyWithImpl;
@useResult
$Res call({
 LibraryRootId libraryRootId
});




}
/// @nodoc
class _$SourcesReconciliationDemandRootChangedCopyWithImpl<$Res>
    implements $SourcesReconciliationDemandRootChangedCopyWith<$Res> {
  _$SourcesReconciliationDemandRootChangedCopyWithImpl(this._self, this._then);

  final SourcesReconciliationDemandRootChanged _self;
  final $Res Function(SourcesReconciliationDemandRootChanged) _then;

/// Create a copy of SourcesReconciliationDemand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? libraryRootId = null,}) {
  return _then(SourcesReconciliationDemandRootChanged(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,
  ));
}


}

// dart format on
