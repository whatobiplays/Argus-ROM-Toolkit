// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'local_filesystem_browser_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LocalFilesystemBrowserState {

 List<LocalFilesystemBrowseRoot> get roots; LocalFilesystemBrowsePage? get page; bool get loading; bool get loadingMore; ClientFailure? get failure;
/// Create a copy of LocalFilesystemBrowserState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LocalFilesystemBrowserStateCopyWith<LocalFilesystemBrowserState> get copyWith => _$LocalFilesystemBrowserStateCopyWithImpl<LocalFilesystemBrowserState>(this as LocalFilesystemBrowserState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LocalFilesystemBrowserState&&const DeepCollectionEquality().equals(other.roots, roots)&&(identical(other.page, page) || other.page == page)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.loadingMore, loadingMore) || other.loadingMore == loadingMore)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(roots),page,loading,loadingMore,failure);

@override
String toString() {
  return 'LocalFilesystemBrowserState(roots: $roots, page: $page, loading: $loading, loadingMore: $loadingMore, failure: $failure)';
}


}

/// @nodoc
abstract mixin class $LocalFilesystemBrowserStateCopyWith<$Res>  {
  factory $LocalFilesystemBrowserStateCopyWith(LocalFilesystemBrowserState value, $Res Function(LocalFilesystemBrowserState) _then) = _$LocalFilesystemBrowserStateCopyWithImpl;
@useResult
$Res call({
 List<LocalFilesystemBrowseRoot> roots, LocalFilesystemBrowsePage? page, bool loading, bool loadingMore, ClientFailure? failure
});




}
/// @nodoc
class _$LocalFilesystemBrowserStateCopyWithImpl<$Res>
    implements $LocalFilesystemBrowserStateCopyWith<$Res> {
  _$LocalFilesystemBrowserStateCopyWithImpl(this._self, this._then);

  final LocalFilesystemBrowserState _self;
  final $Res Function(LocalFilesystemBrowserState) _then;

/// Create a copy of LocalFilesystemBrowserState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? roots = null,Object? page = freezed,Object? loading = null,Object? loadingMore = null,Object? failure = freezed,}) {
  return _then(_self.copyWith(
roots: null == roots ? _self.roots : roots // ignore: cast_nullable_to_non_nullable
as List<LocalFilesystemBrowseRoot>,page: freezed == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as LocalFilesystemBrowsePage?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,loadingMore: null == loadingMore ? _self.loadingMore : loadingMore // ignore: cast_nullable_to_non_nullable
as bool,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as ClientFailure?,
  ));
}

}


/// Adds pattern-matching-related methods to [LocalFilesystemBrowserState].
extension LocalFilesystemBrowserStatePatterns on LocalFilesystemBrowserState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LocalFilesystemBrowserStateReady value)?  ready,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LocalFilesystemBrowserStateReady() when ready != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LocalFilesystemBrowserStateReady value)  ready,}){
final _that = this;
switch (_that) {
case LocalFilesystemBrowserStateReady():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LocalFilesystemBrowserStateReady value)?  ready,}){
final _that = this;
switch (_that) {
case LocalFilesystemBrowserStateReady() when ready != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<LocalFilesystemBrowseRoot> roots,  LocalFilesystemBrowsePage? page,  bool loading,  bool loadingMore,  ClientFailure? failure)?  ready,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LocalFilesystemBrowserStateReady() when ready != null:
return ready(_that.roots,_that.page,_that.loading,_that.loadingMore,_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<LocalFilesystemBrowseRoot> roots,  LocalFilesystemBrowsePage? page,  bool loading,  bool loadingMore,  ClientFailure? failure)  ready,}) {final _that = this;
switch (_that) {
case LocalFilesystemBrowserStateReady():
return ready(_that.roots,_that.page,_that.loading,_that.loadingMore,_that.failure);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<LocalFilesystemBrowseRoot> roots,  LocalFilesystemBrowsePage? page,  bool loading,  bool loadingMore,  ClientFailure? failure)?  ready,}) {final _that = this;
switch (_that) {
case LocalFilesystemBrowserStateReady() when ready != null:
return ready(_that.roots,_that.page,_that.loading,_that.loadingMore,_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class LocalFilesystemBrowserStateReady implements LocalFilesystemBrowserState {
  const LocalFilesystemBrowserStateReady({required final  List<LocalFilesystemBrowseRoot> roots, required this.page, required this.loading, required this.loadingMore, required this.failure}): _roots = roots;


 final  List<LocalFilesystemBrowseRoot> _roots;
@override List<LocalFilesystemBrowseRoot> get roots {
  if (_roots is EqualUnmodifiableListView) return _roots;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_roots);
}

@override final  LocalFilesystemBrowsePage? page;
@override final  bool loading;
@override final  bool loadingMore;
@override final  ClientFailure? failure;

/// Create a copy of LocalFilesystemBrowserState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LocalFilesystemBrowserStateReadyCopyWith<LocalFilesystemBrowserStateReady> get copyWith => _$LocalFilesystemBrowserStateReadyCopyWithImpl<LocalFilesystemBrowserStateReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LocalFilesystemBrowserStateReady&&const DeepCollectionEquality().equals(other._roots, _roots)&&(identical(other.page, page) || other.page == page)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.loadingMore, loadingMore) || other.loadingMore == loadingMore)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_roots),page,loading,loadingMore,failure);

@override
String toString() {
  return 'LocalFilesystemBrowserState.ready(roots: $roots, page: $page, loading: $loading, loadingMore: $loadingMore, failure: $failure)';
}


}

/// @nodoc
abstract mixin class $LocalFilesystemBrowserStateReadyCopyWith<$Res> implements $LocalFilesystemBrowserStateCopyWith<$Res> {
  factory $LocalFilesystemBrowserStateReadyCopyWith(LocalFilesystemBrowserStateReady value, $Res Function(LocalFilesystemBrowserStateReady) _then) = _$LocalFilesystemBrowserStateReadyCopyWithImpl;
@override @useResult
$Res call({
 List<LocalFilesystemBrowseRoot> roots, LocalFilesystemBrowsePage? page, bool loading, bool loadingMore, ClientFailure? failure
});




}
/// @nodoc
class _$LocalFilesystemBrowserStateReadyCopyWithImpl<$Res>
    implements $LocalFilesystemBrowserStateReadyCopyWith<$Res> {
  _$LocalFilesystemBrowserStateReadyCopyWithImpl(this._self, this._then);

  final LocalFilesystemBrowserStateReady _self;
  final $Res Function(LocalFilesystemBrowserStateReady) _then;

/// Create a copy of LocalFilesystemBrowserState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roots = null,Object? page = freezed,Object? loading = null,Object? loadingMore = null,Object? failure = freezed,}) {
  return _then(LocalFilesystemBrowserStateReady(
roots: null == roots ? _self._roots : roots // ignore: cast_nullable_to_non_nullable
as List<LocalFilesystemBrowseRoot>,page: freezed == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as LocalFilesystemBrowsePage?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,loadingMore: null == loadingMore ? _self.loadingMore : loadingMore // ignore: cast_nullable_to_non_nullable
as bool,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as ClientFailure?,
  ));
}


}

// dart format on
