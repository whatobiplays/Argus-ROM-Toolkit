// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LibraryOnboardingProgress {

 String? get acceptedPrivacyTermsVersion; int? get acceptedPrivacyAtMs; bool get metadataPreferencesConfirmed; LibraryProviderSetupOutcome get providerSetupOutcome; int? get completedAtMs;
/// Create a copy of LibraryOnboardingProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryOnboardingProgressCopyWith<LibraryOnboardingProgress> get copyWith => _$LibraryOnboardingProgressCopyWithImpl<LibraryOnboardingProgress>(this as LibraryOnboardingProgress, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryOnboardingProgress&&(identical(other.acceptedPrivacyTermsVersion, acceptedPrivacyTermsVersion) || other.acceptedPrivacyTermsVersion == acceptedPrivacyTermsVersion)&&(identical(other.acceptedPrivacyAtMs, acceptedPrivacyAtMs) || other.acceptedPrivacyAtMs == acceptedPrivacyAtMs)&&(identical(other.metadataPreferencesConfirmed, metadataPreferencesConfirmed) || other.metadataPreferencesConfirmed == metadataPreferencesConfirmed)&&(identical(other.providerSetupOutcome, providerSetupOutcome) || other.providerSetupOutcome == providerSetupOutcome)&&(identical(other.completedAtMs, completedAtMs) || other.completedAtMs == completedAtMs));
}


@override
int get hashCode => Object.hash(runtimeType,acceptedPrivacyTermsVersion,acceptedPrivacyAtMs,metadataPreferencesConfirmed,providerSetupOutcome,completedAtMs);

@override
String toString() {
  return 'LibraryOnboardingProgress(acceptedPrivacyTermsVersion: $acceptedPrivacyTermsVersion, acceptedPrivacyAtMs: $acceptedPrivacyAtMs, metadataPreferencesConfirmed: $metadataPreferencesConfirmed, providerSetupOutcome: $providerSetupOutcome, completedAtMs: $completedAtMs)';
}


}

/// @nodoc
abstract mixin class $LibraryOnboardingProgressCopyWith<$Res>  {
  factory $LibraryOnboardingProgressCopyWith(LibraryOnboardingProgress value, $Res Function(LibraryOnboardingProgress) _then) = _$LibraryOnboardingProgressCopyWithImpl;
@useResult
$Res call({
 String? acceptedPrivacyTermsVersion, int? acceptedPrivacyAtMs, bool metadataPreferencesConfirmed, LibraryProviderSetupOutcome providerSetupOutcome, int? completedAtMs
});




}
/// @nodoc
class _$LibraryOnboardingProgressCopyWithImpl<$Res>
    implements $LibraryOnboardingProgressCopyWith<$Res> {
  _$LibraryOnboardingProgressCopyWithImpl(this._self, this._then);

  final LibraryOnboardingProgress _self;
  final $Res Function(LibraryOnboardingProgress) _then;

/// Create a copy of LibraryOnboardingProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? acceptedPrivacyTermsVersion = freezed,Object? acceptedPrivacyAtMs = freezed,Object? metadataPreferencesConfirmed = null,Object? providerSetupOutcome = null,Object? completedAtMs = freezed,}) {
  return _then(_self.copyWith(
acceptedPrivacyTermsVersion: freezed == acceptedPrivacyTermsVersion ? _self.acceptedPrivacyTermsVersion : acceptedPrivacyTermsVersion // ignore: cast_nullable_to_non_nullable
as String?,acceptedPrivacyAtMs: freezed == acceptedPrivacyAtMs ? _self.acceptedPrivacyAtMs : acceptedPrivacyAtMs // ignore: cast_nullable_to_non_nullable
as int?,metadataPreferencesConfirmed: null == metadataPreferencesConfirmed ? _self.metadataPreferencesConfirmed : metadataPreferencesConfirmed // ignore: cast_nullable_to_non_nullable
as bool,providerSetupOutcome: null == providerSetupOutcome ? _self.providerSetupOutcome : providerSetupOutcome // ignore: cast_nullable_to_non_nullable
as LibraryProviderSetupOutcome,completedAtMs: freezed == completedAtMs ? _self.completedAtMs : completedAtMs // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [LibraryOnboardingProgress].
extension LibraryOnboardingProgressPatterns on LibraryOnboardingProgress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LibraryOnboardingProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LibraryOnboardingProgress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LibraryOnboardingProgress value)  $default,){
final _that = this;
switch (_that) {
case _LibraryOnboardingProgress():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LibraryOnboardingProgress value)?  $default,){
final _that = this;
switch (_that) {
case _LibraryOnboardingProgress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? acceptedPrivacyTermsVersion,  int? acceptedPrivacyAtMs,  bool metadataPreferencesConfirmed,  LibraryProviderSetupOutcome providerSetupOutcome,  int? completedAtMs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LibraryOnboardingProgress() when $default != null:
return $default(_that.acceptedPrivacyTermsVersion,_that.acceptedPrivacyAtMs,_that.metadataPreferencesConfirmed,_that.providerSetupOutcome,_that.completedAtMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? acceptedPrivacyTermsVersion,  int? acceptedPrivacyAtMs,  bool metadataPreferencesConfirmed,  LibraryProviderSetupOutcome providerSetupOutcome,  int? completedAtMs)  $default,) {final _that = this;
switch (_that) {
case _LibraryOnboardingProgress():
return $default(_that.acceptedPrivacyTermsVersion,_that.acceptedPrivacyAtMs,_that.metadataPreferencesConfirmed,_that.providerSetupOutcome,_that.completedAtMs);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? acceptedPrivacyTermsVersion,  int? acceptedPrivacyAtMs,  bool metadataPreferencesConfirmed,  LibraryProviderSetupOutcome providerSetupOutcome,  int? completedAtMs)?  $default,) {final _that = this;
switch (_that) {
case _LibraryOnboardingProgress() when $default != null:
return $default(_that.acceptedPrivacyTermsVersion,_that.acceptedPrivacyAtMs,_that.metadataPreferencesConfirmed,_that.providerSetupOutcome,_that.completedAtMs);case _:
  return null;

}
}

}

/// @nodoc


class _LibraryOnboardingProgress implements LibraryOnboardingProgress {
  const _LibraryOnboardingProgress({this.acceptedPrivacyTermsVersion, this.acceptedPrivacyAtMs, required this.metadataPreferencesConfirmed, required this.providerSetupOutcome, this.completedAtMs});


@override final  String? acceptedPrivacyTermsVersion;
@override final  int? acceptedPrivacyAtMs;
@override final  bool metadataPreferencesConfirmed;
@override final  LibraryProviderSetupOutcome providerSetupOutcome;
@override final  int? completedAtMs;

/// Create a copy of LibraryOnboardingProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LibraryOnboardingProgressCopyWith<_LibraryOnboardingProgress> get copyWith => __$LibraryOnboardingProgressCopyWithImpl<_LibraryOnboardingProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LibraryOnboardingProgress&&(identical(other.acceptedPrivacyTermsVersion, acceptedPrivacyTermsVersion) || other.acceptedPrivacyTermsVersion == acceptedPrivacyTermsVersion)&&(identical(other.acceptedPrivacyAtMs, acceptedPrivacyAtMs) || other.acceptedPrivacyAtMs == acceptedPrivacyAtMs)&&(identical(other.metadataPreferencesConfirmed, metadataPreferencesConfirmed) || other.metadataPreferencesConfirmed == metadataPreferencesConfirmed)&&(identical(other.providerSetupOutcome, providerSetupOutcome) || other.providerSetupOutcome == providerSetupOutcome)&&(identical(other.completedAtMs, completedAtMs) || other.completedAtMs == completedAtMs));
}


@override
int get hashCode => Object.hash(runtimeType,acceptedPrivacyTermsVersion,acceptedPrivacyAtMs,metadataPreferencesConfirmed,providerSetupOutcome,completedAtMs);

@override
String toString() {
  return 'LibraryOnboardingProgress(acceptedPrivacyTermsVersion: $acceptedPrivacyTermsVersion, acceptedPrivacyAtMs: $acceptedPrivacyAtMs, metadataPreferencesConfirmed: $metadataPreferencesConfirmed, providerSetupOutcome: $providerSetupOutcome, completedAtMs: $completedAtMs)';
}


}

/// @nodoc
abstract mixin class _$LibraryOnboardingProgressCopyWith<$Res> implements $LibraryOnboardingProgressCopyWith<$Res> {
  factory _$LibraryOnboardingProgressCopyWith(_LibraryOnboardingProgress value, $Res Function(_LibraryOnboardingProgress) _then) = __$LibraryOnboardingProgressCopyWithImpl;
@override @useResult
$Res call({
 String? acceptedPrivacyTermsVersion, int? acceptedPrivacyAtMs, bool metadataPreferencesConfirmed, LibraryProviderSetupOutcome providerSetupOutcome, int? completedAtMs
});




}
/// @nodoc
class __$LibraryOnboardingProgressCopyWithImpl<$Res>
    implements _$LibraryOnboardingProgressCopyWith<$Res> {
  __$LibraryOnboardingProgressCopyWithImpl(this._self, this._then);

  final _LibraryOnboardingProgress _self;
  final $Res Function(_LibraryOnboardingProgress) _then;

/// Create a copy of LibraryOnboardingProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? acceptedPrivacyTermsVersion = freezed,Object? acceptedPrivacyAtMs = freezed,Object? metadataPreferencesConfirmed = null,Object? providerSetupOutcome = null,Object? completedAtMs = freezed,}) {
  return _then(_LibraryOnboardingProgress(
acceptedPrivacyTermsVersion: freezed == acceptedPrivacyTermsVersion ? _self.acceptedPrivacyTermsVersion : acceptedPrivacyTermsVersion // ignore: cast_nullable_to_non_nullable
as String?,acceptedPrivacyAtMs: freezed == acceptedPrivacyAtMs ? _self.acceptedPrivacyAtMs : acceptedPrivacyAtMs // ignore: cast_nullable_to_non_nullable
as int?,metadataPreferencesConfirmed: null == metadataPreferencesConfirmed ? _self.metadataPreferencesConfirmed : metadataPreferencesConfirmed // ignore: cast_nullable_to_non_nullable
as bool,providerSetupOutcome: null == providerSetupOutcome ? _self.providerSetupOutcome : providerSetupOutcome // ignore: cast_nullable_to_non_nullable
as LibraryProviderSetupOutcome,completedAtMs: freezed == completedAtMs ? _self.completedAtMs : completedAtMs // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$LibraryOnboardingState {

 LibraryOnboardingProgress get progress; String get requiredPrivacyTermsVersion; bool get requiresPrivacyAcceptance; bool get requiresRootSelection; bool get credentialConfigured; bool get complete;
/// Create a copy of LibraryOnboardingState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryOnboardingStateCopyWith<LibraryOnboardingState> get copyWith => _$LibraryOnboardingStateCopyWithImpl<LibraryOnboardingState>(this as LibraryOnboardingState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryOnboardingState&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.requiredPrivacyTermsVersion, requiredPrivacyTermsVersion) || other.requiredPrivacyTermsVersion == requiredPrivacyTermsVersion)&&(identical(other.requiresPrivacyAcceptance, requiresPrivacyAcceptance) || other.requiresPrivacyAcceptance == requiresPrivacyAcceptance)&&(identical(other.requiresRootSelection, requiresRootSelection) || other.requiresRootSelection == requiresRootSelection)&&(identical(other.credentialConfigured, credentialConfigured) || other.credentialConfigured == credentialConfigured)&&(identical(other.complete, complete) || other.complete == complete));
}


@override
int get hashCode => Object.hash(runtimeType,progress,requiredPrivacyTermsVersion,requiresPrivacyAcceptance,requiresRootSelection,credentialConfigured,complete);

@override
String toString() {
  return 'LibraryOnboardingState(progress: $progress, requiredPrivacyTermsVersion: $requiredPrivacyTermsVersion, requiresPrivacyAcceptance: $requiresPrivacyAcceptance, requiresRootSelection: $requiresRootSelection, credentialConfigured: $credentialConfigured, complete: $complete)';
}


}

/// @nodoc
abstract mixin class $LibraryOnboardingStateCopyWith<$Res>  {
  factory $LibraryOnboardingStateCopyWith(LibraryOnboardingState value, $Res Function(LibraryOnboardingState) _then) = _$LibraryOnboardingStateCopyWithImpl;
@useResult
$Res call({
 LibraryOnboardingProgress progress, String requiredPrivacyTermsVersion, bool requiresPrivacyAcceptance, bool requiresRootSelection, bool credentialConfigured, bool complete
});


$LibraryOnboardingProgressCopyWith<$Res> get progress;

}
/// @nodoc
class _$LibraryOnboardingStateCopyWithImpl<$Res>
    implements $LibraryOnboardingStateCopyWith<$Res> {
  _$LibraryOnboardingStateCopyWithImpl(this._self, this._then);

  final LibraryOnboardingState _self;
  final $Res Function(LibraryOnboardingState) _then;

/// Create a copy of LibraryOnboardingState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? progress = null,Object? requiredPrivacyTermsVersion = null,Object? requiresPrivacyAcceptance = null,Object? requiresRootSelection = null,Object? credentialConfigured = null,Object? complete = null,}) {
  return _then(_self.copyWith(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as LibraryOnboardingProgress,requiredPrivacyTermsVersion: null == requiredPrivacyTermsVersion ? _self.requiredPrivacyTermsVersion : requiredPrivacyTermsVersion // ignore: cast_nullable_to_non_nullable
as String,requiresPrivacyAcceptance: null == requiresPrivacyAcceptance ? _self.requiresPrivacyAcceptance : requiresPrivacyAcceptance // ignore: cast_nullable_to_non_nullable
as bool,requiresRootSelection: null == requiresRootSelection ? _self.requiresRootSelection : requiresRootSelection // ignore: cast_nullable_to_non_nullable
as bool,credentialConfigured: null == credentialConfigured ? _self.credentialConfigured : credentialConfigured // ignore: cast_nullable_to_non_nullable
as bool,complete: null == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of LibraryOnboardingState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LibraryOnboardingProgressCopyWith<$Res> get progress {

  return $LibraryOnboardingProgressCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}


/// Adds pattern-matching-related methods to [LibraryOnboardingState].
extension LibraryOnboardingStatePatterns on LibraryOnboardingState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LibraryOnboardingState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LibraryOnboardingState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LibraryOnboardingState value)  $default,){
final _that = this;
switch (_that) {
case _LibraryOnboardingState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LibraryOnboardingState value)?  $default,){
final _that = this;
switch (_that) {
case _LibraryOnboardingState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( LibraryOnboardingProgress progress,  String requiredPrivacyTermsVersion,  bool requiresPrivacyAcceptance,  bool requiresRootSelection,  bool credentialConfigured,  bool complete)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LibraryOnboardingState() when $default != null:
return $default(_that.progress,_that.requiredPrivacyTermsVersion,_that.requiresPrivacyAcceptance,_that.requiresRootSelection,_that.credentialConfigured,_that.complete);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( LibraryOnboardingProgress progress,  String requiredPrivacyTermsVersion,  bool requiresPrivacyAcceptance,  bool requiresRootSelection,  bool credentialConfigured,  bool complete)  $default,) {final _that = this;
switch (_that) {
case _LibraryOnboardingState():
return $default(_that.progress,_that.requiredPrivacyTermsVersion,_that.requiresPrivacyAcceptance,_that.requiresRootSelection,_that.credentialConfigured,_that.complete);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( LibraryOnboardingProgress progress,  String requiredPrivacyTermsVersion,  bool requiresPrivacyAcceptance,  bool requiresRootSelection,  bool credentialConfigured,  bool complete)?  $default,) {final _that = this;
switch (_that) {
case _LibraryOnboardingState() when $default != null:
return $default(_that.progress,_that.requiredPrivacyTermsVersion,_that.requiresPrivacyAcceptance,_that.requiresRootSelection,_that.credentialConfigured,_that.complete);case _:
  return null;

}
}

}

/// @nodoc


class _LibraryOnboardingState implements LibraryOnboardingState {
  const _LibraryOnboardingState({required this.progress, required this.requiredPrivacyTermsVersion, required this.requiresPrivacyAcceptance, required this.requiresRootSelection, required this.credentialConfigured, required this.complete});


@override final  LibraryOnboardingProgress progress;
@override final  String requiredPrivacyTermsVersion;
@override final  bool requiresPrivacyAcceptance;
@override final  bool requiresRootSelection;
@override final  bool credentialConfigured;
@override final  bool complete;

/// Create a copy of LibraryOnboardingState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LibraryOnboardingStateCopyWith<_LibraryOnboardingState> get copyWith => __$LibraryOnboardingStateCopyWithImpl<_LibraryOnboardingState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LibraryOnboardingState&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.requiredPrivacyTermsVersion, requiredPrivacyTermsVersion) || other.requiredPrivacyTermsVersion == requiredPrivacyTermsVersion)&&(identical(other.requiresPrivacyAcceptance, requiresPrivacyAcceptance) || other.requiresPrivacyAcceptance == requiresPrivacyAcceptance)&&(identical(other.requiresRootSelection, requiresRootSelection) || other.requiresRootSelection == requiresRootSelection)&&(identical(other.credentialConfigured, credentialConfigured) || other.credentialConfigured == credentialConfigured)&&(identical(other.complete, complete) || other.complete == complete));
}


@override
int get hashCode => Object.hash(runtimeType,progress,requiredPrivacyTermsVersion,requiresPrivacyAcceptance,requiresRootSelection,credentialConfigured,complete);

@override
String toString() {
  return 'LibraryOnboardingState(progress: $progress, requiredPrivacyTermsVersion: $requiredPrivacyTermsVersion, requiresPrivacyAcceptance: $requiresPrivacyAcceptance, requiresRootSelection: $requiresRootSelection, credentialConfigured: $credentialConfigured, complete: $complete)';
}


}

/// @nodoc
abstract mixin class _$LibraryOnboardingStateCopyWith<$Res> implements $LibraryOnboardingStateCopyWith<$Res> {
  factory _$LibraryOnboardingStateCopyWith(_LibraryOnboardingState value, $Res Function(_LibraryOnboardingState) _then) = __$LibraryOnboardingStateCopyWithImpl;
@override @useResult
$Res call({
 LibraryOnboardingProgress progress, String requiredPrivacyTermsVersion, bool requiresPrivacyAcceptance, bool requiresRootSelection, bool credentialConfigured, bool complete
});


@override $LibraryOnboardingProgressCopyWith<$Res> get progress;

}
/// @nodoc
class __$LibraryOnboardingStateCopyWithImpl<$Res>
    implements _$LibraryOnboardingStateCopyWith<$Res> {
  __$LibraryOnboardingStateCopyWithImpl(this._self, this._then);

  final _LibraryOnboardingState _self;
  final $Res Function(_LibraryOnboardingState) _then;

/// Create a copy of LibraryOnboardingState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? progress = null,Object? requiredPrivacyTermsVersion = null,Object? requiresPrivacyAcceptance = null,Object? requiresRootSelection = null,Object? credentialConfigured = null,Object? complete = null,}) {
  return _then(_LibraryOnboardingState(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as LibraryOnboardingProgress,requiredPrivacyTermsVersion: null == requiredPrivacyTermsVersion ? _self.requiredPrivacyTermsVersion : requiredPrivacyTermsVersion // ignore: cast_nullable_to_non_nullable
as String,requiresPrivacyAcceptance: null == requiresPrivacyAcceptance ? _self.requiresPrivacyAcceptance : requiresPrivacyAcceptance // ignore: cast_nullable_to_non_nullable
as bool,requiresRootSelection: null == requiresRootSelection ? _self.requiresRootSelection : requiresRootSelection // ignore: cast_nullable_to_non_nullable
as bool,credentialConfigured: null == credentialConfigured ? _self.credentialConfigured : credentialConfigured // ignore: cast_nullable_to_non_nullable
as bool,complete: null == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of LibraryOnboardingState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LibraryOnboardingProgressCopyWith<$Res> get progress {

  return $LibraryOnboardingProgressCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}

/// @nodoc
mixin _$MetadataSettings {

 List<String> get preferredRegions; List<String> get preferredLanguages;
/// Create a copy of MetadataSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataSettingsCopyWith<MetadataSettings> get copyWith => _$MetadataSettingsCopyWithImpl<MetadataSettings>(this as MetadataSettings, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataSettings&&const DeepCollectionEquality().equals(other.preferredRegions, preferredRegions)&&const DeepCollectionEquality().equals(other.preferredLanguages, preferredLanguages));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(preferredRegions),const DeepCollectionEquality().hash(preferredLanguages));

@override
String toString() {
  return 'MetadataSettings(preferredRegions: $preferredRegions, preferredLanguages: $preferredLanguages)';
}


}

/// @nodoc
abstract mixin class $MetadataSettingsCopyWith<$Res>  {
  factory $MetadataSettingsCopyWith(MetadataSettings value, $Res Function(MetadataSettings) _then) = _$MetadataSettingsCopyWithImpl;
@useResult
$Res call({
 List<String> preferredRegions, List<String> preferredLanguages
});




}
/// @nodoc
class _$MetadataSettingsCopyWithImpl<$Res>
    implements $MetadataSettingsCopyWith<$Res> {
  _$MetadataSettingsCopyWithImpl(this._self, this._then);

  final MetadataSettings _self;
  final $Res Function(MetadataSettings) _then;

/// Create a copy of MetadataSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? preferredRegions = null,Object? preferredLanguages = null,}) {
  return _then(_self.copyWith(
preferredRegions: null == preferredRegions ? _self.preferredRegions : preferredRegions // ignore: cast_nullable_to_non_nullable
as List<String>,preferredLanguages: null == preferredLanguages ? _self.preferredLanguages : preferredLanguages // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [MetadataSettings].
extension MetadataSettingsPatterns on MetadataSettings {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MetadataSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MetadataSettings() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MetadataSettings value)  $default,){
final _that = this;
switch (_that) {
case _MetadataSettings():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MetadataSettings value)?  $default,){
final _that = this;
switch (_that) {
case _MetadataSettings() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<String> preferredRegions,  List<String> preferredLanguages)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MetadataSettings() when $default != null:
return $default(_that.preferredRegions,_that.preferredLanguages);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<String> preferredRegions,  List<String> preferredLanguages)  $default,) {final _that = this;
switch (_that) {
case _MetadataSettings():
return $default(_that.preferredRegions,_that.preferredLanguages);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<String> preferredRegions,  List<String> preferredLanguages)?  $default,) {final _that = this;
switch (_that) {
case _MetadataSettings() when $default != null:
return $default(_that.preferredRegions,_that.preferredLanguages);case _:
  return null;

}
}

}

/// @nodoc


class _MetadataSettings implements MetadataSettings {
  const _MetadataSettings({required final  List<String> preferredRegions, required final  List<String> preferredLanguages}): _preferredRegions = preferredRegions,_preferredLanguages = preferredLanguages;


 final  List<String> _preferredRegions;
@override List<String> get preferredRegions {
  if (_preferredRegions is EqualUnmodifiableListView) return _preferredRegions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_preferredRegions);
}

 final  List<String> _preferredLanguages;
@override List<String> get preferredLanguages {
  if (_preferredLanguages is EqualUnmodifiableListView) return _preferredLanguages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_preferredLanguages);
}


/// Create a copy of MetadataSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MetadataSettingsCopyWith<_MetadataSettings> get copyWith => __$MetadataSettingsCopyWithImpl<_MetadataSettings>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MetadataSettings&&const DeepCollectionEquality().equals(other._preferredRegions, _preferredRegions)&&const DeepCollectionEquality().equals(other._preferredLanguages, _preferredLanguages));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_preferredRegions),const DeepCollectionEquality().hash(_preferredLanguages));

@override
String toString() {
  return 'MetadataSettings(preferredRegions: $preferredRegions, preferredLanguages: $preferredLanguages)';
}


}

/// @nodoc
abstract mixin class _$MetadataSettingsCopyWith<$Res> implements $MetadataSettingsCopyWith<$Res> {
  factory _$MetadataSettingsCopyWith(_MetadataSettings value, $Res Function(_MetadataSettings) _then) = __$MetadataSettingsCopyWithImpl;
@override @useResult
$Res call({
 List<String> preferredRegions, List<String> preferredLanguages
});




}
/// @nodoc
class __$MetadataSettingsCopyWithImpl<$Res>
    implements _$MetadataSettingsCopyWith<$Res> {
  __$MetadataSettingsCopyWithImpl(this._self, this._then);

  final _MetadataSettings _self;
  final $Res Function(_MetadataSettings) _then;

/// Create a copy of MetadataSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? preferredRegions = null,Object? preferredLanguages = null,}) {
  return _then(_MetadataSettings(
preferredRegions: null == preferredRegions ? _self._preferredRegions : preferredRegions // ignore: cast_nullable_to_non_nullable
as List<String>,preferredLanguages: null == preferredLanguages ? _self._preferredLanguages : preferredLanguages // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc
mixin _$MetadataProviderSettings {

 List<String> get enabledProviders;
/// Create a copy of MetadataProviderSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataProviderSettingsCopyWith<MetadataProviderSettings> get copyWith => _$MetadataProviderSettingsCopyWithImpl<MetadataProviderSettings>(this as MetadataProviderSettings, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataProviderSettings&&const DeepCollectionEquality().equals(other.enabledProviders, enabledProviders));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(enabledProviders));

@override
String toString() {
  return 'MetadataProviderSettings(enabledProviders: $enabledProviders)';
}


}

/// @nodoc
abstract mixin class $MetadataProviderSettingsCopyWith<$Res>  {
  factory $MetadataProviderSettingsCopyWith(MetadataProviderSettings value, $Res Function(MetadataProviderSettings) _then) = _$MetadataProviderSettingsCopyWithImpl;
@useResult
$Res call({
 List<String> enabledProviders
});




}
/// @nodoc
class _$MetadataProviderSettingsCopyWithImpl<$Res>
    implements $MetadataProviderSettingsCopyWith<$Res> {
  _$MetadataProviderSettingsCopyWithImpl(this._self, this._then);

  final MetadataProviderSettings _self;
  final $Res Function(MetadataProviderSettings) _then;

/// Create a copy of MetadataProviderSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? enabledProviders = null,}) {
  return _then(_self.copyWith(
enabledProviders: null == enabledProviders ? _self.enabledProviders : enabledProviders // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [MetadataProviderSettings].
extension MetadataProviderSettingsPatterns on MetadataProviderSettings {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MetadataProviderSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MetadataProviderSettings() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MetadataProviderSettings value)  $default,){
final _that = this;
switch (_that) {
case _MetadataProviderSettings():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MetadataProviderSettings value)?  $default,){
final _that = this;
switch (_that) {
case _MetadataProviderSettings() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<String> enabledProviders)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MetadataProviderSettings() when $default != null:
return $default(_that.enabledProviders);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<String> enabledProviders)  $default,) {final _that = this;
switch (_that) {
case _MetadataProviderSettings():
return $default(_that.enabledProviders);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<String> enabledProviders)?  $default,) {final _that = this;
switch (_that) {
case _MetadataProviderSettings() when $default != null:
return $default(_that.enabledProviders);case _:
  return null;

}
}

}

/// @nodoc


class _MetadataProviderSettings implements MetadataProviderSettings {
  const _MetadataProviderSettings({required final  List<String> enabledProviders}): _enabledProviders = enabledProviders;


 final  List<String> _enabledProviders;
@override List<String> get enabledProviders {
  if (_enabledProviders is EqualUnmodifiableListView) return _enabledProviders;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_enabledProviders);
}


/// Create a copy of MetadataProviderSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MetadataProviderSettingsCopyWith<_MetadataProviderSettings> get copyWith => __$MetadataProviderSettingsCopyWithImpl<_MetadataProviderSettings>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MetadataProviderSettings&&const DeepCollectionEquality().equals(other._enabledProviders, _enabledProviders));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_enabledProviders));

@override
String toString() {
  return 'MetadataProviderSettings(enabledProviders: $enabledProviders)';
}


}

/// @nodoc
abstract mixin class _$MetadataProviderSettingsCopyWith<$Res> implements $MetadataProviderSettingsCopyWith<$Res> {
  factory _$MetadataProviderSettingsCopyWith(_MetadataProviderSettings value, $Res Function(_MetadataProviderSettings) _then) = __$MetadataProviderSettingsCopyWithImpl;
@override @useResult
$Res call({
 List<String> enabledProviders
});




}
/// @nodoc
class __$MetadataProviderSettingsCopyWithImpl<$Res>
    implements _$MetadataProviderSettingsCopyWith<$Res> {
  __$MetadataProviderSettingsCopyWithImpl(this._self, this._then);

  final _MetadataProviderSettings _self;
  final $Res Function(_MetadataProviderSettings) _then;

/// Create a copy of MetadataProviderSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? enabledProviders = null,}) {
  return _then(_MetadataProviderSettings(
enabledProviders: null == enabledProviders ? _self._enabledProviders : enabledProviders // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc
mixin _$CompleteLibraryOnboardingAndRefreshResult {

 LibraryOnboardingState get state;
/// Create a copy of CompleteLibraryOnboardingAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CompleteLibraryOnboardingAndRefreshResultCopyWith<CompleteLibraryOnboardingAndRefreshResult> get copyWith => _$CompleteLibraryOnboardingAndRefreshResultCopyWithImpl<CompleteLibraryOnboardingAndRefreshResult>(this as CompleteLibraryOnboardingAndRefreshResult, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CompleteLibraryOnboardingAndRefreshResult&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode => Object.hash(runtimeType,state);

@override
String toString() {
  return 'CompleteLibraryOnboardingAndRefreshResult(state: $state)';
}


}

/// @nodoc
abstract mixin class $CompleteLibraryOnboardingAndRefreshResultCopyWith<$Res>  {
  factory $CompleteLibraryOnboardingAndRefreshResultCopyWith(CompleteLibraryOnboardingAndRefreshResult value, $Res Function(CompleteLibraryOnboardingAndRefreshResult) _then) = _$CompleteLibraryOnboardingAndRefreshResultCopyWithImpl;
@useResult
$Res call({
 LibraryOnboardingState state
});


$LibraryOnboardingStateCopyWith<$Res> get state;

}
/// @nodoc
class _$CompleteLibraryOnboardingAndRefreshResultCopyWithImpl<$Res>
    implements $CompleteLibraryOnboardingAndRefreshResultCopyWith<$Res> {
  _$CompleteLibraryOnboardingAndRefreshResultCopyWithImpl(this._self, this._then);

  final CompleteLibraryOnboardingAndRefreshResult _self;
  final $Res Function(CompleteLibraryOnboardingAndRefreshResult) _then;

/// Create a copy of CompleteLibraryOnboardingAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? state = null,}) {
  return _then(_self.copyWith(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as LibraryOnboardingState,
  ));
}
/// Create a copy of CompleteLibraryOnboardingAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LibraryOnboardingStateCopyWith<$Res> get state {

  return $LibraryOnboardingStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [CompleteLibraryOnboardingAndRefreshResult].
extension CompleteLibraryOnboardingAndRefreshResultPatterns on CompleteLibraryOnboardingAndRefreshResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CompleteLibraryOnboardingAndRefreshResultAdmitted value)?  admitted,TResult Function( CompleteLibraryOnboardingAndRefreshResultNotAdmitted value)?  notAdmitted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CompleteLibraryOnboardingAndRefreshResultAdmitted() when admitted != null:
return admitted(_that);case CompleteLibraryOnboardingAndRefreshResultNotAdmitted() when notAdmitted != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CompleteLibraryOnboardingAndRefreshResultAdmitted value)  admitted,required TResult Function( CompleteLibraryOnboardingAndRefreshResultNotAdmitted value)  notAdmitted,}){
final _that = this;
switch (_that) {
case CompleteLibraryOnboardingAndRefreshResultAdmitted():
return admitted(_that);case CompleteLibraryOnboardingAndRefreshResultNotAdmitted():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CompleteLibraryOnboardingAndRefreshResultAdmitted value)?  admitted,TResult? Function( CompleteLibraryOnboardingAndRefreshResultNotAdmitted value)?  notAdmitted,}){
final _that = this;
switch (_that) {
case CompleteLibraryOnboardingAndRefreshResultAdmitted() when admitted != null:
return admitted(_that);case CompleteLibraryOnboardingAndRefreshResultNotAdmitted() when notAdmitted != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( LibraryOnboardingState state,  OperationHandle handle)?  admitted,TResult Function( LibraryOnboardingState state,  ClientApplicationError error)?  notAdmitted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CompleteLibraryOnboardingAndRefreshResultAdmitted() when admitted != null:
return admitted(_that.state,_that.handle);case CompleteLibraryOnboardingAndRefreshResultNotAdmitted() when notAdmitted != null:
return notAdmitted(_that.state,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( LibraryOnboardingState state,  OperationHandle handle)  admitted,required TResult Function( LibraryOnboardingState state,  ClientApplicationError error)  notAdmitted,}) {final _that = this;
switch (_that) {
case CompleteLibraryOnboardingAndRefreshResultAdmitted():
return admitted(_that.state,_that.handle);case CompleteLibraryOnboardingAndRefreshResultNotAdmitted():
return notAdmitted(_that.state,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( LibraryOnboardingState state,  OperationHandle handle)?  admitted,TResult? Function( LibraryOnboardingState state,  ClientApplicationError error)?  notAdmitted,}) {final _that = this;
switch (_that) {
case CompleteLibraryOnboardingAndRefreshResultAdmitted() when admitted != null:
return admitted(_that.state,_that.handle);case CompleteLibraryOnboardingAndRefreshResultNotAdmitted() when notAdmitted != null:
return notAdmitted(_that.state,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class CompleteLibraryOnboardingAndRefreshResultAdmitted implements CompleteLibraryOnboardingAndRefreshResult {
  const CompleteLibraryOnboardingAndRefreshResultAdmitted({required this.state, required this.handle});


@override final  LibraryOnboardingState state;
 final  OperationHandle handle;

/// Create a copy of CompleteLibraryOnboardingAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CompleteLibraryOnboardingAndRefreshResultAdmittedCopyWith<CompleteLibraryOnboardingAndRefreshResultAdmitted> get copyWith => _$CompleteLibraryOnboardingAndRefreshResultAdmittedCopyWithImpl<CompleteLibraryOnboardingAndRefreshResultAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CompleteLibraryOnboardingAndRefreshResultAdmitted&&(identical(other.state, state) || other.state == state)&&(identical(other.handle, handle) || other.handle == handle));
}


@override
int get hashCode => Object.hash(runtimeType,state,handle);

@override
String toString() {
  return 'CompleteLibraryOnboardingAndRefreshResult.admitted(state: $state, handle: $handle)';
}


}

/// @nodoc
abstract mixin class $CompleteLibraryOnboardingAndRefreshResultAdmittedCopyWith<$Res> implements $CompleteLibraryOnboardingAndRefreshResultCopyWith<$Res> {
  factory $CompleteLibraryOnboardingAndRefreshResultAdmittedCopyWith(CompleteLibraryOnboardingAndRefreshResultAdmitted value, $Res Function(CompleteLibraryOnboardingAndRefreshResultAdmitted) _then) = _$CompleteLibraryOnboardingAndRefreshResultAdmittedCopyWithImpl;
@override @useResult
$Res call({
 LibraryOnboardingState state, OperationHandle handle
});


@override $LibraryOnboardingStateCopyWith<$Res> get state;

}
/// @nodoc
class _$CompleteLibraryOnboardingAndRefreshResultAdmittedCopyWithImpl<$Res>
    implements $CompleteLibraryOnboardingAndRefreshResultAdmittedCopyWith<$Res> {
  _$CompleteLibraryOnboardingAndRefreshResultAdmittedCopyWithImpl(this._self, this._then);

  final CompleteLibraryOnboardingAndRefreshResultAdmitted _self;
  final $Res Function(CompleteLibraryOnboardingAndRefreshResultAdmitted) _then;

/// Create a copy of CompleteLibraryOnboardingAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? state = null,Object? handle = null,}) {
  return _then(CompleteLibraryOnboardingAndRefreshResultAdmitted(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as LibraryOnboardingState,handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as OperationHandle,
  ));
}

/// Create a copy of CompleteLibraryOnboardingAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LibraryOnboardingStateCopyWith<$Res> get state {

  return $LibraryOnboardingStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc


class CompleteLibraryOnboardingAndRefreshResultNotAdmitted implements CompleteLibraryOnboardingAndRefreshResult {
  const CompleteLibraryOnboardingAndRefreshResultNotAdmitted({required this.state, required this.error});


@override final  LibraryOnboardingState state;
 final  ClientApplicationError error;

/// Create a copy of CompleteLibraryOnboardingAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CompleteLibraryOnboardingAndRefreshResultNotAdmittedCopyWith<CompleteLibraryOnboardingAndRefreshResultNotAdmitted> get copyWith => _$CompleteLibraryOnboardingAndRefreshResultNotAdmittedCopyWithImpl<CompleteLibraryOnboardingAndRefreshResultNotAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CompleteLibraryOnboardingAndRefreshResultNotAdmitted&&(identical(other.state, state) || other.state == state)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,state,error);

@override
String toString() {
  return 'CompleteLibraryOnboardingAndRefreshResult.notAdmitted(state: $state, error: $error)';
}


}

/// @nodoc
abstract mixin class $CompleteLibraryOnboardingAndRefreshResultNotAdmittedCopyWith<$Res> implements $CompleteLibraryOnboardingAndRefreshResultCopyWith<$Res> {
  factory $CompleteLibraryOnboardingAndRefreshResultNotAdmittedCopyWith(CompleteLibraryOnboardingAndRefreshResultNotAdmitted value, $Res Function(CompleteLibraryOnboardingAndRefreshResultNotAdmitted) _then) = _$CompleteLibraryOnboardingAndRefreshResultNotAdmittedCopyWithImpl;
@override @useResult
$Res call({
 LibraryOnboardingState state, ClientApplicationError error
});


@override $LibraryOnboardingStateCopyWith<$Res> get state;$ClientApplicationErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$CompleteLibraryOnboardingAndRefreshResultNotAdmittedCopyWithImpl<$Res>
    implements $CompleteLibraryOnboardingAndRefreshResultNotAdmittedCopyWith<$Res> {
  _$CompleteLibraryOnboardingAndRefreshResultNotAdmittedCopyWithImpl(this._self, this._then);

  final CompleteLibraryOnboardingAndRefreshResultNotAdmitted _self;
  final $Res Function(CompleteLibraryOnboardingAndRefreshResultNotAdmitted) _then;

/// Create a copy of CompleteLibraryOnboardingAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? state = null,Object? error = null,}) {
  return _then(CompleteLibraryOnboardingAndRefreshResultNotAdmitted(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as LibraryOnboardingState,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ClientApplicationError,
  ));
}

/// Create a copy of CompleteLibraryOnboardingAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LibraryOnboardingStateCopyWith<$Res> get state {

  return $LibraryOnboardingStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}/// Create a copy of CompleteLibraryOnboardingAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientApplicationErrorCopyWith<$Res> get error {

  return $ClientApplicationErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$AddLibraryRootAndRefreshResult {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLibraryRootAndRefreshResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AddLibraryRootAndRefreshResult()';
}


}

/// @nodoc
class $AddLibraryRootAndRefreshResultCopyWith<$Res>  {
$AddLibraryRootAndRefreshResultCopyWith(AddLibraryRootAndRefreshResult _, $Res Function(AddLibraryRootAndRefreshResult) __);
}


/// Adds pattern-matching-related methods to [AddLibraryRootAndRefreshResult].
extension AddLibraryRootAndRefreshResultPatterns on AddLibraryRootAndRefreshResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted value)?  addedAndRefreshAdmitted,TResult Function( AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted value)?  addedButRefreshNotAdmitted,TResult Function( AddLibraryRootAndRefreshResultAlreadyConfigured value)?  alreadyConfigured,TResult Function( AddLibraryRootAndRefreshResultOverlapsExisting value)?  overlapsExisting,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted() when addedAndRefreshAdmitted != null:
return addedAndRefreshAdmitted(_that);case AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted() when addedButRefreshNotAdmitted != null:
return addedButRefreshNotAdmitted(_that);case AddLibraryRootAndRefreshResultAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that);case AddLibraryRootAndRefreshResultOverlapsExisting() when overlapsExisting != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted value)  addedAndRefreshAdmitted,required TResult Function( AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted value)  addedButRefreshNotAdmitted,required TResult Function( AddLibraryRootAndRefreshResultAlreadyConfigured value)  alreadyConfigured,required TResult Function( AddLibraryRootAndRefreshResultOverlapsExisting value)  overlapsExisting,}){
final _that = this;
switch (_that) {
case AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted():
return addedAndRefreshAdmitted(_that);case AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted():
return addedButRefreshNotAdmitted(_that);case AddLibraryRootAndRefreshResultAlreadyConfigured():
return alreadyConfigured(_that);case AddLibraryRootAndRefreshResultOverlapsExisting():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted value)?  addedAndRefreshAdmitted,TResult? Function( AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted value)?  addedButRefreshNotAdmitted,TResult? Function( AddLibraryRootAndRefreshResultAlreadyConfigured value)?  alreadyConfigured,TResult? Function( AddLibraryRootAndRefreshResultOverlapsExisting value)?  overlapsExisting,}){
final _that = this;
switch (_that) {
case AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted() when addedAndRefreshAdmitted != null:
return addedAndRefreshAdmitted(_that);case AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted() when addedButRefreshNotAdmitted != null:
return addedButRefreshNotAdmitted(_that);case AddLibraryRootAndRefreshResultAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that);case AddLibraryRootAndRefreshResultOverlapsExisting() when overlapsExisting != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( LibraryRoot root,  OperationHandle handle)?  addedAndRefreshAdmitted,TResult Function( LibraryRoot root,  ClientApplicationError error)?  addedButRefreshNotAdmitted,TResult Function( LibraryRootId existingLibraryRootId)?  alreadyConfigured,TResult Function( LibraryRootId existingLibraryRootId,  RootRelationship relationship)?  overlapsExisting,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted() when addedAndRefreshAdmitted != null:
return addedAndRefreshAdmitted(_that.root,_that.handle);case AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted() when addedButRefreshNotAdmitted != null:
return addedButRefreshNotAdmitted(_that.root,_that.error);case AddLibraryRootAndRefreshResultAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that.existingLibraryRootId);case AddLibraryRootAndRefreshResultOverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that.existingLibraryRootId,_that.relationship);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( LibraryRoot root,  OperationHandle handle)  addedAndRefreshAdmitted,required TResult Function( LibraryRoot root,  ClientApplicationError error)  addedButRefreshNotAdmitted,required TResult Function( LibraryRootId existingLibraryRootId)  alreadyConfigured,required TResult Function( LibraryRootId existingLibraryRootId,  RootRelationship relationship)  overlapsExisting,}) {final _that = this;
switch (_that) {
case AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted():
return addedAndRefreshAdmitted(_that.root,_that.handle);case AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted():
return addedButRefreshNotAdmitted(_that.root,_that.error);case AddLibraryRootAndRefreshResultAlreadyConfigured():
return alreadyConfigured(_that.existingLibraryRootId);case AddLibraryRootAndRefreshResultOverlapsExisting():
return overlapsExisting(_that.existingLibraryRootId,_that.relationship);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( LibraryRoot root,  OperationHandle handle)?  addedAndRefreshAdmitted,TResult? Function( LibraryRoot root,  ClientApplicationError error)?  addedButRefreshNotAdmitted,TResult? Function( LibraryRootId existingLibraryRootId)?  alreadyConfigured,TResult? Function( LibraryRootId existingLibraryRootId,  RootRelationship relationship)?  overlapsExisting,}) {final _that = this;
switch (_that) {
case AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted() when addedAndRefreshAdmitted != null:
return addedAndRefreshAdmitted(_that.root,_that.handle);case AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted() when addedButRefreshNotAdmitted != null:
return addedButRefreshNotAdmitted(_that.root,_that.error);case AddLibraryRootAndRefreshResultAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that.existingLibraryRootId);case AddLibraryRootAndRefreshResultOverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that.existingLibraryRootId,_that.relationship);case _:
  return null;

}
}

}

/// @nodoc


class AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted implements AddLibraryRootAndRefreshResult {
  const AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted({required this.root, required this.handle});


 final  LibraryRoot root;
 final  OperationHandle handle;

/// Create a copy of AddLibraryRootAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLibraryRootAndRefreshResultAddedAndRefreshAdmittedCopyWith<AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted> get copyWith => _$AddLibraryRootAndRefreshResultAddedAndRefreshAdmittedCopyWithImpl<AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted&&(identical(other.root, root) || other.root == root)&&(identical(other.handle, handle) || other.handle == handle));
}


@override
int get hashCode => Object.hash(runtimeType,root,handle);

@override
String toString() {
  return 'AddLibraryRootAndRefreshResult.addedAndRefreshAdmitted(root: $root, handle: $handle)';
}


}

/// @nodoc
abstract mixin class $AddLibraryRootAndRefreshResultAddedAndRefreshAdmittedCopyWith<$Res> implements $AddLibraryRootAndRefreshResultCopyWith<$Res> {
  factory $AddLibraryRootAndRefreshResultAddedAndRefreshAdmittedCopyWith(AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted value, $Res Function(AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted) _then) = _$AddLibraryRootAndRefreshResultAddedAndRefreshAdmittedCopyWithImpl;
@useResult
$Res call({
 LibraryRoot root, OperationHandle handle
});


$LibraryRootCopyWith<$Res> get root;

}
/// @nodoc
class _$AddLibraryRootAndRefreshResultAddedAndRefreshAdmittedCopyWithImpl<$Res>
    implements $AddLibraryRootAndRefreshResultAddedAndRefreshAdmittedCopyWith<$Res> {
  _$AddLibraryRootAndRefreshResultAddedAndRefreshAdmittedCopyWithImpl(this._self, this._then);

  final AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted _self;
  final $Res Function(AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted) _then;

/// Create a copy of AddLibraryRootAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? root = null,Object? handle = null,}) {
  return _then(AddLibraryRootAndRefreshResultAddedAndRefreshAdmitted(
root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as LibraryRoot,handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as OperationHandle,
  ));
}

/// Create a copy of AddLibraryRootAndRefreshResult
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


class AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted implements AddLibraryRootAndRefreshResult {
  const AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted({required this.root, required this.error});


 final  LibraryRoot root;
 final  ClientApplicationError error;

/// Create a copy of AddLibraryRootAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLibraryRootAndRefreshResultAddedButRefreshNotAdmittedCopyWith<AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted> get copyWith => _$AddLibraryRootAndRefreshResultAddedButRefreshNotAdmittedCopyWithImpl<AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted&&(identical(other.root, root) || other.root == root)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,root,error);

@override
String toString() {
  return 'AddLibraryRootAndRefreshResult.addedButRefreshNotAdmitted(root: $root, error: $error)';
}


}

/// @nodoc
abstract mixin class $AddLibraryRootAndRefreshResultAddedButRefreshNotAdmittedCopyWith<$Res> implements $AddLibraryRootAndRefreshResultCopyWith<$Res> {
  factory $AddLibraryRootAndRefreshResultAddedButRefreshNotAdmittedCopyWith(AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted value, $Res Function(AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted) _then) = _$AddLibraryRootAndRefreshResultAddedButRefreshNotAdmittedCopyWithImpl;
@useResult
$Res call({
 LibraryRoot root, ClientApplicationError error
});


$LibraryRootCopyWith<$Res> get root;$ClientApplicationErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$AddLibraryRootAndRefreshResultAddedButRefreshNotAdmittedCopyWithImpl<$Res>
    implements $AddLibraryRootAndRefreshResultAddedButRefreshNotAdmittedCopyWith<$Res> {
  _$AddLibraryRootAndRefreshResultAddedButRefreshNotAdmittedCopyWithImpl(this._self, this._then);

  final AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted _self;
  final $Res Function(AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted) _then;

/// Create a copy of AddLibraryRootAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? root = null,Object? error = null,}) {
  return _then(AddLibraryRootAndRefreshResultAddedButRefreshNotAdmitted(
root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as LibraryRoot,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ClientApplicationError,
  ));
}

/// Create a copy of AddLibraryRootAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LibraryRootCopyWith<$Res> get root {

  return $LibraryRootCopyWith<$Res>(_self.root, (value) {
    return _then(_self.copyWith(root: value));
  });
}/// Create a copy of AddLibraryRootAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientApplicationErrorCopyWith<$Res> get error {

  return $ClientApplicationErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class AddLibraryRootAndRefreshResultAlreadyConfigured implements AddLibraryRootAndRefreshResult {
  const AddLibraryRootAndRefreshResultAlreadyConfigured({required this.existingLibraryRootId});


 final  LibraryRootId existingLibraryRootId;

/// Create a copy of AddLibraryRootAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLibraryRootAndRefreshResultAlreadyConfiguredCopyWith<AddLibraryRootAndRefreshResultAlreadyConfigured> get copyWith => _$AddLibraryRootAndRefreshResultAlreadyConfiguredCopyWithImpl<AddLibraryRootAndRefreshResultAlreadyConfigured>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLibraryRootAndRefreshResultAlreadyConfigured&&(identical(other.existingLibraryRootId, existingLibraryRootId) || other.existingLibraryRootId == existingLibraryRootId));
}


@override
int get hashCode => Object.hash(runtimeType,existingLibraryRootId);

@override
String toString() {
  return 'AddLibraryRootAndRefreshResult.alreadyConfigured(existingLibraryRootId: $existingLibraryRootId)';
}


}

/// @nodoc
abstract mixin class $AddLibraryRootAndRefreshResultAlreadyConfiguredCopyWith<$Res> implements $AddLibraryRootAndRefreshResultCopyWith<$Res> {
  factory $AddLibraryRootAndRefreshResultAlreadyConfiguredCopyWith(AddLibraryRootAndRefreshResultAlreadyConfigured value, $Res Function(AddLibraryRootAndRefreshResultAlreadyConfigured) _then) = _$AddLibraryRootAndRefreshResultAlreadyConfiguredCopyWithImpl;
@useResult
$Res call({
 LibraryRootId existingLibraryRootId
});




}
/// @nodoc
class _$AddLibraryRootAndRefreshResultAlreadyConfiguredCopyWithImpl<$Res>
    implements $AddLibraryRootAndRefreshResultAlreadyConfiguredCopyWith<$Res> {
  _$AddLibraryRootAndRefreshResultAlreadyConfiguredCopyWithImpl(this._self, this._then);

  final AddLibraryRootAndRefreshResultAlreadyConfigured _self;
  final $Res Function(AddLibraryRootAndRefreshResultAlreadyConfigured) _then;

/// Create a copy of AddLibraryRootAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? existingLibraryRootId = null,}) {
  return _then(AddLibraryRootAndRefreshResultAlreadyConfigured(
existingLibraryRootId: null == existingLibraryRootId ? _self.existingLibraryRootId : existingLibraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,
  ));
}


}

/// @nodoc


class AddLibraryRootAndRefreshResultOverlapsExisting implements AddLibraryRootAndRefreshResult {
  const AddLibraryRootAndRefreshResultOverlapsExisting({required this.existingLibraryRootId, required this.relationship});


 final  LibraryRootId existingLibraryRootId;
 final  RootRelationship relationship;

/// Create a copy of AddLibraryRootAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLibraryRootAndRefreshResultOverlapsExistingCopyWith<AddLibraryRootAndRefreshResultOverlapsExisting> get copyWith => _$AddLibraryRootAndRefreshResultOverlapsExistingCopyWithImpl<AddLibraryRootAndRefreshResultOverlapsExisting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLibraryRootAndRefreshResultOverlapsExisting&&(identical(other.existingLibraryRootId, existingLibraryRootId) || other.existingLibraryRootId == existingLibraryRootId)&&(identical(other.relationship, relationship) || other.relationship == relationship));
}


@override
int get hashCode => Object.hash(runtimeType,existingLibraryRootId,relationship);

@override
String toString() {
  return 'AddLibraryRootAndRefreshResult.overlapsExisting(existingLibraryRootId: $existingLibraryRootId, relationship: $relationship)';
}


}

/// @nodoc
abstract mixin class $AddLibraryRootAndRefreshResultOverlapsExistingCopyWith<$Res> implements $AddLibraryRootAndRefreshResultCopyWith<$Res> {
  factory $AddLibraryRootAndRefreshResultOverlapsExistingCopyWith(AddLibraryRootAndRefreshResultOverlapsExisting value, $Res Function(AddLibraryRootAndRefreshResultOverlapsExisting) _then) = _$AddLibraryRootAndRefreshResultOverlapsExistingCopyWithImpl;
@useResult
$Res call({
 LibraryRootId existingLibraryRootId, RootRelationship relationship
});




}
/// @nodoc
class _$AddLibraryRootAndRefreshResultOverlapsExistingCopyWithImpl<$Res>
    implements $AddLibraryRootAndRefreshResultOverlapsExistingCopyWith<$Res> {
  _$AddLibraryRootAndRefreshResultOverlapsExistingCopyWithImpl(this._self, this._then);

  final AddLibraryRootAndRefreshResultOverlapsExisting _self;
  final $Res Function(AddLibraryRootAndRefreshResultOverlapsExisting) _then;

/// Create a copy of AddLibraryRootAndRefreshResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? existingLibraryRootId = null,Object? relationship = null,}) {
  return _then(AddLibraryRootAndRefreshResultOverlapsExisting(
existingLibraryRootId: null == existingLibraryRootId ? _self.existingLibraryRootId : existingLibraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,relationship: null == relationship ? _self.relationship : relationship // ignore: cast_nullable_to_non_nullable
as RootRelationship,
  ));
}


}

/// @nodoc
mixin _$MetadataSettingsUpdateResult {

 MetadataSettings get settings;
/// Create a copy of MetadataSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataSettingsUpdateResultCopyWith<MetadataSettingsUpdateResult> get copyWith => _$MetadataSettingsUpdateResultCopyWithImpl<MetadataSettingsUpdateResult>(this as MetadataSettingsUpdateResult, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataSettingsUpdateResult&&(identical(other.settings, settings) || other.settings == settings));
}


@override
int get hashCode => Object.hash(runtimeType,settings);

@override
String toString() {
  return 'MetadataSettingsUpdateResult(settings: $settings)';
}


}

/// @nodoc
abstract mixin class $MetadataSettingsUpdateResultCopyWith<$Res>  {
  factory $MetadataSettingsUpdateResultCopyWith(MetadataSettingsUpdateResult value, $Res Function(MetadataSettingsUpdateResult) _then) = _$MetadataSettingsUpdateResultCopyWithImpl;
@useResult
$Res call({
 MetadataSettings settings
});


$MetadataSettingsCopyWith<$Res> get settings;

}
/// @nodoc
class _$MetadataSettingsUpdateResultCopyWithImpl<$Res>
    implements $MetadataSettingsUpdateResultCopyWith<$Res> {
  _$MetadataSettingsUpdateResultCopyWithImpl(this._self, this._then);

  final MetadataSettingsUpdateResult _self;
  final $Res Function(MetadataSettingsUpdateResult) _then;

/// Create a copy of MetadataSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? settings = null,}) {
  return _then(_self.copyWith(
settings: null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as MetadataSettings,
  ));
}
/// Create a copy of MetadataSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetadataSettingsCopyWith<$Res> get settings {

  return $MetadataSettingsCopyWith<$Res>(_self.settings, (value) {
    return _then(_self.copyWith(settings: value));
  });
}
}


/// Adds pattern-matching-related methods to [MetadataSettingsUpdateResult].
extension MetadataSettingsUpdateResultPatterns on MetadataSettingsUpdateResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( MetadataSettingsUpdateResultCommittedNoResolutionWork value)?  committedNoResolutionWork,TResult Function( MetadataSettingsUpdateResultCommittedAndResolutionAdmitted value)?  committedAndResolutionAdmitted,TResult Function( MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted value)?  committedButResolutionNotAdmitted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case MetadataSettingsUpdateResultCommittedNoResolutionWork() when committedNoResolutionWork != null:
return committedNoResolutionWork(_that);case MetadataSettingsUpdateResultCommittedAndResolutionAdmitted() when committedAndResolutionAdmitted != null:
return committedAndResolutionAdmitted(_that);case MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted() when committedButResolutionNotAdmitted != null:
return committedButResolutionNotAdmitted(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( MetadataSettingsUpdateResultCommittedNoResolutionWork value)  committedNoResolutionWork,required TResult Function( MetadataSettingsUpdateResultCommittedAndResolutionAdmitted value)  committedAndResolutionAdmitted,required TResult Function( MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted value)  committedButResolutionNotAdmitted,}){
final _that = this;
switch (_that) {
case MetadataSettingsUpdateResultCommittedNoResolutionWork():
return committedNoResolutionWork(_that);case MetadataSettingsUpdateResultCommittedAndResolutionAdmitted():
return committedAndResolutionAdmitted(_that);case MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted():
return committedButResolutionNotAdmitted(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( MetadataSettingsUpdateResultCommittedNoResolutionWork value)?  committedNoResolutionWork,TResult? Function( MetadataSettingsUpdateResultCommittedAndResolutionAdmitted value)?  committedAndResolutionAdmitted,TResult? Function( MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted value)?  committedButResolutionNotAdmitted,}){
final _that = this;
switch (_that) {
case MetadataSettingsUpdateResultCommittedNoResolutionWork() when committedNoResolutionWork != null:
return committedNoResolutionWork(_that);case MetadataSettingsUpdateResultCommittedAndResolutionAdmitted() when committedAndResolutionAdmitted != null:
return committedAndResolutionAdmitted(_that);case MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted() when committedButResolutionNotAdmitted != null:
return committedButResolutionNotAdmitted(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( MetadataSettings settings)?  committedNoResolutionWork,TResult Function( MetadataSettings settings,  OperationHandle handle)?  committedAndResolutionAdmitted,TResult Function( MetadataSettings settings,  ClientApplicationError error)?  committedButResolutionNotAdmitted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case MetadataSettingsUpdateResultCommittedNoResolutionWork() when committedNoResolutionWork != null:
return committedNoResolutionWork(_that.settings);case MetadataSettingsUpdateResultCommittedAndResolutionAdmitted() when committedAndResolutionAdmitted != null:
return committedAndResolutionAdmitted(_that.settings,_that.handle);case MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted() when committedButResolutionNotAdmitted != null:
return committedButResolutionNotAdmitted(_that.settings,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( MetadataSettings settings)  committedNoResolutionWork,required TResult Function( MetadataSettings settings,  OperationHandle handle)  committedAndResolutionAdmitted,required TResult Function( MetadataSettings settings,  ClientApplicationError error)  committedButResolutionNotAdmitted,}) {final _that = this;
switch (_that) {
case MetadataSettingsUpdateResultCommittedNoResolutionWork():
return committedNoResolutionWork(_that.settings);case MetadataSettingsUpdateResultCommittedAndResolutionAdmitted():
return committedAndResolutionAdmitted(_that.settings,_that.handle);case MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted():
return committedButResolutionNotAdmitted(_that.settings,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( MetadataSettings settings)?  committedNoResolutionWork,TResult? Function( MetadataSettings settings,  OperationHandle handle)?  committedAndResolutionAdmitted,TResult? Function( MetadataSettings settings,  ClientApplicationError error)?  committedButResolutionNotAdmitted,}) {final _that = this;
switch (_that) {
case MetadataSettingsUpdateResultCommittedNoResolutionWork() when committedNoResolutionWork != null:
return committedNoResolutionWork(_that.settings);case MetadataSettingsUpdateResultCommittedAndResolutionAdmitted() when committedAndResolutionAdmitted != null:
return committedAndResolutionAdmitted(_that.settings,_that.handle);case MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted() when committedButResolutionNotAdmitted != null:
return committedButResolutionNotAdmitted(_that.settings,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class MetadataSettingsUpdateResultCommittedNoResolutionWork implements MetadataSettingsUpdateResult {
  const MetadataSettingsUpdateResultCommittedNoResolutionWork(this.settings);


@override final  MetadataSettings settings;

/// Create a copy of MetadataSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataSettingsUpdateResultCommittedNoResolutionWorkCopyWith<MetadataSettingsUpdateResultCommittedNoResolutionWork> get copyWith => _$MetadataSettingsUpdateResultCommittedNoResolutionWorkCopyWithImpl<MetadataSettingsUpdateResultCommittedNoResolutionWork>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataSettingsUpdateResultCommittedNoResolutionWork&&(identical(other.settings, settings) || other.settings == settings));
}


@override
int get hashCode => Object.hash(runtimeType,settings);

@override
String toString() {
  return 'MetadataSettingsUpdateResult.committedNoResolutionWork(settings: $settings)';
}


}

/// @nodoc
abstract mixin class $MetadataSettingsUpdateResultCommittedNoResolutionWorkCopyWith<$Res> implements $MetadataSettingsUpdateResultCopyWith<$Res> {
  factory $MetadataSettingsUpdateResultCommittedNoResolutionWorkCopyWith(MetadataSettingsUpdateResultCommittedNoResolutionWork value, $Res Function(MetadataSettingsUpdateResultCommittedNoResolutionWork) _then) = _$MetadataSettingsUpdateResultCommittedNoResolutionWorkCopyWithImpl;
@override @useResult
$Res call({
 MetadataSettings settings
});


@override $MetadataSettingsCopyWith<$Res> get settings;

}
/// @nodoc
class _$MetadataSettingsUpdateResultCommittedNoResolutionWorkCopyWithImpl<$Res>
    implements $MetadataSettingsUpdateResultCommittedNoResolutionWorkCopyWith<$Res> {
  _$MetadataSettingsUpdateResultCommittedNoResolutionWorkCopyWithImpl(this._self, this._then);

  final MetadataSettingsUpdateResultCommittedNoResolutionWork _self;
  final $Res Function(MetadataSettingsUpdateResultCommittedNoResolutionWork) _then;

/// Create a copy of MetadataSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? settings = null,}) {
  return _then(MetadataSettingsUpdateResultCommittedNoResolutionWork(
null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as MetadataSettings,
  ));
}

/// Create a copy of MetadataSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetadataSettingsCopyWith<$Res> get settings {

  return $MetadataSettingsCopyWith<$Res>(_self.settings, (value) {
    return _then(_self.copyWith(settings: value));
  });
}
}

/// @nodoc


class MetadataSettingsUpdateResultCommittedAndResolutionAdmitted implements MetadataSettingsUpdateResult {
  const MetadataSettingsUpdateResultCommittedAndResolutionAdmitted(this.settings, this.handle);


@override final  MetadataSettings settings;
 final  OperationHandle handle;

/// Create a copy of MetadataSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataSettingsUpdateResultCommittedAndResolutionAdmittedCopyWith<MetadataSettingsUpdateResultCommittedAndResolutionAdmitted> get copyWith => _$MetadataSettingsUpdateResultCommittedAndResolutionAdmittedCopyWithImpl<MetadataSettingsUpdateResultCommittedAndResolutionAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataSettingsUpdateResultCommittedAndResolutionAdmitted&&(identical(other.settings, settings) || other.settings == settings)&&(identical(other.handle, handle) || other.handle == handle));
}


@override
int get hashCode => Object.hash(runtimeType,settings,handle);

@override
String toString() {
  return 'MetadataSettingsUpdateResult.committedAndResolutionAdmitted(settings: $settings, handle: $handle)';
}


}

/// @nodoc
abstract mixin class $MetadataSettingsUpdateResultCommittedAndResolutionAdmittedCopyWith<$Res> implements $MetadataSettingsUpdateResultCopyWith<$Res> {
  factory $MetadataSettingsUpdateResultCommittedAndResolutionAdmittedCopyWith(MetadataSettingsUpdateResultCommittedAndResolutionAdmitted value, $Res Function(MetadataSettingsUpdateResultCommittedAndResolutionAdmitted) _then) = _$MetadataSettingsUpdateResultCommittedAndResolutionAdmittedCopyWithImpl;
@override @useResult
$Res call({
 MetadataSettings settings, OperationHandle handle
});


@override $MetadataSettingsCopyWith<$Res> get settings;

}
/// @nodoc
class _$MetadataSettingsUpdateResultCommittedAndResolutionAdmittedCopyWithImpl<$Res>
    implements $MetadataSettingsUpdateResultCommittedAndResolutionAdmittedCopyWith<$Res> {
  _$MetadataSettingsUpdateResultCommittedAndResolutionAdmittedCopyWithImpl(this._self, this._then);

  final MetadataSettingsUpdateResultCommittedAndResolutionAdmitted _self;
  final $Res Function(MetadataSettingsUpdateResultCommittedAndResolutionAdmitted) _then;

/// Create a copy of MetadataSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? settings = null,Object? handle = null,}) {
  return _then(MetadataSettingsUpdateResultCommittedAndResolutionAdmitted(
null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as MetadataSettings,null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as OperationHandle,
  ));
}

/// Create a copy of MetadataSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetadataSettingsCopyWith<$Res> get settings {

  return $MetadataSettingsCopyWith<$Res>(_self.settings, (value) {
    return _then(_self.copyWith(settings: value));
  });
}
}

/// @nodoc


class MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted implements MetadataSettingsUpdateResult {
  const MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted(this.settings, this.error);


@override final  MetadataSettings settings;
 final  ClientApplicationError error;

/// Create a copy of MetadataSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWith<MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted> get copyWith => _$MetadataSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWithImpl<MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted&&(identical(other.settings, settings) || other.settings == settings)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,settings,error);

@override
String toString() {
  return 'MetadataSettingsUpdateResult.committedButResolutionNotAdmitted(settings: $settings, error: $error)';
}


}

/// @nodoc
abstract mixin class $MetadataSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWith<$Res> implements $MetadataSettingsUpdateResultCopyWith<$Res> {
  factory $MetadataSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWith(MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted value, $Res Function(MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted) _then) = _$MetadataSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWithImpl;
@override @useResult
$Res call({
 MetadataSettings settings, ClientApplicationError error
});


@override $MetadataSettingsCopyWith<$Res> get settings;$ClientApplicationErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$MetadataSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWithImpl<$Res>
    implements $MetadataSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWith<$Res> {
  _$MetadataSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWithImpl(this._self, this._then);

  final MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted _self;
  final $Res Function(MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted) _then;

/// Create a copy of MetadataSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? settings = null,Object? error = null,}) {
  return _then(MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted(
null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as MetadataSettings,null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ClientApplicationError,
  ));
}

/// Create a copy of MetadataSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetadataSettingsCopyWith<$Res> get settings {

  return $MetadataSettingsCopyWith<$Res>(_self.settings, (value) {
    return _then(_self.copyWith(settings: value));
  });
}/// Create a copy of MetadataSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientApplicationErrorCopyWith<$Res> get error {

  return $ClientApplicationErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$MetadataProviderSettingsUpdateResult {

 MetadataProviderSettings get settings;
/// Create a copy of MetadataProviderSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataProviderSettingsUpdateResultCopyWith<MetadataProviderSettingsUpdateResult> get copyWith => _$MetadataProviderSettingsUpdateResultCopyWithImpl<MetadataProviderSettingsUpdateResult>(this as MetadataProviderSettingsUpdateResult, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataProviderSettingsUpdateResult&&(identical(other.settings, settings) || other.settings == settings));
}


@override
int get hashCode => Object.hash(runtimeType,settings);

@override
String toString() {
  return 'MetadataProviderSettingsUpdateResult(settings: $settings)';
}


}

/// @nodoc
abstract mixin class $MetadataProviderSettingsUpdateResultCopyWith<$Res>  {
  factory $MetadataProviderSettingsUpdateResultCopyWith(MetadataProviderSettingsUpdateResult value, $Res Function(MetadataProviderSettingsUpdateResult) _then) = _$MetadataProviderSettingsUpdateResultCopyWithImpl;
@useResult
$Res call({
 MetadataProviderSettings settings
});


$MetadataProviderSettingsCopyWith<$Res> get settings;

}
/// @nodoc
class _$MetadataProviderSettingsUpdateResultCopyWithImpl<$Res>
    implements $MetadataProviderSettingsUpdateResultCopyWith<$Res> {
  _$MetadataProviderSettingsUpdateResultCopyWithImpl(this._self, this._then);

  final MetadataProviderSettingsUpdateResult _self;
  final $Res Function(MetadataProviderSettingsUpdateResult) _then;

/// Create a copy of MetadataProviderSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? settings = null,}) {
  return _then(_self.copyWith(
settings: null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as MetadataProviderSettings,
  ));
}
/// Create a copy of MetadataProviderSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetadataProviderSettingsCopyWith<$Res> get settings {

  return $MetadataProviderSettingsCopyWith<$Res>(_self.settings, (value) {
    return _then(_self.copyWith(settings: value));
  });
}
}


/// Adds pattern-matching-related methods to [MetadataProviderSettingsUpdateResult].
extension MetadataProviderSettingsUpdateResultPatterns on MetadataProviderSettingsUpdateResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( MetadataProviderSettingsUpdateResultCommittedNoResolutionWork value)?  committedNoResolutionWork,TResult Function( MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted value)?  committedAndResolutionAdmitted,TResult Function( MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted value)?  committedButResolutionNotAdmitted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case MetadataProviderSettingsUpdateResultCommittedNoResolutionWork() when committedNoResolutionWork != null:
return committedNoResolutionWork(_that);case MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted() when committedAndResolutionAdmitted != null:
return committedAndResolutionAdmitted(_that);case MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted() when committedButResolutionNotAdmitted != null:
return committedButResolutionNotAdmitted(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( MetadataProviderSettingsUpdateResultCommittedNoResolutionWork value)  committedNoResolutionWork,required TResult Function( MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted value)  committedAndResolutionAdmitted,required TResult Function( MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted value)  committedButResolutionNotAdmitted,}){
final _that = this;
switch (_that) {
case MetadataProviderSettingsUpdateResultCommittedNoResolutionWork():
return committedNoResolutionWork(_that);case MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted():
return committedAndResolutionAdmitted(_that);case MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted():
return committedButResolutionNotAdmitted(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( MetadataProviderSettingsUpdateResultCommittedNoResolutionWork value)?  committedNoResolutionWork,TResult? Function( MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted value)?  committedAndResolutionAdmitted,TResult? Function( MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted value)?  committedButResolutionNotAdmitted,}){
final _that = this;
switch (_that) {
case MetadataProviderSettingsUpdateResultCommittedNoResolutionWork() when committedNoResolutionWork != null:
return committedNoResolutionWork(_that);case MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted() when committedAndResolutionAdmitted != null:
return committedAndResolutionAdmitted(_that);case MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted() when committedButResolutionNotAdmitted != null:
return committedButResolutionNotAdmitted(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( MetadataProviderSettings settings)?  committedNoResolutionWork,TResult Function( MetadataProviderSettings settings,  OperationHandle handle)?  committedAndResolutionAdmitted,TResult Function( MetadataProviderSettings settings,  ClientApplicationError error)?  committedButResolutionNotAdmitted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case MetadataProviderSettingsUpdateResultCommittedNoResolutionWork() when committedNoResolutionWork != null:
return committedNoResolutionWork(_that.settings);case MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted() when committedAndResolutionAdmitted != null:
return committedAndResolutionAdmitted(_that.settings,_that.handle);case MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted() when committedButResolutionNotAdmitted != null:
return committedButResolutionNotAdmitted(_that.settings,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( MetadataProviderSettings settings)  committedNoResolutionWork,required TResult Function( MetadataProviderSettings settings,  OperationHandle handle)  committedAndResolutionAdmitted,required TResult Function( MetadataProviderSettings settings,  ClientApplicationError error)  committedButResolutionNotAdmitted,}) {final _that = this;
switch (_that) {
case MetadataProviderSettingsUpdateResultCommittedNoResolutionWork():
return committedNoResolutionWork(_that.settings);case MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted():
return committedAndResolutionAdmitted(_that.settings,_that.handle);case MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted():
return committedButResolutionNotAdmitted(_that.settings,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( MetadataProviderSettings settings)?  committedNoResolutionWork,TResult? Function( MetadataProviderSettings settings,  OperationHandle handle)?  committedAndResolutionAdmitted,TResult? Function( MetadataProviderSettings settings,  ClientApplicationError error)?  committedButResolutionNotAdmitted,}) {final _that = this;
switch (_that) {
case MetadataProviderSettingsUpdateResultCommittedNoResolutionWork() when committedNoResolutionWork != null:
return committedNoResolutionWork(_that.settings);case MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted() when committedAndResolutionAdmitted != null:
return committedAndResolutionAdmitted(_that.settings,_that.handle);case MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted() when committedButResolutionNotAdmitted != null:
return committedButResolutionNotAdmitted(_that.settings,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class MetadataProviderSettingsUpdateResultCommittedNoResolutionWork implements MetadataProviderSettingsUpdateResult {
  const MetadataProviderSettingsUpdateResultCommittedNoResolutionWork(this.settings);


@override final  MetadataProviderSettings settings;

/// Create a copy of MetadataProviderSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataProviderSettingsUpdateResultCommittedNoResolutionWorkCopyWith<MetadataProviderSettingsUpdateResultCommittedNoResolutionWork> get copyWith => _$MetadataProviderSettingsUpdateResultCommittedNoResolutionWorkCopyWithImpl<MetadataProviderSettingsUpdateResultCommittedNoResolutionWork>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataProviderSettingsUpdateResultCommittedNoResolutionWork&&(identical(other.settings, settings) || other.settings == settings));
}


@override
int get hashCode => Object.hash(runtimeType,settings);

@override
String toString() {
  return 'MetadataProviderSettingsUpdateResult.committedNoResolutionWork(settings: $settings)';
}


}

/// @nodoc
abstract mixin class $MetadataProviderSettingsUpdateResultCommittedNoResolutionWorkCopyWith<$Res> implements $MetadataProviderSettingsUpdateResultCopyWith<$Res> {
  factory $MetadataProviderSettingsUpdateResultCommittedNoResolutionWorkCopyWith(MetadataProviderSettingsUpdateResultCommittedNoResolutionWork value, $Res Function(MetadataProviderSettingsUpdateResultCommittedNoResolutionWork) _then) = _$MetadataProviderSettingsUpdateResultCommittedNoResolutionWorkCopyWithImpl;
@override @useResult
$Res call({
 MetadataProviderSettings settings
});


@override $MetadataProviderSettingsCopyWith<$Res> get settings;

}
/// @nodoc
class _$MetadataProviderSettingsUpdateResultCommittedNoResolutionWorkCopyWithImpl<$Res>
    implements $MetadataProviderSettingsUpdateResultCommittedNoResolutionWorkCopyWith<$Res> {
  _$MetadataProviderSettingsUpdateResultCommittedNoResolutionWorkCopyWithImpl(this._self, this._then);

  final MetadataProviderSettingsUpdateResultCommittedNoResolutionWork _self;
  final $Res Function(MetadataProviderSettingsUpdateResultCommittedNoResolutionWork) _then;

/// Create a copy of MetadataProviderSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? settings = null,}) {
  return _then(MetadataProviderSettingsUpdateResultCommittedNoResolutionWork(
null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as MetadataProviderSettings,
  ));
}

/// Create a copy of MetadataProviderSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetadataProviderSettingsCopyWith<$Res> get settings {

  return $MetadataProviderSettingsCopyWith<$Res>(_self.settings, (value) {
    return _then(_self.copyWith(settings: value));
  });
}
}

/// @nodoc


class MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted implements MetadataProviderSettingsUpdateResult {
  const MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted(this.settings, this.handle);


@override final  MetadataProviderSettings settings;
 final  OperationHandle handle;

/// Create a copy of MetadataProviderSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmittedCopyWith<MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted> get copyWith => _$MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmittedCopyWithImpl<MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted&&(identical(other.settings, settings) || other.settings == settings)&&(identical(other.handle, handle) || other.handle == handle));
}


@override
int get hashCode => Object.hash(runtimeType,settings,handle);

@override
String toString() {
  return 'MetadataProviderSettingsUpdateResult.committedAndResolutionAdmitted(settings: $settings, handle: $handle)';
}


}

/// @nodoc
abstract mixin class $MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmittedCopyWith<$Res> implements $MetadataProviderSettingsUpdateResultCopyWith<$Res> {
  factory $MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmittedCopyWith(MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted value, $Res Function(MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted) _then) = _$MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmittedCopyWithImpl;
@override @useResult
$Res call({
 MetadataProviderSettings settings, OperationHandle handle
});


@override $MetadataProviderSettingsCopyWith<$Res> get settings;

}
/// @nodoc
class _$MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmittedCopyWithImpl<$Res>
    implements $MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmittedCopyWith<$Res> {
  _$MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmittedCopyWithImpl(this._self, this._then);

  final MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted _self;
  final $Res Function(MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted) _then;

/// Create a copy of MetadataProviderSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? settings = null,Object? handle = null,}) {
  return _then(MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted(
null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as MetadataProviderSettings,null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as OperationHandle,
  ));
}

/// Create a copy of MetadataProviderSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetadataProviderSettingsCopyWith<$Res> get settings {

  return $MetadataProviderSettingsCopyWith<$Res>(_self.settings, (value) {
    return _then(_self.copyWith(settings: value));
  });
}
}

/// @nodoc


class MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted implements MetadataProviderSettingsUpdateResult {
  const MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted(this.settings, this.error);


@override final  MetadataProviderSettings settings;
 final  ClientApplicationError error;

/// Create a copy of MetadataProviderSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWith<MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted> get copyWith => _$MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWithImpl<MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted&&(identical(other.settings, settings) || other.settings == settings)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,settings,error);

@override
String toString() {
  return 'MetadataProviderSettingsUpdateResult.committedButResolutionNotAdmitted(settings: $settings, error: $error)';
}


}

/// @nodoc
abstract mixin class $MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWith<$Res> implements $MetadataProviderSettingsUpdateResultCopyWith<$Res> {
  factory $MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWith(MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted value, $Res Function(MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted) _then) = _$MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWithImpl;
@override @useResult
$Res call({
 MetadataProviderSettings settings, ClientApplicationError error
});


@override $MetadataProviderSettingsCopyWith<$Res> get settings;$ClientApplicationErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWithImpl<$Res>
    implements $MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWith<$Res> {
  _$MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmittedCopyWithImpl(this._self, this._then);

  final MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted _self;
  final $Res Function(MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted) _then;

/// Create a copy of MetadataProviderSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? settings = null,Object? error = null,}) {
  return _then(MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted(
null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as MetadataProviderSettings,null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ClientApplicationError,
  ));
}

/// Create a copy of MetadataProviderSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetadataProviderSettingsCopyWith<$Res> get settings {

  return $MetadataProviderSettingsCopyWith<$Res>(_self.settings, (value) {
    return _then(_self.copyWith(settings: value));
  });
}/// Create a copy of MetadataProviderSettingsUpdateResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientApplicationErrorCopyWith<$Res> get error {

  return $ClientApplicationErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$JobListItem {

 JobRunId get jobRunId; String get operationType; JobLifecycleState get lifecycleState; String? get phase; int get createdAtMs; int? get startedAtMs; int? get terminalAtMs; bool get cancellationRequested; String? get safeContextSummary;
/// Create a copy of JobListItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobListItemCopyWith<JobListItem> get copyWith => _$JobListItemCopyWithImpl<JobListItem>(this as JobListItem, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobListItem&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId)&&(identical(other.operationType, operationType) || other.operationType == operationType)&&(identical(other.lifecycleState, lifecycleState) || other.lifecycleState == lifecycleState)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.createdAtMs, createdAtMs) || other.createdAtMs == createdAtMs)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs)&&(identical(other.terminalAtMs, terminalAtMs) || other.terminalAtMs == terminalAtMs)&&(identical(other.cancellationRequested, cancellationRequested) || other.cancellationRequested == cancellationRequested)&&(identical(other.safeContextSummary, safeContextSummary) || other.safeContextSummary == safeContextSummary));
}


@override
int get hashCode => Object.hash(runtimeType,jobRunId,operationType,lifecycleState,phase,createdAtMs,startedAtMs,terminalAtMs,cancellationRequested,safeContextSummary);

@override
String toString() {
  return 'JobListItem(jobRunId: $jobRunId, operationType: $operationType, lifecycleState: $lifecycleState, phase: $phase, createdAtMs: $createdAtMs, startedAtMs: $startedAtMs, terminalAtMs: $terminalAtMs, cancellationRequested: $cancellationRequested, safeContextSummary: $safeContextSummary)';
}


}

/// @nodoc
abstract mixin class $JobListItemCopyWith<$Res>  {
  factory $JobListItemCopyWith(JobListItem value, $Res Function(JobListItem) _then) = _$JobListItemCopyWithImpl;
@useResult
$Res call({
 JobRunId jobRunId, String operationType, JobLifecycleState lifecycleState, String? phase, int createdAtMs, int? startedAtMs, int? terminalAtMs, bool cancellationRequested, String? safeContextSummary
});




}
/// @nodoc
class _$JobListItemCopyWithImpl<$Res>
    implements $JobListItemCopyWith<$Res> {
  _$JobListItemCopyWithImpl(this._self, this._then);

  final JobListItem _self;
  final $Res Function(JobListItem) _then;

/// Create a copy of JobListItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? jobRunId = null,Object? operationType = null,Object? lifecycleState = null,Object? phase = freezed,Object? createdAtMs = null,Object? startedAtMs = freezed,Object? terminalAtMs = freezed,Object? cancellationRequested = null,Object? safeContextSummary = freezed,}) {
  return _then(_self.copyWith(
jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,operationType: null == operationType ? _self.operationType : operationType // ignore: cast_nullable_to_non_nullable
as String,lifecycleState: null == lifecycleState ? _self.lifecycleState : lifecycleState // ignore: cast_nullable_to_non_nullable
as JobLifecycleState,phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String?,createdAtMs: null == createdAtMs ? _self.createdAtMs : createdAtMs // ignore: cast_nullable_to_non_nullable
as int,startedAtMs: freezed == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as int?,terminalAtMs: freezed == terminalAtMs ? _self.terminalAtMs : terminalAtMs // ignore: cast_nullable_to_non_nullable
as int?,cancellationRequested: null == cancellationRequested ? _self.cancellationRequested : cancellationRequested // ignore: cast_nullable_to_non_nullable
as bool,safeContextSummary: freezed == safeContextSummary ? _self.safeContextSummary : safeContextSummary // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [JobListItem].
extension JobListItemPatterns on JobListItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JobListItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JobListItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JobListItem value)  $default,){
final _that = this;
switch (_that) {
case _JobListItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JobListItem value)?  $default,){
final _that = this;
switch (_that) {
case _JobListItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( JobRunId jobRunId,  String operationType,  JobLifecycleState lifecycleState,  String? phase,  int createdAtMs,  int? startedAtMs,  int? terminalAtMs,  bool cancellationRequested,  String? safeContextSummary)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JobListItem() when $default != null:
return $default(_that.jobRunId,_that.operationType,_that.lifecycleState,_that.phase,_that.createdAtMs,_that.startedAtMs,_that.terminalAtMs,_that.cancellationRequested,_that.safeContextSummary);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( JobRunId jobRunId,  String operationType,  JobLifecycleState lifecycleState,  String? phase,  int createdAtMs,  int? startedAtMs,  int? terminalAtMs,  bool cancellationRequested,  String? safeContextSummary)  $default,) {final _that = this;
switch (_that) {
case _JobListItem():
return $default(_that.jobRunId,_that.operationType,_that.lifecycleState,_that.phase,_that.createdAtMs,_that.startedAtMs,_that.terminalAtMs,_that.cancellationRequested,_that.safeContextSummary);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( JobRunId jobRunId,  String operationType,  JobLifecycleState lifecycleState,  String? phase,  int createdAtMs,  int? startedAtMs,  int? terminalAtMs,  bool cancellationRequested,  String? safeContextSummary)?  $default,) {final _that = this;
switch (_that) {
case _JobListItem() when $default != null:
return $default(_that.jobRunId,_that.operationType,_that.lifecycleState,_that.phase,_that.createdAtMs,_that.startedAtMs,_that.terminalAtMs,_that.cancellationRequested,_that.safeContextSummary);case _:
  return null;

}
}

}

/// @nodoc


class _JobListItem implements JobListItem {
  const _JobListItem({required this.jobRunId, required this.operationType, required this.lifecycleState, this.phase, required this.createdAtMs, this.startedAtMs, this.terminalAtMs, required this.cancellationRequested, this.safeContextSummary});


@override final  JobRunId jobRunId;
@override final  String operationType;
@override final  JobLifecycleState lifecycleState;
@override final  String? phase;
@override final  int createdAtMs;
@override final  int? startedAtMs;
@override final  int? terminalAtMs;
@override final  bool cancellationRequested;
@override final  String? safeContextSummary;

/// Create a copy of JobListItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JobListItemCopyWith<_JobListItem> get copyWith => __$JobListItemCopyWithImpl<_JobListItem>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _JobListItem&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId)&&(identical(other.operationType, operationType) || other.operationType == operationType)&&(identical(other.lifecycleState, lifecycleState) || other.lifecycleState == lifecycleState)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.createdAtMs, createdAtMs) || other.createdAtMs == createdAtMs)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs)&&(identical(other.terminalAtMs, terminalAtMs) || other.terminalAtMs == terminalAtMs)&&(identical(other.cancellationRequested, cancellationRequested) || other.cancellationRequested == cancellationRequested)&&(identical(other.safeContextSummary, safeContextSummary) || other.safeContextSummary == safeContextSummary));
}


@override
int get hashCode => Object.hash(runtimeType,jobRunId,operationType,lifecycleState,phase,createdAtMs,startedAtMs,terminalAtMs,cancellationRequested,safeContextSummary);

@override
String toString() {
  return 'JobListItem(jobRunId: $jobRunId, operationType: $operationType, lifecycleState: $lifecycleState, phase: $phase, createdAtMs: $createdAtMs, startedAtMs: $startedAtMs, terminalAtMs: $terminalAtMs, cancellationRequested: $cancellationRequested, safeContextSummary: $safeContextSummary)';
}


}

/// @nodoc
abstract mixin class _$JobListItemCopyWith<$Res> implements $JobListItemCopyWith<$Res> {
  factory _$JobListItemCopyWith(_JobListItem value, $Res Function(_JobListItem) _then) = __$JobListItemCopyWithImpl;
@override @useResult
$Res call({
 JobRunId jobRunId, String operationType, JobLifecycleState lifecycleState, String? phase, int createdAtMs, int? startedAtMs, int? terminalAtMs, bool cancellationRequested, String? safeContextSummary
});




}
/// @nodoc
class __$JobListItemCopyWithImpl<$Res>
    implements _$JobListItemCopyWith<$Res> {
  __$JobListItemCopyWithImpl(this._self, this._then);

  final _JobListItem _self;
  final $Res Function(_JobListItem) _then;

/// Create a copy of JobListItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? jobRunId = null,Object? operationType = null,Object? lifecycleState = null,Object? phase = freezed,Object? createdAtMs = null,Object? startedAtMs = freezed,Object? terminalAtMs = freezed,Object? cancellationRequested = null,Object? safeContextSummary = freezed,}) {
  return _then(_JobListItem(
jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,operationType: null == operationType ? _self.operationType : operationType // ignore: cast_nullable_to_non_nullable
as String,lifecycleState: null == lifecycleState ? _self.lifecycleState : lifecycleState // ignore: cast_nullable_to_non_nullable
as JobLifecycleState,phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String?,createdAtMs: null == createdAtMs ? _self.createdAtMs : createdAtMs // ignore: cast_nullable_to_non_nullable
as int,startedAtMs: freezed == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as int?,terminalAtMs: freezed == terminalAtMs ? _self.terminalAtMs : terminalAtMs // ignore: cast_nullable_to_non_nullable
as int?,cancellationRequested: null == cancellationRequested ? _self.cancellationRequested : cancellationRequested // ignore: cast_nullable_to_non_nullable
as bool,safeContextSummary: freezed == safeContextSummary ? _self.safeContextSummary : safeContextSummary // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$JobControlAvailability {

 bool get canCancel; bool get canRetry;
/// Create a copy of JobControlAvailability
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobControlAvailabilityCopyWith<JobControlAvailability> get copyWith => _$JobControlAvailabilityCopyWithImpl<JobControlAvailability>(this as JobControlAvailability, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobControlAvailability&&(identical(other.canCancel, canCancel) || other.canCancel == canCancel)&&(identical(other.canRetry, canRetry) || other.canRetry == canRetry));
}


@override
int get hashCode => Object.hash(runtimeType,canCancel,canRetry);

@override
String toString() {
  return 'JobControlAvailability(canCancel: $canCancel, canRetry: $canRetry)';
}


}

/// @nodoc
abstract mixin class $JobControlAvailabilityCopyWith<$Res>  {
  factory $JobControlAvailabilityCopyWith(JobControlAvailability value, $Res Function(JobControlAvailability) _then) = _$JobControlAvailabilityCopyWithImpl;
@useResult
$Res call({
 bool canCancel, bool canRetry
});




}
/// @nodoc
class _$JobControlAvailabilityCopyWithImpl<$Res>
    implements $JobControlAvailabilityCopyWith<$Res> {
  _$JobControlAvailabilityCopyWithImpl(this._self, this._then);

  final JobControlAvailability _self;
  final $Res Function(JobControlAvailability) _then;

/// Create a copy of JobControlAvailability
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? canCancel = null,Object? canRetry = null,}) {
  return _then(_self.copyWith(
canCancel: null == canCancel ? _self.canCancel : canCancel // ignore: cast_nullable_to_non_nullable
as bool,canRetry: null == canRetry ? _self.canRetry : canRetry // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [JobControlAvailability].
extension JobControlAvailabilityPatterns on JobControlAvailability {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JobControlAvailability value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JobControlAvailability() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JobControlAvailability value)  $default,){
final _that = this;
switch (_that) {
case _JobControlAvailability():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JobControlAvailability value)?  $default,){
final _that = this;
switch (_that) {
case _JobControlAvailability() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool canCancel,  bool canRetry)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JobControlAvailability() when $default != null:
return $default(_that.canCancel,_that.canRetry);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool canCancel,  bool canRetry)  $default,) {final _that = this;
switch (_that) {
case _JobControlAvailability():
return $default(_that.canCancel,_that.canRetry);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool canCancel,  bool canRetry)?  $default,) {final _that = this;
switch (_that) {
case _JobControlAvailability() when $default != null:
return $default(_that.canCancel,_that.canRetry);case _:
  return null;

}
}

}

/// @nodoc


class _JobControlAvailability implements JobControlAvailability {
  const _JobControlAvailability({required this.canCancel, required this.canRetry});


@override final  bool canCancel;
@override final  bool canRetry;

/// Create a copy of JobControlAvailability
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JobControlAvailabilityCopyWith<_JobControlAvailability> get copyWith => __$JobControlAvailabilityCopyWithImpl<_JobControlAvailability>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _JobControlAvailability&&(identical(other.canCancel, canCancel) || other.canCancel == canCancel)&&(identical(other.canRetry, canRetry) || other.canRetry == canRetry));
}


@override
int get hashCode => Object.hash(runtimeType,canCancel,canRetry);

@override
String toString() {
  return 'JobControlAvailability(canCancel: $canCancel, canRetry: $canRetry)';
}


}

/// @nodoc
abstract mixin class _$JobControlAvailabilityCopyWith<$Res> implements $JobControlAvailabilityCopyWith<$Res> {
  factory _$JobControlAvailabilityCopyWith(_JobControlAvailability value, $Res Function(_JobControlAvailability) _then) = __$JobControlAvailabilityCopyWithImpl;
@override @useResult
$Res call({
 bool canCancel, bool canRetry
});




}
/// @nodoc
class __$JobControlAvailabilityCopyWithImpl<$Res>
    implements _$JobControlAvailabilityCopyWith<$Res> {
  __$JobControlAvailabilityCopyWithImpl(this._self, this._then);

  final _JobControlAvailability _self;
  final $Res Function(_JobControlAvailability) _then;

/// Create a copy of JobControlAvailability
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canCancel = null,Object? canRetry = null,}) {
  return _then(_JobControlAvailability(
canCancel: null == canCancel ? _self.canCancel : canCancel // ignore: cast_nullable_to_non_nullable
as bool,canRetry: null == canRetry ? _self.canRetry : canRetry // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$BoundedTerminalFailure {

 String? get errorCode; String? get safeContext;
/// Create a copy of BoundedTerminalFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BoundedTerminalFailureCopyWith<BoundedTerminalFailure> get copyWith => _$BoundedTerminalFailureCopyWithImpl<BoundedTerminalFailure>(this as BoundedTerminalFailure, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BoundedTerminalFailure&&(identical(other.errorCode, errorCode) || other.errorCode == errorCode)&&(identical(other.safeContext, safeContext) || other.safeContext == safeContext));
}


@override
int get hashCode => Object.hash(runtimeType,errorCode,safeContext);

@override
String toString() {
  return 'BoundedTerminalFailure(errorCode: $errorCode, safeContext: $safeContext)';
}


}

/// @nodoc
abstract mixin class $BoundedTerminalFailureCopyWith<$Res>  {
  factory $BoundedTerminalFailureCopyWith(BoundedTerminalFailure value, $Res Function(BoundedTerminalFailure) _then) = _$BoundedTerminalFailureCopyWithImpl;
@useResult
$Res call({
 String? errorCode, String? safeContext
});




}
/// @nodoc
class _$BoundedTerminalFailureCopyWithImpl<$Res>
    implements $BoundedTerminalFailureCopyWith<$Res> {
  _$BoundedTerminalFailureCopyWithImpl(this._self, this._then);

  final BoundedTerminalFailure _self;
  final $Res Function(BoundedTerminalFailure) _then;

/// Create a copy of BoundedTerminalFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? errorCode = freezed,Object? safeContext = freezed,}) {
  return _then(_self.copyWith(
errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,safeContext: freezed == safeContext ? _self.safeContext : safeContext // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BoundedTerminalFailure].
extension BoundedTerminalFailurePatterns on BoundedTerminalFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BoundedTerminalFailure value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BoundedTerminalFailure() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BoundedTerminalFailure value)  $default,){
final _that = this;
switch (_that) {
case _BoundedTerminalFailure():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BoundedTerminalFailure value)?  $default,){
final _that = this;
switch (_that) {
case _BoundedTerminalFailure() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? errorCode,  String? safeContext)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BoundedTerminalFailure() when $default != null:
return $default(_that.errorCode,_that.safeContext);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? errorCode,  String? safeContext)  $default,) {final _that = this;
switch (_that) {
case _BoundedTerminalFailure():
return $default(_that.errorCode,_that.safeContext);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? errorCode,  String? safeContext)?  $default,) {final _that = this;
switch (_that) {
case _BoundedTerminalFailure() when $default != null:
return $default(_that.errorCode,_that.safeContext);case _:
  return null;

}
}

}

/// @nodoc


class _BoundedTerminalFailure implements BoundedTerminalFailure {
  const _BoundedTerminalFailure({this.errorCode, this.safeContext});


@override final  String? errorCode;
@override final  String? safeContext;

/// Create a copy of BoundedTerminalFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BoundedTerminalFailureCopyWith<_BoundedTerminalFailure> get copyWith => __$BoundedTerminalFailureCopyWithImpl<_BoundedTerminalFailure>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BoundedTerminalFailure&&(identical(other.errorCode, errorCode) || other.errorCode == errorCode)&&(identical(other.safeContext, safeContext) || other.safeContext == safeContext));
}


@override
int get hashCode => Object.hash(runtimeType,errorCode,safeContext);

@override
String toString() {
  return 'BoundedTerminalFailure(errorCode: $errorCode, safeContext: $safeContext)';
}


}

/// @nodoc
abstract mixin class _$BoundedTerminalFailureCopyWith<$Res> implements $BoundedTerminalFailureCopyWith<$Res> {
  factory _$BoundedTerminalFailureCopyWith(_BoundedTerminalFailure value, $Res Function(_BoundedTerminalFailure) _then) = __$BoundedTerminalFailureCopyWithImpl;
@override @useResult
$Res call({
 String? errorCode, String? safeContext
});




}
/// @nodoc
class __$BoundedTerminalFailureCopyWithImpl<$Res>
    implements _$BoundedTerminalFailureCopyWith<$Res> {
  __$BoundedTerminalFailureCopyWithImpl(this._self, this._then);

  final _BoundedTerminalFailure _self;
  final $Res Function(_BoundedTerminalFailure) _then;

/// Create a copy of BoundedTerminalFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? errorCode = freezed,Object? safeContext = freezed,}) {
  return _then(_BoundedTerminalFailure(
errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,safeContext: freezed == safeContext ? _self.safeContext : safeContext // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$JobRunProjection {

 JobRunId get jobRunId; String get operationType; JobLifecycleState get lifecycleState; String? get phase; int? get completedUnits; int? get totalUnits; String? get statusKey; int get createdAtMs; int? get queuedAtMs; int? get startedAtMs; int? get terminalAtMs; bool get cancellationRequested; JobControlAvailability get controls; BoundedTerminalFailure? get boundedTerminalFailure;
/// Create a copy of JobRunProjection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobRunProjectionCopyWith<JobRunProjection> get copyWith => _$JobRunProjectionCopyWithImpl<JobRunProjection>(this as JobRunProjection, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobRunProjection&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId)&&(identical(other.operationType, operationType) || other.operationType == operationType)&&(identical(other.lifecycleState, lifecycleState) || other.lifecycleState == lifecycleState)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.completedUnits, completedUnits) || other.completedUnits == completedUnits)&&(identical(other.totalUnits, totalUnits) || other.totalUnits == totalUnits)&&(identical(other.statusKey, statusKey) || other.statusKey == statusKey)&&(identical(other.createdAtMs, createdAtMs) || other.createdAtMs == createdAtMs)&&(identical(other.queuedAtMs, queuedAtMs) || other.queuedAtMs == queuedAtMs)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs)&&(identical(other.terminalAtMs, terminalAtMs) || other.terminalAtMs == terminalAtMs)&&(identical(other.cancellationRequested, cancellationRequested) || other.cancellationRequested == cancellationRequested)&&(identical(other.controls, controls) || other.controls == controls)&&(identical(other.boundedTerminalFailure, boundedTerminalFailure) || other.boundedTerminalFailure == boundedTerminalFailure));
}


@override
int get hashCode => Object.hash(runtimeType,jobRunId,operationType,lifecycleState,phase,completedUnits,totalUnits,statusKey,createdAtMs,queuedAtMs,startedAtMs,terminalAtMs,cancellationRequested,controls,boundedTerminalFailure);

@override
String toString() {
  return 'JobRunProjection(jobRunId: $jobRunId, operationType: $operationType, lifecycleState: $lifecycleState, phase: $phase, completedUnits: $completedUnits, totalUnits: $totalUnits, statusKey: $statusKey, createdAtMs: $createdAtMs, queuedAtMs: $queuedAtMs, startedAtMs: $startedAtMs, terminalAtMs: $terminalAtMs, cancellationRequested: $cancellationRequested, controls: $controls, boundedTerminalFailure: $boundedTerminalFailure)';
}


}

/// @nodoc
abstract mixin class $JobRunProjectionCopyWith<$Res>  {
  factory $JobRunProjectionCopyWith(JobRunProjection value, $Res Function(JobRunProjection) _then) = _$JobRunProjectionCopyWithImpl;
@useResult
$Res call({
 JobRunId jobRunId, String operationType, JobLifecycleState lifecycleState, String? phase, int? completedUnits, int? totalUnits, String? statusKey, int createdAtMs, int? queuedAtMs, int? startedAtMs, int? terminalAtMs, bool cancellationRequested, JobControlAvailability controls, BoundedTerminalFailure? boundedTerminalFailure
});


$JobControlAvailabilityCopyWith<$Res> get controls;$BoundedTerminalFailureCopyWith<$Res>? get boundedTerminalFailure;

}
/// @nodoc
class _$JobRunProjectionCopyWithImpl<$Res>
    implements $JobRunProjectionCopyWith<$Res> {
  _$JobRunProjectionCopyWithImpl(this._self, this._then);

  final JobRunProjection _self;
  final $Res Function(JobRunProjection) _then;

/// Create a copy of JobRunProjection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? jobRunId = null,Object? operationType = null,Object? lifecycleState = null,Object? phase = freezed,Object? completedUnits = freezed,Object? totalUnits = freezed,Object? statusKey = freezed,Object? createdAtMs = null,Object? queuedAtMs = freezed,Object? startedAtMs = freezed,Object? terminalAtMs = freezed,Object? cancellationRequested = null,Object? controls = null,Object? boundedTerminalFailure = freezed,}) {
  return _then(_self.copyWith(
jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,operationType: null == operationType ? _self.operationType : operationType // ignore: cast_nullable_to_non_nullable
as String,lifecycleState: null == lifecycleState ? _self.lifecycleState : lifecycleState // ignore: cast_nullable_to_non_nullable
as JobLifecycleState,phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String?,completedUnits: freezed == completedUnits ? _self.completedUnits : completedUnits // ignore: cast_nullable_to_non_nullable
as int?,totalUnits: freezed == totalUnits ? _self.totalUnits : totalUnits // ignore: cast_nullable_to_non_nullable
as int?,statusKey: freezed == statusKey ? _self.statusKey : statusKey // ignore: cast_nullable_to_non_nullable
as String?,createdAtMs: null == createdAtMs ? _self.createdAtMs : createdAtMs // ignore: cast_nullable_to_non_nullable
as int,queuedAtMs: freezed == queuedAtMs ? _self.queuedAtMs : queuedAtMs // ignore: cast_nullable_to_non_nullable
as int?,startedAtMs: freezed == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as int?,terminalAtMs: freezed == terminalAtMs ? _self.terminalAtMs : terminalAtMs // ignore: cast_nullable_to_non_nullable
as int?,cancellationRequested: null == cancellationRequested ? _self.cancellationRequested : cancellationRequested // ignore: cast_nullable_to_non_nullable
as bool,controls: null == controls ? _self.controls : controls // ignore: cast_nullable_to_non_nullable
as JobControlAvailability,boundedTerminalFailure: freezed == boundedTerminalFailure ? _self.boundedTerminalFailure : boundedTerminalFailure // ignore: cast_nullable_to_non_nullable
as BoundedTerminalFailure?,
  ));
}
/// Create a copy of JobRunProjection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JobControlAvailabilityCopyWith<$Res> get controls {

  return $JobControlAvailabilityCopyWith<$Res>(_self.controls, (value) {
    return _then(_self.copyWith(controls: value));
  });
}/// Create a copy of JobRunProjection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BoundedTerminalFailureCopyWith<$Res>? get boundedTerminalFailure {
    if (_self.boundedTerminalFailure == null) {
    return null;
  }

  return $BoundedTerminalFailureCopyWith<$Res>(_self.boundedTerminalFailure!, (value) {
    return _then(_self.copyWith(boundedTerminalFailure: value));
  });
}
}


/// Adds pattern-matching-related methods to [JobRunProjection].
extension JobRunProjectionPatterns on JobRunProjection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JobRunProjection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JobRunProjection() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JobRunProjection value)  $default,){
final _that = this;
switch (_that) {
case _JobRunProjection():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JobRunProjection value)?  $default,){
final _that = this;
switch (_that) {
case _JobRunProjection() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( JobRunId jobRunId,  String operationType,  JobLifecycleState lifecycleState,  String? phase,  int? completedUnits,  int? totalUnits,  String? statusKey,  int createdAtMs,  int? queuedAtMs,  int? startedAtMs,  int? terminalAtMs,  bool cancellationRequested,  JobControlAvailability controls,  BoundedTerminalFailure? boundedTerminalFailure)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JobRunProjection() when $default != null:
return $default(_that.jobRunId,_that.operationType,_that.lifecycleState,_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey,_that.createdAtMs,_that.queuedAtMs,_that.startedAtMs,_that.terminalAtMs,_that.cancellationRequested,_that.controls,_that.boundedTerminalFailure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( JobRunId jobRunId,  String operationType,  JobLifecycleState lifecycleState,  String? phase,  int? completedUnits,  int? totalUnits,  String? statusKey,  int createdAtMs,  int? queuedAtMs,  int? startedAtMs,  int? terminalAtMs,  bool cancellationRequested,  JobControlAvailability controls,  BoundedTerminalFailure? boundedTerminalFailure)  $default,) {final _that = this;
switch (_that) {
case _JobRunProjection():
return $default(_that.jobRunId,_that.operationType,_that.lifecycleState,_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey,_that.createdAtMs,_that.queuedAtMs,_that.startedAtMs,_that.terminalAtMs,_that.cancellationRequested,_that.controls,_that.boundedTerminalFailure);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( JobRunId jobRunId,  String operationType,  JobLifecycleState lifecycleState,  String? phase,  int? completedUnits,  int? totalUnits,  String? statusKey,  int createdAtMs,  int? queuedAtMs,  int? startedAtMs,  int? terminalAtMs,  bool cancellationRequested,  JobControlAvailability controls,  BoundedTerminalFailure? boundedTerminalFailure)?  $default,) {final _that = this;
switch (_that) {
case _JobRunProjection() when $default != null:
return $default(_that.jobRunId,_that.operationType,_that.lifecycleState,_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey,_that.createdAtMs,_that.queuedAtMs,_that.startedAtMs,_that.terminalAtMs,_that.cancellationRequested,_that.controls,_that.boundedTerminalFailure);case _:
  return null;

}
}

}

/// @nodoc


class _JobRunProjection implements JobRunProjection {
  const _JobRunProjection({required this.jobRunId, required this.operationType, required this.lifecycleState, this.phase, this.completedUnits, this.totalUnits, this.statusKey, required this.createdAtMs, this.queuedAtMs, this.startedAtMs, this.terminalAtMs, required this.cancellationRequested, required this.controls, this.boundedTerminalFailure});


@override final  JobRunId jobRunId;
@override final  String operationType;
@override final  JobLifecycleState lifecycleState;
@override final  String? phase;
@override final  int? completedUnits;
@override final  int? totalUnits;
@override final  String? statusKey;
@override final  int createdAtMs;
@override final  int? queuedAtMs;
@override final  int? startedAtMs;
@override final  int? terminalAtMs;
@override final  bool cancellationRequested;
@override final  JobControlAvailability controls;
@override final  BoundedTerminalFailure? boundedTerminalFailure;

/// Create a copy of JobRunProjection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JobRunProjectionCopyWith<_JobRunProjection> get copyWith => __$JobRunProjectionCopyWithImpl<_JobRunProjection>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _JobRunProjection&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId)&&(identical(other.operationType, operationType) || other.operationType == operationType)&&(identical(other.lifecycleState, lifecycleState) || other.lifecycleState == lifecycleState)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.completedUnits, completedUnits) || other.completedUnits == completedUnits)&&(identical(other.totalUnits, totalUnits) || other.totalUnits == totalUnits)&&(identical(other.statusKey, statusKey) || other.statusKey == statusKey)&&(identical(other.createdAtMs, createdAtMs) || other.createdAtMs == createdAtMs)&&(identical(other.queuedAtMs, queuedAtMs) || other.queuedAtMs == queuedAtMs)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs)&&(identical(other.terminalAtMs, terminalAtMs) || other.terminalAtMs == terminalAtMs)&&(identical(other.cancellationRequested, cancellationRequested) || other.cancellationRequested == cancellationRequested)&&(identical(other.controls, controls) || other.controls == controls)&&(identical(other.boundedTerminalFailure, boundedTerminalFailure) || other.boundedTerminalFailure == boundedTerminalFailure));
}


@override
int get hashCode => Object.hash(runtimeType,jobRunId,operationType,lifecycleState,phase,completedUnits,totalUnits,statusKey,createdAtMs,queuedAtMs,startedAtMs,terminalAtMs,cancellationRequested,controls,boundedTerminalFailure);

@override
String toString() {
  return 'JobRunProjection(jobRunId: $jobRunId, operationType: $operationType, lifecycleState: $lifecycleState, phase: $phase, completedUnits: $completedUnits, totalUnits: $totalUnits, statusKey: $statusKey, createdAtMs: $createdAtMs, queuedAtMs: $queuedAtMs, startedAtMs: $startedAtMs, terminalAtMs: $terminalAtMs, cancellationRequested: $cancellationRequested, controls: $controls, boundedTerminalFailure: $boundedTerminalFailure)';
}


}

/// @nodoc
abstract mixin class _$JobRunProjectionCopyWith<$Res> implements $JobRunProjectionCopyWith<$Res> {
  factory _$JobRunProjectionCopyWith(_JobRunProjection value, $Res Function(_JobRunProjection) _then) = __$JobRunProjectionCopyWithImpl;
@override @useResult
$Res call({
 JobRunId jobRunId, String operationType, JobLifecycleState lifecycleState, String? phase, int? completedUnits, int? totalUnits, String? statusKey, int createdAtMs, int? queuedAtMs, int? startedAtMs, int? terminalAtMs, bool cancellationRequested, JobControlAvailability controls, BoundedTerminalFailure? boundedTerminalFailure
});


@override $JobControlAvailabilityCopyWith<$Res> get controls;@override $BoundedTerminalFailureCopyWith<$Res>? get boundedTerminalFailure;

}
/// @nodoc
class __$JobRunProjectionCopyWithImpl<$Res>
    implements _$JobRunProjectionCopyWith<$Res> {
  __$JobRunProjectionCopyWithImpl(this._self, this._then);

  final _JobRunProjection _self;
  final $Res Function(_JobRunProjection) _then;

/// Create a copy of JobRunProjection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? jobRunId = null,Object? operationType = null,Object? lifecycleState = null,Object? phase = freezed,Object? completedUnits = freezed,Object? totalUnits = freezed,Object? statusKey = freezed,Object? createdAtMs = null,Object? queuedAtMs = freezed,Object? startedAtMs = freezed,Object? terminalAtMs = freezed,Object? cancellationRequested = null,Object? controls = null,Object? boundedTerminalFailure = freezed,}) {
  return _then(_JobRunProjection(
jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,operationType: null == operationType ? _self.operationType : operationType // ignore: cast_nullable_to_non_nullable
as String,lifecycleState: null == lifecycleState ? _self.lifecycleState : lifecycleState // ignore: cast_nullable_to_non_nullable
as JobLifecycleState,phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String?,completedUnits: freezed == completedUnits ? _self.completedUnits : completedUnits // ignore: cast_nullable_to_non_nullable
as int?,totalUnits: freezed == totalUnits ? _self.totalUnits : totalUnits // ignore: cast_nullable_to_non_nullable
as int?,statusKey: freezed == statusKey ? _self.statusKey : statusKey // ignore: cast_nullable_to_non_nullable
as String?,createdAtMs: null == createdAtMs ? _self.createdAtMs : createdAtMs // ignore: cast_nullable_to_non_nullable
as int,queuedAtMs: freezed == queuedAtMs ? _self.queuedAtMs : queuedAtMs // ignore: cast_nullable_to_non_nullable
as int?,startedAtMs: freezed == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as int?,terminalAtMs: freezed == terminalAtMs ? _self.terminalAtMs : terminalAtMs // ignore: cast_nullable_to_non_nullable
as int?,cancellationRequested: null == cancellationRequested ? _self.cancellationRequested : cancellationRequested // ignore: cast_nullable_to_non_nullable
as bool,controls: null == controls ? _self.controls : controls // ignore: cast_nullable_to_non_nullable
as JobControlAvailability,boundedTerminalFailure: freezed == boundedTerminalFailure ? _self.boundedTerminalFailure : boundedTerminalFailure // ignore: cast_nullable_to_non_nullable
as BoundedTerminalFailure?,
  ));
}

/// Create a copy of JobRunProjection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JobControlAvailabilityCopyWith<$Res> get controls {

  return $JobControlAvailabilityCopyWith<$Res>(_self.controls, (value) {
    return _then(_self.copyWith(controls: value));
  });
}/// Create a copy of JobRunProjection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BoundedTerminalFailureCopyWith<$Res>? get boundedTerminalFailure {
    if (_self.boundedTerminalFailure == null) {
    return null;
  }

  return $BoundedTerminalFailureCopyWith<$Res>(_self.boundedTerminalFailure!, (value) {
    return _then(_self.copyWith(boundedTerminalFailure: value));
  });
}
}

/// @nodoc
mixin _$ScanRunSummary {

 ScanRunId get scanRunId; JobRunId get jobRunId; LibraryRootId get libraryRootId; String get displayName; String get safeLocationDisplay; JobScanStatus get status; int get startedAtMs; int? get completedAtMs;
/// Create a copy of ScanRunSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanRunSummaryCopyWith<ScanRunSummary> get copyWith => _$ScanRunSummaryCopyWithImpl<ScanRunSummary>(this as ScanRunSummary, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanRunSummary&&(identical(other.scanRunId, scanRunId) || other.scanRunId == scanRunId)&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId)&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.safeLocationDisplay, safeLocationDisplay) || other.safeLocationDisplay == safeLocationDisplay)&&(identical(other.status, status) || other.status == status)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs)&&(identical(other.completedAtMs, completedAtMs) || other.completedAtMs == completedAtMs));
}


@override
int get hashCode => Object.hash(runtimeType,scanRunId,jobRunId,libraryRootId,displayName,safeLocationDisplay,status,startedAtMs,completedAtMs);

@override
String toString() {
  return 'ScanRunSummary(scanRunId: $scanRunId, jobRunId: $jobRunId, libraryRootId: $libraryRootId, displayName: $displayName, safeLocationDisplay: $safeLocationDisplay, status: $status, startedAtMs: $startedAtMs, completedAtMs: $completedAtMs)';
}


}

/// @nodoc
abstract mixin class $ScanRunSummaryCopyWith<$Res>  {
  factory $ScanRunSummaryCopyWith(ScanRunSummary value, $Res Function(ScanRunSummary) _then) = _$ScanRunSummaryCopyWithImpl;
@useResult
$Res call({
 ScanRunId scanRunId, JobRunId jobRunId, LibraryRootId libraryRootId, String displayName, String safeLocationDisplay, JobScanStatus status, int startedAtMs, int? completedAtMs
});




}
/// @nodoc
class _$ScanRunSummaryCopyWithImpl<$Res>
    implements $ScanRunSummaryCopyWith<$Res> {
  _$ScanRunSummaryCopyWithImpl(this._self, this._then);

  final ScanRunSummary _self;
  final $Res Function(ScanRunSummary) _then;

/// Create a copy of ScanRunSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scanRunId = null,Object? jobRunId = null,Object? libraryRootId = null,Object? displayName = null,Object? safeLocationDisplay = null,Object? status = null,Object? startedAtMs = null,Object? completedAtMs = freezed,}) {
  return _then(_self.copyWith(
scanRunId: null == scanRunId ? _self.scanRunId : scanRunId // ignore: cast_nullable_to_non_nullable
as ScanRunId,jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,safeLocationDisplay: null == safeLocationDisplay ? _self.safeLocationDisplay : safeLocationDisplay // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as JobScanStatus,startedAtMs: null == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as int,completedAtMs: freezed == completedAtMs ? _self.completedAtMs : completedAtMs // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ScanRunSummary].
extension ScanRunSummaryPatterns on ScanRunSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ScanRunSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ScanRunSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ScanRunSummary value)  $default,){
final _that = this;
switch (_that) {
case _ScanRunSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ScanRunSummary value)?  $default,){
final _that = this;
switch (_that) {
case _ScanRunSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ScanRunId scanRunId,  JobRunId jobRunId,  LibraryRootId libraryRootId,  String displayName,  String safeLocationDisplay,  JobScanStatus status,  int startedAtMs,  int? completedAtMs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ScanRunSummary() when $default != null:
return $default(_that.scanRunId,_that.jobRunId,_that.libraryRootId,_that.displayName,_that.safeLocationDisplay,_that.status,_that.startedAtMs,_that.completedAtMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ScanRunId scanRunId,  JobRunId jobRunId,  LibraryRootId libraryRootId,  String displayName,  String safeLocationDisplay,  JobScanStatus status,  int startedAtMs,  int? completedAtMs)  $default,) {final _that = this;
switch (_that) {
case _ScanRunSummary():
return $default(_that.scanRunId,_that.jobRunId,_that.libraryRootId,_that.displayName,_that.safeLocationDisplay,_that.status,_that.startedAtMs,_that.completedAtMs);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ScanRunId scanRunId,  JobRunId jobRunId,  LibraryRootId libraryRootId,  String displayName,  String safeLocationDisplay,  JobScanStatus status,  int startedAtMs,  int? completedAtMs)?  $default,) {final _that = this;
switch (_that) {
case _ScanRunSummary() when $default != null:
return $default(_that.scanRunId,_that.jobRunId,_that.libraryRootId,_that.displayName,_that.safeLocationDisplay,_that.status,_that.startedAtMs,_that.completedAtMs);case _:
  return null;

}
}

}

/// @nodoc


class _ScanRunSummary implements ScanRunSummary {
  const _ScanRunSummary({required this.scanRunId, required this.jobRunId, required this.libraryRootId, required this.displayName, required this.safeLocationDisplay, required this.status, required this.startedAtMs, this.completedAtMs});


@override final  ScanRunId scanRunId;
@override final  JobRunId jobRunId;
@override final  LibraryRootId libraryRootId;
@override final  String displayName;
@override final  String safeLocationDisplay;
@override final  JobScanStatus status;
@override final  int startedAtMs;
@override final  int? completedAtMs;

/// Create a copy of ScanRunSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ScanRunSummaryCopyWith<_ScanRunSummary> get copyWith => __$ScanRunSummaryCopyWithImpl<_ScanRunSummary>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ScanRunSummary&&(identical(other.scanRunId, scanRunId) || other.scanRunId == scanRunId)&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId)&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.safeLocationDisplay, safeLocationDisplay) || other.safeLocationDisplay == safeLocationDisplay)&&(identical(other.status, status) || other.status == status)&&(identical(other.startedAtMs, startedAtMs) || other.startedAtMs == startedAtMs)&&(identical(other.completedAtMs, completedAtMs) || other.completedAtMs == completedAtMs));
}


@override
int get hashCode => Object.hash(runtimeType,scanRunId,jobRunId,libraryRootId,displayName,safeLocationDisplay,status,startedAtMs,completedAtMs);

@override
String toString() {
  return 'ScanRunSummary(scanRunId: $scanRunId, jobRunId: $jobRunId, libraryRootId: $libraryRootId, displayName: $displayName, safeLocationDisplay: $safeLocationDisplay, status: $status, startedAtMs: $startedAtMs, completedAtMs: $completedAtMs)';
}


}

/// @nodoc
abstract mixin class _$ScanRunSummaryCopyWith<$Res> implements $ScanRunSummaryCopyWith<$Res> {
  factory _$ScanRunSummaryCopyWith(_ScanRunSummary value, $Res Function(_ScanRunSummary) _then) = __$ScanRunSummaryCopyWithImpl;
@override @useResult
$Res call({
 ScanRunId scanRunId, JobRunId jobRunId, LibraryRootId libraryRootId, String displayName, String safeLocationDisplay, JobScanStatus status, int startedAtMs, int? completedAtMs
});




}
/// @nodoc
class __$ScanRunSummaryCopyWithImpl<$Res>
    implements _$ScanRunSummaryCopyWith<$Res> {
  __$ScanRunSummaryCopyWithImpl(this._self, this._then);

  final _ScanRunSummary _self;
  final $Res Function(_ScanRunSummary) _then;

/// Create a copy of ScanRunSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scanRunId = null,Object? jobRunId = null,Object? libraryRootId = null,Object? displayName = null,Object? safeLocationDisplay = null,Object? status = null,Object? startedAtMs = null,Object? completedAtMs = freezed,}) {
  return _then(_ScanRunSummary(
scanRunId: null == scanRunId ? _self.scanRunId : scanRunId // ignore: cast_nullable_to_non_nullable
as ScanRunId,jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,safeLocationDisplay: null == safeLocationDisplay ? _self.safeLocationDisplay : safeLocationDisplay // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as JobScanStatus,startedAtMs: null == startedAtMs ? _self.startedAtMs : startedAtMs // ignore: cast_nullable_to_non_nullable
as int,completedAtMs: freezed == completedAtMs ? _self.completedAtMs : completedAtMs // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$LibraryScanRootSummary {

 LibraryRootId get libraryRootId; String get displayName; String get safeLocationDisplay;
/// Create a copy of LibraryScanRootSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryScanRootSummaryCopyWith<LibraryScanRootSummary> get copyWith => _$LibraryScanRootSummaryCopyWithImpl<LibraryScanRootSummary>(this as LibraryScanRootSummary, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanRootSummary&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.safeLocationDisplay, safeLocationDisplay) || other.safeLocationDisplay == safeLocationDisplay));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId,displayName,safeLocationDisplay);

@override
String toString() {
  return 'LibraryScanRootSummary(libraryRootId: $libraryRootId, displayName: $displayName, safeLocationDisplay: $safeLocationDisplay)';
}


}

/// @nodoc
abstract mixin class $LibraryScanRootSummaryCopyWith<$Res>  {
  factory $LibraryScanRootSummaryCopyWith(LibraryScanRootSummary value, $Res Function(LibraryScanRootSummary) _then) = _$LibraryScanRootSummaryCopyWithImpl;
@useResult
$Res call({
 LibraryRootId libraryRootId, String displayName, String safeLocationDisplay
});




}
/// @nodoc
class _$LibraryScanRootSummaryCopyWithImpl<$Res>
    implements $LibraryScanRootSummaryCopyWith<$Res> {
  _$LibraryScanRootSummaryCopyWithImpl(this._self, this._then);

  final LibraryScanRootSummary _self;
  final $Res Function(LibraryScanRootSummary) _then;

/// Create a copy of LibraryScanRootSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? libraryRootId = null,Object? displayName = null,Object? safeLocationDisplay = null,}) {
  return _then(_self.copyWith(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,safeLocationDisplay: null == safeLocationDisplay ? _self.safeLocationDisplay : safeLocationDisplay // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [LibraryScanRootSummary].
extension LibraryScanRootSummaryPatterns on LibraryScanRootSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LibraryScanRootSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LibraryScanRootSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LibraryScanRootSummary value)  $default,){
final _that = this;
switch (_that) {
case _LibraryScanRootSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LibraryScanRootSummary value)?  $default,){
final _that = this;
switch (_that) {
case _LibraryScanRootSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( LibraryRootId libraryRootId,  String displayName,  String safeLocationDisplay)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LibraryScanRootSummary() when $default != null:
return $default(_that.libraryRootId,_that.displayName,_that.safeLocationDisplay);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( LibraryRootId libraryRootId,  String displayName,  String safeLocationDisplay)  $default,) {final _that = this;
switch (_that) {
case _LibraryScanRootSummary():
return $default(_that.libraryRootId,_that.displayName,_that.safeLocationDisplay);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( LibraryRootId libraryRootId,  String displayName,  String safeLocationDisplay)?  $default,) {final _that = this;
switch (_that) {
case _LibraryScanRootSummary() when $default != null:
return $default(_that.libraryRootId,_that.displayName,_that.safeLocationDisplay);case _:
  return null;

}
}

}

/// @nodoc


class _LibraryScanRootSummary implements LibraryScanRootSummary {
  const _LibraryScanRootSummary({required this.libraryRootId, required this.displayName, required this.safeLocationDisplay});


@override final  LibraryRootId libraryRootId;
@override final  String displayName;
@override final  String safeLocationDisplay;

/// Create a copy of LibraryScanRootSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LibraryScanRootSummaryCopyWith<_LibraryScanRootSummary> get copyWith => __$LibraryScanRootSummaryCopyWithImpl<_LibraryScanRootSummary>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LibraryScanRootSummary&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.safeLocationDisplay, safeLocationDisplay) || other.safeLocationDisplay == safeLocationDisplay));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId,displayName,safeLocationDisplay);

@override
String toString() {
  return 'LibraryScanRootSummary(libraryRootId: $libraryRootId, displayName: $displayName, safeLocationDisplay: $safeLocationDisplay)';
}


}

/// @nodoc
abstract mixin class _$LibraryScanRootSummaryCopyWith<$Res> implements $LibraryScanRootSummaryCopyWith<$Res> {
  factory _$LibraryScanRootSummaryCopyWith(_LibraryScanRootSummary value, $Res Function(_LibraryScanRootSummary) _then) = __$LibraryScanRootSummaryCopyWithImpl;
@override @useResult
$Res call({
 LibraryRootId libraryRootId, String displayName, String safeLocationDisplay
});




}
/// @nodoc
class __$LibraryScanRootSummaryCopyWithImpl<$Res>
    implements _$LibraryScanRootSummaryCopyWith<$Res> {
  __$LibraryScanRootSummaryCopyWithImpl(this._self, this._then);

  final _LibraryScanRootSummary _self;
  final $Res Function(_LibraryScanRootSummary) _then;

/// Create a copy of LibraryScanRootSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? libraryRootId = null,Object? displayName = null,Object? safeLocationDisplay = null,}) {
  return _then(_LibraryScanRootSummary(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,safeLocationDisplay: null == safeLocationDisplay ? _self.safeLocationDisplay : safeLocationDisplay // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$LibraryScanAdmissionExclusion {

 LibraryRootId get libraryRootId; String get reason; JobRunId? get activeJobRunId; ScanRunId? get activeScanRunId; ClientApplicationError? get applicationError;
/// Create a copy of LibraryScanAdmissionExclusion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryScanAdmissionExclusionCopyWith<LibraryScanAdmissionExclusion> get copyWith => _$LibraryScanAdmissionExclusionCopyWithImpl<LibraryScanAdmissionExclusion>(this as LibraryScanAdmissionExclusion, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanAdmissionExclusion&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.activeJobRunId, activeJobRunId) || other.activeJobRunId == activeJobRunId)&&(identical(other.activeScanRunId, activeScanRunId) || other.activeScanRunId == activeScanRunId)&&(identical(other.applicationError, applicationError) || other.applicationError == applicationError));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId,reason,activeJobRunId,activeScanRunId,applicationError);

@override
String toString() {
  return 'LibraryScanAdmissionExclusion(libraryRootId: $libraryRootId, reason: $reason, activeJobRunId: $activeJobRunId, activeScanRunId: $activeScanRunId, applicationError: $applicationError)';
}


}

/// @nodoc
abstract mixin class $LibraryScanAdmissionExclusionCopyWith<$Res>  {
  factory $LibraryScanAdmissionExclusionCopyWith(LibraryScanAdmissionExclusion value, $Res Function(LibraryScanAdmissionExclusion) _then) = _$LibraryScanAdmissionExclusionCopyWithImpl;
@useResult
$Res call({
 LibraryRootId libraryRootId, String reason, JobRunId? activeJobRunId, ScanRunId? activeScanRunId, ClientApplicationError? applicationError
});


$ClientApplicationErrorCopyWith<$Res>? get applicationError;

}
/// @nodoc
class _$LibraryScanAdmissionExclusionCopyWithImpl<$Res>
    implements $LibraryScanAdmissionExclusionCopyWith<$Res> {
  _$LibraryScanAdmissionExclusionCopyWithImpl(this._self, this._then);

  final LibraryScanAdmissionExclusion _self;
  final $Res Function(LibraryScanAdmissionExclusion) _then;

/// Create a copy of LibraryScanAdmissionExclusion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? libraryRootId = null,Object? reason = null,Object? activeJobRunId = freezed,Object? activeScanRunId = freezed,Object? applicationError = freezed,}) {
  return _then(_self.copyWith(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,activeJobRunId: freezed == activeJobRunId ? _self.activeJobRunId : activeJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,activeScanRunId: freezed == activeScanRunId ? _self.activeScanRunId : activeScanRunId // ignore: cast_nullable_to_non_nullable
as ScanRunId?,applicationError: freezed == applicationError ? _self.applicationError : applicationError // ignore: cast_nullable_to_non_nullable
as ClientApplicationError?,
  ));
}
/// Create a copy of LibraryScanAdmissionExclusion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientApplicationErrorCopyWith<$Res>? get applicationError {
    if (_self.applicationError == null) {
    return null;
  }

  return $ClientApplicationErrorCopyWith<$Res>(_self.applicationError!, (value) {
    return _then(_self.copyWith(applicationError: value));
  });
}
}


/// Adds pattern-matching-related methods to [LibraryScanAdmissionExclusion].
extension LibraryScanAdmissionExclusionPatterns on LibraryScanAdmissionExclusion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LibraryScanAdmissionExclusion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LibraryScanAdmissionExclusion() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LibraryScanAdmissionExclusion value)  $default,){
final _that = this;
switch (_that) {
case _LibraryScanAdmissionExclusion():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LibraryScanAdmissionExclusion value)?  $default,){
final _that = this;
switch (_that) {
case _LibraryScanAdmissionExclusion() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( LibraryRootId libraryRootId,  String reason,  JobRunId? activeJobRunId,  ScanRunId? activeScanRunId,  ClientApplicationError? applicationError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LibraryScanAdmissionExclusion() when $default != null:
return $default(_that.libraryRootId,_that.reason,_that.activeJobRunId,_that.activeScanRunId,_that.applicationError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( LibraryRootId libraryRootId,  String reason,  JobRunId? activeJobRunId,  ScanRunId? activeScanRunId,  ClientApplicationError? applicationError)  $default,) {final _that = this;
switch (_that) {
case _LibraryScanAdmissionExclusion():
return $default(_that.libraryRootId,_that.reason,_that.activeJobRunId,_that.activeScanRunId,_that.applicationError);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( LibraryRootId libraryRootId,  String reason,  JobRunId? activeJobRunId,  ScanRunId? activeScanRunId,  ClientApplicationError? applicationError)?  $default,) {final _that = this;
switch (_that) {
case _LibraryScanAdmissionExclusion() when $default != null:
return $default(_that.libraryRootId,_that.reason,_that.activeJobRunId,_that.activeScanRunId,_that.applicationError);case _:
  return null;

}
}

}

/// @nodoc


class _LibraryScanAdmissionExclusion implements LibraryScanAdmissionExclusion {
  const _LibraryScanAdmissionExclusion({required this.libraryRootId, required this.reason, this.activeJobRunId, this.activeScanRunId, this.applicationError});


@override final  LibraryRootId libraryRootId;
@override final  String reason;
@override final  JobRunId? activeJobRunId;
@override final  ScanRunId? activeScanRunId;
@override final  ClientApplicationError? applicationError;

/// Create a copy of LibraryScanAdmissionExclusion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LibraryScanAdmissionExclusionCopyWith<_LibraryScanAdmissionExclusion> get copyWith => __$LibraryScanAdmissionExclusionCopyWithImpl<_LibraryScanAdmissionExclusion>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LibraryScanAdmissionExclusion&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.activeJobRunId, activeJobRunId) || other.activeJobRunId == activeJobRunId)&&(identical(other.activeScanRunId, activeScanRunId) || other.activeScanRunId == activeScanRunId)&&(identical(other.applicationError, applicationError) || other.applicationError == applicationError));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId,reason,activeJobRunId,activeScanRunId,applicationError);

@override
String toString() {
  return 'LibraryScanAdmissionExclusion(libraryRootId: $libraryRootId, reason: $reason, activeJobRunId: $activeJobRunId, activeScanRunId: $activeScanRunId, applicationError: $applicationError)';
}


}

/// @nodoc
abstract mixin class _$LibraryScanAdmissionExclusionCopyWith<$Res> implements $LibraryScanAdmissionExclusionCopyWith<$Res> {
  factory _$LibraryScanAdmissionExclusionCopyWith(_LibraryScanAdmissionExclusion value, $Res Function(_LibraryScanAdmissionExclusion) _then) = __$LibraryScanAdmissionExclusionCopyWithImpl;
@override @useResult
$Res call({
 LibraryRootId libraryRootId, String reason, JobRunId? activeJobRunId, ScanRunId? activeScanRunId, ClientApplicationError? applicationError
});


@override $ClientApplicationErrorCopyWith<$Res>? get applicationError;

}
/// @nodoc
class __$LibraryScanAdmissionExclusionCopyWithImpl<$Res>
    implements _$LibraryScanAdmissionExclusionCopyWith<$Res> {
  __$LibraryScanAdmissionExclusionCopyWithImpl(this._self, this._then);

  final _LibraryScanAdmissionExclusion _self;
  final $Res Function(_LibraryScanAdmissionExclusion) _then;

/// Create a copy of LibraryScanAdmissionExclusion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? libraryRootId = null,Object? reason = null,Object? activeJobRunId = freezed,Object? activeScanRunId = freezed,Object? applicationError = freezed,}) {
  return _then(_LibraryScanAdmissionExclusion(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,activeJobRunId: freezed == activeJobRunId ? _self.activeJobRunId : activeJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,activeScanRunId: freezed == activeScanRunId ? _self.activeScanRunId : activeScanRunId // ignore: cast_nullable_to_non_nullable
as ScanRunId?,applicationError: freezed == applicationError ? _self.applicationError : applicationError // ignore: cast_nullable_to_non_nullable
as ClientApplicationError?,
  ));
}

/// Create a copy of LibraryScanAdmissionExclusion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientApplicationErrorCopyWith<$Res>? get applicationError {
    if (_self.applicationError == null) {
    return null;
  }

  return $ClientApplicationErrorCopyWith<$Res>(_self.applicationError!, (value) {
    return _then(_self.copyWith(applicationError: value));
  });
}
}

/// @nodoc
mixin _$ScanProgressFacts {

 String? get phase; int? get completedUnits; int? get totalUnits; String? get statusKey; int get rootsRequested; int get rootsAdmitted; int get rootsTerminal; int? get entriesObserved; int? get entriesCommitted; int? get issueCount;
/// Create a copy of ScanProgressFacts
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanProgressFactsCopyWith<ScanProgressFacts> get copyWith => _$ScanProgressFactsCopyWithImpl<ScanProgressFacts>(this as ScanProgressFacts, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanProgressFacts&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.completedUnits, completedUnits) || other.completedUnits == completedUnits)&&(identical(other.totalUnits, totalUnits) || other.totalUnits == totalUnits)&&(identical(other.statusKey, statusKey) || other.statusKey == statusKey)&&(identical(other.rootsRequested, rootsRequested) || other.rootsRequested == rootsRequested)&&(identical(other.rootsAdmitted, rootsAdmitted) || other.rootsAdmitted == rootsAdmitted)&&(identical(other.rootsTerminal, rootsTerminal) || other.rootsTerminal == rootsTerminal)&&(identical(other.entriesObserved, entriesObserved) || other.entriesObserved == entriesObserved)&&(identical(other.entriesCommitted, entriesCommitted) || other.entriesCommitted == entriesCommitted)&&(identical(other.issueCount, issueCount) || other.issueCount == issueCount));
}


@override
int get hashCode => Object.hash(runtimeType,phase,completedUnits,totalUnits,statusKey,rootsRequested,rootsAdmitted,rootsTerminal,entriesObserved,entriesCommitted,issueCount);

@override
String toString() {
  return 'ScanProgressFacts(phase: $phase, completedUnits: $completedUnits, totalUnits: $totalUnits, statusKey: $statusKey, rootsRequested: $rootsRequested, rootsAdmitted: $rootsAdmitted, rootsTerminal: $rootsTerminal, entriesObserved: $entriesObserved, entriesCommitted: $entriesCommitted, issueCount: $issueCount)';
}


}

/// @nodoc
abstract mixin class $ScanProgressFactsCopyWith<$Res>  {
  factory $ScanProgressFactsCopyWith(ScanProgressFacts value, $Res Function(ScanProgressFacts) _then) = _$ScanProgressFactsCopyWithImpl;
@useResult
$Res call({
 String? phase, int? completedUnits, int? totalUnits, String? statusKey, int rootsRequested, int rootsAdmitted, int rootsTerminal, int? entriesObserved, int? entriesCommitted, int? issueCount
});




}
/// @nodoc
class _$ScanProgressFactsCopyWithImpl<$Res>
    implements $ScanProgressFactsCopyWith<$Res> {
  _$ScanProgressFactsCopyWithImpl(this._self, this._then);

  final ScanProgressFacts _self;
  final $Res Function(ScanProgressFacts) _then;

/// Create a copy of ScanProgressFacts
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = freezed,Object? completedUnits = freezed,Object? totalUnits = freezed,Object? statusKey = freezed,Object? rootsRequested = null,Object? rootsAdmitted = null,Object? rootsTerminal = null,Object? entriesObserved = freezed,Object? entriesCommitted = freezed,Object? issueCount = freezed,}) {
  return _then(_self.copyWith(
phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String?,completedUnits: freezed == completedUnits ? _self.completedUnits : completedUnits // ignore: cast_nullable_to_non_nullable
as int?,totalUnits: freezed == totalUnits ? _self.totalUnits : totalUnits // ignore: cast_nullable_to_non_nullable
as int?,statusKey: freezed == statusKey ? _self.statusKey : statusKey // ignore: cast_nullable_to_non_nullable
as String?,rootsRequested: null == rootsRequested ? _self.rootsRequested : rootsRequested // ignore: cast_nullable_to_non_nullable
as int,rootsAdmitted: null == rootsAdmitted ? _self.rootsAdmitted : rootsAdmitted // ignore: cast_nullable_to_non_nullable
as int,rootsTerminal: null == rootsTerminal ? _self.rootsTerminal : rootsTerminal // ignore: cast_nullable_to_non_nullable
as int,entriesObserved: freezed == entriesObserved ? _self.entriesObserved : entriesObserved // ignore: cast_nullable_to_non_nullable
as int?,entriesCommitted: freezed == entriesCommitted ? _self.entriesCommitted : entriesCommitted // ignore: cast_nullable_to_non_nullable
as int?,issueCount: freezed == issueCount ? _self.issueCount : issueCount // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ScanProgressFacts].
extension ScanProgressFactsPatterns on ScanProgressFacts {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ScanProgressFacts value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ScanProgressFacts() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ScanProgressFacts value)  $default,){
final _that = this;
switch (_that) {
case _ScanProgressFacts():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ScanProgressFacts value)?  $default,){
final _that = this;
switch (_that) {
case _ScanProgressFacts() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? phase,  int? completedUnits,  int? totalUnits,  String? statusKey,  int rootsRequested,  int rootsAdmitted,  int rootsTerminal,  int? entriesObserved,  int? entriesCommitted,  int? issueCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ScanProgressFacts() when $default != null:
return $default(_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey,_that.rootsRequested,_that.rootsAdmitted,_that.rootsTerminal,_that.entriesObserved,_that.entriesCommitted,_that.issueCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? phase,  int? completedUnits,  int? totalUnits,  String? statusKey,  int rootsRequested,  int rootsAdmitted,  int rootsTerminal,  int? entriesObserved,  int? entriesCommitted,  int? issueCount)  $default,) {final _that = this;
switch (_that) {
case _ScanProgressFacts():
return $default(_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey,_that.rootsRequested,_that.rootsAdmitted,_that.rootsTerminal,_that.entriesObserved,_that.entriesCommitted,_that.issueCount);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? phase,  int? completedUnits,  int? totalUnits,  String? statusKey,  int rootsRequested,  int rootsAdmitted,  int rootsTerminal,  int? entriesObserved,  int? entriesCommitted,  int? issueCount)?  $default,) {final _that = this;
switch (_that) {
case _ScanProgressFacts() when $default != null:
return $default(_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey,_that.rootsRequested,_that.rootsAdmitted,_that.rootsTerminal,_that.entriesObserved,_that.entriesCommitted,_that.issueCount);case _:
  return null;

}
}

}

/// @nodoc


class _ScanProgressFacts implements ScanProgressFacts {
  const _ScanProgressFacts({this.phase, this.completedUnits, this.totalUnits, this.statusKey, required this.rootsRequested, required this.rootsAdmitted, required this.rootsTerminal, this.entriesObserved, this.entriesCommitted, this.issueCount});


@override final  String? phase;
@override final  int? completedUnits;
@override final  int? totalUnits;
@override final  String? statusKey;
@override final  int rootsRequested;
@override final  int rootsAdmitted;
@override final  int rootsTerminal;
@override final  int? entriesObserved;
@override final  int? entriesCommitted;
@override final  int? issueCount;

/// Create a copy of ScanProgressFacts
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ScanProgressFactsCopyWith<_ScanProgressFacts> get copyWith => __$ScanProgressFactsCopyWithImpl<_ScanProgressFacts>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ScanProgressFacts&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.completedUnits, completedUnits) || other.completedUnits == completedUnits)&&(identical(other.totalUnits, totalUnits) || other.totalUnits == totalUnits)&&(identical(other.statusKey, statusKey) || other.statusKey == statusKey)&&(identical(other.rootsRequested, rootsRequested) || other.rootsRequested == rootsRequested)&&(identical(other.rootsAdmitted, rootsAdmitted) || other.rootsAdmitted == rootsAdmitted)&&(identical(other.rootsTerminal, rootsTerminal) || other.rootsTerminal == rootsTerminal)&&(identical(other.entriesObserved, entriesObserved) || other.entriesObserved == entriesObserved)&&(identical(other.entriesCommitted, entriesCommitted) || other.entriesCommitted == entriesCommitted)&&(identical(other.issueCount, issueCount) || other.issueCount == issueCount));
}


@override
int get hashCode => Object.hash(runtimeType,phase,completedUnits,totalUnits,statusKey,rootsRequested,rootsAdmitted,rootsTerminal,entriesObserved,entriesCommitted,issueCount);

@override
String toString() {
  return 'ScanProgressFacts(phase: $phase, completedUnits: $completedUnits, totalUnits: $totalUnits, statusKey: $statusKey, rootsRequested: $rootsRequested, rootsAdmitted: $rootsAdmitted, rootsTerminal: $rootsTerminal, entriesObserved: $entriesObserved, entriesCommitted: $entriesCommitted, issueCount: $issueCount)';
}


}

/// @nodoc
abstract mixin class _$ScanProgressFactsCopyWith<$Res> implements $ScanProgressFactsCopyWith<$Res> {
  factory _$ScanProgressFactsCopyWith(_ScanProgressFacts value, $Res Function(_ScanProgressFacts) _then) = __$ScanProgressFactsCopyWithImpl;
@override @useResult
$Res call({
 String? phase, int? completedUnits, int? totalUnits, String? statusKey, int rootsRequested, int rootsAdmitted, int rootsTerminal, int? entriesObserved, int? entriesCommitted, int? issueCount
});




}
/// @nodoc
class __$ScanProgressFactsCopyWithImpl<$Res>
    implements _$ScanProgressFactsCopyWith<$Res> {
  __$ScanProgressFactsCopyWithImpl(this._self, this._then);

  final _ScanProgressFacts _self;
  final $Res Function(_ScanProgressFacts) _then;

/// Create a copy of ScanProgressFacts
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = freezed,Object? completedUnits = freezed,Object? totalUnits = freezed,Object? statusKey = freezed,Object? rootsRequested = null,Object? rootsAdmitted = null,Object? rootsTerminal = null,Object? entriesObserved = freezed,Object? entriesCommitted = freezed,Object? issueCount = freezed,}) {
  return _then(_ScanProgressFacts(
phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String?,completedUnits: freezed == completedUnits ? _self.completedUnits : completedUnits // ignore: cast_nullable_to_non_nullable
as int?,totalUnits: freezed == totalUnits ? _self.totalUnits : totalUnits // ignore: cast_nullable_to_non_nullable
as int?,statusKey: freezed == statusKey ? _self.statusKey : statusKey // ignore: cast_nullable_to_non_nullable
as String?,rootsRequested: null == rootsRequested ? _self.rootsRequested : rootsRequested // ignore: cast_nullable_to_non_nullable
as int,rootsAdmitted: null == rootsAdmitted ? _self.rootsAdmitted : rootsAdmitted // ignore: cast_nullable_to_non_nullable
as int,rootsTerminal: null == rootsTerminal ? _self.rootsTerminal : rootsTerminal // ignore: cast_nullable_to_non_nullable
as int,entriesObserved: freezed == entriesObserved ? _self.entriesObserved : entriesObserved // ignore: cast_nullable_to_non_nullable
as int?,entriesCommitted: freezed == entriesCommitted ? _self.entriesCommitted : entriesCommitted // ignore: cast_nullable_to_non_nullable
as int?,issueCount: freezed == issueCount ? _self.issueCount : issueCount // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$RefreshProgressFacts {

 String? get phase; int? get completedUnits; int? get totalUnits; String? get statusKey; int? get issueCount;
/// Create a copy of RefreshProgressFacts
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RefreshProgressFactsCopyWith<RefreshProgressFacts> get copyWith => _$RefreshProgressFactsCopyWithImpl<RefreshProgressFacts>(this as RefreshProgressFacts, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RefreshProgressFacts&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.completedUnits, completedUnits) || other.completedUnits == completedUnits)&&(identical(other.totalUnits, totalUnits) || other.totalUnits == totalUnits)&&(identical(other.statusKey, statusKey) || other.statusKey == statusKey)&&(identical(other.issueCount, issueCount) || other.issueCount == issueCount));
}


@override
int get hashCode => Object.hash(runtimeType,phase,completedUnits,totalUnits,statusKey,issueCount);

@override
String toString() {
  return 'RefreshProgressFacts(phase: $phase, completedUnits: $completedUnits, totalUnits: $totalUnits, statusKey: $statusKey, issueCount: $issueCount)';
}


}

/// @nodoc
abstract mixin class $RefreshProgressFactsCopyWith<$Res>  {
  factory $RefreshProgressFactsCopyWith(RefreshProgressFacts value, $Res Function(RefreshProgressFacts) _then) = _$RefreshProgressFactsCopyWithImpl;
@useResult
$Res call({
 String? phase, int? completedUnits, int? totalUnits, String? statusKey, int? issueCount
});




}
/// @nodoc
class _$RefreshProgressFactsCopyWithImpl<$Res>
    implements $RefreshProgressFactsCopyWith<$Res> {
  _$RefreshProgressFactsCopyWithImpl(this._self, this._then);

  final RefreshProgressFacts _self;
  final $Res Function(RefreshProgressFacts) _then;

/// Create a copy of RefreshProgressFacts
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = freezed,Object? completedUnits = freezed,Object? totalUnits = freezed,Object? statusKey = freezed,Object? issueCount = freezed,}) {
  return _then(_self.copyWith(
phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String?,completedUnits: freezed == completedUnits ? _self.completedUnits : completedUnits // ignore: cast_nullable_to_non_nullable
as int?,totalUnits: freezed == totalUnits ? _self.totalUnits : totalUnits // ignore: cast_nullable_to_non_nullable
as int?,statusKey: freezed == statusKey ? _self.statusKey : statusKey // ignore: cast_nullable_to_non_nullable
as String?,issueCount: freezed == issueCount ? _self.issueCount : issueCount // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [RefreshProgressFacts].
extension RefreshProgressFactsPatterns on RefreshProgressFacts {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RefreshProgressFacts value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RefreshProgressFacts() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RefreshProgressFacts value)  $default,){
final _that = this;
switch (_that) {
case _RefreshProgressFacts():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RefreshProgressFacts value)?  $default,){
final _that = this;
switch (_that) {
case _RefreshProgressFacts() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? phase,  int? completedUnits,  int? totalUnits,  String? statusKey,  int? issueCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RefreshProgressFacts() when $default != null:
return $default(_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey,_that.issueCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? phase,  int? completedUnits,  int? totalUnits,  String? statusKey,  int? issueCount)  $default,) {final _that = this;
switch (_that) {
case _RefreshProgressFacts():
return $default(_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey,_that.issueCount);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? phase,  int? completedUnits,  int? totalUnits,  String? statusKey,  int? issueCount)?  $default,) {final _that = this;
switch (_that) {
case _RefreshProgressFacts() when $default != null:
return $default(_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey,_that.issueCount);case _:
  return null;

}
}

}

/// @nodoc


class _RefreshProgressFacts implements RefreshProgressFacts {
  const _RefreshProgressFacts({this.phase, this.completedUnits, this.totalUnits, this.statusKey, this.issueCount});


@override final  String? phase;
@override final  int? completedUnits;
@override final  int? totalUnits;
@override final  String? statusKey;
@override final  int? issueCount;

/// Create a copy of RefreshProgressFacts
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RefreshProgressFactsCopyWith<_RefreshProgressFacts> get copyWith => __$RefreshProgressFactsCopyWithImpl<_RefreshProgressFacts>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RefreshProgressFacts&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.completedUnits, completedUnits) || other.completedUnits == completedUnits)&&(identical(other.totalUnits, totalUnits) || other.totalUnits == totalUnits)&&(identical(other.statusKey, statusKey) || other.statusKey == statusKey)&&(identical(other.issueCount, issueCount) || other.issueCount == issueCount));
}


@override
int get hashCode => Object.hash(runtimeType,phase,completedUnits,totalUnits,statusKey,issueCount);

@override
String toString() {
  return 'RefreshProgressFacts(phase: $phase, completedUnits: $completedUnits, totalUnits: $totalUnits, statusKey: $statusKey, issueCount: $issueCount)';
}


}

/// @nodoc
abstract mixin class _$RefreshProgressFactsCopyWith<$Res> implements $RefreshProgressFactsCopyWith<$Res> {
  factory _$RefreshProgressFactsCopyWith(_RefreshProgressFacts value, $Res Function(_RefreshProgressFacts) _then) = __$RefreshProgressFactsCopyWithImpl;
@override @useResult
$Res call({
 String? phase, int? completedUnits, int? totalUnits, String? statusKey, int? issueCount
});




}
/// @nodoc
class __$RefreshProgressFactsCopyWithImpl<$Res>
    implements _$RefreshProgressFactsCopyWith<$Res> {
  __$RefreshProgressFactsCopyWithImpl(this._self, this._then);

  final _RefreshProgressFacts _self;
  final $Res Function(_RefreshProgressFacts) _then;

/// Create a copy of RefreshProgressFacts
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = freezed,Object? completedUnits = freezed,Object? totalUnits = freezed,Object? statusKey = freezed,Object? issueCount = freezed,}) {
  return _then(_RefreshProgressFacts(
phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String?,completedUnits: freezed == completedUnits ? _self.completedUnits : completedUnits // ignore: cast_nullable_to_non_nullable
as int?,totalUnits: freezed == totalUnits ? _self.totalUnits : totalUnits // ignore: cast_nullable_to_non_nullable
as int?,statusKey: freezed == statusKey ? _self.statusKey : statusKey // ignore: cast_nullable_to_non_nullable
as String?,issueCount: freezed == issueCount ? _self.issueCount : issueCount // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$LibraryScanJobDetail {

 List<LibraryScanRootSummary> get requestedRoots; List<LibraryScanRootSummary> get admittedRoots; List<LibraryScanAdmissionExclusion> get exclusions; List<ScanRunSummary> get scanRuns; ScanProgressFacts get progress; JobRunId? get retrySourceJobRunId; JobRunId? get retrySuccessorJobRunId;
/// Create a copy of LibraryScanJobDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryScanJobDetailCopyWith<LibraryScanJobDetail> get copyWith => _$LibraryScanJobDetailCopyWithImpl<LibraryScanJobDetail>(this as LibraryScanJobDetail, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanJobDetail&&const DeepCollectionEquality().equals(other.requestedRoots, requestedRoots)&&const DeepCollectionEquality().equals(other.admittedRoots, admittedRoots)&&const DeepCollectionEquality().equals(other.exclusions, exclusions)&&const DeepCollectionEquality().equals(other.scanRuns, scanRuns)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.retrySourceJobRunId, retrySourceJobRunId) || other.retrySourceJobRunId == retrySourceJobRunId)&&(identical(other.retrySuccessorJobRunId, retrySuccessorJobRunId) || other.retrySuccessorJobRunId == retrySuccessorJobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(requestedRoots),const DeepCollectionEquality().hash(admittedRoots),const DeepCollectionEquality().hash(exclusions),const DeepCollectionEquality().hash(scanRuns),progress,retrySourceJobRunId,retrySuccessorJobRunId);

@override
String toString() {
  return 'LibraryScanJobDetail(requestedRoots: $requestedRoots, admittedRoots: $admittedRoots, exclusions: $exclusions, scanRuns: $scanRuns, progress: $progress, retrySourceJobRunId: $retrySourceJobRunId, retrySuccessorJobRunId: $retrySuccessorJobRunId)';
}


}

/// @nodoc
abstract mixin class $LibraryScanJobDetailCopyWith<$Res>  {
  factory $LibraryScanJobDetailCopyWith(LibraryScanJobDetail value, $Res Function(LibraryScanJobDetail) _then) = _$LibraryScanJobDetailCopyWithImpl;
@useResult
$Res call({
 List<LibraryScanRootSummary> requestedRoots, List<LibraryScanRootSummary> admittedRoots, List<LibraryScanAdmissionExclusion> exclusions, List<ScanRunSummary> scanRuns, ScanProgressFacts progress, JobRunId? retrySourceJobRunId, JobRunId? retrySuccessorJobRunId
});


$ScanProgressFactsCopyWith<$Res> get progress;

}
/// @nodoc
class _$LibraryScanJobDetailCopyWithImpl<$Res>
    implements $LibraryScanJobDetailCopyWith<$Res> {
  _$LibraryScanJobDetailCopyWithImpl(this._self, this._then);

  final LibraryScanJobDetail _self;
  final $Res Function(LibraryScanJobDetail) _then;

/// Create a copy of LibraryScanJobDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? requestedRoots = null,Object? admittedRoots = null,Object? exclusions = null,Object? scanRuns = null,Object? progress = null,Object? retrySourceJobRunId = freezed,Object? retrySuccessorJobRunId = freezed,}) {
  return _then(_self.copyWith(
requestedRoots: null == requestedRoots ? _self.requestedRoots : requestedRoots // ignore: cast_nullable_to_non_nullable
as List<LibraryScanRootSummary>,admittedRoots: null == admittedRoots ? _self.admittedRoots : admittedRoots // ignore: cast_nullable_to_non_nullable
as List<LibraryScanRootSummary>,exclusions: null == exclusions ? _self.exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as List<LibraryScanAdmissionExclusion>,scanRuns: null == scanRuns ? _self.scanRuns : scanRuns // ignore: cast_nullable_to_non_nullable
as List<ScanRunSummary>,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as ScanProgressFacts,retrySourceJobRunId: freezed == retrySourceJobRunId ? _self.retrySourceJobRunId : retrySourceJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,retrySuccessorJobRunId: freezed == retrySuccessorJobRunId ? _self.retrySuccessorJobRunId : retrySuccessorJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,
  ));
}
/// Create a copy of LibraryScanJobDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ScanProgressFactsCopyWith<$Res> get progress {

  return $ScanProgressFactsCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}


/// Adds pattern-matching-related methods to [LibraryScanJobDetail].
extension LibraryScanJobDetailPatterns on LibraryScanJobDetail {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LibraryScanJobDetail value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LibraryScanJobDetail() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LibraryScanJobDetail value)  $default,){
final _that = this;
switch (_that) {
case _LibraryScanJobDetail():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LibraryScanJobDetail value)?  $default,){
final _that = this;
switch (_that) {
case _LibraryScanJobDetail() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<LibraryScanRootSummary> requestedRoots,  List<LibraryScanRootSummary> admittedRoots,  List<LibraryScanAdmissionExclusion> exclusions,  List<ScanRunSummary> scanRuns,  ScanProgressFacts progress,  JobRunId? retrySourceJobRunId,  JobRunId? retrySuccessorJobRunId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LibraryScanJobDetail() when $default != null:
return $default(_that.requestedRoots,_that.admittedRoots,_that.exclusions,_that.scanRuns,_that.progress,_that.retrySourceJobRunId,_that.retrySuccessorJobRunId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<LibraryScanRootSummary> requestedRoots,  List<LibraryScanRootSummary> admittedRoots,  List<LibraryScanAdmissionExclusion> exclusions,  List<ScanRunSummary> scanRuns,  ScanProgressFacts progress,  JobRunId? retrySourceJobRunId,  JobRunId? retrySuccessorJobRunId)  $default,) {final _that = this;
switch (_that) {
case _LibraryScanJobDetail():
return $default(_that.requestedRoots,_that.admittedRoots,_that.exclusions,_that.scanRuns,_that.progress,_that.retrySourceJobRunId,_that.retrySuccessorJobRunId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<LibraryScanRootSummary> requestedRoots,  List<LibraryScanRootSummary> admittedRoots,  List<LibraryScanAdmissionExclusion> exclusions,  List<ScanRunSummary> scanRuns,  ScanProgressFacts progress,  JobRunId? retrySourceJobRunId,  JobRunId? retrySuccessorJobRunId)?  $default,) {final _that = this;
switch (_that) {
case _LibraryScanJobDetail() when $default != null:
return $default(_that.requestedRoots,_that.admittedRoots,_that.exclusions,_that.scanRuns,_that.progress,_that.retrySourceJobRunId,_that.retrySuccessorJobRunId);case _:
  return null;

}
}

}

/// @nodoc


class _LibraryScanJobDetail implements LibraryScanJobDetail {
  const _LibraryScanJobDetail({required final  List<LibraryScanRootSummary> requestedRoots, required final  List<LibraryScanRootSummary> admittedRoots, required final  List<LibraryScanAdmissionExclusion> exclusions, required final  List<ScanRunSummary> scanRuns, required this.progress, this.retrySourceJobRunId, this.retrySuccessorJobRunId}): _requestedRoots = requestedRoots,_admittedRoots = admittedRoots,_exclusions = exclusions,_scanRuns = scanRuns;


 final  List<LibraryScanRootSummary> _requestedRoots;
@override List<LibraryScanRootSummary> get requestedRoots {
  if (_requestedRoots is EqualUnmodifiableListView) return _requestedRoots;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_requestedRoots);
}

 final  List<LibraryScanRootSummary> _admittedRoots;
@override List<LibraryScanRootSummary> get admittedRoots {
  if (_admittedRoots is EqualUnmodifiableListView) return _admittedRoots;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_admittedRoots);
}

 final  List<LibraryScanAdmissionExclusion> _exclusions;
@override List<LibraryScanAdmissionExclusion> get exclusions {
  if (_exclusions is EqualUnmodifiableListView) return _exclusions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_exclusions);
}

 final  List<ScanRunSummary> _scanRuns;
@override List<ScanRunSummary> get scanRuns {
  if (_scanRuns is EqualUnmodifiableListView) return _scanRuns;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_scanRuns);
}

@override final  ScanProgressFacts progress;
@override final  JobRunId? retrySourceJobRunId;
@override final  JobRunId? retrySuccessorJobRunId;

/// Create a copy of LibraryScanJobDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LibraryScanJobDetailCopyWith<_LibraryScanJobDetail> get copyWith => __$LibraryScanJobDetailCopyWithImpl<_LibraryScanJobDetail>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LibraryScanJobDetail&&const DeepCollectionEquality().equals(other._requestedRoots, _requestedRoots)&&const DeepCollectionEquality().equals(other._admittedRoots, _admittedRoots)&&const DeepCollectionEquality().equals(other._exclusions, _exclusions)&&const DeepCollectionEquality().equals(other._scanRuns, _scanRuns)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.retrySourceJobRunId, retrySourceJobRunId) || other.retrySourceJobRunId == retrySourceJobRunId)&&(identical(other.retrySuccessorJobRunId, retrySuccessorJobRunId) || other.retrySuccessorJobRunId == retrySuccessorJobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_requestedRoots),const DeepCollectionEquality().hash(_admittedRoots),const DeepCollectionEquality().hash(_exclusions),const DeepCollectionEquality().hash(_scanRuns),progress,retrySourceJobRunId,retrySuccessorJobRunId);

@override
String toString() {
  return 'LibraryScanJobDetail(requestedRoots: $requestedRoots, admittedRoots: $admittedRoots, exclusions: $exclusions, scanRuns: $scanRuns, progress: $progress, retrySourceJobRunId: $retrySourceJobRunId, retrySuccessorJobRunId: $retrySuccessorJobRunId)';
}


}

/// @nodoc
abstract mixin class _$LibraryScanJobDetailCopyWith<$Res> implements $LibraryScanJobDetailCopyWith<$Res> {
  factory _$LibraryScanJobDetailCopyWith(_LibraryScanJobDetail value, $Res Function(_LibraryScanJobDetail) _then) = __$LibraryScanJobDetailCopyWithImpl;
@override @useResult
$Res call({
 List<LibraryScanRootSummary> requestedRoots, List<LibraryScanRootSummary> admittedRoots, List<LibraryScanAdmissionExclusion> exclusions, List<ScanRunSummary> scanRuns, ScanProgressFacts progress, JobRunId? retrySourceJobRunId, JobRunId? retrySuccessorJobRunId
});


@override $ScanProgressFactsCopyWith<$Res> get progress;

}
/// @nodoc
class __$LibraryScanJobDetailCopyWithImpl<$Res>
    implements _$LibraryScanJobDetailCopyWith<$Res> {
  __$LibraryScanJobDetailCopyWithImpl(this._self, this._then);

  final _LibraryScanJobDetail _self;
  final $Res Function(_LibraryScanJobDetail) _then;

/// Create a copy of LibraryScanJobDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? requestedRoots = null,Object? admittedRoots = null,Object? exclusions = null,Object? scanRuns = null,Object? progress = null,Object? retrySourceJobRunId = freezed,Object? retrySuccessorJobRunId = freezed,}) {
  return _then(_LibraryScanJobDetail(
requestedRoots: null == requestedRoots ? _self._requestedRoots : requestedRoots // ignore: cast_nullable_to_non_nullable
as List<LibraryScanRootSummary>,admittedRoots: null == admittedRoots ? _self._admittedRoots : admittedRoots // ignore: cast_nullable_to_non_nullable
as List<LibraryScanRootSummary>,exclusions: null == exclusions ? _self._exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as List<LibraryScanAdmissionExclusion>,scanRuns: null == scanRuns ? _self._scanRuns : scanRuns // ignore: cast_nullable_to_non_nullable
as List<ScanRunSummary>,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as ScanProgressFacts,retrySourceJobRunId: freezed == retrySourceJobRunId ? _self.retrySourceJobRunId : retrySourceJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,retrySuccessorJobRunId: freezed == retrySuccessorJobRunId ? _self.retrySuccessorJobRunId : retrySuccessorJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,
  ));
}

/// Create a copy of LibraryScanJobDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ScanProgressFactsCopyWith<$Res> get progress {

  return $ScanProgressFactsCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}

/// @nodoc
mixin _$LibraryRefreshJobDetail {

 String get trigger; String? get triggerRootId; String get mode; List<LibraryRootId> get requestedRootIds; List<ScanRunSummary> get scanRuns; RefreshProgressFacts get progress; JobRunId? get retrySourceJobRunId; JobRunId? get retrySuccessorJobRunId;
/// Create a copy of LibraryRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryRefreshJobDetailCopyWith<LibraryRefreshJobDetail> get copyWith => _$LibraryRefreshJobDetailCopyWithImpl<LibraryRefreshJobDetail>(this as LibraryRefreshJobDetail, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryRefreshJobDetail&&(identical(other.trigger, trigger) || other.trigger == trigger)&&(identical(other.triggerRootId, triggerRootId) || other.triggerRootId == triggerRootId)&&(identical(other.mode, mode) || other.mode == mode)&&const DeepCollectionEquality().equals(other.requestedRootIds, requestedRootIds)&&const DeepCollectionEquality().equals(other.scanRuns, scanRuns)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.retrySourceJobRunId, retrySourceJobRunId) || other.retrySourceJobRunId == retrySourceJobRunId)&&(identical(other.retrySuccessorJobRunId, retrySuccessorJobRunId) || other.retrySuccessorJobRunId == retrySuccessorJobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,trigger,triggerRootId,mode,const DeepCollectionEquality().hash(requestedRootIds),const DeepCollectionEquality().hash(scanRuns),progress,retrySourceJobRunId,retrySuccessorJobRunId);

@override
String toString() {
  return 'LibraryRefreshJobDetail(trigger: $trigger, triggerRootId: $triggerRootId, mode: $mode, requestedRootIds: $requestedRootIds, scanRuns: $scanRuns, progress: $progress, retrySourceJobRunId: $retrySourceJobRunId, retrySuccessorJobRunId: $retrySuccessorJobRunId)';
}


}

/// @nodoc
abstract mixin class $LibraryRefreshJobDetailCopyWith<$Res>  {
  factory $LibraryRefreshJobDetailCopyWith(LibraryRefreshJobDetail value, $Res Function(LibraryRefreshJobDetail) _then) = _$LibraryRefreshJobDetailCopyWithImpl;
@useResult
$Res call({
 String trigger, String? triggerRootId, String mode, List<LibraryRootId> requestedRootIds, List<ScanRunSummary> scanRuns, RefreshProgressFacts progress, JobRunId? retrySourceJobRunId, JobRunId? retrySuccessorJobRunId
});


$RefreshProgressFactsCopyWith<$Res> get progress;

}
/// @nodoc
class _$LibraryRefreshJobDetailCopyWithImpl<$Res>
    implements $LibraryRefreshJobDetailCopyWith<$Res> {
  _$LibraryRefreshJobDetailCopyWithImpl(this._self, this._then);

  final LibraryRefreshJobDetail _self;
  final $Res Function(LibraryRefreshJobDetail) _then;

/// Create a copy of LibraryRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? trigger = null,Object? triggerRootId = freezed,Object? mode = null,Object? requestedRootIds = null,Object? scanRuns = null,Object? progress = null,Object? retrySourceJobRunId = freezed,Object? retrySuccessorJobRunId = freezed,}) {
  return _then(_self.copyWith(
trigger: null == trigger ? _self.trigger : trigger // ignore: cast_nullable_to_non_nullable
as String,triggerRootId: freezed == triggerRootId ? _self.triggerRootId : triggerRootId // ignore: cast_nullable_to_non_nullable
as String?,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,requestedRootIds: null == requestedRootIds ? _self.requestedRootIds : requestedRootIds // ignore: cast_nullable_to_non_nullable
as List<LibraryRootId>,scanRuns: null == scanRuns ? _self.scanRuns : scanRuns // ignore: cast_nullable_to_non_nullable
as List<ScanRunSummary>,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as RefreshProgressFacts,retrySourceJobRunId: freezed == retrySourceJobRunId ? _self.retrySourceJobRunId : retrySourceJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,retrySuccessorJobRunId: freezed == retrySuccessorJobRunId ? _self.retrySuccessorJobRunId : retrySuccessorJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,
  ));
}
/// Create a copy of LibraryRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RefreshProgressFactsCopyWith<$Res> get progress {

  return $RefreshProgressFactsCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}


/// Adds pattern-matching-related methods to [LibraryRefreshJobDetail].
extension LibraryRefreshJobDetailPatterns on LibraryRefreshJobDetail {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LibraryRefreshJobDetail value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LibraryRefreshJobDetail() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LibraryRefreshJobDetail value)  $default,){
final _that = this;
switch (_that) {
case _LibraryRefreshJobDetail():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LibraryRefreshJobDetail value)?  $default,){
final _that = this;
switch (_that) {
case _LibraryRefreshJobDetail() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String trigger,  String? triggerRootId,  String mode,  List<LibraryRootId> requestedRootIds,  List<ScanRunSummary> scanRuns,  RefreshProgressFacts progress,  JobRunId? retrySourceJobRunId,  JobRunId? retrySuccessorJobRunId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LibraryRefreshJobDetail() when $default != null:
return $default(_that.trigger,_that.triggerRootId,_that.mode,_that.requestedRootIds,_that.scanRuns,_that.progress,_that.retrySourceJobRunId,_that.retrySuccessorJobRunId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String trigger,  String? triggerRootId,  String mode,  List<LibraryRootId> requestedRootIds,  List<ScanRunSummary> scanRuns,  RefreshProgressFacts progress,  JobRunId? retrySourceJobRunId,  JobRunId? retrySuccessorJobRunId)  $default,) {final _that = this;
switch (_that) {
case _LibraryRefreshJobDetail():
return $default(_that.trigger,_that.triggerRootId,_that.mode,_that.requestedRootIds,_that.scanRuns,_that.progress,_that.retrySourceJobRunId,_that.retrySuccessorJobRunId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String trigger,  String? triggerRootId,  String mode,  List<LibraryRootId> requestedRootIds,  List<ScanRunSummary> scanRuns,  RefreshProgressFacts progress,  JobRunId? retrySourceJobRunId,  JobRunId? retrySuccessorJobRunId)?  $default,) {final _that = this;
switch (_that) {
case _LibraryRefreshJobDetail() when $default != null:
return $default(_that.trigger,_that.triggerRootId,_that.mode,_that.requestedRootIds,_that.scanRuns,_that.progress,_that.retrySourceJobRunId,_that.retrySuccessorJobRunId);case _:
  return null;

}
}

}

/// @nodoc


class _LibraryRefreshJobDetail implements LibraryRefreshJobDetail {
  const _LibraryRefreshJobDetail({required this.trigger, this.triggerRootId, required this.mode, required final  List<LibraryRootId> requestedRootIds, required final  List<ScanRunSummary> scanRuns, required this.progress, this.retrySourceJobRunId, this.retrySuccessorJobRunId}): _requestedRootIds = requestedRootIds,_scanRuns = scanRuns;


@override final  String trigger;
@override final  String? triggerRootId;
@override final  String mode;
 final  List<LibraryRootId> _requestedRootIds;
@override List<LibraryRootId> get requestedRootIds {
  if (_requestedRootIds is EqualUnmodifiableListView) return _requestedRootIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_requestedRootIds);
}

 final  List<ScanRunSummary> _scanRuns;
@override List<ScanRunSummary> get scanRuns {
  if (_scanRuns is EqualUnmodifiableListView) return _scanRuns;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_scanRuns);
}

@override final  RefreshProgressFacts progress;
@override final  JobRunId? retrySourceJobRunId;
@override final  JobRunId? retrySuccessorJobRunId;

/// Create a copy of LibraryRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LibraryRefreshJobDetailCopyWith<_LibraryRefreshJobDetail> get copyWith => __$LibraryRefreshJobDetailCopyWithImpl<_LibraryRefreshJobDetail>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LibraryRefreshJobDetail&&(identical(other.trigger, trigger) || other.trigger == trigger)&&(identical(other.triggerRootId, triggerRootId) || other.triggerRootId == triggerRootId)&&(identical(other.mode, mode) || other.mode == mode)&&const DeepCollectionEquality().equals(other._requestedRootIds, _requestedRootIds)&&const DeepCollectionEquality().equals(other._scanRuns, _scanRuns)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.retrySourceJobRunId, retrySourceJobRunId) || other.retrySourceJobRunId == retrySourceJobRunId)&&(identical(other.retrySuccessorJobRunId, retrySuccessorJobRunId) || other.retrySuccessorJobRunId == retrySuccessorJobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,trigger,triggerRootId,mode,const DeepCollectionEquality().hash(_requestedRootIds),const DeepCollectionEquality().hash(_scanRuns),progress,retrySourceJobRunId,retrySuccessorJobRunId);

@override
String toString() {
  return 'LibraryRefreshJobDetail(trigger: $trigger, triggerRootId: $triggerRootId, mode: $mode, requestedRootIds: $requestedRootIds, scanRuns: $scanRuns, progress: $progress, retrySourceJobRunId: $retrySourceJobRunId, retrySuccessorJobRunId: $retrySuccessorJobRunId)';
}


}

/// @nodoc
abstract mixin class _$LibraryRefreshJobDetailCopyWith<$Res> implements $LibraryRefreshJobDetailCopyWith<$Res> {
  factory _$LibraryRefreshJobDetailCopyWith(_LibraryRefreshJobDetail value, $Res Function(_LibraryRefreshJobDetail) _then) = __$LibraryRefreshJobDetailCopyWithImpl;
@override @useResult
$Res call({
 String trigger, String? triggerRootId, String mode, List<LibraryRootId> requestedRootIds, List<ScanRunSummary> scanRuns, RefreshProgressFacts progress, JobRunId? retrySourceJobRunId, JobRunId? retrySuccessorJobRunId
});


@override $RefreshProgressFactsCopyWith<$Res> get progress;

}
/// @nodoc
class __$LibraryRefreshJobDetailCopyWithImpl<$Res>
    implements _$LibraryRefreshJobDetailCopyWith<$Res> {
  __$LibraryRefreshJobDetailCopyWithImpl(this._self, this._then);

  final _LibraryRefreshJobDetail _self;
  final $Res Function(_LibraryRefreshJobDetail) _then;

/// Create a copy of LibraryRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? trigger = null,Object? triggerRootId = freezed,Object? mode = null,Object? requestedRootIds = null,Object? scanRuns = null,Object? progress = null,Object? retrySourceJobRunId = freezed,Object? retrySuccessorJobRunId = freezed,}) {
  return _then(_LibraryRefreshJobDetail(
trigger: null == trigger ? _self.trigger : trigger // ignore: cast_nullable_to_non_nullable
as String,triggerRootId: freezed == triggerRootId ? _self.triggerRootId : triggerRootId // ignore: cast_nullable_to_non_nullable
as String?,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,requestedRootIds: null == requestedRootIds ? _self._requestedRootIds : requestedRootIds // ignore: cast_nullable_to_non_nullable
as List<LibraryRootId>,scanRuns: null == scanRuns ? _self._scanRuns : scanRuns // ignore: cast_nullable_to_non_nullable
as List<ScanRunSummary>,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as RefreshProgressFacts,retrySourceJobRunId: freezed == retrySourceJobRunId ? _self.retrySourceJobRunId : retrySourceJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,retrySuccessorJobRunId: freezed == retrySuccessorJobRunId ? _self.retrySuccessorJobRunId : retrySuccessorJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,
  ));
}

/// Create a copy of LibraryRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RefreshProgressFactsCopyWith<$Res> get progress {

  return $RefreshProgressFactsCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}

/// @nodoc
mixin _$GameRefreshJobDetail {

 List<GameId> get gameIds; String get mode; RefreshProgressFacts get progress; JobRunId? get retrySourceJobRunId; JobRunId? get retrySuccessorJobRunId;
/// Create a copy of GameRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameRefreshJobDetailCopyWith<GameRefreshJobDetail> get copyWith => _$GameRefreshJobDetailCopyWithImpl<GameRefreshJobDetail>(this as GameRefreshJobDetail, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameRefreshJobDetail&&const DeepCollectionEquality().equals(other.gameIds, gameIds)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.retrySourceJobRunId, retrySourceJobRunId) || other.retrySourceJobRunId == retrySourceJobRunId)&&(identical(other.retrySuccessorJobRunId, retrySuccessorJobRunId) || other.retrySuccessorJobRunId == retrySuccessorJobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(gameIds),mode,progress,retrySourceJobRunId,retrySuccessorJobRunId);

@override
String toString() {
  return 'GameRefreshJobDetail(gameIds: $gameIds, mode: $mode, progress: $progress, retrySourceJobRunId: $retrySourceJobRunId, retrySuccessorJobRunId: $retrySuccessorJobRunId)';
}


}

/// @nodoc
abstract mixin class $GameRefreshJobDetailCopyWith<$Res>  {
  factory $GameRefreshJobDetailCopyWith(GameRefreshJobDetail value, $Res Function(GameRefreshJobDetail) _then) = _$GameRefreshJobDetailCopyWithImpl;
@useResult
$Res call({
 List<GameId> gameIds, String mode, RefreshProgressFacts progress, JobRunId? retrySourceJobRunId, JobRunId? retrySuccessorJobRunId
});


$RefreshProgressFactsCopyWith<$Res> get progress;

}
/// @nodoc
class _$GameRefreshJobDetailCopyWithImpl<$Res>
    implements $GameRefreshJobDetailCopyWith<$Res> {
  _$GameRefreshJobDetailCopyWithImpl(this._self, this._then);

  final GameRefreshJobDetail _self;
  final $Res Function(GameRefreshJobDetail) _then;

/// Create a copy of GameRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? gameIds = null,Object? mode = null,Object? progress = null,Object? retrySourceJobRunId = freezed,Object? retrySuccessorJobRunId = freezed,}) {
  return _then(_self.copyWith(
gameIds: null == gameIds ? _self.gameIds : gameIds // ignore: cast_nullable_to_non_nullable
as List<GameId>,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as RefreshProgressFacts,retrySourceJobRunId: freezed == retrySourceJobRunId ? _self.retrySourceJobRunId : retrySourceJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,retrySuccessorJobRunId: freezed == retrySuccessorJobRunId ? _self.retrySuccessorJobRunId : retrySuccessorJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,
  ));
}
/// Create a copy of GameRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RefreshProgressFactsCopyWith<$Res> get progress {

  return $RefreshProgressFactsCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}


/// Adds pattern-matching-related methods to [GameRefreshJobDetail].
extension GameRefreshJobDetailPatterns on GameRefreshJobDetail {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameRefreshJobDetail value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameRefreshJobDetail() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameRefreshJobDetail value)  $default,){
final _that = this;
switch (_that) {
case _GameRefreshJobDetail():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameRefreshJobDetail value)?  $default,){
final _that = this;
switch (_that) {
case _GameRefreshJobDetail() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<GameId> gameIds,  String mode,  RefreshProgressFacts progress,  JobRunId? retrySourceJobRunId,  JobRunId? retrySuccessorJobRunId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameRefreshJobDetail() when $default != null:
return $default(_that.gameIds,_that.mode,_that.progress,_that.retrySourceJobRunId,_that.retrySuccessorJobRunId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<GameId> gameIds,  String mode,  RefreshProgressFacts progress,  JobRunId? retrySourceJobRunId,  JobRunId? retrySuccessorJobRunId)  $default,) {final _that = this;
switch (_that) {
case _GameRefreshJobDetail():
return $default(_that.gameIds,_that.mode,_that.progress,_that.retrySourceJobRunId,_that.retrySuccessorJobRunId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<GameId> gameIds,  String mode,  RefreshProgressFacts progress,  JobRunId? retrySourceJobRunId,  JobRunId? retrySuccessorJobRunId)?  $default,) {final _that = this;
switch (_that) {
case _GameRefreshJobDetail() when $default != null:
return $default(_that.gameIds,_that.mode,_that.progress,_that.retrySourceJobRunId,_that.retrySuccessorJobRunId);case _:
  return null;

}
}

}

/// @nodoc


class _GameRefreshJobDetail implements GameRefreshJobDetail {
  const _GameRefreshJobDetail({required final  List<GameId> gameIds, required this.mode, required this.progress, this.retrySourceJobRunId, this.retrySuccessorJobRunId}): _gameIds = gameIds;


 final  List<GameId> _gameIds;
@override List<GameId> get gameIds {
  if (_gameIds is EqualUnmodifiableListView) return _gameIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_gameIds);
}

@override final  String mode;
@override final  RefreshProgressFacts progress;
@override final  JobRunId? retrySourceJobRunId;
@override final  JobRunId? retrySuccessorJobRunId;

/// Create a copy of GameRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameRefreshJobDetailCopyWith<_GameRefreshJobDetail> get copyWith => __$GameRefreshJobDetailCopyWithImpl<_GameRefreshJobDetail>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameRefreshJobDetail&&const DeepCollectionEquality().equals(other._gameIds, _gameIds)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.retrySourceJobRunId, retrySourceJobRunId) || other.retrySourceJobRunId == retrySourceJobRunId)&&(identical(other.retrySuccessorJobRunId, retrySuccessorJobRunId) || other.retrySuccessorJobRunId == retrySuccessorJobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_gameIds),mode,progress,retrySourceJobRunId,retrySuccessorJobRunId);

@override
String toString() {
  return 'GameRefreshJobDetail(gameIds: $gameIds, mode: $mode, progress: $progress, retrySourceJobRunId: $retrySourceJobRunId, retrySuccessorJobRunId: $retrySuccessorJobRunId)';
}


}

/// @nodoc
abstract mixin class _$GameRefreshJobDetailCopyWith<$Res> implements $GameRefreshJobDetailCopyWith<$Res> {
  factory _$GameRefreshJobDetailCopyWith(_GameRefreshJobDetail value, $Res Function(_GameRefreshJobDetail) _then) = __$GameRefreshJobDetailCopyWithImpl;
@override @useResult
$Res call({
 List<GameId> gameIds, String mode, RefreshProgressFacts progress, JobRunId? retrySourceJobRunId, JobRunId? retrySuccessorJobRunId
});


@override $RefreshProgressFactsCopyWith<$Res> get progress;

}
/// @nodoc
class __$GameRefreshJobDetailCopyWithImpl<$Res>
    implements _$GameRefreshJobDetailCopyWith<$Res> {
  __$GameRefreshJobDetailCopyWithImpl(this._self, this._then);

  final _GameRefreshJobDetail _self;
  final $Res Function(_GameRefreshJobDetail) _then;

/// Create a copy of GameRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? gameIds = null,Object? mode = null,Object? progress = null,Object? retrySourceJobRunId = freezed,Object? retrySuccessorJobRunId = freezed,}) {
  return _then(_GameRefreshJobDetail(
gameIds: null == gameIds ? _self._gameIds : gameIds // ignore: cast_nullable_to_non_nullable
as List<GameId>,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as RefreshProgressFacts,retrySourceJobRunId: freezed == retrySourceJobRunId ? _self.retrySourceJobRunId : retrySourceJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,retrySuccessorJobRunId: freezed == retrySuccessorJobRunId ? _self.retrySuccessorJobRunId : retrySuccessorJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,
  ));
}

/// Create a copy of GameRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RefreshProgressFactsCopyWith<$Res> get progress {

  return $RefreshProgressFactsCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}

/// @nodoc
mixin _$LibraryResolutionRefreshJobDetail {

 JobRunId get jobRunId; int get settingsRevision; RefreshProgressFacts get progress; JobRunId? get retrySourceJobRunId; JobRunId? get retrySuccessorJobRunId;
/// Create a copy of LibraryResolutionRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryResolutionRefreshJobDetailCopyWith<LibraryResolutionRefreshJobDetail> get copyWith => _$LibraryResolutionRefreshJobDetailCopyWithImpl<LibraryResolutionRefreshJobDetail>(this as LibraryResolutionRefreshJobDetail, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryResolutionRefreshJobDetail&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId)&&(identical(other.settingsRevision, settingsRevision) || other.settingsRevision == settingsRevision)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.retrySourceJobRunId, retrySourceJobRunId) || other.retrySourceJobRunId == retrySourceJobRunId)&&(identical(other.retrySuccessorJobRunId, retrySuccessorJobRunId) || other.retrySuccessorJobRunId == retrySuccessorJobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,jobRunId,settingsRevision,progress,retrySourceJobRunId,retrySuccessorJobRunId);

@override
String toString() {
  return 'LibraryResolutionRefreshJobDetail(jobRunId: $jobRunId, settingsRevision: $settingsRevision, progress: $progress, retrySourceJobRunId: $retrySourceJobRunId, retrySuccessorJobRunId: $retrySuccessorJobRunId)';
}


}

/// @nodoc
abstract mixin class $LibraryResolutionRefreshJobDetailCopyWith<$Res>  {
  factory $LibraryResolutionRefreshJobDetailCopyWith(LibraryResolutionRefreshJobDetail value, $Res Function(LibraryResolutionRefreshJobDetail) _then) = _$LibraryResolutionRefreshJobDetailCopyWithImpl;
@useResult
$Res call({
 JobRunId jobRunId, int settingsRevision, RefreshProgressFacts progress, JobRunId? retrySourceJobRunId, JobRunId? retrySuccessorJobRunId
});


$RefreshProgressFactsCopyWith<$Res> get progress;

}
/// @nodoc
class _$LibraryResolutionRefreshJobDetailCopyWithImpl<$Res>
    implements $LibraryResolutionRefreshJobDetailCopyWith<$Res> {
  _$LibraryResolutionRefreshJobDetailCopyWithImpl(this._self, this._then);

  final LibraryResolutionRefreshJobDetail _self;
  final $Res Function(LibraryResolutionRefreshJobDetail) _then;

/// Create a copy of LibraryResolutionRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? jobRunId = null,Object? settingsRevision = null,Object? progress = null,Object? retrySourceJobRunId = freezed,Object? retrySuccessorJobRunId = freezed,}) {
  return _then(_self.copyWith(
jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,settingsRevision: null == settingsRevision ? _self.settingsRevision : settingsRevision // ignore: cast_nullable_to_non_nullable
as int,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as RefreshProgressFacts,retrySourceJobRunId: freezed == retrySourceJobRunId ? _self.retrySourceJobRunId : retrySourceJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,retrySuccessorJobRunId: freezed == retrySuccessorJobRunId ? _self.retrySuccessorJobRunId : retrySuccessorJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,
  ));
}
/// Create a copy of LibraryResolutionRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RefreshProgressFactsCopyWith<$Res> get progress {

  return $RefreshProgressFactsCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}


/// Adds pattern-matching-related methods to [LibraryResolutionRefreshJobDetail].
extension LibraryResolutionRefreshJobDetailPatterns on LibraryResolutionRefreshJobDetail {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LibraryResolutionRefreshJobDetail value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LibraryResolutionRefreshJobDetail() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LibraryResolutionRefreshJobDetail value)  $default,){
final _that = this;
switch (_that) {
case _LibraryResolutionRefreshJobDetail():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LibraryResolutionRefreshJobDetail value)?  $default,){
final _that = this;
switch (_that) {
case _LibraryResolutionRefreshJobDetail() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( JobRunId jobRunId,  int settingsRevision,  RefreshProgressFacts progress,  JobRunId? retrySourceJobRunId,  JobRunId? retrySuccessorJobRunId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LibraryResolutionRefreshJobDetail() when $default != null:
return $default(_that.jobRunId,_that.settingsRevision,_that.progress,_that.retrySourceJobRunId,_that.retrySuccessorJobRunId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( JobRunId jobRunId,  int settingsRevision,  RefreshProgressFacts progress,  JobRunId? retrySourceJobRunId,  JobRunId? retrySuccessorJobRunId)  $default,) {final _that = this;
switch (_that) {
case _LibraryResolutionRefreshJobDetail():
return $default(_that.jobRunId,_that.settingsRevision,_that.progress,_that.retrySourceJobRunId,_that.retrySuccessorJobRunId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( JobRunId jobRunId,  int settingsRevision,  RefreshProgressFacts progress,  JobRunId? retrySourceJobRunId,  JobRunId? retrySuccessorJobRunId)?  $default,) {final _that = this;
switch (_that) {
case _LibraryResolutionRefreshJobDetail() when $default != null:
return $default(_that.jobRunId,_that.settingsRevision,_that.progress,_that.retrySourceJobRunId,_that.retrySuccessorJobRunId);case _:
  return null;

}
}

}

/// @nodoc


class _LibraryResolutionRefreshJobDetail implements LibraryResolutionRefreshJobDetail {
  const _LibraryResolutionRefreshJobDetail({required this.jobRunId, required this.settingsRevision, required this.progress, this.retrySourceJobRunId, this.retrySuccessorJobRunId});


@override final  JobRunId jobRunId;
@override final  int settingsRevision;
@override final  RefreshProgressFacts progress;
@override final  JobRunId? retrySourceJobRunId;
@override final  JobRunId? retrySuccessorJobRunId;

/// Create a copy of LibraryResolutionRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LibraryResolutionRefreshJobDetailCopyWith<_LibraryResolutionRefreshJobDetail> get copyWith => __$LibraryResolutionRefreshJobDetailCopyWithImpl<_LibraryResolutionRefreshJobDetail>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LibraryResolutionRefreshJobDetail&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId)&&(identical(other.settingsRevision, settingsRevision) || other.settingsRevision == settingsRevision)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.retrySourceJobRunId, retrySourceJobRunId) || other.retrySourceJobRunId == retrySourceJobRunId)&&(identical(other.retrySuccessorJobRunId, retrySuccessorJobRunId) || other.retrySuccessorJobRunId == retrySuccessorJobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,jobRunId,settingsRevision,progress,retrySourceJobRunId,retrySuccessorJobRunId);

@override
String toString() {
  return 'LibraryResolutionRefreshJobDetail(jobRunId: $jobRunId, settingsRevision: $settingsRevision, progress: $progress, retrySourceJobRunId: $retrySourceJobRunId, retrySuccessorJobRunId: $retrySuccessorJobRunId)';
}


}

/// @nodoc
abstract mixin class _$LibraryResolutionRefreshJobDetailCopyWith<$Res> implements $LibraryResolutionRefreshJobDetailCopyWith<$Res> {
  factory _$LibraryResolutionRefreshJobDetailCopyWith(_LibraryResolutionRefreshJobDetail value, $Res Function(_LibraryResolutionRefreshJobDetail) _then) = __$LibraryResolutionRefreshJobDetailCopyWithImpl;
@override @useResult
$Res call({
 JobRunId jobRunId, int settingsRevision, RefreshProgressFacts progress, JobRunId? retrySourceJobRunId, JobRunId? retrySuccessorJobRunId
});


@override $RefreshProgressFactsCopyWith<$Res> get progress;

}
/// @nodoc
class __$LibraryResolutionRefreshJobDetailCopyWithImpl<$Res>
    implements _$LibraryResolutionRefreshJobDetailCopyWith<$Res> {
  __$LibraryResolutionRefreshJobDetailCopyWithImpl(this._self, this._then);

  final _LibraryResolutionRefreshJobDetail _self;
  final $Res Function(_LibraryResolutionRefreshJobDetail) _then;

/// Create a copy of LibraryResolutionRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? jobRunId = null,Object? settingsRevision = null,Object? progress = null,Object? retrySourceJobRunId = freezed,Object? retrySuccessorJobRunId = freezed,}) {
  return _then(_LibraryResolutionRefreshJobDetail(
jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,settingsRevision: null == settingsRevision ? _self.settingsRevision : settingsRevision // ignore: cast_nullable_to_non_nullable
as int,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as RefreshProgressFacts,retrySourceJobRunId: freezed == retrySourceJobRunId ? _self.retrySourceJobRunId : retrySourceJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,retrySuccessorJobRunId: freezed == retrySuccessorJobRunId ? _self.retrySuccessorJobRunId : retrySuccessorJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,
  ));
}

/// Create a copy of LibraryResolutionRefreshJobDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RefreshProgressFactsCopyWith<$Res> get progress {

  return $RefreshProgressFactsCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}

/// @nodoc
mixin _$OperationDetail {

 Object get detail;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationDetail&&const DeepCollectionEquality().equals(other.detail, detail));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(detail));

@override
String toString() {
  return 'OperationDetail(detail: $detail)';
}


}

/// @nodoc
class $OperationDetailCopyWith<$Res>  {
$OperationDetailCopyWith(OperationDetail _, $Res Function(OperationDetail) __);
}


/// Adds pattern-matching-related methods to [OperationDetail].
extension OperationDetailPatterns on OperationDetail {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( OperationDetailLibraryScan value)?  libraryScan,TResult Function( OperationDetailLibraryRefresh value)?  libraryRefresh,TResult Function( OperationDetailGameRefresh value)?  gameRefresh,TResult Function( OperationDetailLibraryResolutionRefresh value)?  libraryResolutionRefresh,required TResult orElse(),}){
final _that = this;
switch (_that) {
case OperationDetailLibraryScan() when libraryScan != null:
return libraryScan(_that);case OperationDetailLibraryRefresh() when libraryRefresh != null:
return libraryRefresh(_that);case OperationDetailGameRefresh() when gameRefresh != null:
return gameRefresh(_that);case OperationDetailLibraryResolutionRefresh() when libraryResolutionRefresh != null:
return libraryResolutionRefresh(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( OperationDetailLibraryScan value)  libraryScan,required TResult Function( OperationDetailLibraryRefresh value)  libraryRefresh,required TResult Function( OperationDetailGameRefresh value)  gameRefresh,required TResult Function( OperationDetailLibraryResolutionRefresh value)  libraryResolutionRefresh,}){
final _that = this;
switch (_that) {
case OperationDetailLibraryScan():
return libraryScan(_that);case OperationDetailLibraryRefresh():
return libraryRefresh(_that);case OperationDetailGameRefresh():
return gameRefresh(_that);case OperationDetailLibraryResolutionRefresh():
return libraryResolutionRefresh(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( OperationDetailLibraryScan value)?  libraryScan,TResult? Function( OperationDetailLibraryRefresh value)?  libraryRefresh,TResult? Function( OperationDetailGameRefresh value)?  gameRefresh,TResult? Function( OperationDetailLibraryResolutionRefresh value)?  libraryResolutionRefresh,}){
final _that = this;
switch (_that) {
case OperationDetailLibraryScan() when libraryScan != null:
return libraryScan(_that);case OperationDetailLibraryRefresh() when libraryRefresh != null:
return libraryRefresh(_that);case OperationDetailGameRefresh() when gameRefresh != null:
return gameRefresh(_that);case OperationDetailLibraryResolutionRefresh() when libraryResolutionRefresh != null:
return libraryResolutionRefresh(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( LibraryScanJobDetail detail)?  libraryScan,TResult Function( LibraryRefreshJobDetail detail)?  libraryRefresh,TResult Function( GameRefreshJobDetail detail)?  gameRefresh,TResult Function( LibraryResolutionRefreshJobDetail detail)?  libraryResolutionRefresh,required TResult orElse(),}) {final _that = this;
switch (_that) {
case OperationDetailLibraryScan() when libraryScan != null:
return libraryScan(_that.detail);case OperationDetailLibraryRefresh() when libraryRefresh != null:
return libraryRefresh(_that.detail);case OperationDetailGameRefresh() when gameRefresh != null:
return gameRefresh(_that.detail);case OperationDetailLibraryResolutionRefresh() when libraryResolutionRefresh != null:
return libraryResolutionRefresh(_that.detail);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( LibraryScanJobDetail detail)  libraryScan,required TResult Function( LibraryRefreshJobDetail detail)  libraryRefresh,required TResult Function( GameRefreshJobDetail detail)  gameRefresh,required TResult Function( LibraryResolutionRefreshJobDetail detail)  libraryResolutionRefresh,}) {final _that = this;
switch (_that) {
case OperationDetailLibraryScan():
return libraryScan(_that.detail);case OperationDetailLibraryRefresh():
return libraryRefresh(_that.detail);case OperationDetailGameRefresh():
return gameRefresh(_that.detail);case OperationDetailLibraryResolutionRefresh():
return libraryResolutionRefresh(_that.detail);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( LibraryScanJobDetail detail)?  libraryScan,TResult? Function( LibraryRefreshJobDetail detail)?  libraryRefresh,TResult? Function( GameRefreshJobDetail detail)?  gameRefresh,TResult? Function( LibraryResolutionRefreshJobDetail detail)?  libraryResolutionRefresh,}) {final _that = this;
switch (_that) {
case OperationDetailLibraryScan() when libraryScan != null:
return libraryScan(_that.detail);case OperationDetailLibraryRefresh() when libraryRefresh != null:
return libraryRefresh(_that.detail);case OperationDetailGameRefresh() when gameRefresh != null:
return gameRefresh(_that.detail);case OperationDetailLibraryResolutionRefresh() when libraryResolutionRefresh != null:
return libraryResolutionRefresh(_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class OperationDetailLibraryScan implements OperationDetail {
  const OperationDetailLibraryScan(this.detail);


@override final  LibraryScanJobDetail detail;

/// Create a copy of OperationDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperationDetailLibraryScanCopyWith<OperationDetailLibraryScan> get copyWith => _$OperationDetailLibraryScanCopyWithImpl<OperationDetailLibraryScan>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationDetailLibraryScan&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'OperationDetail.libraryScan(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $OperationDetailLibraryScanCopyWith<$Res> implements $OperationDetailCopyWith<$Res> {
  factory $OperationDetailLibraryScanCopyWith(OperationDetailLibraryScan value, $Res Function(OperationDetailLibraryScan) _then) = _$OperationDetailLibraryScanCopyWithImpl;
@useResult
$Res call({
 LibraryScanJobDetail detail
});


$LibraryScanJobDetailCopyWith<$Res> get detail;

}
/// @nodoc
class _$OperationDetailLibraryScanCopyWithImpl<$Res>
    implements $OperationDetailLibraryScanCopyWith<$Res> {
  _$OperationDetailLibraryScanCopyWithImpl(this._self, this._then);

  final OperationDetailLibraryScan _self;
  final $Res Function(OperationDetailLibraryScan) _then;

/// Create a copy of OperationDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(OperationDetailLibraryScan(
null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as LibraryScanJobDetail,
  ));
}

/// Create a copy of OperationDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LibraryScanJobDetailCopyWith<$Res> get detail {

  return $LibraryScanJobDetailCopyWith<$Res>(_self.detail, (value) {
    return _then(_self.copyWith(detail: value));
  });
}
}

/// @nodoc


class OperationDetailLibraryRefresh implements OperationDetail {
  const OperationDetailLibraryRefresh(this.detail);


@override final  LibraryRefreshJobDetail detail;

/// Create a copy of OperationDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperationDetailLibraryRefreshCopyWith<OperationDetailLibraryRefresh> get copyWith => _$OperationDetailLibraryRefreshCopyWithImpl<OperationDetailLibraryRefresh>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationDetailLibraryRefresh&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'OperationDetail.libraryRefresh(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $OperationDetailLibraryRefreshCopyWith<$Res> implements $OperationDetailCopyWith<$Res> {
  factory $OperationDetailLibraryRefreshCopyWith(OperationDetailLibraryRefresh value, $Res Function(OperationDetailLibraryRefresh) _then) = _$OperationDetailLibraryRefreshCopyWithImpl;
@useResult
$Res call({
 LibraryRefreshJobDetail detail
});


$LibraryRefreshJobDetailCopyWith<$Res> get detail;

}
/// @nodoc
class _$OperationDetailLibraryRefreshCopyWithImpl<$Res>
    implements $OperationDetailLibraryRefreshCopyWith<$Res> {
  _$OperationDetailLibraryRefreshCopyWithImpl(this._self, this._then);

  final OperationDetailLibraryRefresh _self;
  final $Res Function(OperationDetailLibraryRefresh) _then;

/// Create a copy of OperationDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(OperationDetailLibraryRefresh(
null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as LibraryRefreshJobDetail,
  ));
}

/// Create a copy of OperationDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LibraryRefreshJobDetailCopyWith<$Res> get detail {

  return $LibraryRefreshJobDetailCopyWith<$Res>(_self.detail, (value) {
    return _then(_self.copyWith(detail: value));
  });
}
}

/// @nodoc


class OperationDetailGameRefresh implements OperationDetail {
  const OperationDetailGameRefresh(this.detail);


@override final  GameRefreshJobDetail detail;

/// Create a copy of OperationDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperationDetailGameRefreshCopyWith<OperationDetailGameRefresh> get copyWith => _$OperationDetailGameRefreshCopyWithImpl<OperationDetailGameRefresh>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationDetailGameRefresh&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'OperationDetail.gameRefresh(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $OperationDetailGameRefreshCopyWith<$Res> implements $OperationDetailCopyWith<$Res> {
  factory $OperationDetailGameRefreshCopyWith(OperationDetailGameRefresh value, $Res Function(OperationDetailGameRefresh) _then) = _$OperationDetailGameRefreshCopyWithImpl;
@useResult
$Res call({
 GameRefreshJobDetail detail
});


$GameRefreshJobDetailCopyWith<$Res> get detail;

}
/// @nodoc
class _$OperationDetailGameRefreshCopyWithImpl<$Res>
    implements $OperationDetailGameRefreshCopyWith<$Res> {
  _$OperationDetailGameRefreshCopyWithImpl(this._self, this._then);

  final OperationDetailGameRefresh _self;
  final $Res Function(OperationDetailGameRefresh) _then;

/// Create a copy of OperationDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(OperationDetailGameRefresh(
null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as GameRefreshJobDetail,
  ));
}

/// Create a copy of OperationDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GameRefreshJobDetailCopyWith<$Res> get detail {

  return $GameRefreshJobDetailCopyWith<$Res>(_self.detail, (value) {
    return _then(_self.copyWith(detail: value));
  });
}
}

/// @nodoc


class OperationDetailLibraryResolutionRefresh implements OperationDetail {
  const OperationDetailLibraryResolutionRefresh(this.detail);


@override final  LibraryResolutionRefreshJobDetail detail;

/// Create a copy of OperationDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperationDetailLibraryResolutionRefreshCopyWith<OperationDetailLibraryResolutionRefresh> get copyWith => _$OperationDetailLibraryResolutionRefreshCopyWithImpl<OperationDetailLibraryResolutionRefresh>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationDetailLibraryResolutionRefresh&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,detail);

@override
String toString() {
  return 'OperationDetail.libraryResolutionRefresh(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $OperationDetailLibraryResolutionRefreshCopyWith<$Res> implements $OperationDetailCopyWith<$Res> {
  factory $OperationDetailLibraryResolutionRefreshCopyWith(OperationDetailLibraryResolutionRefresh value, $Res Function(OperationDetailLibraryResolutionRefresh) _then) = _$OperationDetailLibraryResolutionRefreshCopyWithImpl;
@useResult
$Res call({
 LibraryResolutionRefreshJobDetail detail
});


$LibraryResolutionRefreshJobDetailCopyWith<$Res> get detail;

}
/// @nodoc
class _$OperationDetailLibraryResolutionRefreshCopyWithImpl<$Res>
    implements $OperationDetailLibraryResolutionRefreshCopyWith<$Res> {
  _$OperationDetailLibraryResolutionRefreshCopyWithImpl(this._self, this._then);

  final OperationDetailLibraryResolutionRefresh _self;
  final $Res Function(OperationDetailLibraryResolutionRefresh) _then;

/// Create a copy of OperationDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(OperationDetailLibraryResolutionRefresh(
null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as LibraryResolutionRefreshJobDetail,
  ));
}

/// Create a copy of OperationDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LibraryResolutionRefreshJobDetailCopyWith<$Res> get detail {

  return $LibraryResolutionRefreshJobDetailCopyWith<$Res>(_self.detail, (value) {
    return _then(_self.copyWith(detail: value));
  });
}
}

/// @nodoc
mixin _$JobDetail {

 JobRunProjection get job; OperationDetail get operationDetail;
/// Create a copy of JobDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JobDetailCopyWith<JobDetail> get copyWith => _$JobDetailCopyWithImpl<JobDetail>(this as JobDetail, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JobDetail&&(identical(other.job, job) || other.job == job)&&(identical(other.operationDetail, operationDetail) || other.operationDetail == operationDetail));
}


@override
int get hashCode => Object.hash(runtimeType,job,operationDetail);

@override
String toString() {
  return 'JobDetail(job: $job, operationDetail: $operationDetail)';
}


}

/// @nodoc
abstract mixin class $JobDetailCopyWith<$Res>  {
  factory $JobDetailCopyWith(JobDetail value, $Res Function(JobDetail) _then) = _$JobDetailCopyWithImpl;
@useResult
$Res call({
 JobRunProjection job, OperationDetail operationDetail
});


$JobRunProjectionCopyWith<$Res> get job;$OperationDetailCopyWith<$Res> get operationDetail;

}
/// @nodoc
class _$JobDetailCopyWithImpl<$Res>
    implements $JobDetailCopyWith<$Res> {
  _$JobDetailCopyWithImpl(this._self, this._then);

  final JobDetail _self;
  final $Res Function(JobDetail) _then;

/// Create a copy of JobDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? job = null,Object? operationDetail = null,}) {
  return _then(_self.copyWith(
job: null == job ? _self.job : job // ignore: cast_nullable_to_non_nullable
as JobRunProjection,operationDetail: null == operationDetail ? _self.operationDetail : operationDetail // ignore: cast_nullable_to_non_nullable
as OperationDetail,
  ));
}
/// Create a copy of JobDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JobRunProjectionCopyWith<$Res> get job {

  return $JobRunProjectionCopyWith<$Res>(_self.job, (value) {
    return _then(_self.copyWith(job: value));
  });
}/// Create a copy of JobDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationDetailCopyWith<$Res> get operationDetail {

  return $OperationDetailCopyWith<$Res>(_self.operationDetail, (value) {
    return _then(_self.copyWith(operationDetail: value));
  });
}
}


/// Adds pattern-matching-related methods to [JobDetail].
extension JobDetailPatterns on JobDetail {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JobDetail value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JobDetail() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JobDetail value)  $default,){
final _that = this;
switch (_that) {
case _JobDetail():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JobDetail value)?  $default,){
final _that = this;
switch (_that) {
case _JobDetail() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( JobRunProjection job,  OperationDetail operationDetail)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JobDetail() when $default != null:
return $default(_that.job,_that.operationDetail);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( JobRunProjection job,  OperationDetail operationDetail)  $default,) {final _that = this;
switch (_that) {
case _JobDetail():
return $default(_that.job,_that.operationDetail);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( JobRunProjection job,  OperationDetail operationDetail)?  $default,) {final _that = this;
switch (_that) {
case _JobDetail() when $default != null:
return $default(_that.job,_that.operationDetail);case _:
  return null;

}
}

}

/// @nodoc


class _JobDetail implements JobDetail {
  const _JobDetail({required this.job, required this.operationDetail});


@override final  JobRunProjection job;
@override final  OperationDetail operationDetail;

/// Create a copy of JobDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JobDetailCopyWith<_JobDetail> get copyWith => __$JobDetailCopyWithImpl<_JobDetail>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _JobDetail&&(identical(other.job, job) || other.job == job)&&(identical(other.operationDetail, operationDetail) || other.operationDetail == operationDetail));
}


@override
int get hashCode => Object.hash(runtimeType,job,operationDetail);

@override
String toString() {
  return 'JobDetail(job: $job, operationDetail: $operationDetail)';
}


}

/// @nodoc
abstract mixin class _$JobDetailCopyWith<$Res> implements $JobDetailCopyWith<$Res> {
  factory _$JobDetailCopyWith(_JobDetail value, $Res Function(_JobDetail) _then) = __$JobDetailCopyWithImpl;
@override @useResult
$Res call({
 JobRunProjection job, OperationDetail operationDetail
});


@override $JobRunProjectionCopyWith<$Res> get job;@override $OperationDetailCopyWith<$Res> get operationDetail;

}
/// @nodoc
class __$JobDetailCopyWithImpl<$Res>
    implements _$JobDetailCopyWith<$Res> {
  __$JobDetailCopyWithImpl(this._self, this._then);

  final _JobDetail _self;
  final $Res Function(_JobDetail) _then;

/// Create a copy of JobDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? job = null,Object? operationDetail = null,}) {
  return _then(_JobDetail(
job: null == job ? _self.job : job // ignore: cast_nullable_to_non_nullable
as JobRunProjection,operationDetail: null == operationDetail ? _self.operationDetail : operationDetail // ignore: cast_nullable_to_non_nullable
as OperationDetail,
  ));
}

/// Create a copy of JobDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JobRunProjectionCopyWith<$Res> get job {

  return $JobRunProjectionCopyWith<$Res>(_self.job, (value) {
    return _then(_self.copyWith(job: value));
  });
}/// Create a copy of JobDetail
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationDetailCopyWith<$Res> get operationDetail {

  return $OperationDetailCopyWith<$Res>(_self.operationDetail, (value) {
    return _then(_self.copyWith(operationDetail: value));
  });
}
}

/// @nodoc
mixin _$ActiveJobSummary {

 int get activeCount; JobRunId? get soleActiveJobRunId;
/// Create a copy of ActiveJobSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActiveJobSummaryCopyWith<ActiveJobSummary> get copyWith => _$ActiveJobSummaryCopyWithImpl<ActiveJobSummary>(this as ActiveJobSummary, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActiveJobSummary&&(identical(other.activeCount, activeCount) || other.activeCount == activeCount)&&(identical(other.soleActiveJobRunId, soleActiveJobRunId) || other.soleActiveJobRunId == soleActiveJobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,activeCount,soleActiveJobRunId);

@override
String toString() {
  return 'ActiveJobSummary(activeCount: $activeCount, soleActiveJobRunId: $soleActiveJobRunId)';
}


}

/// @nodoc
abstract mixin class $ActiveJobSummaryCopyWith<$Res>  {
  factory $ActiveJobSummaryCopyWith(ActiveJobSummary value, $Res Function(ActiveJobSummary) _then) = _$ActiveJobSummaryCopyWithImpl;
@useResult
$Res call({
 int activeCount, JobRunId? soleActiveJobRunId
});




}
/// @nodoc
class _$ActiveJobSummaryCopyWithImpl<$Res>
    implements $ActiveJobSummaryCopyWith<$Res> {
  _$ActiveJobSummaryCopyWithImpl(this._self, this._then);

  final ActiveJobSummary _self;
  final $Res Function(ActiveJobSummary) _then;

/// Create a copy of ActiveJobSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? activeCount = null,Object? soleActiveJobRunId = freezed,}) {
  return _then(_self.copyWith(
activeCount: null == activeCount ? _self.activeCount : activeCount // ignore: cast_nullable_to_non_nullable
as int,soleActiveJobRunId: freezed == soleActiveJobRunId ? _self.soleActiveJobRunId : soleActiveJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,
  ));
}

}


/// Adds pattern-matching-related methods to [ActiveJobSummary].
extension ActiveJobSummaryPatterns on ActiveJobSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActiveJobSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActiveJobSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActiveJobSummary value)  $default,){
final _that = this;
switch (_that) {
case _ActiveJobSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActiveJobSummary value)?  $default,){
final _that = this;
switch (_that) {
case _ActiveJobSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int activeCount,  JobRunId? soleActiveJobRunId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActiveJobSummary() when $default != null:
return $default(_that.activeCount,_that.soleActiveJobRunId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int activeCount,  JobRunId? soleActiveJobRunId)  $default,) {final _that = this;
switch (_that) {
case _ActiveJobSummary():
return $default(_that.activeCount,_that.soleActiveJobRunId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int activeCount,  JobRunId? soleActiveJobRunId)?  $default,) {final _that = this;
switch (_that) {
case _ActiveJobSummary() when $default != null:
return $default(_that.activeCount,_that.soleActiveJobRunId);case _:
  return null;

}
}

}

/// @nodoc


class _ActiveJobSummary implements ActiveJobSummary {
  const _ActiveJobSummary({required this.activeCount, this.soleActiveJobRunId});


@override final  int activeCount;
@override final  JobRunId? soleActiveJobRunId;

/// Create a copy of ActiveJobSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActiveJobSummaryCopyWith<_ActiveJobSummary> get copyWith => __$ActiveJobSummaryCopyWithImpl<_ActiveJobSummary>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActiveJobSummary&&(identical(other.activeCount, activeCount) || other.activeCount == activeCount)&&(identical(other.soleActiveJobRunId, soleActiveJobRunId) || other.soleActiveJobRunId == soleActiveJobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,activeCount,soleActiveJobRunId);

@override
String toString() {
  return 'ActiveJobSummary(activeCount: $activeCount, soleActiveJobRunId: $soleActiveJobRunId)';
}


}

/// @nodoc
abstract mixin class _$ActiveJobSummaryCopyWith<$Res> implements $ActiveJobSummaryCopyWith<$Res> {
  factory _$ActiveJobSummaryCopyWith(_ActiveJobSummary value, $Res Function(_ActiveJobSummary) _then) = __$ActiveJobSummaryCopyWithImpl;
@override @useResult
$Res call({
 int activeCount, JobRunId? soleActiveJobRunId
});




}
/// @nodoc
class __$ActiveJobSummaryCopyWithImpl<$Res>
    implements _$ActiveJobSummaryCopyWith<$Res> {
  __$ActiveJobSummaryCopyWithImpl(this._self, this._then);

  final _ActiveJobSummary _self;
  final $Res Function(_ActiveJobSummary) _then;

/// Create a copy of ActiveJobSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? activeCount = null,Object? soleActiveJobRunId = freezed,}) {
  return _then(_ActiveJobSummary(
activeCount: null == activeCount ? _self.activeCount : activeCount // ignore: cast_nullable_to_non_nullable
as int,soleActiveJobRunId: freezed == soleActiveJobRunId ? _self.soleActiveJobRunId : soleActiveJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId?,
  ));
}


}

/// @nodoc
mixin _$StartLibraryScanResult {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartLibraryScanResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'StartLibraryScanResult()';
}


}

/// @nodoc
class $StartLibraryScanResultCopyWith<$Res>  {
$StartLibraryScanResultCopyWith(StartLibraryScanResult _, $Res Function(StartLibraryScanResult) __);
}


/// Adds pattern-matching-related methods to [StartLibraryScanResult].
extension StartLibraryScanResultPatterns on StartLibraryScanResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StartLibraryScanResultAdmitted value)?  admitted,TResult Function( StartLibraryScanResultAlreadyScanning value)?  alreadyScanning,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StartLibraryScanResultAdmitted() when admitted != null:
return admitted(_that);case StartLibraryScanResultAlreadyScanning() when alreadyScanning != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StartLibraryScanResultAdmitted value)  admitted,required TResult Function( StartLibraryScanResultAlreadyScanning value)  alreadyScanning,}){
final _that = this;
switch (_that) {
case StartLibraryScanResultAdmitted():
return admitted(_that);case StartLibraryScanResultAlreadyScanning():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StartLibraryScanResultAdmitted value)?  admitted,TResult? Function( StartLibraryScanResultAlreadyScanning value)?  alreadyScanning,}){
final _that = this;
switch (_that) {
case StartLibraryScanResultAdmitted() when admitted != null:
return admitted(_that);case StartLibraryScanResultAlreadyScanning() when alreadyScanning != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OperationHandle handle)?  admitted,TResult Function( LibraryRootId libraryRootId,  JobRunId activeJobRunId,  ScanRunId activeScanRunId)?  alreadyScanning,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StartLibraryScanResultAdmitted() when admitted != null:
return admitted(_that.handle);case StartLibraryScanResultAlreadyScanning() when alreadyScanning != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OperationHandle handle)  admitted,required TResult Function( LibraryRootId libraryRootId,  JobRunId activeJobRunId,  ScanRunId activeScanRunId)  alreadyScanning,}) {final _that = this;
switch (_that) {
case StartLibraryScanResultAdmitted():
return admitted(_that.handle);case StartLibraryScanResultAlreadyScanning():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OperationHandle handle)?  admitted,TResult? Function( LibraryRootId libraryRootId,  JobRunId activeJobRunId,  ScanRunId activeScanRunId)?  alreadyScanning,}) {final _that = this;
switch (_that) {
case StartLibraryScanResultAdmitted() when admitted != null:
return admitted(_that.handle);case StartLibraryScanResultAlreadyScanning() when alreadyScanning != null:
return alreadyScanning(_that.libraryRootId,_that.activeJobRunId,_that.activeScanRunId);case _:
  return null;

}
}

}

/// @nodoc


class StartLibraryScanResultAdmitted implements StartLibraryScanResult {
  const StartLibraryScanResultAdmitted(this.handle);


 final  OperationHandle handle;

/// Create a copy of StartLibraryScanResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartLibraryScanResultAdmittedCopyWith<StartLibraryScanResultAdmitted> get copyWith => _$StartLibraryScanResultAdmittedCopyWithImpl<StartLibraryScanResultAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartLibraryScanResultAdmitted&&(identical(other.handle, handle) || other.handle == handle));
}


@override
int get hashCode => Object.hash(runtimeType,handle);

@override
String toString() {
  return 'StartLibraryScanResult.admitted(handle: $handle)';
}


}

/// @nodoc
abstract mixin class $StartLibraryScanResultAdmittedCopyWith<$Res> implements $StartLibraryScanResultCopyWith<$Res> {
  factory $StartLibraryScanResultAdmittedCopyWith(StartLibraryScanResultAdmitted value, $Res Function(StartLibraryScanResultAdmitted) _then) = _$StartLibraryScanResultAdmittedCopyWithImpl;
@useResult
$Res call({
 OperationHandle handle
});




}
/// @nodoc
class _$StartLibraryScanResultAdmittedCopyWithImpl<$Res>
    implements $StartLibraryScanResultAdmittedCopyWith<$Res> {
  _$StartLibraryScanResultAdmittedCopyWithImpl(this._self, this._then);

  final StartLibraryScanResultAdmitted _self;
  final $Res Function(StartLibraryScanResultAdmitted) _then;

/// Create a copy of StartLibraryScanResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? handle = null,}) {
  return _then(StartLibraryScanResultAdmitted(
null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as OperationHandle,
  ));
}


}

/// @nodoc


class StartLibraryScanResultAlreadyScanning implements StartLibraryScanResult {
  const StartLibraryScanResultAlreadyScanning({required this.libraryRootId, required this.activeJobRunId, required this.activeScanRunId});


 final  LibraryRootId libraryRootId;
 final  JobRunId activeJobRunId;
 final  ScanRunId activeScanRunId;

/// Create a copy of StartLibraryScanResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartLibraryScanResultAlreadyScanningCopyWith<StartLibraryScanResultAlreadyScanning> get copyWith => _$StartLibraryScanResultAlreadyScanningCopyWithImpl<StartLibraryScanResultAlreadyScanning>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartLibraryScanResultAlreadyScanning&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId)&&(identical(other.activeJobRunId, activeJobRunId) || other.activeJobRunId == activeJobRunId)&&(identical(other.activeScanRunId, activeScanRunId) || other.activeScanRunId == activeScanRunId));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId,activeJobRunId,activeScanRunId);

@override
String toString() {
  return 'StartLibraryScanResult.alreadyScanning(libraryRootId: $libraryRootId, activeJobRunId: $activeJobRunId, activeScanRunId: $activeScanRunId)';
}


}

/// @nodoc
abstract mixin class $StartLibraryScanResultAlreadyScanningCopyWith<$Res> implements $StartLibraryScanResultCopyWith<$Res> {
  factory $StartLibraryScanResultAlreadyScanningCopyWith(StartLibraryScanResultAlreadyScanning value, $Res Function(StartLibraryScanResultAlreadyScanning) _then) = _$StartLibraryScanResultAlreadyScanningCopyWithImpl;
@useResult
$Res call({
 LibraryRootId libraryRootId, JobRunId activeJobRunId, ScanRunId activeScanRunId
});




}
/// @nodoc
class _$StartLibraryScanResultAlreadyScanningCopyWithImpl<$Res>
    implements $StartLibraryScanResultAlreadyScanningCopyWith<$Res> {
  _$StartLibraryScanResultAlreadyScanningCopyWithImpl(this._self, this._then);

  final StartLibraryScanResultAlreadyScanning _self;
  final $Res Function(StartLibraryScanResultAlreadyScanning) _then;

/// Create a copy of StartLibraryScanResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? libraryRootId = null,Object? activeJobRunId = null,Object? activeScanRunId = null,}) {
  return _then(StartLibraryScanResultAlreadyScanning(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,activeJobRunId: null == activeJobRunId ? _self.activeJobRunId : activeJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,activeScanRunId: null == activeScanRunId ? _self.activeScanRunId : activeScanRunId // ignore: cast_nullable_to_non_nullable
as ScanRunId,
  ));
}


}

/// @nodoc
mixin _$StartLibraryScanAllResult {

 List<LibraryScanAdmissionExclusion> get exclusions;
/// Create a copy of StartLibraryScanAllResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartLibraryScanAllResultCopyWith<StartLibraryScanAllResult> get copyWith => _$StartLibraryScanAllResultCopyWithImpl<StartLibraryScanAllResult>(this as StartLibraryScanAllResult, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartLibraryScanAllResult&&const DeepCollectionEquality().equals(other.exclusions, exclusions));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(exclusions));

@override
String toString() {
  return 'StartLibraryScanAllResult(exclusions: $exclusions)';
}


}

/// @nodoc
abstract mixin class $StartLibraryScanAllResultCopyWith<$Res>  {
  factory $StartLibraryScanAllResultCopyWith(StartLibraryScanAllResult value, $Res Function(StartLibraryScanAllResult) _then) = _$StartLibraryScanAllResultCopyWithImpl;
@useResult
$Res call({
 List<LibraryScanAdmissionExclusion> exclusions
});




}
/// @nodoc
class _$StartLibraryScanAllResultCopyWithImpl<$Res>
    implements $StartLibraryScanAllResultCopyWith<$Res> {
  _$StartLibraryScanAllResultCopyWithImpl(this._self, this._then);

  final StartLibraryScanAllResult _self;
  final $Res Function(StartLibraryScanAllResult) _then;

/// Create a copy of StartLibraryScanAllResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? exclusions = null,}) {
  return _then(_self.copyWith(
exclusions: null == exclusions ? _self.exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as List<LibraryScanAdmissionExclusion>,
  ));
}

}


/// Adds pattern-matching-related methods to [StartLibraryScanAllResult].
extension StartLibraryScanAllResultPatterns on StartLibraryScanAllResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StartLibraryScanAllResultAdmitted value)?  admitted,TResult Function( StartLibraryScanAllResultNothingEligible value)?  nothingEligible,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StartLibraryScanAllResultAdmitted() when admitted != null:
return admitted(_that);case StartLibraryScanAllResultNothingEligible() when nothingEligible != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StartLibraryScanAllResultAdmitted value)  admitted,required TResult Function( StartLibraryScanAllResultNothingEligible value)  nothingEligible,}){
final _that = this;
switch (_that) {
case StartLibraryScanAllResultAdmitted():
return admitted(_that);case StartLibraryScanAllResultNothingEligible():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StartLibraryScanAllResultAdmitted value)?  admitted,TResult? Function( StartLibraryScanAllResultNothingEligible value)?  nothingEligible,}){
final _that = this;
switch (_that) {
case StartLibraryScanAllResultAdmitted() when admitted != null:
return admitted(_that);case StartLibraryScanAllResultNothingEligible() when nothingEligible != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OperationHandle handle,  List<LibraryRootId> admittedRoots,  List<LibraryScanAdmissionExclusion> exclusions)?  admitted,TResult Function( List<LibraryScanAdmissionExclusion> exclusions)?  nothingEligible,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StartLibraryScanAllResultAdmitted() when admitted != null:
return admitted(_that.handle,_that.admittedRoots,_that.exclusions);case StartLibraryScanAllResultNothingEligible() when nothingEligible != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OperationHandle handle,  List<LibraryRootId> admittedRoots,  List<LibraryScanAdmissionExclusion> exclusions)  admitted,required TResult Function( List<LibraryScanAdmissionExclusion> exclusions)  nothingEligible,}) {final _that = this;
switch (_that) {
case StartLibraryScanAllResultAdmitted():
return admitted(_that.handle,_that.admittedRoots,_that.exclusions);case StartLibraryScanAllResultNothingEligible():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OperationHandle handle,  List<LibraryRootId> admittedRoots,  List<LibraryScanAdmissionExclusion> exclusions)?  admitted,TResult? Function( List<LibraryScanAdmissionExclusion> exclusions)?  nothingEligible,}) {final _that = this;
switch (_that) {
case StartLibraryScanAllResultAdmitted() when admitted != null:
return admitted(_that.handle,_that.admittedRoots,_that.exclusions);case StartLibraryScanAllResultNothingEligible() when nothingEligible != null:
return nothingEligible(_that.exclusions);case _:
  return null;

}
}

}

/// @nodoc


class StartLibraryScanAllResultAdmitted implements StartLibraryScanAllResult {
  const StartLibraryScanAllResultAdmitted({required this.handle, required final  List<LibraryRootId> admittedRoots, required final  List<LibraryScanAdmissionExclusion> exclusions}): _admittedRoots = admittedRoots,_exclusions = exclusions;


 final  OperationHandle handle;
 final  List<LibraryRootId> _admittedRoots;
 List<LibraryRootId> get admittedRoots {
  if (_admittedRoots is EqualUnmodifiableListView) return _admittedRoots;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_admittedRoots);
}

 final  List<LibraryScanAdmissionExclusion> _exclusions;
@override List<LibraryScanAdmissionExclusion> get exclusions {
  if (_exclusions is EqualUnmodifiableListView) return _exclusions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_exclusions);
}


/// Create a copy of StartLibraryScanAllResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartLibraryScanAllResultAdmittedCopyWith<StartLibraryScanAllResultAdmitted> get copyWith => _$StartLibraryScanAllResultAdmittedCopyWithImpl<StartLibraryScanAllResultAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartLibraryScanAllResultAdmitted&&(identical(other.handle, handle) || other.handle == handle)&&const DeepCollectionEquality().equals(other._admittedRoots, _admittedRoots)&&const DeepCollectionEquality().equals(other._exclusions, _exclusions));
}


@override
int get hashCode => Object.hash(runtimeType,handle,const DeepCollectionEquality().hash(_admittedRoots),const DeepCollectionEquality().hash(_exclusions));

@override
String toString() {
  return 'StartLibraryScanAllResult.admitted(handle: $handle, admittedRoots: $admittedRoots, exclusions: $exclusions)';
}


}

/// @nodoc
abstract mixin class $StartLibraryScanAllResultAdmittedCopyWith<$Res> implements $StartLibraryScanAllResultCopyWith<$Res> {
  factory $StartLibraryScanAllResultAdmittedCopyWith(StartLibraryScanAllResultAdmitted value, $Res Function(StartLibraryScanAllResultAdmitted) _then) = _$StartLibraryScanAllResultAdmittedCopyWithImpl;
@override @useResult
$Res call({
 OperationHandle handle, List<LibraryRootId> admittedRoots, List<LibraryScanAdmissionExclusion> exclusions
});




}
/// @nodoc
class _$StartLibraryScanAllResultAdmittedCopyWithImpl<$Res>
    implements $StartLibraryScanAllResultAdmittedCopyWith<$Res> {
  _$StartLibraryScanAllResultAdmittedCopyWithImpl(this._self, this._then);

  final StartLibraryScanAllResultAdmitted _self;
  final $Res Function(StartLibraryScanAllResultAdmitted) _then;

/// Create a copy of StartLibraryScanAllResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? handle = null,Object? admittedRoots = null,Object? exclusions = null,}) {
  return _then(StartLibraryScanAllResultAdmitted(
handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as OperationHandle,admittedRoots: null == admittedRoots ? _self._admittedRoots : admittedRoots // ignore: cast_nullable_to_non_nullable
as List<LibraryRootId>,exclusions: null == exclusions ? _self._exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as List<LibraryScanAdmissionExclusion>,
  ));
}


}

/// @nodoc


class StartLibraryScanAllResultNothingEligible implements StartLibraryScanAllResult {
  const StartLibraryScanAllResultNothingEligible({required final  List<LibraryScanAdmissionExclusion> exclusions}): _exclusions = exclusions;


 final  List<LibraryScanAdmissionExclusion> _exclusions;
@override List<LibraryScanAdmissionExclusion> get exclusions {
  if (_exclusions is EqualUnmodifiableListView) return _exclusions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_exclusions);
}


/// Create a copy of StartLibraryScanAllResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartLibraryScanAllResultNothingEligibleCopyWith<StartLibraryScanAllResultNothingEligible> get copyWith => _$StartLibraryScanAllResultNothingEligibleCopyWithImpl<StartLibraryScanAllResultNothingEligible>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartLibraryScanAllResultNothingEligible&&const DeepCollectionEquality().equals(other._exclusions, _exclusions));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_exclusions));

@override
String toString() {
  return 'StartLibraryScanAllResult.nothingEligible(exclusions: $exclusions)';
}


}

/// @nodoc
abstract mixin class $StartLibraryScanAllResultNothingEligibleCopyWith<$Res> implements $StartLibraryScanAllResultCopyWith<$Res> {
  factory $StartLibraryScanAllResultNothingEligibleCopyWith(StartLibraryScanAllResultNothingEligible value, $Res Function(StartLibraryScanAllResultNothingEligible) _then) = _$StartLibraryScanAllResultNothingEligibleCopyWithImpl;
@override @useResult
$Res call({
 List<LibraryScanAdmissionExclusion> exclusions
});




}
/// @nodoc
class _$StartLibraryScanAllResultNothingEligibleCopyWithImpl<$Res>
    implements $StartLibraryScanAllResultNothingEligibleCopyWith<$Res> {
  _$StartLibraryScanAllResultNothingEligibleCopyWithImpl(this._self, this._then);

  final StartLibraryScanAllResultNothingEligible _self;
  final $Res Function(StartLibraryScanAllResultNothingEligible) _then;

/// Create a copy of StartLibraryScanAllResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? exclusions = null,}) {
  return _then(StartLibraryScanAllResultNothingEligible(
exclusions: null == exclusions ? _self._exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as List<LibraryScanAdmissionExclusion>,
  ));
}


}

/// @nodoc
mixin _$LibraryScanAllRequestResolution {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanAllRequestResolution);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LibraryScanAllRequestResolution()';
}


}

/// @nodoc
class $LibraryScanAllRequestResolutionCopyWith<$Res>  {
$LibraryScanAllRequestResolutionCopyWith(LibraryScanAllRequestResolution _, $Res Function(LibraryScanAllRequestResolution) __);
}


/// Adds pattern-matching-related methods to [LibraryScanAllRequestResolution].
extension LibraryScanAllRequestResolutionPatterns on LibraryScanAllRequestResolution {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LibraryScanAllRequestResolutionAdmitted value)?  admitted,TResult Function( LibraryScanAllRequestResolutionNothingAdmitted value)?  nothingAdmitted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LibraryScanAllRequestResolutionAdmitted() when admitted != null:
return admitted(_that);case LibraryScanAllRequestResolutionNothingAdmitted() when nothingAdmitted != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LibraryScanAllRequestResolutionAdmitted value)  admitted,required TResult Function( LibraryScanAllRequestResolutionNothingAdmitted value)  nothingAdmitted,}){
final _that = this;
switch (_that) {
case LibraryScanAllRequestResolutionAdmitted():
return admitted(_that);case LibraryScanAllRequestResolutionNothingAdmitted():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LibraryScanAllRequestResolutionAdmitted value)?  admitted,TResult? Function( LibraryScanAllRequestResolutionNothingAdmitted value)?  nothingAdmitted,}){
final _that = this;
switch (_that) {
case LibraryScanAllRequestResolutionAdmitted() when admitted != null:
return admitted(_that);case LibraryScanAllRequestResolutionNothingAdmitted() when nothingAdmitted != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OperationHandle handle,  List<LibraryRootId> admittedRoots,  List<LibraryScanAdmissionExclusion> exclusions)?  admitted,TResult Function()?  nothingAdmitted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LibraryScanAllRequestResolutionAdmitted() when admitted != null:
return admitted(_that.handle,_that.admittedRoots,_that.exclusions);case LibraryScanAllRequestResolutionNothingAdmitted() when nothingAdmitted != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OperationHandle handle,  List<LibraryRootId> admittedRoots,  List<LibraryScanAdmissionExclusion> exclusions)  admitted,required TResult Function()  nothingAdmitted,}) {final _that = this;
switch (_that) {
case LibraryScanAllRequestResolutionAdmitted():
return admitted(_that.handle,_that.admittedRoots,_that.exclusions);case LibraryScanAllRequestResolutionNothingAdmitted():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OperationHandle handle,  List<LibraryRootId> admittedRoots,  List<LibraryScanAdmissionExclusion> exclusions)?  admitted,TResult? Function()?  nothingAdmitted,}) {final _that = this;
switch (_that) {
case LibraryScanAllRequestResolutionAdmitted() when admitted != null:
return admitted(_that.handle,_that.admittedRoots,_that.exclusions);case LibraryScanAllRequestResolutionNothingAdmitted() when nothingAdmitted != null:
return nothingAdmitted();case _:
  return null;

}
}

}

/// @nodoc


class LibraryScanAllRequestResolutionAdmitted implements LibraryScanAllRequestResolution {
  const LibraryScanAllRequestResolutionAdmitted({required this.handle, required final  List<LibraryRootId> admittedRoots, required final  List<LibraryScanAdmissionExclusion> exclusions}): _admittedRoots = admittedRoots,_exclusions = exclusions;


 final  OperationHandle handle;
 final  List<LibraryRootId> _admittedRoots;
 List<LibraryRootId> get admittedRoots {
  if (_admittedRoots is EqualUnmodifiableListView) return _admittedRoots;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_admittedRoots);
}

 final  List<LibraryScanAdmissionExclusion> _exclusions;
 List<LibraryScanAdmissionExclusion> get exclusions {
  if (_exclusions is EqualUnmodifiableListView) return _exclusions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_exclusions);
}


/// Create a copy of LibraryScanAllRequestResolution
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryScanAllRequestResolutionAdmittedCopyWith<LibraryScanAllRequestResolutionAdmitted> get copyWith => _$LibraryScanAllRequestResolutionAdmittedCopyWithImpl<LibraryScanAllRequestResolutionAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanAllRequestResolutionAdmitted&&(identical(other.handle, handle) || other.handle == handle)&&const DeepCollectionEquality().equals(other._admittedRoots, _admittedRoots)&&const DeepCollectionEquality().equals(other._exclusions, _exclusions));
}


@override
int get hashCode => Object.hash(runtimeType,handle,const DeepCollectionEquality().hash(_admittedRoots),const DeepCollectionEquality().hash(_exclusions));

@override
String toString() {
  return 'LibraryScanAllRequestResolution.admitted(handle: $handle, admittedRoots: $admittedRoots, exclusions: $exclusions)';
}


}

/// @nodoc
abstract mixin class $LibraryScanAllRequestResolutionAdmittedCopyWith<$Res> implements $LibraryScanAllRequestResolutionCopyWith<$Res> {
  factory $LibraryScanAllRequestResolutionAdmittedCopyWith(LibraryScanAllRequestResolutionAdmitted value, $Res Function(LibraryScanAllRequestResolutionAdmitted) _then) = _$LibraryScanAllRequestResolutionAdmittedCopyWithImpl;
@useResult
$Res call({
 OperationHandle handle, List<LibraryRootId> admittedRoots, List<LibraryScanAdmissionExclusion> exclusions
});




}
/// @nodoc
class _$LibraryScanAllRequestResolutionAdmittedCopyWithImpl<$Res>
    implements $LibraryScanAllRequestResolutionAdmittedCopyWith<$Res> {
  _$LibraryScanAllRequestResolutionAdmittedCopyWithImpl(this._self, this._then);

  final LibraryScanAllRequestResolutionAdmitted _self;
  final $Res Function(LibraryScanAllRequestResolutionAdmitted) _then;

/// Create a copy of LibraryScanAllRequestResolution
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? handle = null,Object? admittedRoots = null,Object? exclusions = null,}) {
  return _then(LibraryScanAllRequestResolutionAdmitted(
handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as OperationHandle,admittedRoots: null == admittedRoots ? _self._admittedRoots : admittedRoots // ignore: cast_nullable_to_non_nullable
as List<LibraryRootId>,exclusions: null == exclusions ? _self._exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as List<LibraryScanAdmissionExclusion>,
  ));
}


}

/// @nodoc


class LibraryScanAllRequestResolutionNothingAdmitted implements LibraryScanAllRequestResolution {
  const LibraryScanAllRequestResolutionNothingAdmitted();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanAllRequestResolutionNothingAdmitted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LibraryScanAllRequestResolution.nothingAdmitted()';
}


}




/// @nodoc
mixin _$RetryNotAdmittedReason {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryNotAdmittedReason);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RetryNotAdmittedReason()';
}


}

/// @nodoc
class $RetryNotAdmittedReasonCopyWith<$Res>  {
$RetryNotAdmittedReasonCopyWith(RetryNotAdmittedReason _, $Res Function(RetryNotAdmittedReason) __);
}


/// Adds pattern-matching-related methods to [RetryNotAdmittedReason].
extension RetryNotAdmittedReasonPatterns on RetryNotAdmittedReason {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RetryNotAdmittedReasonSourceRunNotTerminal value)?  sourceRunNotTerminal,TResult Function( RetryNotAdmittedReasonOperationNotRetryable value)?  operationNotRetryable,TResult Function( RetryNotAdmittedReasonNoEligibleTargets value)?  noEligibleTargets,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RetryNotAdmittedReasonSourceRunNotTerminal() when sourceRunNotTerminal != null:
return sourceRunNotTerminal(_that);case RetryNotAdmittedReasonOperationNotRetryable() when operationNotRetryable != null:
return operationNotRetryable(_that);case RetryNotAdmittedReasonNoEligibleTargets() when noEligibleTargets != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RetryNotAdmittedReasonSourceRunNotTerminal value)  sourceRunNotTerminal,required TResult Function( RetryNotAdmittedReasonOperationNotRetryable value)  operationNotRetryable,required TResult Function( RetryNotAdmittedReasonNoEligibleTargets value)  noEligibleTargets,}){
final _that = this;
switch (_that) {
case RetryNotAdmittedReasonSourceRunNotTerminal():
return sourceRunNotTerminal(_that);case RetryNotAdmittedReasonOperationNotRetryable():
return operationNotRetryable(_that);case RetryNotAdmittedReasonNoEligibleTargets():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RetryNotAdmittedReasonSourceRunNotTerminal value)?  sourceRunNotTerminal,TResult? Function( RetryNotAdmittedReasonOperationNotRetryable value)?  operationNotRetryable,TResult? Function( RetryNotAdmittedReasonNoEligibleTargets value)?  noEligibleTargets,}){
final _that = this;
switch (_that) {
case RetryNotAdmittedReasonSourceRunNotTerminal() when sourceRunNotTerminal != null:
return sourceRunNotTerminal(_that);case RetryNotAdmittedReasonOperationNotRetryable() when operationNotRetryable != null:
return operationNotRetryable(_that);case RetryNotAdmittedReasonNoEligibleTargets() when noEligibleTargets != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  sourceRunNotTerminal,TResult Function()?  operationNotRetryable,TResult Function( List<LibraryScanAdmissionExclusion> exclusions)?  noEligibleTargets,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RetryNotAdmittedReasonSourceRunNotTerminal() when sourceRunNotTerminal != null:
return sourceRunNotTerminal();case RetryNotAdmittedReasonOperationNotRetryable() when operationNotRetryable != null:
return operationNotRetryable();case RetryNotAdmittedReasonNoEligibleTargets() when noEligibleTargets != null:
return noEligibleTargets(_that.exclusions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  sourceRunNotTerminal,required TResult Function()  operationNotRetryable,required TResult Function( List<LibraryScanAdmissionExclusion> exclusions)  noEligibleTargets,}) {final _that = this;
switch (_that) {
case RetryNotAdmittedReasonSourceRunNotTerminal():
return sourceRunNotTerminal();case RetryNotAdmittedReasonOperationNotRetryable():
return operationNotRetryable();case RetryNotAdmittedReasonNoEligibleTargets():
return noEligibleTargets(_that.exclusions);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  sourceRunNotTerminal,TResult? Function()?  operationNotRetryable,TResult? Function( List<LibraryScanAdmissionExclusion> exclusions)?  noEligibleTargets,}) {final _that = this;
switch (_that) {
case RetryNotAdmittedReasonSourceRunNotTerminal() when sourceRunNotTerminal != null:
return sourceRunNotTerminal();case RetryNotAdmittedReasonOperationNotRetryable() when operationNotRetryable != null:
return operationNotRetryable();case RetryNotAdmittedReasonNoEligibleTargets() when noEligibleTargets != null:
return noEligibleTargets(_that.exclusions);case _:
  return null;

}
}

}

/// @nodoc


class RetryNotAdmittedReasonSourceRunNotTerminal implements RetryNotAdmittedReason {
  const RetryNotAdmittedReasonSourceRunNotTerminal();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryNotAdmittedReasonSourceRunNotTerminal);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RetryNotAdmittedReason.sourceRunNotTerminal()';
}


}




/// @nodoc


class RetryNotAdmittedReasonOperationNotRetryable implements RetryNotAdmittedReason {
  const RetryNotAdmittedReasonOperationNotRetryable();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryNotAdmittedReasonOperationNotRetryable);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RetryNotAdmittedReason.operationNotRetryable()';
}


}




/// @nodoc


class RetryNotAdmittedReasonNoEligibleTargets implements RetryNotAdmittedReason {
  const RetryNotAdmittedReasonNoEligibleTargets(final  List<LibraryScanAdmissionExclusion> exclusions): _exclusions = exclusions;


 final  List<LibraryScanAdmissionExclusion> _exclusions;
 List<LibraryScanAdmissionExclusion> get exclusions {
  if (_exclusions is EqualUnmodifiableListView) return _exclusions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_exclusions);
}


/// Create a copy of RetryNotAdmittedReason
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RetryNotAdmittedReasonNoEligibleTargetsCopyWith<RetryNotAdmittedReasonNoEligibleTargets> get copyWith => _$RetryNotAdmittedReasonNoEligibleTargetsCopyWithImpl<RetryNotAdmittedReasonNoEligibleTargets>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryNotAdmittedReasonNoEligibleTargets&&const DeepCollectionEquality().equals(other._exclusions, _exclusions));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_exclusions));

@override
String toString() {
  return 'RetryNotAdmittedReason.noEligibleTargets(exclusions: $exclusions)';
}


}

/// @nodoc
abstract mixin class $RetryNotAdmittedReasonNoEligibleTargetsCopyWith<$Res> implements $RetryNotAdmittedReasonCopyWith<$Res> {
  factory $RetryNotAdmittedReasonNoEligibleTargetsCopyWith(RetryNotAdmittedReasonNoEligibleTargets value, $Res Function(RetryNotAdmittedReasonNoEligibleTargets) _then) = _$RetryNotAdmittedReasonNoEligibleTargetsCopyWithImpl;
@useResult
$Res call({
 List<LibraryScanAdmissionExclusion> exclusions
});




}
/// @nodoc
class _$RetryNotAdmittedReasonNoEligibleTargetsCopyWithImpl<$Res>
    implements $RetryNotAdmittedReasonNoEligibleTargetsCopyWith<$Res> {
  _$RetryNotAdmittedReasonNoEligibleTargetsCopyWithImpl(this._self, this._then);

  final RetryNotAdmittedReasonNoEligibleTargets _self;
  final $Res Function(RetryNotAdmittedReasonNoEligibleTargets) _then;

/// Create a copy of RetryNotAdmittedReason
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? exclusions = null,}) {
  return _then(RetryNotAdmittedReasonNoEligibleTargets(
null == exclusions ? _self._exclusions : exclusions // ignore: cast_nullable_to_non_nullable
as List<LibraryScanAdmissionExclusion>,
  ));
}


}

/// @nodoc
mixin _$RetryJobResult {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryJobResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RetryJobResult()';
}


}

/// @nodoc
class $RetryJobResultCopyWith<$Res>  {
$RetryJobResultCopyWith(RetryJobResult _, $Res Function(RetryJobResult) __);
}


/// Adds pattern-matching-related methods to [RetryJobResult].
extension RetryJobResultPatterns on RetryJobResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RetryJobResultAdmitted value)?  admitted,TResult Function( RetryJobResultAlreadyRetried value)?  alreadyRetried,TResult Function( RetryJobResultNotAdmitted value)?  notAdmitted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RetryJobResultAdmitted() when admitted != null:
return admitted(_that);case RetryJobResultAlreadyRetried() when alreadyRetried != null:
return alreadyRetried(_that);case RetryJobResultNotAdmitted() when notAdmitted != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RetryJobResultAdmitted value)  admitted,required TResult Function( RetryJobResultAlreadyRetried value)  alreadyRetried,required TResult Function( RetryJobResultNotAdmitted value)  notAdmitted,}){
final _that = this;
switch (_that) {
case RetryJobResultAdmitted():
return admitted(_that);case RetryJobResultAlreadyRetried():
return alreadyRetried(_that);case RetryJobResultNotAdmitted():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RetryJobResultAdmitted value)?  admitted,TResult? Function( RetryJobResultAlreadyRetried value)?  alreadyRetried,TResult? Function( RetryJobResultNotAdmitted value)?  notAdmitted,}){
final _that = this;
switch (_that) {
case RetryJobResultAdmitted() when admitted != null:
return admitted(_that);case RetryJobResultAlreadyRetried() when alreadyRetried != null:
return alreadyRetried(_that);case RetryJobResultNotAdmitted() when notAdmitted != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( OperationHandle handle)?  admitted,TResult Function( JobRunId existingJobRunId)?  alreadyRetried,TResult Function( RetryNotAdmittedReason reason)?  notAdmitted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RetryJobResultAdmitted() when admitted != null:
return admitted(_that.handle);case RetryJobResultAlreadyRetried() when alreadyRetried != null:
return alreadyRetried(_that.existingJobRunId);case RetryJobResultNotAdmitted() when notAdmitted != null:
return notAdmitted(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( OperationHandle handle)  admitted,required TResult Function( JobRunId existingJobRunId)  alreadyRetried,required TResult Function( RetryNotAdmittedReason reason)  notAdmitted,}) {final _that = this;
switch (_that) {
case RetryJobResultAdmitted():
return admitted(_that.handle);case RetryJobResultAlreadyRetried():
return alreadyRetried(_that.existingJobRunId);case RetryJobResultNotAdmitted():
return notAdmitted(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( OperationHandle handle)?  admitted,TResult? Function( JobRunId existingJobRunId)?  alreadyRetried,TResult? Function( RetryNotAdmittedReason reason)?  notAdmitted,}) {final _that = this;
switch (_that) {
case RetryJobResultAdmitted() when admitted != null:
return admitted(_that.handle);case RetryJobResultAlreadyRetried() when alreadyRetried != null:
return alreadyRetried(_that.existingJobRunId);case RetryJobResultNotAdmitted() when notAdmitted != null:
return notAdmitted(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class RetryJobResultAdmitted implements RetryJobResult {
  const RetryJobResultAdmitted(this.handle);


 final  OperationHandle handle;

/// Create a copy of RetryJobResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RetryJobResultAdmittedCopyWith<RetryJobResultAdmitted> get copyWith => _$RetryJobResultAdmittedCopyWithImpl<RetryJobResultAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryJobResultAdmitted&&(identical(other.handle, handle) || other.handle == handle));
}


@override
int get hashCode => Object.hash(runtimeType,handle);

@override
String toString() {
  return 'RetryJobResult.admitted(handle: $handle)';
}


}

/// @nodoc
abstract mixin class $RetryJobResultAdmittedCopyWith<$Res> implements $RetryJobResultCopyWith<$Res> {
  factory $RetryJobResultAdmittedCopyWith(RetryJobResultAdmitted value, $Res Function(RetryJobResultAdmitted) _then) = _$RetryJobResultAdmittedCopyWithImpl;
@useResult
$Res call({
 OperationHandle handle
});




}
/// @nodoc
class _$RetryJobResultAdmittedCopyWithImpl<$Res>
    implements $RetryJobResultAdmittedCopyWith<$Res> {
  _$RetryJobResultAdmittedCopyWithImpl(this._self, this._then);

  final RetryJobResultAdmitted _self;
  final $Res Function(RetryJobResultAdmitted) _then;

/// Create a copy of RetryJobResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? handle = null,}) {
  return _then(RetryJobResultAdmitted(
null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as OperationHandle,
  ));
}


}

/// @nodoc


class RetryJobResultAlreadyRetried implements RetryJobResult {
  const RetryJobResultAlreadyRetried(this.existingJobRunId);


 final  JobRunId existingJobRunId;

/// Create a copy of RetryJobResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RetryJobResultAlreadyRetriedCopyWith<RetryJobResultAlreadyRetried> get copyWith => _$RetryJobResultAlreadyRetriedCopyWithImpl<RetryJobResultAlreadyRetried>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryJobResultAlreadyRetried&&(identical(other.existingJobRunId, existingJobRunId) || other.existingJobRunId == existingJobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,existingJobRunId);

@override
String toString() {
  return 'RetryJobResult.alreadyRetried(existingJobRunId: $existingJobRunId)';
}


}

/// @nodoc
abstract mixin class $RetryJobResultAlreadyRetriedCopyWith<$Res> implements $RetryJobResultCopyWith<$Res> {
  factory $RetryJobResultAlreadyRetriedCopyWith(RetryJobResultAlreadyRetried value, $Res Function(RetryJobResultAlreadyRetried) _then) = _$RetryJobResultAlreadyRetriedCopyWithImpl;
@useResult
$Res call({
 JobRunId existingJobRunId
});




}
/// @nodoc
class _$RetryJobResultAlreadyRetriedCopyWithImpl<$Res>
    implements $RetryJobResultAlreadyRetriedCopyWith<$Res> {
  _$RetryJobResultAlreadyRetriedCopyWithImpl(this._self, this._then);

  final RetryJobResultAlreadyRetried _self;
  final $Res Function(RetryJobResultAlreadyRetried) _then;

/// Create a copy of RetryJobResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? existingJobRunId = null,}) {
  return _then(RetryJobResultAlreadyRetried(
null == existingJobRunId ? _self.existingJobRunId : existingJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,
  ));
}


}

/// @nodoc


class RetryJobResultNotAdmitted implements RetryJobResult {
  const RetryJobResultNotAdmitted(this.reason);


 final  RetryNotAdmittedReason reason;

/// Create a copy of RetryJobResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RetryJobResultNotAdmittedCopyWith<RetryJobResultNotAdmitted> get copyWith => _$RetryJobResultNotAdmittedCopyWithImpl<RetryJobResultNotAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryJobResultNotAdmitted&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'RetryJobResult.notAdmitted(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $RetryJobResultNotAdmittedCopyWith<$Res> implements $RetryJobResultCopyWith<$Res> {
  factory $RetryJobResultNotAdmittedCopyWith(RetryJobResultNotAdmitted value, $Res Function(RetryJobResultNotAdmitted) _then) = _$RetryJobResultNotAdmittedCopyWithImpl;
@useResult
$Res call({
 RetryNotAdmittedReason reason
});


$RetryNotAdmittedReasonCopyWith<$Res> get reason;

}
/// @nodoc
class _$RetryJobResultNotAdmittedCopyWithImpl<$Res>
    implements $RetryJobResultNotAdmittedCopyWith<$Res> {
  _$RetryJobResultNotAdmittedCopyWithImpl(this._self, this._then);

  final RetryJobResultNotAdmitted _self;
  final $Res Function(RetryJobResultNotAdmitted) _then;

/// Create a copy of RetryJobResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(RetryJobResultNotAdmitted(
null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as RetryNotAdmittedReason,
  ));
}

/// Create a copy of RetryJobResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RetryNotAdmittedReasonCopyWith<$Res> get reason {

  return $RetryNotAdmittedReasonCopyWith<$Res>(_self.reason, (value) {
    return _then(_self.copyWith(reason: value));
  });
}
}

/// @nodoc
mixin _$SourceEntriesChangeScope {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceEntriesChangeScope);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourceEntriesChangeScope()';
}


}

/// @nodoc
class $SourceEntriesChangeScopeCopyWith<$Res>  {
$SourceEntriesChangeScopeCopyWith(SourceEntriesChangeScope _, $Res Function(SourceEntriesChangeScope) __);
}


/// Adds pattern-matching-related methods to [SourceEntriesChangeScope].
extension SourceEntriesChangeScopePatterns on SourceEntriesChangeScope {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SourceEntriesChangeScopeRootChildren value)?  rootChildren,TResult Function( SourceEntriesChangeScopeEntryChildren value)?  entryChildren,TResult Function( SourceEntriesChangeScopeEntireRootHierarchy value)?  entireRootHierarchy,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SourceEntriesChangeScopeRootChildren() when rootChildren != null:
return rootChildren(_that);case SourceEntriesChangeScopeEntryChildren() when entryChildren != null:
return entryChildren(_that);case SourceEntriesChangeScopeEntireRootHierarchy() when entireRootHierarchy != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SourceEntriesChangeScopeRootChildren value)  rootChildren,required TResult Function( SourceEntriesChangeScopeEntryChildren value)  entryChildren,required TResult Function( SourceEntriesChangeScopeEntireRootHierarchy value)  entireRootHierarchy,}){
final _that = this;
switch (_that) {
case SourceEntriesChangeScopeRootChildren():
return rootChildren(_that);case SourceEntriesChangeScopeEntryChildren():
return entryChildren(_that);case SourceEntriesChangeScopeEntireRootHierarchy():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SourceEntriesChangeScopeRootChildren value)?  rootChildren,TResult? Function( SourceEntriesChangeScopeEntryChildren value)?  entryChildren,TResult? Function( SourceEntriesChangeScopeEntireRootHierarchy value)?  entireRootHierarchy,}){
final _that = this;
switch (_that) {
case SourceEntriesChangeScopeRootChildren() when rootChildren != null:
return rootChildren(_that);case SourceEntriesChangeScopeEntryChildren() when entryChildren != null:
return entryChildren(_that);case SourceEntriesChangeScopeEntireRootHierarchy() when entireRootHierarchy != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  rootChildren,TResult Function( SourceEntryId parentSourceEntryId)?  entryChildren,TResult Function()?  entireRootHierarchy,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SourceEntriesChangeScopeRootChildren() when rootChildren != null:
return rootChildren();case SourceEntriesChangeScopeEntryChildren() when entryChildren != null:
return entryChildren(_that.parentSourceEntryId);case SourceEntriesChangeScopeEntireRootHierarchy() when entireRootHierarchy != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  rootChildren,required TResult Function( SourceEntryId parentSourceEntryId)  entryChildren,required TResult Function()  entireRootHierarchy,}) {final _that = this;
switch (_that) {
case SourceEntriesChangeScopeRootChildren():
return rootChildren();case SourceEntriesChangeScopeEntryChildren():
return entryChildren(_that.parentSourceEntryId);case SourceEntriesChangeScopeEntireRootHierarchy():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  rootChildren,TResult? Function( SourceEntryId parentSourceEntryId)?  entryChildren,TResult? Function()?  entireRootHierarchy,}) {final _that = this;
switch (_that) {
case SourceEntriesChangeScopeRootChildren() when rootChildren != null:
return rootChildren();case SourceEntriesChangeScopeEntryChildren() when entryChildren != null:
return entryChildren(_that.parentSourceEntryId);case SourceEntriesChangeScopeEntireRootHierarchy() when entireRootHierarchy != null:
return entireRootHierarchy();case _:
  return null;

}
}

}

/// @nodoc


class SourceEntriesChangeScopeRootChildren implements SourceEntriesChangeScope {
  const SourceEntriesChangeScopeRootChildren();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceEntriesChangeScopeRootChildren);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourceEntriesChangeScope.rootChildren()';
}


}




/// @nodoc


class SourceEntriesChangeScopeEntryChildren implements SourceEntriesChangeScope {
  const SourceEntriesChangeScopeEntryChildren({required this.parentSourceEntryId});


 final  SourceEntryId parentSourceEntryId;

/// Create a copy of SourceEntriesChangeScope
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourceEntriesChangeScopeEntryChildrenCopyWith<SourceEntriesChangeScopeEntryChildren> get copyWith => _$SourceEntriesChangeScopeEntryChildrenCopyWithImpl<SourceEntriesChangeScopeEntryChildren>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceEntriesChangeScopeEntryChildren&&(identical(other.parentSourceEntryId, parentSourceEntryId) || other.parentSourceEntryId == parentSourceEntryId));
}


@override
int get hashCode => Object.hash(runtimeType,parentSourceEntryId);

@override
String toString() {
  return 'SourceEntriesChangeScope.entryChildren(parentSourceEntryId: $parentSourceEntryId)';
}


}

/// @nodoc
abstract mixin class $SourceEntriesChangeScopeEntryChildrenCopyWith<$Res> implements $SourceEntriesChangeScopeCopyWith<$Res> {
  factory $SourceEntriesChangeScopeEntryChildrenCopyWith(SourceEntriesChangeScopeEntryChildren value, $Res Function(SourceEntriesChangeScopeEntryChildren) _then) = _$SourceEntriesChangeScopeEntryChildrenCopyWithImpl;
@useResult
$Res call({
 SourceEntryId parentSourceEntryId
});




}
/// @nodoc
class _$SourceEntriesChangeScopeEntryChildrenCopyWithImpl<$Res>
    implements $SourceEntriesChangeScopeEntryChildrenCopyWith<$Res> {
  _$SourceEntriesChangeScopeEntryChildrenCopyWithImpl(this._self, this._then);

  final SourceEntriesChangeScopeEntryChildren _self;
  final $Res Function(SourceEntriesChangeScopeEntryChildren) _then;

/// Create a copy of SourceEntriesChangeScope
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? parentSourceEntryId = null,}) {
  return _then(SourceEntriesChangeScopeEntryChildren(
parentSourceEntryId: null == parentSourceEntryId ? _self.parentSourceEntryId : parentSourceEntryId // ignore: cast_nullable_to_non_nullable
as SourceEntryId,
  ));
}


}

/// @nodoc


class SourceEntriesChangeScopeEntireRootHierarchy implements SourceEntriesChangeScope {
  const SourceEntriesChangeScopeEntireRootHierarchy();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceEntriesChangeScopeEntireRootHierarchy);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SourceEntriesChangeScope.entireRootHierarchy()';
}


}




/// @nodoc
mixin _$SafeContextValue {

 Object get value;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SafeContextValue&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(value));

@override
String toString() {
  return 'SafeContextValue(value: $value)';
}


}

/// @nodoc
class $SafeContextValueCopyWith<$Res>  {
$SafeContextValueCopyWith(SafeContextValue _, $Res Function(SafeContextValue) __);
}


/// Adds pattern-matching-related methods to [SafeContextValue].
extension SafeContextValuePatterns on SafeContextValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SafeContextValueString value)?  string,TResult Function( SafeContextValueInteger value)?  integer,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SafeContextValueString() when string != null:
return string(_that);case SafeContextValueInteger() when integer != null:
return integer(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SafeContextValueString value)  string,required TResult Function( SafeContextValueInteger value)  integer,}){
final _that = this;
switch (_that) {
case SafeContextValueString():
return string(_that);case SafeContextValueInteger():
return integer(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SafeContextValueString value)?  string,TResult? Function( SafeContextValueInteger value)?  integer,}){
final _that = this;
switch (_that) {
case SafeContextValueString() when string != null:
return string(_that);case SafeContextValueInteger() when integer != null:
return integer(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String value)?  string,TResult Function( int value)?  integer,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SafeContextValueString() when string != null:
return string(_that.value);case SafeContextValueInteger() when integer != null:
return integer(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String value)  string,required TResult Function( int value)  integer,}) {final _that = this;
switch (_that) {
case SafeContextValueString():
return string(_that.value);case SafeContextValueInteger():
return integer(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String value)?  string,TResult? Function( int value)?  integer,}) {final _that = this;
switch (_that) {
case SafeContextValueString() when string != null:
return string(_that.value);case SafeContextValueInteger() when integer != null:
return integer(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class SafeContextValueString implements SafeContextValue {
  const SafeContextValueString(this.value);


@override final  String value;

/// Create a copy of SafeContextValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SafeContextValueStringCopyWith<SafeContextValueString> get copyWith => _$SafeContextValueStringCopyWithImpl<SafeContextValueString>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SafeContextValueString&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'SafeContextValue.string(value: $value)';
}


}

/// @nodoc
abstract mixin class $SafeContextValueStringCopyWith<$Res> implements $SafeContextValueCopyWith<$Res> {
  factory $SafeContextValueStringCopyWith(SafeContextValueString value, $Res Function(SafeContextValueString) _then) = _$SafeContextValueStringCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$SafeContextValueStringCopyWithImpl<$Res>
    implements $SafeContextValueStringCopyWith<$Res> {
  _$SafeContextValueStringCopyWithImpl(this._self, this._then);

  final SafeContextValueString _self;
  final $Res Function(SafeContextValueString) _then;

/// Create a copy of SafeContextValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(SafeContextValueString(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SafeContextValueInteger implements SafeContextValue {
  const SafeContextValueInteger(this.value);


@override final  int value;

/// Create a copy of SafeContextValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SafeContextValueIntegerCopyWith<SafeContextValueInteger> get copyWith => _$SafeContextValueIntegerCopyWithImpl<SafeContextValueInteger>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SafeContextValueInteger&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'SafeContextValue.integer(value: $value)';
}


}

/// @nodoc
abstract mixin class $SafeContextValueIntegerCopyWith<$Res> implements $SafeContextValueCopyWith<$Res> {
  factory $SafeContextValueIntegerCopyWith(SafeContextValueInteger value, $Res Function(SafeContextValueInteger) _then) = _$SafeContextValueIntegerCopyWithImpl;
@useResult
$Res call({
 int value
});




}
/// @nodoc
class _$SafeContextValueIntegerCopyWithImpl<$Res>
    implements $SafeContextValueIntegerCopyWith<$Res> {
  _$SafeContextValueIntegerCopyWithImpl(this._self, this._then);

  final SafeContextValueInteger _self;
  final $Res Function(SafeContextValueInteger) _then;

/// Create a copy of SafeContextValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(SafeContextValueInteger(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ClientApplicationError {

 ErrorCode get code; ErrorCategory get category; ApplicationSeverity get severity; Recoverability get recoverability; RetryPolicy get retryPolicy; MessageKey get messageKey; TraceId get traceId; List<SafeContextEntry> get safeContext;
/// Create a copy of ClientApplicationError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClientApplicationErrorCopyWith<ClientApplicationError> get copyWith => _$ClientApplicationErrorCopyWithImpl<ClientApplicationError>(this as ClientApplicationError, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientApplicationError&&(identical(other.code, code) || other.code == code)&&(identical(other.category, category) || other.category == category)&&(identical(other.severity, severity) || other.severity == severity)&&(identical(other.recoverability, recoverability) || other.recoverability == recoverability)&&(identical(other.retryPolicy, retryPolicy) || other.retryPolicy == retryPolicy)&&(identical(other.messageKey, messageKey) || other.messageKey == messageKey)&&(identical(other.traceId, traceId) || other.traceId == traceId)&&const DeepCollectionEquality().equals(other.safeContext, safeContext));
}


@override
int get hashCode => Object.hash(runtimeType,code,category,severity,recoverability,retryPolicy,messageKey,traceId,const DeepCollectionEquality().hash(safeContext));

@override
String toString() {
  return 'ClientApplicationError(code: $code, category: $category, severity: $severity, recoverability: $recoverability, retryPolicy: $retryPolicy, messageKey: $messageKey, traceId: $traceId, safeContext: $safeContext)';
}


}

/// @nodoc
abstract mixin class $ClientApplicationErrorCopyWith<$Res>  {
  factory $ClientApplicationErrorCopyWith(ClientApplicationError value, $Res Function(ClientApplicationError) _then) = _$ClientApplicationErrorCopyWithImpl;
@useResult
$Res call({
 ErrorCode code, ErrorCategory category, ApplicationSeverity severity, Recoverability recoverability, RetryPolicy retryPolicy, MessageKey messageKey, TraceId traceId, List<SafeContextEntry> safeContext
});




}
/// @nodoc
class _$ClientApplicationErrorCopyWithImpl<$Res>
    implements $ClientApplicationErrorCopyWith<$Res> {
  _$ClientApplicationErrorCopyWithImpl(this._self, this._then);

  final ClientApplicationError _self;
  final $Res Function(ClientApplicationError) _then;

/// Create a copy of ClientApplicationError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? category = null,Object? severity = null,Object? recoverability = null,Object? retryPolicy = null,Object? messageKey = null,Object? traceId = null,Object? safeContext = null,}) {
  return _then(_self.copyWith(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as ErrorCode,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as ErrorCategory,severity: null == severity ? _self.severity : severity // ignore: cast_nullable_to_non_nullable
as ApplicationSeverity,recoverability: null == recoverability ? _self.recoverability : recoverability // ignore: cast_nullable_to_non_nullable
as Recoverability,retryPolicy: null == retryPolicy ? _self.retryPolicy : retryPolicy // ignore: cast_nullable_to_non_nullable
as RetryPolicy,messageKey: null == messageKey ? _self.messageKey : messageKey // ignore: cast_nullable_to_non_nullable
as MessageKey,traceId: null == traceId ? _self.traceId : traceId // ignore: cast_nullable_to_non_nullable
as TraceId,safeContext: null == safeContext ? _self.safeContext : safeContext // ignore: cast_nullable_to_non_nullable
as List<SafeContextEntry>,
  ));
}

}


/// Adds pattern-matching-related methods to [ClientApplicationError].
extension ClientApplicationErrorPatterns on ClientApplicationError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ClientApplicationError value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ClientApplicationError() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ClientApplicationError value)  $default,){
final _that = this;
switch (_that) {
case _ClientApplicationError():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ClientApplicationError value)?  $default,){
final _that = this;
switch (_that) {
case _ClientApplicationError() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ErrorCode code,  ErrorCategory category,  ApplicationSeverity severity,  Recoverability recoverability,  RetryPolicy retryPolicy,  MessageKey messageKey,  TraceId traceId,  List<SafeContextEntry> safeContext)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ClientApplicationError() when $default != null:
return $default(_that.code,_that.category,_that.severity,_that.recoverability,_that.retryPolicy,_that.messageKey,_that.traceId,_that.safeContext);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ErrorCode code,  ErrorCategory category,  ApplicationSeverity severity,  Recoverability recoverability,  RetryPolicy retryPolicy,  MessageKey messageKey,  TraceId traceId,  List<SafeContextEntry> safeContext)  $default,) {final _that = this;
switch (_that) {
case _ClientApplicationError():
return $default(_that.code,_that.category,_that.severity,_that.recoverability,_that.retryPolicy,_that.messageKey,_that.traceId,_that.safeContext);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ErrorCode code,  ErrorCategory category,  ApplicationSeverity severity,  Recoverability recoverability,  RetryPolicy retryPolicy,  MessageKey messageKey,  TraceId traceId,  List<SafeContextEntry> safeContext)?  $default,) {final _that = this;
switch (_that) {
case _ClientApplicationError() when $default != null:
return $default(_that.code,_that.category,_that.severity,_that.recoverability,_that.retryPolicy,_that.messageKey,_that.traceId,_that.safeContext);case _:
  return null;

}
}

}

/// @nodoc


class _ClientApplicationError implements ClientApplicationError {
  const _ClientApplicationError({required this.code, required this.category, required this.severity, required this.recoverability, required this.retryPolicy, required this.messageKey, required this.traceId, required final  List<SafeContextEntry> safeContext}): _safeContext = safeContext;


@override final  ErrorCode code;
@override final  ErrorCategory category;
@override final  ApplicationSeverity severity;
@override final  Recoverability recoverability;
@override final  RetryPolicy retryPolicy;
@override final  MessageKey messageKey;
@override final  TraceId traceId;
 final  List<SafeContextEntry> _safeContext;
@override List<SafeContextEntry> get safeContext {
  if (_safeContext is EqualUnmodifiableListView) return _safeContext;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_safeContext);
}


/// Create a copy of ClientApplicationError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ClientApplicationErrorCopyWith<_ClientApplicationError> get copyWith => __$ClientApplicationErrorCopyWithImpl<_ClientApplicationError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ClientApplicationError&&(identical(other.code, code) || other.code == code)&&(identical(other.category, category) || other.category == category)&&(identical(other.severity, severity) || other.severity == severity)&&(identical(other.recoverability, recoverability) || other.recoverability == recoverability)&&(identical(other.retryPolicy, retryPolicy) || other.retryPolicy == retryPolicy)&&(identical(other.messageKey, messageKey) || other.messageKey == messageKey)&&(identical(other.traceId, traceId) || other.traceId == traceId)&&const DeepCollectionEquality().equals(other._safeContext, _safeContext));
}


@override
int get hashCode => Object.hash(runtimeType,code,category,severity,recoverability,retryPolicy,messageKey,traceId,const DeepCollectionEquality().hash(_safeContext));

@override
String toString() {
  return 'ClientApplicationError(code: $code, category: $category, severity: $severity, recoverability: $recoverability, retryPolicy: $retryPolicy, messageKey: $messageKey, traceId: $traceId, safeContext: $safeContext)';
}


}

/// @nodoc
abstract mixin class _$ClientApplicationErrorCopyWith<$Res> implements $ClientApplicationErrorCopyWith<$Res> {
  factory _$ClientApplicationErrorCopyWith(_ClientApplicationError value, $Res Function(_ClientApplicationError) _then) = __$ClientApplicationErrorCopyWithImpl;
@override @useResult
$Res call({
 ErrorCode code, ErrorCategory category, ApplicationSeverity severity, Recoverability recoverability, RetryPolicy retryPolicy, MessageKey messageKey, TraceId traceId, List<SafeContextEntry> safeContext
});




}
/// @nodoc
class __$ClientApplicationErrorCopyWithImpl<$Res>
    implements _$ClientApplicationErrorCopyWith<$Res> {
  __$ClientApplicationErrorCopyWithImpl(this._self, this._then);

  final _ClientApplicationError _self;
  final $Res Function(_ClientApplicationError) _then;

/// Create a copy of ClientApplicationError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? category = null,Object? severity = null,Object? recoverability = null,Object? retryPolicy = null,Object? messageKey = null,Object? traceId = null,Object? safeContext = null,}) {
  return _then(_ClientApplicationError(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as ErrorCode,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as ErrorCategory,severity: null == severity ? _self.severity : severity // ignore: cast_nullable_to_non_nullable
as ApplicationSeverity,recoverability: null == recoverability ? _self.recoverability : recoverability // ignore: cast_nullable_to_non_nullable
as Recoverability,retryPolicy: null == retryPolicy ? _self.retryPolicy : retryPolicy // ignore: cast_nullable_to_non_nullable
as RetryPolicy,messageKey: null == messageKey ? _self.messageKey : messageKey // ignore: cast_nullable_to_non_nullable
as MessageKey,traceId: null == traceId ? _self.traceId : traceId // ignore: cast_nullable_to_non_nullable
as TraceId,safeContext: null == safeContext ? _self._safeContext : safeContext // ignore: cast_nullable_to_non_nullable
as List<SafeContextEntry>,
  ));
}


}

/// @nodoc
mixin _$SafeContextEntry {

 SafeContextField get field; SafeContextValue get value;
/// Create a copy of SafeContextEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SafeContextEntryCopyWith<SafeContextEntry> get copyWith => _$SafeContextEntryCopyWithImpl<SafeContextEntry>(this as SafeContextEntry, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SafeContextEntry&&(identical(other.field, field) || other.field == field)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,field,value);

@override
String toString() {
  return 'SafeContextEntry(field: $field, value: $value)';
}


}

/// @nodoc
abstract mixin class $SafeContextEntryCopyWith<$Res>  {
  factory $SafeContextEntryCopyWith(SafeContextEntry value, $Res Function(SafeContextEntry) _then) = _$SafeContextEntryCopyWithImpl;
@useResult
$Res call({
 SafeContextField field, SafeContextValue value
});


$SafeContextValueCopyWith<$Res> get value;

}
/// @nodoc
class _$SafeContextEntryCopyWithImpl<$Res>
    implements $SafeContextEntryCopyWith<$Res> {
  _$SafeContextEntryCopyWithImpl(this._self, this._then);

  final SafeContextEntry _self;
  final $Res Function(SafeContextEntry) _then;

/// Create a copy of SafeContextEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? field = null,Object? value = null,}) {
  return _then(_self.copyWith(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as SafeContextField,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SafeContextValue,
  ));
}
/// Create a copy of SafeContextEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SafeContextValueCopyWith<$Res> get value {

  return $SafeContextValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [SafeContextEntry].
extension SafeContextEntryPatterns on SafeContextEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SafeContextEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SafeContextEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SafeContextEntry value)  $default,){
final _that = this;
switch (_that) {
case _SafeContextEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SafeContextEntry value)?  $default,){
final _that = this;
switch (_that) {
case _SafeContextEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SafeContextField field,  SafeContextValue value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SafeContextEntry() when $default != null:
return $default(_that.field,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SafeContextField field,  SafeContextValue value)  $default,) {final _that = this;
switch (_that) {
case _SafeContextEntry():
return $default(_that.field,_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SafeContextField field,  SafeContextValue value)?  $default,) {final _that = this;
switch (_that) {
case _SafeContextEntry() when $default != null:
return $default(_that.field,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _SafeContextEntry implements SafeContextEntry {
  const _SafeContextEntry({required this.field, required this.value});


@override final  SafeContextField field;
@override final  SafeContextValue value;

/// Create a copy of SafeContextEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SafeContextEntryCopyWith<_SafeContextEntry> get copyWith => __$SafeContextEntryCopyWithImpl<_SafeContextEntry>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SafeContextEntry&&(identical(other.field, field) || other.field == field)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,field,value);

@override
String toString() {
  return 'SafeContextEntry(field: $field, value: $value)';
}


}

/// @nodoc
abstract mixin class _$SafeContextEntryCopyWith<$Res> implements $SafeContextEntryCopyWith<$Res> {
  factory _$SafeContextEntryCopyWith(_SafeContextEntry value, $Res Function(_SafeContextEntry) _then) = __$SafeContextEntryCopyWithImpl;
@override @useResult
$Res call({
 SafeContextField field, SafeContextValue value
});


@override $SafeContextValueCopyWith<$Res> get value;

}
/// @nodoc
class __$SafeContextEntryCopyWithImpl<$Res>
    implements _$SafeContextEntryCopyWith<$Res> {
  __$SafeContextEntryCopyWithImpl(this._self, this._then);

  final _SafeContextEntry _self;
  final $Res Function(_SafeContextEntry) _then;

/// Create a copy of SafeContextEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field = null,Object? value = null,}) {
  return _then(_SafeContextEntry(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as SafeContextField,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SafeContextValue,
  ));
}

/// Create a copy of SafeContextEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SafeContextValueCopyWith<$Res> get value {

  return $SafeContextValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$RecoveryAction {

 RecoveryActionKind get kind;
/// Create a copy of RecoveryAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryActionCopyWith<RecoveryAction> get copyWith => _$RecoveryActionCopyWithImpl<RecoveryAction>(this as RecoveryAction, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryAction&&(identical(other.kind, kind) || other.kind == kind));
}


@override
int get hashCode => Object.hash(runtimeType,kind);

@override
String toString() {
  return 'RecoveryAction(kind: $kind)';
}


}

/// @nodoc
abstract mixin class $RecoveryActionCopyWith<$Res>  {
  factory $RecoveryActionCopyWith(RecoveryAction value, $Res Function(RecoveryAction) _then) = _$RecoveryActionCopyWithImpl;
@useResult
$Res call({
 RecoveryActionKind kind
});




}
/// @nodoc
class _$RecoveryActionCopyWithImpl<$Res>
    implements $RecoveryActionCopyWith<$Res> {
  _$RecoveryActionCopyWithImpl(this._self, this._then);

  final RecoveryAction _self;
  final $Res Function(RecoveryAction) _then;

/// Create a copy of RecoveryAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,}) {
  return _then(_self.copyWith(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as RecoveryActionKind,
  ));
}

}


/// Adds pattern-matching-related methods to [RecoveryAction].
extension RecoveryActionPatterns on RecoveryAction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecoveryAction value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecoveryAction() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecoveryAction value)  $default,){
final _that = this;
switch (_that) {
case _RecoveryAction():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecoveryAction value)?  $default,){
final _that = this;
switch (_that) {
case _RecoveryAction() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RecoveryActionKind kind)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecoveryAction() when $default != null:
return $default(_that.kind);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RecoveryActionKind kind)  $default,) {final _that = this;
switch (_that) {
case _RecoveryAction():
return $default(_that.kind);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RecoveryActionKind kind)?  $default,) {final _that = this;
switch (_that) {
case _RecoveryAction() when $default != null:
return $default(_that.kind);case _:
  return null;

}
}

}

/// @nodoc


class _RecoveryAction implements RecoveryAction {
  const _RecoveryAction({required this.kind});


@override final  RecoveryActionKind kind;

/// Create a copy of RecoveryAction
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecoveryActionCopyWith<_RecoveryAction> get copyWith => __$RecoveryActionCopyWithImpl<_RecoveryAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecoveryAction&&(identical(other.kind, kind) || other.kind == kind));
}


@override
int get hashCode => Object.hash(runtimeType,kind);

@override
String toString() {
  return 'RecoveryAction(kind: $kind)';
}


}

/// @nodoc
abstract mixin class _$RecoveryActionCopyWith<$Res> implements $RecoveryActionCopyWith<$Res> {
  factory _$RecoveryActionCopyWith(_RecoveryAction value, $Res Function(_RecoveryAction) _then) = __$RecoveryActionCopyWithImpl;
@override @useResult
$Res call({
 RecoveryActionKind kind
});




}
/// @nodoc
class __$RecoveryActionCopyWithImpl<$Res>
    implements _$RecoveryActionCopyWith<$Res> {
  __$RecoveryActionCopyWithImpl(this._self, this._then);

  final _RecoveryAction _self;
  final $Res Function(_RecoveryAction) _then;

/// Create a copy of RecoveryAction
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,}) {
  return _then(_RecoveryAction(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as RecoveryActionKind,
  ));
}


}

/// @nodoc
mixin _$StartupFailure {

 StartupPhase get phase; ClientApplicationError get error; List<RecoveryAction> get recoveryActions;
/// Create a copy of StartupFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupFailureCopyWith<StartupFailure> get copyWith => _$StartupFailureCopyWithImpl<StartupFailure>(this as StartupFailure, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupFailure&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.error, error) || other.error == error)&&const DeepCollectionEquality().equals(other.recoveryActions, recoveryActions));
}


@override
int get hashCode => Object.hash(runtimeType,phase,error,const DeepCollectionEquality().hash(recoveryActions));

@override
String toString() {
  return 'StartupFailure(phase: $phase, error: $error, recoveryActions: $recoveryActions)';
}


}

/// @nodoc
abstract mixin class $StartupFailureCopyWith<$Res>  {
  factory $StartupFailureCopyWith(StartupFailure value, $Res Function(StartupFailure) _then) = _$StartupFailureCopyWithImpl;
@useResult
$Res call({
 StartupPhase phase, ClientApplicationError error, List<RecoveryAction> recoveryActions
});


$ClientApplicationErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$StartupFailureCopyWithImpl<$Res>
    implements $StartupFailureCopyWith<$Res> {
  _$StartupFailureCopyWithImpl(this._self, this._then);

  final StartupFailure _self;
  final $Res Function(StartupFailure) _then;

/// Create a copy of StartupFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = null,Object? error = null,Object? recoveryActions = null,}) {
  return _then(_self.copyWith(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as StartupPhase,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ClientApplicationError,recoveryActions: null == recoveryActions ? _self.recoveryActions : recoveryActions // ignore: cast_nullable_to_non_nullable
as List<RecoveryAction>,
  ));
}
/// Create a copy of StartupFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientApplicationErrorCopyWith<$Res> get error {

  return $ClientApplicationErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [StartupFailure].
extension StartupFailurePatterns on StartupFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartupFailure value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartupFailure() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartupFailure value)  $default,){
final _that = this;
switch (_that) {
case _StartupFailure():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartupFailure value)?  $default,){
final _that = this;
switch (_that) {
case _StartupFailure() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( StartupPhase phase,  ClientApplicationError error,  List<RecoveryAction> recoveryActions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartupFailure() when $default != null:
return $default(_that.phase,_that.error,_that.recoveryActions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( StartupPhase phase,  ClientApplicationError error,  List<RecoveryAction> recoveryActions)  $default,) {final _that = this;
switch (_that) {
case _StartupFailure():
return $default(_that.phase,_that.error,_that.recoveryActions);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( StartupPhase phase,  ClientApplicationError error,  List<RecoveryAction> recoveryActions)?  $default,) {final _that = this;
switch (_that) {
case _StartupFailure() when $default != null:
return $default(_that.phase,_that.error,_that.recoveryActions);case _:
  return null;

}
}

}

/// @nodoc


class _StartupFailure implements StartupFailure {
  const _StartupFailure({required this.phase, required this.error, required final  List<RecoveryAction> recoveryActions}): _recoveryActions = recoveryActions;


@override final  StartupPhase phase;
@override final  ClientApplicationError error;
 final  List<RecoveryAction> _recoveryActions;
@override List<RecoveryAction> get recoveryActions {
  if (_recoveryActions is EqualUnmodifiableListView) return _recoveryActions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_recoveryActions);
}


/// Create a copy of StartupFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartupFailureCopyWith<_StartupFailure> get copyWith => __$StartupFailureCopyWithImpl<_StartupFailure>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartupFailure&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.error, error) || other.error == error)&&const DeepCollectionEquality().equals(other._recoveryActions, _recoveryActions));
}


@override
int get hashCode => Object.hash(runtimeType,phase,error,const DeepCollectionEquality().hash(_recoveryActions));

@override
String toString() {
  return 'StartupFailure(phase: $phase, error: $error, recoveryActions: $recoveryActions)';
}


}

/// @nodoc
abstract mixin class _$StartupFailureCopyWith<$Res> implements $StartupFailureCopyWith<$Res> {
  factory _$StartupFailureCopyWith(_StartupFailure value, $Res Function(_StartupFailure) _then) = __$StartupFailureCopyWithImpl;
@override @useResult
$Res call({
 StartupPhase phase, ClientApplicationError error, List<RecoveryAction> recoveryActions
});


@override $ClientApplicationErrorCopyWith<$Res> get error;

}
/// @nodoc
class __$StartupFailureCopyWithImpl<$Res>
    implements _$StartupFailureCopyWith<$Res> {
  __$StartupFailureCopyWithImpl(this._self, this._then);

  final _StartupFailure _self;
  final $Res Function(_StartupFailure) _then;

/// Create a copy of StartupFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? error = null,Object? recoveryActions = null,}) {
  return _then(_StartupFailure(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as StartupPhase,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ClientApplicationError,recoveryActions: null == recoveryActions ? _self._recoveryActions : recoveryActions // ignore: cast_nullable_to_non_nullable
as List<RecoveryAction>,
  ));
}

/// Create a copy of StartupFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientApplicationErrorCopyWith<$Res> get error {

  return $ClientApplicationErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$RuntimeState {

 RuntimeInstanceId get runtimeInstanceId;
/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeStateCopyWith<RuntimeState> get copyWith => _$RuntimeStateCopyWithImpl<RuntimeState>(this as RuntimeState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeState&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId);

@override
String toString() {
  return 'RuntimeState(runtimeInstanceId: $runtimeInstanceId)';
}


}

/// @nodoc
abstract mixin class $RuntimeStateCopyWith<$Res>  {
  factory $RuntimeStateCopyWith(RuntimeState value, $Res Function(RuntimeState) _then) = _$RuntimeStateCopyWithImpl;
@useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId
});




}
/// @nodoc
class _$RuntimeStateCopyWithImpl<$Res>
    implements $RuntimeStateCopyWith<$Res> {
  _$RuntimeStateCopyWithImpl(this._self, this._then);

  final RuntimeState _self;
  final $Res Function(RuntimeState) _then;

/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? runtimeInstanceId = null,}) {
  return _then(_self.copyWith(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,
  ));
}

}


/// Adds pattern-matching-related methods to [RuntimeState].
extension RuntimeStatePatterns on RuntimeState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RuntimeStateUninitialized value)?  uninitialized,TResult Function( RuntimeStateStarting value)?  starting,TResult Function( RuntimeStateReady value)?  ready,TResult Function( RuntimeStateStartupFailed value)?  startupFailed,TResult Function( RuntimeStateShuttingDown value)?  shuttingDown,TResult Function( RuntimeStateStopped value)?  stopped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RuntimeStateUninitialized() when uninitialized != null:
return uninitialized(_that);case RuntimeStateStarting() when starting != null:
return starting(_that);case RuntimeStateReady() when ready != null:
return ready(_that);case RuntimeStateStartupFailed() when startupFailed != null:
return startupFailed(_that);case RuntimeStateShuttingDown() when shuttingDown != null:
return shuttingDown(_that);case RuntimeStateStopped() when stopped != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RuntimeStateUninitialized value)  uninitialized,required TResult Function( RuntimeStateStarting value)  starting,required TResult Function( RuntimeStateReady value)  ready,required TResult Function( RuntimeStateStartupFailed value)  startupFailed,required TResult Function( RuntimeStateShuttingDown value)  shuttingDown,required TResult Function( RuntimeStateStopped value)  stopped,}){
final _that = this;
switch (_that) {
case RuntimeStateUninitialized():
return uninitialized(_that);case RuntimeStateStarting():
return starting(_that);case RuntimeStateReady():
return ready(_that);case RuntimeStateStartupFailed():
return startupFailed(_that);case RuntimeStateShuttingDown():
return shuttingDown(_that);case RuntimeStateStopped():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RuntimeStateUninitialized value)?  uninitialized,TResult? Function( RuntimeStateStarting value)?  starting,TResult? Function( RuntimeStateReady value)?  ready,TResult? Function( RuntimeStateStartupFailed value)?  startupFailed,TResult? Function( RuntimeStateShuttingDown value)?  shuttingDown,TResult? Function( RuntimeStateStopped value)?  stopped,}){
final _that = this;
switch (_that) {
case RuntimeStateUninitialized() when uninitialized != null:
return uninitialized(_that);case RuntimeStateStarting() when starting != null:
return starting(_that);case RuntimeStateReady() when ready != null:
return ready(_that);case RuntimeStateStartupFailed() when startupFailed != null:
return startupFailed(_that);case RuntimeStateShuttingDown() when shuttingDown != null:
return shuttingDown(_that);case RuntimeStateStopped() when stopped != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( RuntimeInstanceId runtimeInstanceId)?  uninitialized,TResult Function( RuntimeInstanceId runtimeInstanceId,  StartupPhase? phase)?  starting,TResult Function( RuntimeInstanceId runtimeInstanceId)?  ready,TResult Function( RuntimeInstanceId runtimeInstanceId,  StartupFailure failure)?  startupFailed,TResult Function( RuntimeInstanceId runtimeInstanceId)?  shuttingDown,TResult Function( RuntimeInstanceId runtimeInstanceId)?  stopped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RuntimeStateUninitialized() when uninitialized != null:
return uninitialized(_that.runtimeInstanceId);case RuntimeStateStarting() when starting != null:
return starting(_that.runtimeInstanceId,_that.phase);case RuntimeStateReady() when ready != null:
return ready(_that.runtimeInstanceId);case RuntimeStateStartupFailed() when startupFailed != null:
return startupFailed(_that.runtimeInstanceId,_that.failure);case RuntimeStateShuttingDown() when shuttingDown != null:
return shuttingDown(_that.runtimeInstanceId);case RuntimeStateStopped() when stopped != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( RuntimeInstanceId runtimeInstanceId)  uninitialized,required TResult Function( RuntimeInstanceId runtimeInstanceId,  StartupPhase? phase)  starting,required TResult Function( RuntimeInstanceId runtimeInstanceId)  ready,required TResult Function( RuntimeInstanceId runtimeInstanceId,  StartupFailure failure)  startupFailed,required TResult Function( RuntimeInstanceId runtimeInstanceId)  shuttingDown,required TResult Function( RuntimeInstanceId runtimeInstanceId)  stopped,}) {final _that = this;
switch (_that) {
case RuntimeStateUninitialized():
return uninitialized(_that.runtimeInstanceId);case RuntimeStateStarting():
return starting(_that.runtimeInstanceId,_that.phase);case RuntimeStateReady():
return ready(_that.runtimeInstanceId);case RuntimeStateStartupFailed():
return startupFailed(_that.runtimeInstanceId,_that.failure);case RuntimeStateShuttingDown():
return shuttingDown(_that.runtimeInstanceId);case RuntimeStateStopped():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( RuntimeInstanceId runtimeInstanceId)?  uninitialized,TResult? Function( RuntimeInstanceId runtimeInstanceId,  StartupPhase? phase)?  starting,TResult? Function( RuntimeInstanceId runtimeInstanceId)?  ready,TResult? Function( RuntimeInstanceId runtimeInstanceId,  StartupFailure failure)?  startupFailed,TResult? Function( RuntimeInstanceId runtimeInstanceId)?  shuttingDown,TResult? Function( RuntimeInstanceId runtimeInstanceId)?  stopped,}) {final _that = this;
switch (_that) {
case RuntimeStateUninitialized() when uninitialized != null:
return uninitialized(_that.runtimeInstanceId);case RuntimeStateStarting() when starting != null:
return starting(_that.runtimeInstanceId,_that.phase);case RuntimeStateReady() when ready != null:
return ready(_that.runtimeInstanceId);case RuntimeStateStartupFailed() when startupFailed != null:
return startupFailed(_that.runtimeInstanceId,_that.failure);case RuntimeStateShuttingDown() when shuttingDown != null:
return shuttingDown(_that.runtimeInstanceId);case RuntimeStateStopped() when stopped != null:
return stopped(_that.runtimeInstanceId);case _:
  return null;

}
}

}

/// @nodoc


class RuntimeStateUninitialized implements RuntimeState {
  const RuntimeStateUninitialized({required this.runtimeInstanceId});


@override final  RuntimeInstanceId runtimeInstanceId;

/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeStateUninitializedCopyWith<RuntimeStateUninitialized> get copyWith => _$RuntimeStateUninitializedCopyWithImpl<RuntimeStateUninitialized>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeStateUninitialized&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId);

@override
String toString() {
  return 'RuntimeState.uninitialized(runtimeInstanceId: $runtimeInstanceId)';
}


}

/// @nodoc
abstract mixin class $RuntimeStateUninitializedCopyWith<$Res> implements $RuntimeStateCopyWith<$Res> {
  factory $RuntimeStateUninitializedCopyWith(RuntimeStateUninitialized value, $Res Function(RuntimeStateUninitialized) _then) = _$RuntimeStateUninitializedCopyWithImpl;
@override @useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId
});




}
/// @nodoc
class _$RuntimeStateUninitializedCopyWithImpl<$Res>
    implements $RuntimeStateUninitializedCopyWith<$Res> {
  _$RuntimeStateUninitializedCopyWithImpl(this._self, this._then);

  final RuntimeStateUninitialized _self;
  final $Res Function(RuntimeStateUninitialized) _then;

/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,}) {
  return _then(RuntimeStateUninitialized(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,
  ));
}


}

/// @nodoc


class RuntimeStateStarting implements RuntimeState {
  const RuntimeStateStarting({required this.runtimeInstanceId, this.phase});


@override final  RuntimeInstanceId runtimeInstanceId;
 final  StartupPhase? phase;

/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeStateStartingCopyWith<RuntimeStateStarting> get copyWith => _$RuntimeStateStartingCopyWithImpl<RuntimeStateStarting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeStateStarting&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId)&&(identical(other.phase, phase) || other.phase == phase));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId,phase);

@override
String toString() {
  return 'RuntimeState.starting(runtimeInstanceId: $runtimeInstanceId, phase: $phase)';
}


}

/// @nodoc
abstract mixin class $RuntimeStateStartingCopyWith<$Res> implements $RuntimeStateCopyWith<$Res> {
  factory $RuntimeStateStartingCopyWith(RuntimeStateStarting value, $Res Function(RuntimeStateStarting) _then) = _$RuntimeStateStartingCopyWithImpl;
@override @useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId, StartupPhase? phase
});




}
/// @nodoc
class _$RuntimeStateStartingCopyWithImpl<$Res>
    implements $RuntimeStateStartingCopyWith<$Res> {
  _$RuntimeStateStartingCopyWithImpl(this._self, this._then);

  final RuntimeStateStarting _self;
  final $Res Function(RuntimeStateStarting) _then;

/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,Object? phase = freezed,}) {
  return _then(RuntimeStateStarting(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,phase: freezed == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as StartupPhase?,
  ));
}


}

/// @nodoc


class RuntimeStateReady implements RuntimeState {
  const RuntimeStateReady({required this.runtimeInstanceId});


@override final  RuntimeInstanceId runtimeInstanceId;

/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeStateReadyCopyWith<RuntimeStateReady> get copyWith => _$RuntimeStateReadyCopyWithImpl<RuntimeStateReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeStateReady&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId);

@override
String toString() {
  return 'RuntimeState.ready(runtimeInstanceId: $runtimeInstanceId)';
}


}

/// @nodoc
abstract mixin class $RuntimeStateReadyCopyWith<$Res> implements $RuntimeStateCopyWith<$Res> {
  factory $RuntimeStateReadyCopyWith(RuntimeStateReady value, $Res Function(RuntimeStateReady) _then) = _$RuntimeStateReadyCopyWithImpl;
@override @useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId
});




}
/// @nodoc
class _$RuntimeStateReadyCopyWithImpl<$Res>
    implements $RuntimeStateReadyCopyWith<$Res> {
  _$RuntimeStateReadyCopyWithImpl(this._self, this._then);

  final RuntimeStateReady _self;
  final $Res Function(RuntimeStateReady) _then;

/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,}) {
  return _then(RuntimeStateReady(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,
  ));
}


}

/// @nodoc


class RuntimeStateStartupFailed implements RuntimeState {
  const RuntimeStateStartupFailed({required this.runtimeInstanceId, required this.failure});


@override final  RuntimeInstanceId runtimeInstanceId;
 final  StartupFailure failure;

/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeStateStartupFailedCopyWith<RuntimeStateStartupFailed> get copyWith => _$RuntimeStateStartupFailedCopyWithImpl<RuntimeStateStartupFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeStateStartupFailed&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId,failure);

@override
String toString() {
  return 'RuntimeState.startupFailed(runtimeInstanceId: $runtimeInstanceId, failure: $failure)';
}


}

/// @nodoc
abstract mixin class $RuntimeStateStartupFailedCopyWith<$Res> implements $RuntimeStateCopyWith<$Res> {
  factory $RuntimeStateStartupFailedCopyWith(RuntimeStateStartupFailed value, $Res Function(RuntimeStateStartupFailed) _then) = _$RuntimeStateStartupFailedCopyWithImpl;
@override @useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId, StartupFailure failure
});


$StartupFailureCopyWith<$Res> get failure;

}
/// @nodoc
class _$RuntimeStateStartupFailedCopyWithImpl<$Res>
    implements $RuntimeStateStartupFailedCopyWith<$Res> {
  _$RuntimeStateStartupFailedCopyWithImpl(this._self, this._then);

  final RuntimeStateStartupFailed _self;
  final $Res Function(RuntimeStateStartupFailed) _then;

/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,Object? failure = null,}) {
  return _then(RuntimeStateStartupFailed(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as StartupFailure,
  ));
}

/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartupFailureCopyWith<$Res> get failure {

  return $StartupFailureCopyWith<$Res>(_self.failure, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}

/// @nodoc


class RuntimeStateShuttingDown implements RuntimeState {
  const RuntimeStateShuttingDown({required this.runtimeInstanceId});


@override final  RuntimeInstanceId runtimeInstanceId;

/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeStateShuttingDownCopyWith<RuntimeStateShuttingDown> get copyWith => _$RuntimeStateShuttingDownCopyWithImpl<RuntimeStateShuttingDown>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeStateShuttingDown&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId);

@override
String toString() {
  return 'RuntimeState.shuttingDown(runtimeInstanceId: $runtimeInstanceId)';
}


}

/// @nodoc
abstract mixin class $RuntimeStateShuttingDownCopyWith<$Res> implements $RuntimeStateCopyWith<$Res> {
  factory $RuntimeStateShuttingDownCopyWith(RuntimeStateShuttingDown value, $Res Function(RuntimeStateShuttingDown) _then) = _$RuntimeStateShuttingDownCopyWithImpl;
@override @useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId
});




}
/// @nodoc
class _$RuntimeStateShuttingDownCopyWithImpl<$Res>
    implements $RuntimeStateShuttingDownCopyWith<$Res> {
  _$RuntimeStateShuttingDownCopyWithImpl(this._self, this._then);

  final RuntimeStateShuttingDown _self;
  final $Res Function(RuntimeStateShuttingDown) _then;

/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,}) {
  return _then(RuntimeStateShuttingDown(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,
  ));
}


}

/// @nodoc


class RuntimeStateStopped implements RuntimeState {
  const RuntimeStateStopped({required this.runtimeInstanceId});


@override final  RuntimeInstanceId runtimeInstanceId;

/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeStateStoppedCopyWith<RuntimeStateStopped> get copyWith => _$RuntimeStateStoppedCopyWithImpl<RuntimeStateStopped>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeStateStopped&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId);

@override
String toString() {
  return 'RuntimeState.stopped(runtimeInstanceId: $runtimeInstanceId)';
}


}

/// @nodoc
abstract mixin class $RuntimeStateStoppedCopyWith<$Res> implements $RuntimeStateCopyWith<$Res> {
  factory $RuntimeStateStoppedCopyWith(RuntimeStateStopped value, $Res Function(RuntimeStateStopped) _then) = _$RuntimeStateStoppedCopyWithImpl;
@override @useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId
});




}
/// @nodoc
class _$RuntimeStateStoppedCopyWithImpl<$Res>
    implements $RuntimeStateStoppedCopyWith<$Res> {
  _$RuntimeStateStoppedCopyWithImpl(this._self, this._then);

  final RuntimeStateStopped _self;
  final $Res Function(RuntimeStateStopped) _then;

/// Create a copy of RuntimeState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,}) {
  return _then(RuntimeStateStopped(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,
  ));
}


}

/// @nodoc
mixin _$AppearanceSettings {

 ThemeMode get themeMode;
/// Create a copy of AppearanceSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppearanceSettingsCopyWith<AppearanceSettings> get copyWith => _$AppearanceSettingsCopyWithImpl<AppearanceSettings>(this as AppearanceSettings, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppearanceSettings&&(identical(other.themeMode, themeMode) || other.themeMode == themeMode));
}


@override
int get hashCode => Object.hash(runtimeType,themeMode);

@override
String toString() {
  return 'AppearanceSettings(themeMode: $themeMode)';
}


}

/// @nodoc
abstract mixin class $AppearanceSettingsCopyWith<$Res>  {
  factory $AppearanceSettingsCopyWith(AppearanceSettings value, $Res Function(AppearanceSettings) _then) = _$AppearanceSettingsCopyWithImpl;
@useResult
$Res call({
 ThemeMode themeMode
});




}
/// @nodoc
class _$AppearanceSettingsCopyWithImpl<$Res>
    implements $AppearanceSettingsCopyWith<$Res> {
  _$AppearanceSettingsCopyWithImpl(this._self, this._then);

  final AppearanceSettings _self;
  final $Res Function(AppearanceSettings) _then;

/// Create a copy of AppearanceSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? themeMode = null,}) {
  return _then(_self.copyWith(
themeMode: null == themeMode ? _self.themeMode : themeMode // ignore: cast_nullable_to_non_nullable
as ThemeMode,
  ));
}

}


/// Adds pattern-matching-related methods to [AppearanceSettings].
extension AppearanceSettingsPatterns on AppearanceSettings {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AppearanceSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AppearanceSettings() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AppearanceSettings value)  $default,){
final _that = this;
switch (_that) {
case _AppearanceSettings():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AppearanceSettings value)?  $default,){
final _that = this;
switch (_that) {
case _AppearanceSettings() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThemeMode themeMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppearanceSettings() when $default != null:
return $default(_that.themeMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThemeMode themeMode)  $default,) {final _that = this;
switch (_that) {
case _AppearanceSettings():
return $default(_that.themeMode);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThemeMode themeMode)?  $default,) {final _that = this;
switch (_that) {
case _AppearanceSettings() when $default != null:
return $default(_that.themeMode);case _:
  return null;

}
}

}

/// @nodoc


class _AppearanceSettings implements AppearanceSettings {
  const _AppearanceSettings({required this.themeMode});


@override final  ThemeMode themeMode;

/// Create a copy of AppearanceSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppearanceSettingsCopyWith<_AppearanceSettings> get copyWith => __$AppearanceSettingsCopyWithImpl<_AppearanceSettings>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppearanceSettings&&(identical(other.themeMode, themeMode) || other.themeMode == themeMode));
}


@override
int get hashCode => Object.hash(runtimeType,themeMode);

@override
String toString() {
  return 'AppearanceSettings(themeMode: $themeMode)';
}


}

/// @nodoc
abstract mixin class _$AppearanceSettingsCopyWith<$Res> implements $AppearanceSettingsCopyWith<$Res> {
  factory _$AppearanceSettingsCopyWith(_AppearanceSettings value, $Res Function(_AppearanceSettings) _then) = __$AppearanceSettingsCopyWithImpl;
@override @useResult
$Res call({
 ThemeMode themeMode
});




}
/// @nodoc
class __$AppearanceSettingsCopyWithImpl<$Res>
    implements _$AppearanceSettingsCopyWith<$Res> {
  __$AppearanceSettingsCopyWithImpl(this._self, this._then);

  final _AppearanceSettings _self;
  final $Res Function(_AppearanceSettings) _then;

/// Create a copy of AppearanceSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? themeMode = null,}) {
  return _then(_AppearanceSettings(
themeMode: null == themeMode ? _self.themeMode : themeMode // ignore: cast_nullable_to_non_nullable
as ThemeMode,
  ));
}


}

/// @nodoc
mixin _$DiagnosticsExport {

 DiagnosticsExportOutcome get outcome; String get destinationClassification;
/// Create a copy of DiagnosticsExport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosticsExportCopyWith<DiagnosticsExport> get copyWith => _$DiagnosticsExportCopyWithImpl<DiagnosticsExport>(this as DiagnosticsExport, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosticsExport&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.destinationClassification, destinationClassification) || other.destinationClassification == destinationClassification));
}


@override
int get hashCode => Object.hash(runtimeType,outcome,destinationClassification);

@override
String toString() {
  return 'DiagnosticsExport(outcome: $outcome, destinationClassification: $destinationClassification)';
}


}

/// @nodoc
abstract mixin class $DiagnosticsExportCopyWith<$Res>  {
  factory $DiagnosticsExportCopyWith(DiagnosticsExport value, $Res Function(DiagnosticsExport) _then) = _$DiagnosticsExportCopyWithImpl;
@useResult
$Res call({
 DiagnosticsExportOutcome outcome, String destinationClassification
});




}
/// @nodoc
class _$DiagnosticsExportCopyWithImpl<$Res>
    implements $DiagnosticsExportCopyWith<$Res> {
  _$DiagnosticsExportCopyWithImpl(this._self, this._then);

  final DiagnosticsExport _self;
  final $Res Function(DiagnosticsExport) _then;

/// Create a copy of DiagnosticsExport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? outcome = null,Object? destinationClassification = null,}) {
  return _then(_self.copyWith(
outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as DiagnosticsExportOutcome,destinationClassification: null == destinationClassification ? _self.destinationClassification : destinationClassification // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [DiagnosticsExport].
extension DiagnosticsExportPatterns on DiagnosticsExport {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DiagnosticsExport value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DiagnosticsExport() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DiagnosticsExport value)  $default,){
final _that = this;
switch (_that) {
case _DiagnosticsExport():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DiagnosticsExport value)?  $default,){
final _that = this;
switch (_that) {
case _DiagnosticsExport() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DiagnosticsExportOutcome outcome,  String destinationClassification)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DiagnosticsExport() when $default != null:
return $default(_that.outcome,_that.destinationClassification);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DiagnosticsExportOutcome outcome,  String destinationClassification)  $default,) {final _that = this;
switch (_that) {
case _DiagnosticsExport():
return $default(_that.outcome,_that.destinationClassification);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DiagnosticsExportOutcome outcome,  String destinationClassification)?  $default,) {final _that = this;
switch (_that) {
case _DiagnosticsExport() when $default != null:
return $default(_that.outcome,_that.destinationClassification);case _:
  return null;

}
}

}

/// @nodoc


class _DiagnosticsExport implements DiagnosticsExport {
  const _DiagnosticsExport({required this.outcome, required this.destinationClassification});


@override final  DiagnosticsExportOutcome outcome;
@override final  String destinationClassification;

/// Create a copy of DiagnosticsExport
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DiagnosticsExportCopyWith<_DiagnosticsExport> get copyWith => __$DiagnosticsExportCopyWithImpl<_DiagnosticsExport>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DiagnosticsExport&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.destinationClassification, destinationClassification) || other.destinationClassification == destinationClassification));
}


@override
int get hashCode => Object.hash(runtimeType,outcome,destinationClassification);

@override
String toString() {
  return 'DiagnosticsExport(outcome: $outcome, destinationClassification: $destinationClassification)';
}


}

/// @nodoc
abstract mixin class _$DiagnosticsExportCopyWith<$Res> implements $DiagnosticsExportCopyWith<$Res> {
  factory _$DiagnosticsExportCopyWith(_DiagnosticsExport value, $Res Function(_DiagnosticsExport) _then) = __$DiagnosticsExportCopyWithImpl;
@override @useResult
$Res call({
 DiagnosticsExportOutcome outcome, String destinationClassification
});




}
/// @nodoc
class __$DiagnosticsExportCopyWithImpl<$Res>
    implements _$DiagnosticsExportCopyWith<$Res> {
  __$DiagnosticsExportCopyWithImpl(this._self, this._then);

  final _DiagnosticsExport _self;
  final $Res Function(_DiagnosticsExport) _then;

/// Create a copy of DiagnosticsExport
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? outcome = null,Object? destinationClassification = null,}) {
  return _then(_DiagnosticsExport(
outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as DiagnosticsExportOutcome,destinationClassification: null == destinationClassification ? _self.destinationClassification : destinationClassification // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$TechnicalDetails {

 String get text;
/// Create a copy of TechnicalDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TechnicalDetailsCopyWith<TechnicalDetails> get copyWith => _$TechnicalDetailsCopyWithImpl<TechnicalDetails>(this as TechnicalDetails, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TechnicalDetails&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,text);

@override
String toString() {
  return 'TechnicalDetails(text: $text)';
}


}

/// @nodoc
abstract mixin class $TechnicalDetailsCopyWith<$Res>  {
  factory $TechnicalDetailsCopyWith(TechnicalDetails value, $Res Function(TechnicalDetails) _then) = _$TechnicalDetailsCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$TechnicalDetailsCopyWithImpl<$Res>
    implements $TechnicalDetailsCopyWith<$Res> {
  _$TechnicalDetailsCopyWithImpl(this._self, this._then);

  final TechnicalDetails _self;
  final $Res Function(TechnicalDetails) _then;

/// Create a copy of TechnicalDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? text = null,}) {
  return _then(_self.copyWith(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TechnicalDetails].
extension TechnicalDetailsPatterns on TechnicalDetails {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TechnicalDetails value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TechnicalDetails() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TechnicalDetails value)  $default,){
final _that = this;
switch (_that) {
case _TechnicalDetails():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TechnicalDetails value)?  $default,){
final _that = this;
switch (_that) {
case _TechnicalDetails() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String text)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TechnicalDetails() when $default != null:
return $default(_that.text);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String text)  $default,) {final _that = this;
switch (_that) {
case _TechnicalDetails():
return $default(_that.text);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String text)?  $default,) {final _that = this;
switch (_that) {
case _TechnicalDetails() when $default != null:
return $default(_that.text);case _:
  return null;

}
}

}

/// @nodoc


class _TechnicalDetails implements TechnicalDetails {
  const _TechnicalDetails({required this.text});


@override final  String text;

/// Create a copy of TechnicalDetails
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TechnicalDetailsCopyWith<_TechnicalDetails> get copyWith => __$TechnicalDetailsCopyWithImpl<_TechnicalDetails>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TechnicalDetails&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,text);

@override
String toString() {
  return 'TechnicalDetails(text: $text)';
}


}

/// @nodoc
abstract mixin class _$TechnicalDetailsCopyWith<$Res> implements $TechnicalDetailsCopyWith<$Res> {
  factory _$TechnicalDetailsCopyWith(_TechnicalDetails value, $Res Function(_TechnicalDetails) _then) = __$TechnicalDetailsCopyWithImpl;
@override @useResult
$Res call({
 String text
});




}
/// @nodoc
class __$TechnicalDetailsCopyWithImpl<$Res>
    implements _$TechnicalDetailsCopyWith<$Res> {
  __$TechnicalDetailsCopyWithImpl(this._self, this._then);

  final _TechnicalDetails _self;
  final $Res Function(_TechnicalDetails) _then;

/// Create a copy of TechnicalDetails
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(_TechnicalDetails(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$LibraryRoot {

 LibraryRootId get id; String get displayName; String get safeLocationPresentation; LibraryRootAvailability get availability; LibraryRootLastScan? get lastScan; LibraryRootActiveScan? get activeScan;
/// Create a copy of LibraryRoot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryRootCopyWith<LibraryRoot> get copyWith => _$LibraryRootCopyWithImpl<LibraryRoot>(this as LibraryRoot, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryRoot&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.safeLocationPresentation, safeLocationPresentation) || other.safeLocationPresentation == safeLocationPresentation)&&(identical(other.availability, availability) || other.availability == availability)&&(identical(other.lastScan, lastScan) || other.lastScan == lastScan)&&(identical(other.activeScan, activeScan) || other.activeScan == activeScan));
}


@override
int get hashCode => Object.hash(runtimeType,id,displayName,safeLocationPresentation,availability,lastScan,activeScan);

@override
String toString() {
  return 'LibraryRoot(id: $id, displayName: $displayName, safeLocationPresentation: $safeLocationPresentation, availability: $availability, lastScan: $lastScan, activeScan: $activeScan)';
}


}

/// @nodoc
abstract mixin class $LibraryRootCopyWith<$Res>  {
  factory $LibraryRootCopyWith(LibraryRoot value, $Res Function(LibraryRoot) _then) = _$LibraryRootCopyWithImpl;
@useResult
$Res call({
 LibraryRootId id, String displayName, String safeLocationPresentation, LibraryRootAvailability availability, LibraryRootLastScan? lastScan, LibraryRootActiveScan? activeScan
});




}
/// @nodoc
class _$LibraryRootCopyWithImpl<$Res>
    implements $LibraryRootCopyWith<$Res> {
  _$LibraryRootCopyWithImpl(this._self, this._then);

  final LibraryRoot _self;
  final $Res Function(LibraryRoot) _then;

/// Create a copy of LibraryRoot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? safeLocationPresentation = null,Object? availability = null,Object? lastScan = freezed,Object? activeScan = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as LibraryRootId,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,safeLocationPresentation: null == safeLocationPresentation ? _self.safeLocationPresentation : safeLocationPresentation // ignore: cast_nullable_to_non_nullable
as String,availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as LibraryRootAvailability,lastScan: freezed == lastScan ? _self.lastScan : lastScan // ignore: cast_nullable_to_non_nullable
as LibraryRootLastScan?,activeScan: freezed == activeScan ? _self.activeScan : activeScan // ignore: cast_nullable_to_non_nullable
as LibraryRootActiveScan?,
  ));
}

}


/// Adds pattern-matching-related methods to [LibraryRoot].
extension LibraryRootPatterns on LibraryRoot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LibraryRoot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LibraryRoot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LibraryRoot value)  $default,){
final _that = this;
switch (_that) {
case _LibraryRoot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LibraryRoot value)?  $default,){
final _that = this;
switch (_that) {
case _LibraryRoot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( LibraryRootId id,  String displayName,  String safeLocationPresentation,  LibraryRootAvailability availability,  LibraryRootLastScan? lastScan,  LibraryRootActiveScan? activeScan)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LibraryRoot() when $default != null:
return $default(_that.id,_that.displayName,_that.safeLocationPresentation,_that.availability,_that.lastScan,_that.activeScan);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( LibraryRootId id,  String displayName,  String safeLocationPresentation,  LibraryRootAvailability availability,  LibraryRootLastScan? lastScan,  LibraryRootActiveScan? activeScan)  $default,) {final _that = this;
switch (_that) {
case _LibraryRoot():
return $default(_that.id,_that.displayName,_that.safeLocationPresentation,_that.availability,_that.lastScan,_that.activeScan);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( LibraryRootId id,  String displayName,  String safeLocationPresentation,  LibraryRootAvailability availability,  LibraryRootLastScan? lastScan,  LibraryRootActiveScan? activeScan)?  $default,) {final _that = this;
switch (_that) {
case _LibraryRoot() when $default != null:
return $default(_that.id,_that.displayName,_that.safeLocationPresentation,_that.availability,_that.lastScan,_that.activeScan);case _:
  return null;

}
}

}

/// @nodoc


class _LibraryRoot implements LibraryRoot {
  const _LibraryRoot({required this.id, required this.displayName, required this.safeLocationPresentation, required this.availability, this.lastScan, this.activeScan});


@override final  LibraryRootId id;
@override final  String displayName;
@override final  String safeLocationPresentation;
@override final  LibraryRootAvailability availability;
@override final  LibraryRootLastScan? lastScan;
@override final  LibraryRootActiveScan? activeScan;

/// Create a copy of LibraryRoot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LibraryRootCopyWith<_LibraryRoot> get copyWith => __$LibraryRootCopyWithImpl<_LibraryRoot>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LibraryRoot&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.safeLocationPresentation, safeLocationPresentation) || other.safeLocationPresentation == safeLocationPresentation)&&(identical(other.availability, availability) || other.availability == availability)&&(identical(other.lastScan, lastScan) || other.lastScan == lastScan)&&(identical(other.activeScan, activeScan) || other.activeScan == activeScan));
}


@override
int get hashCode => Object.hash(runtimeType,id,displayName,safeLocationPresentation,availability,lastScan,activeScan);

@override
String toString() {
  return 'LibraryRoot(id: $id, displayName: $displayName, safeLocationPresentation: $safeLocationPresentation, availability: $availability, lastScan: $lastScan, activeScan: $activeScan)';
}


}

/// @nodoc
abstract mixin class _$LibraryRootCopyWith<$Res> implements $LibraryRootCopyWith<$Res> {
  factory _$LibraryRootCopyWith(_LibraryRoot value, $Res Function(_LibraryRoot) _then) = __$LibraryRootCopyWithImpl;
@override @useResult
$Res call({
 LibraryRootId id, String displayName, String safeLocationPresentation, LibraryRootAvailability availability, LibraryRootLastScan? lastScan, LibraryRootActiveScan? activeScan
});




}
/// @nodoc
class __$LibraryRootCopyWithImpl<$Res>
    implements _$LibraryRootCopyWith<$Res> {
  __$LibraryRootCopyWithImpl(this._self, this._then);

  final _LibraryRoot _self;
  final $Res Function(_LibraryRoot) _then;

/// Create a copy of LibraryRoot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? safeLocationPresentation = null,Object? availability = null,Object? lastScan = freezed,Object? activeScan = freezed,}) {
  return _then(_LibraryRoot(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as LibraryRootId,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,safeLocationPresentation: null == safeLocationPresentation ? _self.safeLocationPresentation : safeLocationPresentation // ignore: cast_nullable_to_non_nullable
as String,availability: null == availability ? _self.availability : availability // ignore: cast_nullable_to_non_nullable
as LibraryRootAvailability,lastScan: freezed == lastScan ? _self.lastScan : lastScan // ignore: cast_nullable_to_non_nullable
as LibraryRootLastScan?,activeScan: freezed == activeScan ? _self.activeScan : activeScan // ignore: cast_nullable_to_non_nullable
as LibraryRootActiveScan?,
  ));
}


}

/// @nodoc
mixin _$SourceEntry {

 SourceEntryId get sourceEntryId; SourceEntryId? get parentSourceEntryId; String get displayName; String get displayLocation; SourceEntryKind get kind; SourceEntryClassification get classification;
/// Create a copy of SourceEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourceEntryCopyWith<SourceEntry> get copyWith => _$SourceEntryCopyWithImpl<SourceEntry>(this as SourceEntry, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceEntry&&(identical(other.sourceEntryId, sourceEntryId) || other.sourceEntryId == sourceEntryId)&&(identical(other.parentSourceEntryId, parentSourceEntryId) || other.parentSourceEntryId == parentSourceEntryId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.displayLocation, displayLocation) || other.displayLocation == displayLocation)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.classification, classification) || other.classification == classification));
}


@override
int get hashCode => Object.hash(runtimeType,sourceEntryId,parentSourceEntryId,displayName,displayLocation,kind,classification);

@override
String toString() {
  return 'SourceEntry(sourceEntryId: $sourceEntryId, parentSourceEntryId: $parentSourceEntryId, displayName: $displayName, displayLocation: $displayLocation, kind: $kind, classification: $classification)';
}


}

/// @nodoc
abstract mixin class $SourceEntryCopyWith<$Res>  {
  factory $SourceEntryCopyWith(SourceEntry value, $Res Function(SourceEntry) _then) = _$SourceEntryCopyWithImpl;
@useResult
$Res call({
 SourceEntryId sourceEntryId, SourceEntryId? parentSourceEntryId, String displayName, String displayLocation, SourceEntryKind kind, SourceEntryClassification classification
});




}
/// @nodoc
class _$SourceEntryCopyWithImpl<$Res>
    implements $SourceEntryCopyWith<$Res> {
  _$SourceEntryCopyWithImpl(this._self, this._then);

  final SourceEntry _self;
  final $Res Function(SourceEntry) _then;

/// Create a copy of SourceEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sourceEntryId = null,Object? parentSourceEntryId = freezed,Object? displayName = null,Object? displayLocation = null,Object? kind = null,Object? classification = null,}) {
  return _then(_self.copyWith(
sourceEntryId: null == sourceEntryId ? _self.sourceEntryId : sourceEntryId // ignore: cast_nullable_to_non_nullable
as SourceEntryId,parentSourceEntryId: freezed == parentSourceEntryId ? _self.parentSourceEntryId : parentSourceEntryId // ignore: cast_nullable_to_non_nullable
as SourceEntryId?,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,displayLocation: null == displayLocation ? _self.displayLocation : displayLocation // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as SourceEntryKind,classification: null == classification ? _self.classification : classification // ignore: cast_nullable_to_non_nullable
as SourceEntryClassification,
  ));
}

}


/// Adds pattern-matching-related methods to [SourceEntry].
extension SourceEntryPatterns on SourceEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SourceEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SourceEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SourceEntry value)  $default,){
final _that = this;
switch (_that) {
case _SourceEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SourceEntry value)?  $default,){
final _that = this;
switch (_that) {
case _SourceEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SourceEntryId sourceEntryId,  SourceEntryId? parentSourceEntryId,  String displayName,  String displayLocation,  SourceEntryKind kind,  SourceEntryClassification classification)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SourceEntry() when $default != null:
return $default(_that.sourceEntryId,_that.parentSourceEntryId,_that.displayName,_that.displayLocation,_that.kind,_that.classification);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SourceEntryId sourceEntryId,  SourceEntryId? parentSourceEntryId,  String displayName,  String displayLocation,  SourceEntryKind kind,  SourceEntryClassification classification)  $default,) {final _that = this;
switch (_that) {
case _SourceEntry():
return $default(_that.sourceEntryId,_that.parentSourceEntryId,_that.displayName,_that.displayLocation,_that.kind,_that.classification);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SourceEntryId sourceEntryId,  SourceEntryId? parentSourceEntryId,  String displayName,  String displayLocation,  SourceEntryKind kind,  SourceEntryClassification classification)?  $default,) {final _that = this;
switch (_that) {
case _SourceEntry() when $default != null:
return $default(_that.sourceEntryId,_that.parentSourceEntryId,_that.displayName,_that.displayLocation,_that.kind,_that.classification);case _:
  return null;

}
}

}

/// @nodoc


class _SourceEntry implements SourceEntry {
  const _SourceEntry({required this.sourceEntryId, this.parentSourceEntryId, required this.displayName, required this.displayLocation, required this.kind, required this.classification});


@override final  SourceEntryId sourceEntryId;
@override final  SourceEntryId? parentSourceEntryId;
@override final  String displayName;
@override final  String displayLocation;
@override final  SourceEntryKind kind;
@override final  SourceEntryClassification classification;

/// Create a copy of SourceEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SourceEntryCopyWith<_SourceEntry> get copyWith => __$SourceEntryCopyWithImpl<_SourceEntry>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SourceEntry&&(identical(other.sourceEntryId, sourceEntryId) || other.sourceEntryId == sourceEntryId)&&(identical(other.parentSourceEntryId, parentSourceEntryId) || other.parentSourceEntryId == parentSourceEntryId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.displayLocation, displayLocation) || other.displayLocation == displayLocation)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.classification, classification) || other.classification == classification));
}


@override
int get hashCode => Object.hash(runtimeType,sourceEntryId,parentSourceEntryId,displayName,displayLocation,kind,classification);

@override
String toString() {
  return 'SourceEntry(sourceEntryId: $sourceEntryId, parentSourceEntryId: $parentSourceEntryId, displayName: $displayName, displayLocation: $displayLocation, kind: $kind, classification: $classification)';
}


}

/// @nodoc
abstract mixin class _$SourceEntryCopyWith<$Res> implements $SourceEntryCopyWith<$Res> {
  factory _$SourceEntryCopyWith(_SourceEntry value, $Res Function(_SourceEntry) _then) = __$SourceEntryCopyWithImpl;
@override @useResult
$Res call({
 SourceEntryId sourceEntryId, SourceEntryId? parentSourceEntryId, String displayName, String displayLocation, SourceEntryKind kind, SourceEntryClassification classification
});




}
/// @nodoc
class __$SourceEntryCopyWithImpl<$Res>
    implements _$SourceEntryCopyWith<$Res> {
  __$SourceEntryCopyWithImpl(this._self, this._then);

  final _SourceEntry _self;
  final $Res Function(_SourceEntry) _then;

/// Create a copy of SourceEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sourceEntryId = null,Object? parentSourceEntryId = freezed,Object? displayName = null,Object? displayLocation = null,Object? kind = null,Object? classification = null,}) {
  return _then(_SourceEntry(
sourceEntryId: null == sourceEntryId ? _self.sourceEntryId : sourceEntryId // ignore: cast_nullable_to_non_nullable
as SourceEntryId,parentSourceEntryId: freezed == parentSourceEntryId ? _self.parentSourceEntryId : parentSourceEntryId // ignore: cast_nullable_to_non_nullable
as SourceEntryId?,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,displayLocation: null == displayLocation ? _self.displayLocation : displayLocation // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as SourceEntryKind,classification: null == classification ? _self.classification : classification // ignore: cast_nullable_to_non_nullable
as SourceEntryClassification,
  ));
}


}

/// @nodoc
mixin _$SourceEntryDetail {

 SourceEntryId get sourceEntryId; SourceEntryId? get parentSourceEntryId; String get displayName; String get displayLocation; SourceEntryKind get kind; SourceEntryClassification get classification;
/// Create a copy of SourceEntryDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourceEntryDetailCopyWith<SourceEntryDetail> get copyWith => _$SourceEntryDetailCopyWithImpl<SourceEntryDetail>(this as SourceEntryDetail, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceEntryDetail&&(identical(other.sourceEntryId, sourceEntryId) || other.sourceEntryId == sourceEntryId)&&(identical(other.parentSourceEntryId, parentSourceEntryId) || other.parentSourceEntryId == parentSourceEntryId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.displayLocation, displayLocation) || other.displayLocation == displayLocation)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.classification, classification) || other.classification == classification));
}


@override
int get hashCode => Object.hash(runtimeType,sourceEntryId,parentSourceEntryId,displayName,displayLocation,kind,classification);

@override
String toString() {
  return 'SourceEntryDetail(sourceEntryId: $sourceEntryId, parentSourceEntryId: $parentSourceEntryId, displayName: $displayName, displayLocation: $displayLocation, kind: $kind, classification: $classification)';
}


}

/// @nodoc
abstract mixin class $SourceEntryDetailCopyWith<$Res>  {
  factory $SourceEntryDetailCopyWith(SourceEntryDetail value, $Res Function(SourceEntryDetail) _then) = _$SourceEntryDetailCopyWithImpl;
@useResult
$Res call({
 SourceEntryId sourceEntryId, SourceEntryId? parentSourceEntryId, String displayName, String displayLocation, SourceEntryKind kind, SourceEntryClassification classification
});




}
/// @nodoc
class _$SourceEntryDetailCopyWithImpl<$Res>
    implements $SourceEntryDetailCopyWith<$Res> {
  _$SourceEntryDetailCopyWithImpl(this._self, this._then);

  final SourceEntryDetail _self;
  final $Res Function(SourceEntryDetail) _then;

/// Create a copy of SourceEntryDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sourceEntryId = null,Object? parentSourceEntryId = freezed,Object? displayName = null,Object? displayLocation = null,Object? kind = null,Object? classification = null,}) {
  return _then(_self.copyWith(
sourceEntryId: null == sourceEntryId ? _self.sourceEntryId : sourceEntryId // ignore: cast_nullable_to_non_nullable
as SourceEntryId,parentSourceEntryId: freezed == parentSourceEntryId ? _self.parentSourceEntryId : parentSourceEntryId // ignore: cast_nullable_to_non_nullable
as SourceEntryId?,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,displayLocation: null == displayLocation ? _self.displayLocation : displayLocation // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as SourceEntryKind,classification: null == classification ? _self.classification : classification // ignore: cast_nullable_to_non_nullable
as SourceEntryClassification,
  ));
}

}


/// Adds pattern-matching-related methods to [SourceEntryDetail].
extension SourceEntryDetailPatterns on SourceEntryDetail {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SourceEntryDetail value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SourceEntryDetail() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SourceEntryDetail value)  $default,){
final _that = this;
switch (_that) {
case _SourceEntryDetail():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SourceEntryDetail value)?  $default,){
final _that = this;
switch (_that) {
case _SourceEntryDetail() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SourceEntryId sourceEntryId,  SourceEntryId? parentSourceEntryId,  String displayName,  String displayLocation,  SourceEntryKind kind,  SourceEntryClassification classification)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SourceEntryDetail() when $default != null:
return $default(_that.sourceEntryId,_that.parentSourceEntryId,_that.displayName,_that.displayLocation,_that.kind,_that.classification);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SourceEntryId sourceEntryId,  SourceEntryId? parentSourceEntryId,  String displayName,  String displayLocation,  SourceEntryKind kind,  SourceEntryClassification classification)  $default,) {final _that = this;
switch (_that) {
case _SourceEntryDetail():
return $default(_that.sourceEntryId,_that.parentSourceEntryId,_that.displayName,_that.displayLocation,_that.kind,_that.classification);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SourceEntryId sourceEntryId,  SourceEntryId? parentSourceEntryId,  String displayName,  String displayLocation,  SourceEntryKind kind,  SourceEntryClassification classification)?  $default,) {final _that = this;
switch (_that) {
case _SourceEntryDetail() when $default != null:
return $default(_that.sourceEntryId,_that.parentSourceEntryId,_that.displayName,_that.displayLocation,_that.kind,_that.classification);case _:
  return null;

}
}

}

/// @nodoc


class _SourceEntryDetail implements SourceEntryDetail {
  const _SourceEntryDetail({required this.sourceEntryId, this.parentSourceEntryId, required this.displayName, required this.displayLocation, required this.kind, required this.classification});


@override final  SourceEntryId sourceEntryId;
@override final  SourceEntryId? parentSourceEntryId;
@override final  String displayName;
@override final  String displayLocation;
@override final  SourceEntryKind kind;
@override final  SourceEntryClassification classification;

/// Create a copy of SourceEntryDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SourceEntryDetailCopyWith<_SourceEntryDetail> get copyWith => __$SourceEntryDetailCopyWithImpl<_SourceEntryDetail>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SourceEntryDetail&&(identical(other.sourceEntryId, sourceEntryId) || other.sourceEntryId == sourceEntryId)&&(identical(other.parentSourceEntryId, parentSourceEntryId) || other.parentSourceEntryId == parentSourceEntryId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.displayLocation, displayLocation) || other.displayLocation == displayLocation)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.classification, classification) || other.classification == classification));
}


@override
int get hashCode => Object.hash(runtimeType,sourceEntryId,parentSourceEntryId,displayName,displayLocation,kind,classification);

@override
String toString() {
  return 'SourceEntryDetail(sourceEntryId: $sourceEntryId, parentSourceEntryId: $parentSourceEntryId, displayName: $displayName, displayLocation: $displayLocation, kind: $kind, classification: $classification)';
}


}

/// @nodoc
abstract mixin class _$SourceEntryDetailCopyWith<$Res> implements $SourceEntryDetailCopyWith<$Res> {
  factory _$SourceEntryDetailCopyWith(_SourceEntryDetail value, $Res Function(_SourceEntryDetail) _then) = __$SourceEntryDetailCopyWithImpl;
@override @useResult
$Res call({
 SourceEntryId sourceEntryId, SourceEntryId? parentSourceEntryId, String displayName, String displayLocation, SourceEntryKind kind, SourceEntryClassification classification
});




}
/// @nodoc
class __$SourceEntryDetailCopyWithImpl<$Res>
    implements _$SourceEntryDetailCopyWith<$Res> {
  __$SourceEntryDetailCopyWithImpl(this._self, this._then);

  final _SourceEntryDetail _self;
  final $Res Function(_SourceEntryDetail) _then;

/// Create a copy of SourceEntryDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sourceEntryId = null,Object? parentSourceEntryId = freezed,Object? displayName = null,Object? displayLocation = null,Object? kind = null,Object? classification = null,}) {
  return _then(_SourceEntryDetail(
sourceEntryId: null == sourceEntryId ? _self.sourceEntryId : sourceEntryId // ignore: cast_nullable_to_non_nullable
as SourceEntryId,parentSourceEntryId: freezed == parentSourceEntryId ? _self.parentSourceEntryId : parentSourceEntryId // ignore: cast_nullable_to_non_nullable
as SourceEntryId?,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,displayLocation: null == displayLocation ? _self.displayLocation : displayLocation // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as SourceEntryKind,classification: null == classification ? _self.classification : classification // ignore: cast_nullable_to_non_nullable
as SourceEntryClassification,
  ));
}


}

/// @nodoc
mixin _$AddLocalLibraryRootResult {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AddLocalLibraryRootResult()';
}


}

/// @nodoc
class $AddLocalLibraryRootResultCopyWith<$Res>  {
$AddLocalLibraryRootResultCopyWith(AddLocalLibraryRootResult _, $Res Function(AddLocalLibraryRootResult) __);
}


/// Adds pattern-matching-related methods to [AddLocalLibraryRootResult].
extension AddLocalLibraryRootResultPatterns on AddLocalLibraryRootResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AddLocalLibraryRootResultAdded value)?  added,TResult Function( AddLocalLibraryRootResultAlreadyConfigured value)?  alreadyConfigured,TResult Function( AddLocalLibraryRootResultOverlapsExisting value)?  overlapsExisting,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AddLocalLibraryRootResultAdded() when added != null:
return added(_that);case AddLocalLibraryRootResultAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that);case AddLocalLibraryRootResultOverlapsExisting() when overlapsExisting != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AddLocalLibraryRootResultAdded value)  added,required TResult Function( AddLocalLibraryRootResultAlreadyConfigured value)  alreadyConfigured,required TResult Function( AddLocalLibraryRootResultOverlapsExisting value)  overlapsExisting,}){
final _that = this;
switch (_that) {
case AddLocalLibraryRootResultAdded():
return added(_that);case AddLocalLibraryRootResultAlreadyConfigured():
return alreadyConfigured(_that);case AddLocalLibraryRootResultOverlapsExisting():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AddLocalLibraryRootResultAdded value)?  added,TResult? Function( AddLocalLibraryRootResultAlreadyConfigured value)?  alreadyConfigured,TResult? Function( AddLocalLibraryRootResultOverlapsExisting value)?  overlapsExisting,}){
final _that = this;
switch (_that) {
case AddLocalLibraryRootResultAdded() when added != null:
return added(_that);case AddLocalLibraryRootResultAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that);case AddLocalLibraryRootResultOverlapsExisting() when overlapsExisting != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( LibraryRoot root)?  added,TResult Function( LibraryRootId existingLibraryRootId)?  alreadyConfigured,TResult Function( LibraryRootId existingLibraryRootId,  RootRelationship relationship)?  overlapsExisting,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AddLocalLibraryRootResultAdded() when added != null:
return added(_that.root);case AddLocalLibraryRootResultAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that.existingLibraryRootId);case AddLocalLibraryRootResultOverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that.existingLibraryRootId,_that.relationship);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( LibraryRoot root)  added,required TResult Function( LibraryRootId existingLibraryRootId)  alreadyConfigured,required TResult Function( LibraryRootId existingLibraryRootId,  RootRelationship relationship)  overlapsExisting,}) {final _that = this;
switch (_that) {
case AddLocalLibraryRootResultAdded():
return added(_that.root);case AddLocalLibraryRootResultAlreadyConfigured():
return alreadyConfigured(_that.existingLibraryRootId);case AddLocalLibraryRootResultOverlapsExisting():
return overlapsExisting(_that.existingLibraryRootId,_that.relationship);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( LibraryRoot root)?  added,TResult? Function( LibraryRootId existingLibraryRootId)?  alreadyConfigured,TResult? Function( LibraryRootId existingLibraryRootId,  RootRelationship relationship)?  overlapsExisting,}) {final _that = this;
switch (_that) {
case AddLocalLibraryRootResultAdded() when added != null:
return added(_that.root);case AddLocalLibraryRootResultAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that.existingLibraryRootId);case AddLocalLibraryRootResultOverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that.existingLibraryRootId,_that.relationship);case _:
  return null;

}
}

}

/// @nodoc


class AddLocalLibraryRootResultAdded implements AddLocalLibraryRootResult {
  const AddLocalLibraryRootResultAdded(this.root);


 final  LibraryRoot root;

/// Create a copy of AddLocalLibraryRootResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLocalLibraryRootResultAddedCopyWith<AddLocalLibraryRootResultAdded> get copyWith => _$AddLocalLibraryRootResultAddedCopyWithImpl<AddLocalLibraryRootResultAdded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootResultAdded&&(identical(other.root, root) || other.root == root));
}


@override
int get hashCode => Object.hash(runtimeType,root);

@override
String toString() {
  return 'AddLocalLibraryRootResult.added(root: $root)';
}


}

/// @nodoc
abstract mixin class $AddLocalLibraryRootResultAddedCopyWith<$Res> implements $AddLocalLibraryRootResultCopyWith<$Res> {
  factory $AddLocalLibraryRootResultAddedCopyWith(AddLocalLibraryRootResultAdded value, $Res Function(AddLocalLibraryRootResultAdded) _then) = _$AddLocalLibraryRootResultAddedCopyWithImpl;
@useResult
$Res call({
 LibraryRoot root
});


$LibraryRootCopyWith<$Res> get root;

}
/// @nodoc
class _$AddLocalLibraryRootResultAddedCopyWithImpl<$Res>
    implements $AddLocalLibraryRootResultAddedCopyWith<$Res> {
  _$AddLocalLibraryRootResultAddedCopyWithImpl(this._self, this._then);

  final AddLocalLibraryRootResultAdded _self;
  final $Res Function(AddLocalLibraryRootResultAdded) _then;

/// Create a copy of AddLocalLibraryRootResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? root = null,}) {
  return _then(AddLocalLibraryRootResultAdded(
null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as LibraryRoot,
  ));
}

/// Create a copy of AddLocalLibraryRootResult
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


class AddLocalLibraryRootResultAlreadyConfigured implements AddLocalLibraryRootResult {
  const AddLocalLibraryRootResultAlreadyConfigured(this.existingLibraryRootId);


 final  LibraryRootId existingLibraryRootId;

/// Create a copy of AddLocalLibraryRootResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLocalLibraryRootResultAlreadyConfiguredCopyWith<AddLocalLibraryRootResultAlreadyConfigured> get copyWith => _$AddLocalLibraryRootResultAlreadyConfiguredCopyWithImpl<AddLocalLibraryRootResultAlreadyConfigured>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootResultAlreadyConfigured&&(identical(other.existingLibraryRootId, existingLibraryRootId) || other.existingLibraryRootId == existingLibraryRootId));
}


@override
int get hashCode => Object.hash(runtimeType,existingLibraryRootId);

@override
String toString() {
  return 'AddLocalLibraryRootResult.alreadyConfigured(existingLibraryRootId: $existingLibraryRootId)';
}


}

/// @nodoc
abstract mixin class $AddLocalLibraryRootResultAlreadyConfiguredCopyWith<$Res> implements $AddLocalLibraryRootResultCopyWith<$Res> {
  factory $AddLocalLibraryRootResultAlreadyConfiguredCopyWith(AddLocalLibraryRootResultAlreadyConfigured value, $Res Function(AddLocalLibraryRootResultAlreadyConfigured) _then) = _$AddLocalLibraryRootResultAlreadyConfiguredCopyWithImpl;
@useResult
$Res call({
 LibraryRootId existingLibraryRootId
});




}
/// @nodoc
class _$AddLocalLibraryRootResultAlreadyConfiguredCopyWithImpl<$Res>
    implements $AddLocalLibraryRootResultAlreadyConfiguredCopyWith<$Res> {
  _$AddLocalLibraryRootResultAlreadyConfiguredCopyWithImpl(this._self, this._then);

  final AddLocalLibraryRootResultAlreadyConfigured _self;
  final $Res Function(AddLocalLibraryRootResultAlreadyConfigured) _then;

/// Create a copy of AddLocalLibraryRootResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? existingLibraryRootId = null,}) {
  return _then(AddLocalLibraryRootResultAlreadyConfigured(
null == existingLibraryRootId ? _self.existingLibraryRootId : existingLibraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,
  ));
}


}

/// @nodoc


class AddLocalLibraryRootResultOverlapsExisting implements AddLocalLibraryRootResult {
  const AddLocalLibraryRootResultOverlapsExisting({required this.existingLibraryRootId, required this.relationship});


 final  LibraryRootId existingLibraryRootId;
 final  RootRelationship relationship;

/// Create a copy of AddLocalLibraryRootResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLocalLibraryRootResultOverlapsExistingCopyWith<AddLocalLibraryRootResultOverlapsExisting> get copyWith => _$AddLocalLibraryRootResultOverlapsExistingCopyWithImpl<AddLocalLibraryRootResultOverlapsExisting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootResultOverlapsExisting&&(identical(other.existingLibraryRootId, existingLibraryRootId) || other.existingLibraryRootId == existingLibraryRootId)&&(identical(other.relationship, relationship) || other.relationship == relationship));
}


@override
int get hashCode => Object.hash(runtimeType,existingLibraryRootId,relationship);

@override
String toString() {
  return 'AddLocalLibraryRootResult.overlapsExisting(existingLibraryRootId: $existingLibraryRootId, relationship: $relationship)';
}


}

/// @nodoc
abstract mixin class $AddLocalLibraryRootResultOverlapsExistingCopyWith<$Res> implements $AddLocalLibraryRootResultCopyWith<$Res> {
  factory $AddLocalLibraryRootResultOverlapsExistingCopyWith(AddLocalLibraryRootResultOverlapsExisting value, $Res Function(AddLocalLibraryRootResultOverlapsExisting) _then) = _$AddLocalLibraryRootResultOverlapsExistingCopyWithImpl;
@useResult
$Res call({
 LibraryRootId existingLibraryRootId, RootRelationship relationship
});




}
/// @nodoc
class _$AddLocalLibraryRootResultOverlapsExistingCopyWithImpl<$Res>
    implements $AddLocalLibraryRootResultOverlapsExistingCopyWith<$Res> {
  _$AddLocalLibraryRootResultOverlapsExistingCopyWithImpl(this._self, this._then);

  final AddLocalLibraryRootResultOverlapsExisting _self;
  final $Res Function(AddLocalLibraryRootResultOverlapsExisting) _then;

/// Create a copy of AddLocalLibraryRootResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? existingLibraryRootId = null,Object? relationship = null,}) {
  return _then(AddLocalLibraryRootResultOverlapsExisting(
existingLibraryRootId: null == existingLibraryRootId ? _self.existingLibraryRootId : existingLibraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,relationship: null == relationship ? _self.relationship : relationship // ignore: cast_nullable_to_non_nullable
as RootRelationship,
  ));
}


}

/// @nodoc
mixin _$LibraryScanChildAdmissionIssue {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanChildAdmissionIssue);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LibraryScanChildAdmissionIssue()';
}


}

/// @nodoc
class $LibraryScanChildAdmissionIssueCopyWith<$Res>  {
$LibraryScanChildAdmissionIssueCopyWith(LibraryScanChildAdmissionIssue _, $Res Function(LibraryScanChildAdmissionIssue) __);
}


/// Adds pattern-matching-related methods to [LibraryScanChildAdmissionIssue].
extension LibraryScanChildAdmissionIssuePatterns on LibraryScanChildAdmissionIssue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LibraryScanChildAdmissionIssueAlreadyScanning value)?  alreadyScanning,TResult Function( LibraryScanChildAdmissionIssueAdmissionFailure value)?  admissionFailure,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LibraryScanChildAdmissionIssueAlreadyScanning() when alreadyScanning != null:
return alreadyScanning(_that);case LibraryScanChildAdmissionIssueAdmissionFailure() when admissionFailure != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LibraryScanChildAdmissionIssueAlreadyScanning value)  alreadyScanning,required TResult Function( LibraryScanChildAdmissionIssueAdmissionFailure value)  admissionFailure,}){
final _that = this;
switch (_that) {
case LibraryScanChildAdmissionIssueAlreadyScanning():
return alreadyScanning(_that);case LibraryScanChildAdmissionIssueAdmissionFailure():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LibraryScanChildAdmissionIssueAlreadyScanning value)?  alreadyScanning,TResult? Function( LibraryScanChildAdmissionIssueAdmissionFailure value)?  admissionFailure,}){
final _that = this;
switch (_that) {
case LibraryScanChildAdmissionIssueAlreadyScanning() when alreadyScanning != null:
return alreadyScanning(_that);case LibraryScanChildAdmissionIssueAdmissionFailure() when admissionFailure != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( LibraryRootId libraryRootId,  JobRunId activeJobRunId,  ScanRunId activeScanRunId)?  alreadyScanning,TResult Function( ClientApplicationError error)?  admissionFailure,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LibraryScanChildAdmissionIssueAlreadyScanning() when alreadyScanning != null:
return alreadyScanning(_that.libraryRootId,_that.activeJobRunId,_that.activeScanRunId);case LibraryScanChildAdmissionIssueAdmissionFailure() when admissionFailure != null:
return admissionFailure(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( LibraryRootId libraryRootId,  JobRunId activeJobRunId,  ScanRunId activeScanRunId)  alreadyScanning,required TResult Function( ClientApplicationError error)  admissionFailure,}) {final _that = this;
switch (_that) {
case LibraryScanChildAdmissionIssueAlreadyScanning():
return alreadyScanning(_that.libraryRootId,_that.activeJobRunId,_that.activeScanRunId);case LibraryScanChildAdmissionIssueAdmissionFailure():
return admissionFailure(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( LibraryRootId libraryRootId,  JobRunId activeJobRunId,  ScanRunId activeScanRunId)?  alreadyScanning,TResult? Function( ClientApplicationError error)?  admissionFailure,}) {final _that = this;
switch (_that) {
case LibraryScanChildAdmissionIssueAlreadyScanning() when alreadyScanning != null:
return alreadyScanning(_that.libraryRootId,_that.activeJobRunId,_that.activeScanRunId);case LibraryScanChildAdmissionIssueAdmissionFailure() when admissionFailure != null:
return admissionFailure(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class LibraryScanChildAdmissionIssueAlreadyScanning implements LibraryScanChildAdmissionIssue {
  const LibraryScanChildAdmissionIssueAlreadyScanning({required this.libraryRootId, required this.activeJobRunId, required this.activeScanRunId});


 final  LibraryRootId libraryRootId;
 final  JobRunId activeJobRunId;
 final  ScanRunId activeScanRunId;

/// Create a copy of LibraryScanChildAdmissionIssue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryScanChildAdmissionIssueAlreadyScanningCopyWith<LibraryScanChildAdmissionIssueAlreadyScanning> get copyWith => _$LibraryScanChildAdmissionIssueAlreadyScanningCopyWithImpl<LibraryScanChildAdmissionIssueAlreadyScanning>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanChildAdmissionIssueAlreadyScanning&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId)&&(identical(other.activeJobRunId, activeJobRunId) || other.activeJobRunId == activeJobRunId)&&(identical(other.activeScanRunId, activeScanRunId) || other.activeScanRunId == activeScanRunId));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId,activeJobRunId,activeScanRunId);

@override
String toString() {
  return 'LibraryScanChildAdmissionIssue.alreadyScanning(libraryRootId: $libraryRootId, activeJobRunId: $activeJobRunId, activeScanRunId: $activeScanRunId)';
}


}

/// @nodoc
abstract mixin class $LibraryScanChildAdmissionIssueAlreadyScanningCopyWith<$Res> implements $LibraryScanChildAdmissionIssueCopyWith<$Res> {
  factory $LibraryScanChildAdmissionIssueAlreadyScanningCopyWith(LibraryScanChildAdmissionIssueAlreadyScanning value, $Res Function(LibraryScanChildAdmissionIssueAlreadyScanning) _then) = _$LibraryScanChildAdmissionIssueAlreadyScanningCopyWithImpl;
@useResult
$Res call({
 LibraryRootId libraryRootId, JobRunId activeJobRunId, ScanRunId activeScanRunId
});




}
/// @nodoc
class _$LibraryScanChildAdmissionIssueAlreadyScanningCopyWithImpl<$Res>
    implements $LibraryScanChildAdmissionIssueAlreadyScanningCopyWith<$Res> {
  _$LibraryScanChildAdmissionIssueAlreadyScanningCopyWithImpl(this._self, this._then);

  final LibraryScanChildAdmissionIssueAlreadyScanning _self;
  final $Res Function(LibraryScanChildAdmissionIssueAlreadyScanning) _then;

/// Create a copy of LibraryScanChildAdmissionIssue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? libraryRootId = null,Object? activeJobRunId = null,Object? activeScanRunId = null,}) {
  return _then(LibraryScanChildAdmissionIssueAlreadyScanning(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,activeJobRunId: null == activeJobRunId ? _self.activeJobRunId : activeJobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,activeScanRunId: null == activeScanRunId ? _self.activeScanRunId : activeScanRunId // ignore: cast_nullable_to_non_nullable
as ScanRunId,
  ));
}


}

/// @nodoc


class LibraryScanChildAdmissionIssueAdmissionFailure implements LibraryScanChildAdmissionIssue {
  const LibraryScanChildAdmissionIssueAdmissionFailure(this.error);


 final  ClientApplicationError error;

/// Create a copy of LibraryScanChildAdmissionIssue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryScanChildAdmissionIssueAdmissionFailureCopyWith<LibraryScanChildAdmissionIssueAdmissionFailure> get copyWith => _$LibraryScanChildAdmissionIssueAdmissionFailureCopyWithImpl<LibraryScanChildAdmissionIssueAdmissionFailure>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryScanChildAdmissionIssueAdmissionFailure&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'LibraryScanChildAdmissionIssue.admissionFailure(error: $error)';
}


}

/// @nodoc
abstract mixin class $LibraryScanChildAdmissionIssueAdmissionFailureCopyWith<$Res> implements $LibraryScanChildAdmissionIssueCopyWith<$Res> {
  factory $LibraryScanChildAdmissionIssueAdmissionFailureCopyWith(LibraryScanChildAdmissionIssueAdmissionFailure value, $Res Function(LibraryScanChildAdmissionIssueAdmissionFailure) _then) = _$LibraryScanChildAdmissionIssueAdmissionFailureCopyWithImpl;
@useResult
$Res call({
 ClientApplicationError error
});


$ClientApplicationErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$LibraryScanChildAdmissionIssueAdmissionFailureCopyWithImpl<$Res>
    implements $LibraryScanChildAdmissionIssueAdmissionFailureCopyWith<$Res> {
  _$LibraryScanChildAdmissionIssueAdmissionFailureCopyWithImpl(this._self, this._then);

  final LibraryScanChildAdmissionIssueAdmissionFailure _self;
  final $Res Function(LibraryScanChildAdmissionIssueAdmissionFailure) _then;

/// Create a copy of LibraryScanChildAdmissionIssue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(LibraryScanChildAdmissionIssueAdmissionFailure(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ClientApplicationError,
  ));
}

/// Create a copy of LibraryScanChildAdmissionIssue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientApplicationErrorCopyWith<$Res> get error {

  return $ClientApplicationErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$AddLocalLibraryRootAndScanResult {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootAndScanResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AddLocalLibraryRootAndScanResult()';
}


}

/// @nodoc
class $AddLocalLibraryRootAndScanResultCopyWith<$Res>  {
$AddLocalLibraryRootAndScanResultCopyWith(AddLocalLibraryRootAndScanResult _, $Res Function(AddLocalLibraryRootAndScanResult) __);
}


/// Adds pattern-matching-related methods to [AddLocalLibraryRootAndScanResult].
extension AddLocalLibraryRootAndScanResultPatterns on AddLocalLibraryRootAndScanResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AddLocalLibraryRootAndScanResultAddedAndScanAdmitted value)?  addedAndScanAdmitted,TResult Function( AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted value)?  addedButScanNotAdmitted,TResult Function( AddLocalLibraryRootAndScanResultAlreadyConfigured value)?  alreadyConfigured,TResult Function( AddLocalLibraryRootAndScanResultOverlapsExisting value)?  overlapsExisting,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AddLocalLibraryRootAndScanResultAddedAndScanAdmitted() when addedAndScanAdmitted != null:
return addedAndScanAdmitted(_that);case AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted() when addedButScanNotAdmitted != null:
return addedButScanNotAdmitted(_that);case AddLocalLibraryRootAndScanResultAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that);case AddLocalLibraryRootAndScanResultOverlapsExisting() when overlapsExisting != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AddLocalLibraryRootAndScanResultAddedAndScanAdmitted value)  addedAndScanAdmitted,required TResult Function( AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted value)  addedButScanNotAdmitted,required TResult Function( AddLocalLibraryRootAndScanResultAlreadyConfigured value)  alreadyConfigured,required TResult Function( AddLocalLibraryRootAndScanResultOverlapsExisting value)  overlapsExisting,}){
final _that = this;
switch (_that) {
case AddLocalLibraryRootAndScanResultAddedAndScanAdmitted():
return addedAndScanAdmitted(_that);case AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted():
return addedButScanNotAdmitted(_that);case AddLocalLibraryRootAndScanResultAlreadyConfigured():
return alreadyConfigured(_that);case AddLocalLibraryRootAndScanResultOverlapsExisting():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AddLocalLibraryRootAndScanResultAddedAndScanAdmitted value)?  addedAndScanAdmitted,TResult? Function( AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted value)?  addedButScanNotAdmitted,TResult? Function( AddLocalLibraryRootAndScanResultAlreadyConfigured value)?  alreadyConfigured,TResult? Function( AddLocalLibraryRootAndScanResultOverlapsExisting value)?  overlapsExisting,}){
final _that = this;
switch (_that) {
case AddLocalLibraryRootAndScanResultAddedAndScanAdmitted() when addedAndScanAdmitted != null:
return addedAndScanAdmitted(_that);case AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted() when addedButScanNotAdmitted != null:
return addedButScanNotAdmitted(_that);case AddLocalLibraryRootAndScanResultAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that);case AddLocalLibraryRootAndScanResultOverlapsExisting() when overlapsExisting != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( LibraryRoot root,  OperationHandle handle)?  addedAndScanAdmitted,TResult Function( LibraryRoot root,  LibraryScanChildAdmissionIssue issue)?  addedButScanNotAdmitted,TResult Function( LibraryRootId existingLibraryRootId)?  alreadyConfigured,TResult Function( LibraryRootId existingLibraryRootId,  RootRelationship relationship)?  overlapsExisting,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AddLocalLibraryRootAndScanResultAddedAndScanAdmitted() when addedAndScanAdmitted != null:
return addedAndScanAdmitted(_that.root,_that.handle);case AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted() when addedButScanNotAdmitted != null:
return addedButScanNotAdmitted(_that.root,_that.issue);case AddLocalLibraryRootAndScanResultAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that.existingLibraryRootId);case AddLocalLibraryRootAndScanResultOverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that.existingLibraryRootId,_that.relationship);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( LibraryRoot root,  OperationHandle handle)  addedAndScanAdmitted,required TResult Function( LibraryRoot root,  LibraryScanChildAdmissionIssue issue)  addedButScanNotAdmitted,required TResult Function( LibraryRootId existingLibraryRootId)  alreadyConfigured,required TResult Function( LibraryRootId existingLibraryRootId,  RootRelationship relationship)  overlapsExisting,}) {final _that = this;
switch (_that) {
case AddLocalLibraryRootAndScanResultAddedAndScanAdmitted():
return addedAndScanAdmitted(_that.root,_that.handle);case AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted():
return addedButScanNotAdmitted(_that.root,_that.issue);case AddLocalLibraryRootAndScanResultAlreadyConfigured():
return alreadyConfigured(_that.existingLibraryRootId);case AddLocalLibraryRootAndScanResultOverlapsExisting():
return overlapsExisting(_that.existingLibraryRootId,_that.relationship);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( LibraryRoot root,  OperationHandle handle)?  addedAndScanAdmitted,TResult? Function( LibraryRoot root,  LibraryScanChildAdmissionIssue issue)?  addedButScanNotAdmitted,TResult? Function( LibraryRootId existingLibraryRootId)?  alreadyConfigured,TResult? Function( LibraryRootId existingLibraryRootId,  RootRelationship relationship)?  overlapsExisting,}) {final _that = this;
switch (_that) {
case AddLocalLibraryRootAndScanResultAddedAndScanAdmitted() when addedAndScanAdmitted != null:
return addedAndScanAdmitted(_that.root,_that.handle);case AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted() when addedButScanNotAdmitted != null:
return addedButScanNotAdmitted(_that.root,_that.issue);case AddLocalLibraryRootAndScanResultAlreadyConfigured() when alreadyConfigured != null:
return alreadyConfigured(_that.existingLibraryRootId);case AddLocalLibraryRootAndScanResultOverlapsExisting() when overlapsExisting != null:
return overlapsExisting(_that.existingLibraryRootId,_that.relationship);case _:
  return null;

}
}

}

/// @nodoc


class AddLocalLibraryRootAndScanResultAddedAndScanAdmitted implements AddLocalLibraryRootAndScanResult {
  const AddLocalLibraryRootAndScanResultAddedAndScanAdmitted({required this.root, required this.handle});


 final  LibraryRoot root;
 final  OperationHandle handle;

/// Create a copy of AddLocalLibraryRootAndScanResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLocalLibraryRootAndScanResultAddedAndScanAdmittedCopyWith<AddLocalLibraryRootAndScanResultAddedAndScanAdmitted> get copyWith => _$AddLocalLibraryRootAndScanResultAddedAndScanAdmittedCopyWithImpl<AddLocalLibraryRootAndScanResultAddedAndScanAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootAndScanResultAddedAndScanAdmitted&&(identical(other.root, root) || other.root == root)&&(identical(other.handle, handle) || other.handle == handle));
}


@override
int get hashCode => Object.hash(runtimeType,root,handle);

@override
String toString() {
  return 'AddLocalLibraryRootAndScanResult.addedAndScanAdmitted(root: $root, handle: $handle)';
}


}

/// @nodoc
abstract mixin class $AddLocalLibraryRootAndScanResultAddedAndScanAdmittedCopyWith<$Res> implements $AddLocalLibraryRootAndScanResultCopyWith<$Res> {
  factory $AddLocalLibraryRootAndScanResultAddedAndScanAdmittedCopyWith(AddLocalLibraryRootAndScanResultAddedAndScanAdmitted value, $Res Function(AddLocalLibraryRootAndScanResultAddedAndScanAdmitted) _then) = _$AddLocalLibraryRootAndScanResultAddedAndScanAdmittedCopyWithImpl;
@useResult
$Res call({
 LibraryRoot root, OperationHandle handle
});


$LibraryRootCopyWith<$Res> get root;

}
/// @nodoc
class _$AddLocalLibraryRootAndScanResultAddedAndScanAdmittedCopyWithImpl<$Res>
    implements $AddLocalLibraryRootAndScanResultAddedAndScanAdmittedCopyWith<$Res> {
  _$AddLocalLibraryRootAndScanResultAddedAndScanAdmittedCopyWithImpl(this._self, this._then);

  final AddLocalLibraryRootAndScanResultAddedAndScanAdmitted _self;
  final $Res Function(AddLocalLibraryRootAndScanResultAddedAndScanAdmitted) _then;

/// Create a copy of AddLocalLibraryRootAndScanResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? root = null,Object? handle = null,}) {
  return _then(AddLocalLibraryRootAndScanResultAddedAndScanAdmitted(
root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as LibraryRoot,handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as OperationHandle,
  ));
}

/// Create a copy of AddLocalLibraryRootAndScanResult
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


class AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted implements AddLocalLibraryRootAndScanResult {
  const AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted({required this.root, required this.issue});


 final  LibraryRoot root;
 final  LibraryScanChildAdmissionIssue issue;

/// Create a copy of AddLocalLibraryRootAndScanResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLocalLibraryRootAndScanResultAddedButScanNotAdmittedCopyWith<AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted> get copyWith => _$AddLocalLibraryRootAndScanResultAddedButScanNotAdmittedCopyWithImpl<AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted&&(identical(other.root, root) || other.root == root)&&(identical(other.issue, issue) || other.issue == issue));
}


@override
int get hashCode => Object.hash(runtimeType,root,issue);

@override
String toString() {
  return 'AddLocalLibraryRootAndScanResult.addedButScanNotAdmitted(root: $root, issue: $issue)';
}


}

/// @nodoc
abstract mixin class $AddLocalLibraryRootAndScanResultAddedButScanNotAdmittedCopyWith<$Res> implements $AddLocalLibraryRootAndScanResultCopyWith<$Res> {
  factory $AddLocalLibraryRootAndScanResultAddedButScanNotAdmittedCopyWith(AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted value, $Res Function(AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted) _then) = _$AddLocalLibraryRootAndScanResultAddedButScanNotAdmittedCopyWithImpl;
@useResult
$Res call({
 LibraryRoot root, LibraryScanChildAdmissionIssue issue
});


$LibraryRootCopyWith<$Res> get root;$LibraryScanChildAdmissionIssueCopyWith<$Res> get issue;

}
/// @nodoc
class _$AddLocalLibraryRootAndScanResultAddedButScanNotAdmittedCopyWithImpl<$Res>
    implements $AddLocalLibraryRootAndScanResultAddedButScanNotAdmittedCopyWith<$Res> {
  _$AddLocalLibraryRootAndScanResultAddedButScanNotAdmittedCopyWithImpl(this._self, this._then);

  final AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted _self;
  final $Res Function(AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted) _then;

/// Create a copy of AddLocalLibraryRootAndScanResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? root = null,Object? issue = null,}) {
  return _then(AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted(
root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as LibraryRoot,issue: null == issue ? _self.issue : issue // ignore: cast_nullable_to_non_nullable
as LibraryScanChildAdmissionIssue,
  ));
}

/// Create a copy of AddLocalLibraryRootAndScanResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LibraryRootCopyWith<$Res> get root {

  return $LibraryRootCopyWith<$Res>(_self.root, (value) {
    return _then(_self.copyWith(root: value));
  });
}/// Create a copy of AddLocalLibraryRootAndScanResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LibraryScanChildAdmissionIssueCopyWith<$Res> get issue {

  return $LibraryScanChildAdmissionIssueCopyWith<$Res>(_self.issue, (value) {
    return _then(_self.copyWith(issue: value));
  });
}
}

/// @nodoc


class AddLocalLibraryRootAndScanResultAlreadyConfigured implements AddLocalLibraryRootAndScanResult {
  const AddLocalLibraryRootAndScanResultAlreadyConfigured(this.existingLibraryRootId);


 final  LibraryRootId existingLibraryRootId;

/// Create a copy of AddLocalLibraryRootAndScanResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLocalLibraryRootAndScanResultAlreadyConfiguredCopyWith<AddLocalLibraryRootAndScanResultAlreadyConfigured> get copyWith => _$AddLocalLibraryRootAndScanResultAlreadyConfiguredCopyWithImpl<AddLocalLibraryRootAndScanResultAlreadyConfigured>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootAndScanResultAlreadyConfigured&&(identical(other.existingLibraryRootId, existingLibraryRootId) || other.existingLibraryRootId == existingLibraryRootId));
}


@override
int get hashCode => Object.hash(runtimeType,existingLibraryRootId);

@override
String toString() {
  return 'AddLocalLibraryRootAndScanResult.alreadyConfigured(existingLibraryRootId: $existingLibraryRootId)';
}


}

/// @nodoc
abstract mixin class $AddLocalLibraryRootAndScanResultAlreadyConfiguredCopyWith<$Res> implements $AddLocalLibraryRootAndScanResultCopyWith<$Res> {
  factory $AddLocalLibraryRootAndScanResultAlreadyConfiguredCopyWith(AddLocalLibraryRootAndScanResultAlreadyConfigured value, $Res Function(AddLocalLibraryRootAndScanResultAlreadyConfigured) _then) = _$AddLocalLibraryRootAndScanResultAlreadyConfiguredCopyWithImpl;
@useResult
$Res call({
 LibraryRootId existingLibraryRootId
});




}
/// @nodoc
class _$AddLocalLibraryRootAndScanResultAlreadyConfiguredCopyWithImpl<$Res>
    implements $AddLocalLibraryRootAndScanResultAlreadyConfiguredCopyWith<$Res> {
  _$AddLocalLibraryRootAndScanResultAlreadyConfiguredCopyWithImpl(this._self, this._then);

  final AddLocalLibraryRootAndScanResultAlreadyConfigured _self;
  final $Res Function(AddLocalLibraryRootAndScanResultAlreadyConfigured) _then;

/// Create a copy of AddLocalLibraryRootAndScanResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? existingLibraryRootId = null,}) {
  return _then(AddLocalLibraryRootAndScanResultAlreadyConfigured(
null == existingLibraryRootId ? _self.existingLibraryRootId : existingLibraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,
  ));
}


}

/// @nodoc


class AddLocalLibraryRootAndScanResultOverlapsExisting implements AddLocalLibraryRootAndScanResult {
  const AddLocalLibraryRootAndScanResultOverlapsExisting({required this.existingLibraryRootId, required this.relationship});


 final  LibraryRootId existingLibraryRootId;
 final  RootRelationship relationship;

/// Create a copy of AddLocalLibraryRootAndScanResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AddLocalLibraryRootAndScanResultOverlapsExistingCopyWith<AddLocalLibraryRootAndScanResultOverlapsExisting> get copyWith => _$AddLocalLibraryRootAndScanResultOverlapsExistingCopyWithImpl<AddLocalLibraryRootAndScanResultOverlapsExisting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AddLocalLibraryRootAndScanResultOverlapsExisting&&(identical(other.existingLibraryRootId, existingLibraryRootId) || other.existingLibraryRootId == existingLibraryRootId)&&(identical(other.relationship, relationship) || other.relationship == relationship));
}


@override
int get hashCode => Object.hash(runtimeType,existingLibraryRootId,relationship);

@override
String toString() {
  return 'AddLocalLibraryRootAndScanResult.overlapsExisting(existingLibraryRootId: $existingLibraryRootId, relationship: $relationship)';
}


}

/// @nodoc
abstract mixin class $AddLocalLibraryRootAndScanResultOverlapsExistingCopyWith<$Res> implements $AddLocalLibraryRootAndScanResultCopyWith<$Res> {
  factory $AddLocalLibraryRootAndScanResultOverlapsExistingCopyWith(AddLocalLibraryRootAndScanResultOverlapsExisting value, $Res Function(AddLocalLibraryRootAndScanResultOverlapsExisting) _then) = _$AddLocalLibraryRootAndScanResultOverlapsExistingCopyWithImpl;
@useResult
$Res call({
 LibraryRootId existingLibraryRootId, RootRelationship relationship
});




}
/// @nodoc
class _$AddLocalLibraryRootAndScanResultOverlapsExistingCopyWithImpl<$Res>
    implements $AddLocalLibraryRootAndScanResultOverlapsExistingCopyWith<$Res> {
  _$AddLocalLibraryRootAndScanResultOverlapsExistingCopyWithImpl(this._self, this._then);

  final AddLocalLibraryRootAndScanResultOverlapsExisting _self;
  final $Res Function(AddLocalLibraryRootAndScanResultOverlapsExisting) _then;

/// Create a copy of AddLocalLibraryRootAndScanResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? existingLibraryRootId = null,Object? relationship = null,}) {
  return _then(AddLocalLibraryRootAndScanResultOverlapsExisting(
existingLibraryRootId: null == existingLibraryRootId ? _self.existingLibraryRootId : existingLibraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,relationship: null == relationship ? _self.relationship : relationship // ignore: cast_nullable_to_non_nullable
as RootRelationship,
  ));
}


}

/// @nodoc
mixin _$RemoveLibraryRootResult {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoveLibraryRootResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RemoveLibraryRootResult()';
}


}

/// @nodoc
class $RemoveLibraryRootResultCopyWith<$Res>  {
$RemoveLibraryRootResultCopyWith(RemoveLibraryRootResult _, $Res Function(RemoveLibraryRootResult) __);
}


/// Adds pattern-matching-related methods to [RemoveLibraryRootResult].
extension RemoveLibraryRootResultPatterns on RemoveLibraryRootResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RemoveLibraryRootResultRemoved value)?  removed,TResult Function( RemoveLibraryRootResultRootHasActiveScan value)?  rootHasActiveScan,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RemoveLibraryRootResultRemoved() when removed != null:
return removed(_that);case RemoveLibraryRootResultRootHasActiveScan() when rootHasActiveScan != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RemoveLibraryRootResultRemoved value)  removed,required TResult Function( RemoveLibraryRootResultRootHasActiveScan value)  rootHasActiveScan,}){
final _that = this;
switch (_that) {
case RemoveLibraryRootResultRemoved():
return removed(_that);case RemoveLibraryRootResultRootHasActiveScan():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RemoveLibraryRootResultRemoved value)?  removed,TResult? Function( RemoveLibraryRootResultRootHasActiveScan value)?  rootHasActiveScan,}){
final _that = this;
switch (_that) {
case RemoveLibraryRootResultRemoved() when removed != null:
return removed(_that);case RemoveLibraryRootResultRootHasActiveScan() when rootHasActiveScan != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  removed,TResult Function( LibraryRootId libraryRootId,  JobRunId jobRunId,  ScanRunId scanRunId,  int owningJobRootCount)?  rootHasActiveScan,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RemoveLibraryRootResultRemoved() when removed != null:
return removed();case RemoveLibraryRootResultRootHasActiveScan() when rootHasActiveScan != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  removed,required TResult Function( LibraryRootId libraryRootId,  JobRunId jobRunId,  ScanRunId scanRunId,  int owningJobRootCount)  rootHasActiveScan,}) {final _that = this;
switch (_that) {
case RemoveLibraryRootResultRemoved():
return removed();case RemoveLibraryRootResultRootHasActiveScan():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  removed,TResult? Function( LibraryRootId libraryRootId,  JobRunId jobRunId,  ScanRunId scanRunId,  int owningJobRootCount)?  rootHasActiveScan,}) {final _that = this;
switch (_that) {
case RemoveLibraryRootResultRemoved() when removed != null:
return removed();case RemoveLibraryRootResultRootHasActiveScan() when rootHasActiveScan != null:
return rootHasActiveScan(_that.libraryRootId,_that.jobRunId,_that.scanRunId,_that.owningJobRootCount);case _:
  return null;

}
}

}

/// @nodoc


class RemoveLibraryRootResultRemoved implements RemoveLibraryRootResult {
  const RemoveLibraryRootResultRemoved();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoveLibraryRootResultRemoved);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RemoveLibraryRootResult.removed()';
}


}




/// @nodoc


class RemoveLibraryRootResultRootHasActiveScan implements RemoveLibraryRootResult {
  const RemoveLibraryRootResultRootHasActiveScan({required this.libraryRootId, required this.jobRunId, required this.scanRunId, required this.owningJobRootCount});


 final  LibraryRootId libraryRootId;
 final  JobRunId jobRunId;
 final  ScanRunId scanRunId;
 final  int owningJobRootCount;

/// Create a copy of RemoveLibraryRootResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoveLibraryRootResultRootHasActiveScanCopyWith<RemoveLibraryRootResultRootHasActiveScan> get copyWith => _$RemoveLibraryRootResultRootHasActiveScanCopyWithImpl<RemoveLibraryRootResultRootHasActiveScan>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoveLibraryRootResultRootHasActiveScan&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId)&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId)&&(identical(other.scanRunId, scanRunId) || other.scanRunId == scanRunId)&&(identical(other.owningJobRootCount, owningJobRootCount) || other.owningJobRootCount == owningJobRootCount));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId,jobRunId,scanRunId,owningJobRootCount);

@override
String toString() {
  return 'RemoveLibraryRootResult.rootHasActiveScan(libraryRootId: $libraryRootId, jobRunId: $jobRunId, scanRunId: $scanRunId, owningJobRootCount: $owningJobRootCount)';
}


}

/// @nodoc
abstract mixin class $RemoveLibraryRootResultRootHasActiveScanCopyWith<$Res> implements $RemoveLibraryRootResultCopyWith<$Res> {
  factory $RemoveLibraryRootResultRootHasActiveScanCopyWith(RemoveLibraryRootResultRootHasActiveScan value, $Res Function(RemoveLibraryRootResultRootHasActiveScan) _then) = _$RemoveLibraryRootResultRootHasActiveScanCopyWithImpl;
@useResult
$Res call({
 LibraryRootId libraryRootId, JobRunId jobRunId, ScanRunId scanRunId, int owningJobRootCount
});




}
/// @nodoc
class _$RemoveLibraryRootResultRootHasActiveScanCopyWithImpl<$Res>
    implements $RemoveLibraryRootResultRootHasActiveScanCopyWith<$Res> {
  _$RemoveLibraryRootResultRootHasActiveScanCopyWithImpl(this._self, this._then);

  final RemoveLibraryRootResultRootHasActiveScan _self;
  final $Res Function(RemoveLibraryRootResultRootHasActiveScan) _then;

/// Create a copy of RemoveLibraryRootResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? libraryRootId = null,Object? jobRunId = null,Object? scanRunId = null,Object? owningJobRootCount = null,}) {
  return _then(RemoveLibraryRootResultRootHasActiveScan(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,scanRunId: null == scanRunId ? _self.scanRunId : scanRunId // ignore: cast_nullable_to_non_nullable
as ScanRunId,owningJobRootCount: null == owningJobRootCount ? _self.owningJobRootCount : owningJobRootCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$RuntimeEventPayload {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayload);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RuntimeEventPayload()';
}


}

/// @nodoc
class $RuntimeEventPayloadCopyWith<$Res>  {
$RuntimeEventPayloadCopyWith(RuntimeEventPayload _, $Res Function(RuntimeEventPayload) __);
}


/// Adds pattern-matching-related methods to [RuntimeEventPayload].
extension RuntimeEventPayloadPatterns on RuntimeEventPayload {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RuntimeEventPayloadRuntimeStateChanged value)?  runtimeStateChanged,TResult Function( RuntimeEventPayloadStartupFailed value)?  startupFailed,TResult Function( RuntimeEventPayloadAppearanceSettingsChanged value)?  appearanceSettingsChanged,TResult Function( RuntimeEventPayloadLibraryRootsChanged value)?  libraryRootsChanged,TResult Function( RuntimeEventPayloadLibraryRootChanged value)?  libraryRootChanged,TResult Function( RuntimeEventPayloadJobStateChanged value)?  jobStateChanged,TResult Function( RuntimeEventPayloadJobProgress value)?  jobProgress,TResult Function( RuntimeEventPayloadSourceEntriesChanged value)?  sourceEntriesChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadRuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that);case RuntimeEventPayloadStartupFailed() when startupFailed != null:
return startupFailed(_that);case RuntimeEventPayloadAppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged(_that);case RuntimeEventPayloadLibraryRootsChanged() when libraryRootsChanged != null:
return libraryRootsChanged(_that);case RuntimeEventPayloadLibraryRootChanged() when libraryRootChanged != null:
return libraryRootChanged(_that);case RuntimeEventPayloadJobStateChanged() when jobStateChanged != null:
return jobStateChanged(_that);case RuntimeEventPayloadJobProgress() when jobProgress != null:
return jobProgress(_that);case RuntimeEventPayloadSourceEntriesChanged() when sourceEntriesChanged != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RuntimeEventPayloadRuntimeStateChanged value)  runtimeStateChanged,required TResult Function( RuntimeEventPayloadStartupFailed value)  startupFailed,required TResult Function( RuntimeEventPayloadAppearanceSettingsChanged value)  appearanceSettingsChanged,required TResult Function( RuntimeEventPayloadLibraryRootsChanged value)  libraryRootsChanged,required TResult Function( RuntimeEventPayloadLibraryRootChanged value)  libraryRootChanged,required TResult Function( RuntimeEventPayloadJobStateChanged value)  jobStateChanged,required TResult Function( RuntimeEventPayloadJobProgress value)  jobProgress,required TResult Function( RuntimeEventPayloadSourceEntriesChanged value)  sourceEntriesChanged,}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadRuntimeStateChanged():
return runtimeStateChanged(_that);case RuntimeEventPayloadStartupFailed():
return startupFailed(_that);case RuntimeEventPayloadAppearanceSettingsChanged():
return appearanceSettingsChanged(_that);case RuntimeEventPayloadLibraryRootsChanged():
return libraryRootsChanged(_that);case RuntimeEventPayloadLibraryRootChanged():
return libraryRootChanged(_that);case RuntimeEventPayloadJobStateChanged():
return jobStateChanged(_that);case RuntimeEventPayloadJobProgress():
return jobProgress(_that);case RuntimeEventPayloadSourceEntriesChanged():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RuntimeEventPayloadRuntimeStateChanged value)?  runtimeStateChanged,TResult? Function( RuntimeEventPayloadStartupFailed value)?  startupFailed,TResult? Function( RuntimeEventPayloadAppearanceSettingsChanged value)?  appearanceSettingsChanged,TResult? Function( RuntimeEventPayloadLibraryRootsChanged value)?  libraryRootsChanged,TResult? Function( RuntimeEventPayloadLibraryRootChanged value)?  libraryRootChanged,TResult? Function( RuntimeEventPayloadJobStateChanged value)?  jobStateChanged,TResult? Function( RuntimeEventPayloadJobProgress value)?  jobProgress,TResult? Function( RuntimeEventPayloadSourceEntriesChanged value)?  sourceEntriesChanged,}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadRuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that);case RuntimeEventPayloadStartupFailed() when startupFailed != null:
return startupFailed(_that);case RuntimeEventPayloadAppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged(_that);case RuntimeEventPayloadLibraryRootsChanged() when libraryRootsChanged != null:
return libraryRootsChanged(_that);case RuntimeEventPayloadLibraryRootChanged() when libraryRootChanged != null:
return libraryRootChanged(_that);case RuntimeEventPayloadJobStateChanged() when jobStateChanged != null:
return jobStateChanged(_that);case RuntimeEventPayloadJobProgress() when jobProgress != null:
return jobProgress(_that);case RuntimeEventPayloadSourceEntriesChanged() when sourceEntriesChanged != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( RuntimeLifecycle lifecycle)?  runtimeStateChanged,TResult Function( StartupPhase phase)?  startupFailed,TResult Function()?  appearanceSettingsChanged,TResult Function()?  libraryRootsChanged,TResult Function( LibraryRootId libraryRootId)?  libraryRootChanged,TResult Function( JobRunId jobRunId)?  jobStateChanged,TResult Function( JobRunId jobRunId,  String phase,  int? completedUnits,  int? totalUnits,  String? statusKey)?  jobProgress,TResult Function( LibraryRootId libraryRootId,  SourceEntriesChangeScope scope)?  sourceEntriesChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadRuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadStartupFailed() when startupFailed != null:
return startupFailed(_that.phase);case RuntimeEventPayloadAppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged();case RuntimeEventPayloadLibraryRootsChanged() when libraryRootsChanged != null:
return libraryRootsChanged();case RuntimeEventPayloadLibraryRootChanged() when libraryRootChanged != null:
return libraryRootChanged(_that.libraryRootId);case RuntimeEventPayloadJobStateChanged() when jobStateChanged != null:
return jobStateChanged(_that.jobRunId);case RuntimeEventPayloadJobProgress() when jobProgress != null:
return jobProgress(_that.jobRunId,_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey);case RuntimeEventPayloadSourceEntriesChanged() when sourceEntriesChanged != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( RuntimeLifecycle lifecycle)  runtimeStateChanged,required TResult Function( StartupPhase phase)  startupFailed,required TResult Function()  appearanceSettingsChanged,required TResult Function()  libraryRootsChanged,required TResult Function( LibraryRootId libraryRootId)  libraryRootChanged,required TResult Function( JobRunId jobRunId)  jobStateChanged,required TResult Function( JobRunId jobRunId,  String phase,  int? completedUnits,  int? totalUnits,  String? statusKey)  jobProgress,required TResult Function( LibraryRootId libraryRootId,  SourceEntriesChangeScope scope)  sourceEntriesChanged,}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadRuntimeStateChanged():
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadStartupFailed():
return startupFailed(_that.phase);case RuntimeEventPayloadAppearanceSettingsChanged():
return appearanceSettingsChanged();case RuntimeEventPayloadLibraryRootsChanged():
return libraryRootsChanged();case RuntimeEventPayloadLibraryRootChanged():
return libraryRootChanged(_that.libraryRootId);case RuntimeEventPayloadJobStateChanged():
return jobStateChanged(_that.jobRunId);case RuntimeEventPayloadJobProgress():
return jobProgress(_that.jobRunId,_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey);case RuntimeEventPayloadSourceEntriesChanged():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( RuntimeLifecycle lifecycle)?  runtimeStateChanged,TResult? Function( StartupPhase phase)?  startupFailed,TResult? Function()?  appearanceSettingsChanged,TResult? Function()?  libraryRootsChanged,TResult? Function( LibraryRootId libraryRootId)?  libraryRootChanged,TResult? Function( JobRunId jobRunId)?  jobStateChanged,TResult? Function( JobRunId jobRunId,  String phase,  int? completedUnits,  int? totalUnits,  String? statusKey)?  jobProgress,TResult? Function( LibraryRootId libraryRootId,  SourceEntriesChangeScope scope)?  sourceEntriesChanged,}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadRuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadStartupFailed() when startupFailed != null:
return startupFailed(_that.phase);case RuntimeEventPayloadAppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged();case RuntimeEventPayloadLibraryRootsChanged() when libraryRootsChanged != null:
return libraryRootsChanged();case RuntimeEventPayloadLibraryRootChanged() when libraryRootChanged != null:
return libraryRootChanged(_that.libraryRootId);case RuntimeEventPayloadJobStateChanged() when jobStateChanged != null:
return jobStateChanged(_that.jobRunId);case RuntimeEventPayloadJobProgress() when jobProgress != null:
return jobProgress(_that.jobRunId,_that.phase,_that.completedUnits,_that.totalUnits,_that.statusKey);case RuntimeEventPayloadSourceEntriesChanged() when sourceEntriesChanged != null:
return sourceEntriesChanged(_that.libraryRootId,_that.scope);case _:
  return null;

}
}

}

/// @nodoc


class RuntimeEventPayloadRuntimeStateChanged implements RuntimeEventPayload {
  const RuntimeEventPayloadRuntimeStateChanged({required this.lifecycle});


 final  RuntimeLifecycle lifecycle;

/// Create a copy of RuntimeEventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeEventPayloadRuntimeStateChangedCopyWith<RuntimeEventPayloadRuntimeStateChanged> get copyWith => _$RuntimeEventPayloadRuntimeStateChangedCopyWithImpl<RuntimeEventPayloadRuntimeStateChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadRuntimeStateChanged&&(identical(other.lifecycle, lifecycle) || other.lifecycle == lifecycle));
}


@override
int get hashCode => Object.hash(runtimeType,lifecycle);

@override
String toString() {
  return 'RuntimeEventPayload.runtimeStateChanged(lifecycle: $lifecycle)';
}


}

/// @nodoc
abstract mixin class $RuntimeEventPayloadRuntimeStateChangedCopyWith<$Res> implements $RuntimeEventPayloadCopyWith<$Res> {
  factory $RuntimeEventPayloadRuntimeStateChangedCopyWith(RuntimeEventPayloadRuntimeStateChanged value, $Res Function(RuntimeEventPayloadRuntimeStateChanged) _then) = _$RuntimeEventPayloadRuntimeStateChangedCopyWithImpl;
@useResult
$Res call({
 RuntimeLifecycle lifecycle
});




}
/// @nodoc
class _$RuntimeEventPayloadRuntimeStateChangedCopyWithImpl<$Res>
    implements $RuntimeEventPayloadRuntimeStateChangedCopyWith<$Res> {
  _$RuntimeEventPayloadRuntimeStateChangedCopyWithImpl(this._self, this._then);

  final RuntimeEventPayloadRuntimeStateChanged _self;
  final $Res Function(RuntimeEventPayloadRuntimeStateChanged) _then;

/// Create a copy of RuntimeEventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? lifecycle = null,}) {
  return _then(RuntimeEventPayloadRuntimeStateChanged(
lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as RuntimeLifecycle,
  ));
}


}

/// @nodoc


class RuntimeEventPayloadStartupFailed implements RuntimeEventPayload {
  const RuntimeEventPayloadStartupFailed({required this.phase});


 final  StartupPhase phase;

/// Create a copy of RuntimeEventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeEventPayloadStartupFailedCopyWith<RuntimeEventPayloadStartupFailed> get copyWith => _$RuntimeEventPayloadStartupFailedCopyWithImpl<RuntimeEventPayloadStartupFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadStartupFailed&&(identical(other.phase, phase) || other.phase == phase));
}


@override
int get hashCode => Object.hash(runtimeType,phase);

@override
String toString() {
  return 'RuntimeEventPayload.startupFailed(phase: $phase)';
}


}

/// @nodoc
abstract mixin class $RuntimeEventPayloadStartupFailedCopyWith<$Res> implements $RuntimeEventPayloadCopyWith<$Res> {
  factory $RuntimeEventPayloadStartupFailedCopyWith(RuntimeEventPayloadStartupFailed value, $Res Function(RuntimeEventPayloadStartupFailed) _then) = _$RuntimeEventPayloadStartupFailedCopyWithImpl;
@useResult
$Res call({
 StartupPhase phase
});




}
/// @nodoc
class _$RuntimeEventPayloadStartupFailedCopyWithImpl<$Res>
    implements $RuntimeEventPayloadStartupFailedCopyWith<$Res> {
  _$RuntimeEventPayloadStartupFailedCopyWithImpl(this._self, this._then);

  final RuntimeEventPayloadStartupFailed _self;
  final $Res Function(RuntimeEventPayloadStartupFailed) _then;

/// Create a copy of RuntimeEventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? phase = null,}) {
  return _then(RuntimeEventPayloadStartupFailed(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as StartupPhase,
  ));
}


}

/// @nodoc


class RuntimeEventPayloadAppearanceSettingsChanged implements RuntimeEventPayload {
  const RuntimeEventPayloadAppearanceSettingsChanged();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadAppearanceSettingsChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RuntimeEventPayload.appearanceSettingsChanged()';
}


}




/// @nodoc


class RuntimeEventPayloadLibraryRootsChanged implements RuntimeEventPayload {
  const RuntimeEventPayloadLibraryRootsChanged();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadLibraryRootsChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RuntimeEventPayload.libraryRootsChanged()';
}


}




/// @nodoc


class RuntimeEventPayloadLibraryRootChanged implements RuntimeEventPayload {
  const RuntimeEventPayloadLibraryRootChanged({required this.libraryRootId});


 final  LibraryRootId libraryRootId;

/// Create a copy of RuntimeEventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeEventPayloadLibraryRootChangedCopyWith<RuntimeEventPayloadLibraryRootChanged> get copyWith => _$RuntimeEventPayloadLibraryRootChangedCopyWithImpl<RuntimeEventPayloadLibraryRootChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadLibraryRootChanged&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId);

@override
String toString() {
  return 'RuntimeEventPayload.libraryRootChanged(libraryRootId: $libraryRootId)';
}


}

/// @nodoc
abstract mixin class $RuntimeEventPayloadLibraryRootChangedCopyWith<$Res> implements $RuntimeEventPayloadCopyWith<$Res> {
  factory $RuntimeEventPayloadLibraryRootChangedCopyWith(RuntimeEventPayloadLibraryRootChanged value, $Res Function(RuntimeEventPayloadLibraryRootChanged) _then) = _$RuntimeEventPayloadLibraryRootChangedCopyWithImpl;
@useResult
$Res call({
 LibraryRootId libraryRootId
});




}
/// @nodoc
class _$RuntimeEventPayloadLibraryRootChangedCopyWithImpl<$Res>
    implements $RuntimeEventPayloadLibraryRootChangedCopyWith<$Res> {
  _$RuntimeEventPayloadLibraryRootChangedCopyWithImpl(this._self, this._then);

  final RuntimeEventPayloadLibraryRootChanged _self;
  final $Res Function(RuntimeEventPayloadLibraryRootChanged) _then;

/// Create a copy of RuntimeEventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? libraryRootId = null,}) {
  return _then(RuntimeEventPayloadLibraryRootChanged(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,
  ));
}


}

/// @nodoc


class RuntimeEventPayloadJobStateChanged implements RuntimeEventPayload {
  const RuntimeEventPayloadJobStateChanged({required this.jobRunId});


 final  JobRunId jobRunId;

/// Create a copy of RuntimeEventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeEventPayloadJobStateChangedCopyWith<RuntimeEventPayloadJobStateChanged> get copyWith => _$RuntimeEventPayloadJobStateChangedCopyWithImpl<RuntimeEventPayloadJobStateChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadJobStateChanged&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId));
}


@override
int get hashCode => Object.hash(runtimeType,jobRunId);

@override
String toString() {
  return 'RuntimeEventPayload.jobStateChanged(jobRunId: $jobRunId)';
}


}

/// @nodoc
abstract mixin class $RuntimeEventPayloadJobStateChangedCopyWith<$Res> implements $RuntimeEventPayloadCopyWith<$Res> {
  factory $RuntimeEventPayloadJobStateChangedCopyWith(RuntimeEventPayloadJobStateChanged value, $Res Function(RuntimeEventPayloadJobStateChanged) _then) = _$RuntimeEventPayloadJobStateChangedCopyWithImpl;
@useResult
$Res call({
 JobRunId jobRunId
});




}
/// @nodoc
class _$RuntimeEventPayloadJobStateChangedCopyWithImpl<$Res>
    implements $RuntimeEventPayloadJobStateChangedCopyWith<$Res> {
  _$RuntimeEventPayloadJobStateChangedCopyWithImpl(this._self, this._then);

  final RuntimeEventPayloadJobStateChanged _self;
  final $Res Function(RuntimeEventPayloadJobStateChanged) _then;

/// Create a copy of RuntimeEventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? jobRunId = null,}) {
  return _then(RuntimeEventPayloadJobStateChanged(
jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,
  ));
}


}

/// @nodoc


class RuntimeEventPayloadJobProgress implements RuntimeEventPayload {
  const RuntimeEventPayloadJobProgress({required this.jobRunId, required this.phase, this.completedUnits, this.totalUnits, this.statusKey});


 final  JobRunId jobRunId;
 final  String phase;
 final  int? completedUnits;
 final  int? totalUnits;
 final  String? statusKey;

/// Create a copy of RuntimeEventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeEventPayloadJobProgressCopyWith<RuntimeEventPayloadJobProgress> get copyWith => _$RuntimeEventPayloadJobProgressCopyWithImpl<RuntimeEventPayloadJobProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadJobProgress&&(identical(other.jobRunId, jobRunId) || other.jobRunId == jobRunId)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.completedUnits, completedUnits) || other.completedUnits == completedUnits)&&(identical(other.totalUnits, totalUnits) || other.totalUnits == totalUnits)&&(identical(other.statusKey, statusKey) || other.statusKey == statusKey));
}


@override
int get hashCode => Object.hash(runtimeType,jobRunId,phase,completedUnits,totalUnits,statusKey);

@override
String toString() {
  return 'RuntimeEventPayload.jobProgress(jobRunId: $jobRunId, phase: $phase, completedUnits: $completedUnits, totalUnits: $totalUnits, statusKey: $statusKey)';
}


}

/// @nodoc
abstract mixin class $RuntimeEventPayloadJobProgressCopyWith<$Res> implements $RuntimeEventPayloadCopyWith<$Res> {
  factory $RuntimeEventPayloadJobProgressCopyWith(RuntimeEventPayloadJobProgress value, $Res Function(RuntimeEventPayloadJobProgress) _then) = _$RuntimeEventPayloadJobProgressCopyWithImpl;
@useResult
$Res call({
 JobRunId jobRunId, String phase, int? completedUnits, int? totalUnits, String? statusKey
});




}
/// @nodoc
class _$RuntimeEventPayloadJobProgressCopyWithImpl<$Res>
    implements $RuntimeEventPayloadJobProgressCopyWith<$Res> {
  _$RuntimeEventPayloadJobProgressCopyWithImpl(this._self, this._then);

  final RuntimeEventPayloadJobProgress _self;
  final $Res Function(RuntimeEventPayloadJobProgress) _then;

/// Create a copy of RuntimeEventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? jobRunId = null,Object? phase = null,Object? completedUnits = freezed,Object? totalUnits = freezed,Object? statusKey = freezed,}) {
  return _then(RuntimeEventPayloadJobProgress(
jobRunId: null == jobRunId ? _self.jobRunId : jobRunId // ignore: cast_nullable_to_non_nullable
as JobRunId,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String,completedUnits: freezed == completedUnits ? _self.completedUnits : completedUnits // ignore: cast_nullable_to_non_nullable
as int?,totalUnits: freezed == totalUnits ? _self.totalUnits : totalUnits // ignore: cast_nullable_to_non_nullable
as int?,statusKey: freezed == statusKey ? _self.statusKey : statusKey // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class RuntimeEventPayloadSourceEntriesChanged implements RuntimeEventPayload {
  const RuntimeEventPayloadSourceEntriesChanged({required this.libraryRootId, required this.scope});


 final  LibraryRootId libraryRootId;
 final  SourceEntriesChangeScope scope;

/// Create a copy of RuntimeEventPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeEventPayloadSourceEntriesChangedCopyWith<RuntimeEventPayloadSourceEntriesChanged> get copyWith => _$RuntimeEventPayloadSourceEntriesChangedCopyWithImpl<RuntimeEventPayloadSourceEntriesChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEventPayloadSourceEntriesChanged&&(identical(other.libraryRootId, libraryRootId) || other.libraryRootId == libraryRootId)&&(identical(other.scope, scope) || other.scope == scope));
}


@override
int get hashCode => Object.hash(runtimeType,libraryRootId,scope);

@override
String toString() {
  return 'RuntimeEventPayload.sourceEntriesChanged(libraryRootId: $libraryRootId, scope: $scope)';
}


}

/// @nodoc
abstract mixin class $RuntimeEventPayloadSourceEntriesChangedCopyWith<$Res> implements $RuntimeEventPayloadCopyWith<$Res> {
  factory $RuntimeEventPayloadSourceEntriesChangedCopyWith(RuntimeEventPayloadSourceEntriesChanged value, $Res Function(RuntimeEventPayloadSourceEntriesChanged) _then) = _$RuntimeEventPayloadSourceEntriesChangedCopyWithImpl;
@useResult
$Res call({
 LibraryRootId libraryRootId, SourceEntriesChangeScope scope
});


$SourceEntriesChangeScopeCopyWith<$Res> get scope;

}
/// @nodoc
class _$RuntimeEventPayloadSourceEntriesChangedCopyWithImpl<$Res>
    implements $RuntimeEventPayloadSourceEntriesChangedCopyWith<$Res> {
  _$RuntimeEventPayloadSourceEntriesChangedCopyWithImpl(this._self, this._then);

  final RuntimeEventPayloadSourceEntriesChanged _self;
  final $Res Function(RuntimeEventPayloadSourceEntriesChanged) _then;

/// Create a copy of RuntimeEventPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? libraryRootId = null,Object? scope = null,}) {
  return _then(RuntimeEventPayloadSourceEntriesChanged(
libraryRootId: null == libraryRootId ? _self.libraryRootId : libraryRootId // ignore: cast_nullable_to_non_nullable
as LibraryRootId,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as SourceEntriesChangeScope,
  ));
}

/// Create a copy of RuntimeEventPayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceEntriesChangeScopeCopyWith<$Res> get scope {

  return $SourceEntriesChangeScopeCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}

/// @nodoc
mixin _$RuntimeEvent {

 RuntimeInstanceId get runtimeInstanceId; BigInt get sequence; BigInt get occurredAtMs; RuntimeEventPayload get payload;
/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeEventCopyWith<RuntimeEvent> get copyWith => _$RuntimeEventCopyWithImpl<RuntimeEvent>(this as RuntimeEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEvent&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId)&&(identical(other.sequence, sequence) || other.sequence == sequence)&&(identical(other.occurredAtMs, occurredAtMs) || other.occurredAtMs == occurredAtMs)&&(identical(other.payload, payload) || other.payload == payload));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId,sequence,occurredAtMs,payload);

@override
String toString() {
  return 'RuntimeEvent(runtimeInstanceId: $runtimeInstanceId, sequence: $sequence, occurredAtMs: $occurredAtMs, payload: $payload)';
}


}

/// @nodoc
abstract mixin class $RuntimeEventCopyWith<$Res>  {
  factory $RuntimeEventCopyWith(RuntimeEvent value, $Res Function(RuntimeEvent) _then) = _$RuntimeEventCopyWithImpl;
@useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId, BigInt sequence, BigInt occurredAtMs, RuntimeEventPayload payload
});


$RuntimeEventPayloadCopyWith<$Res> get payload;

}
/// @nodoc
class _$RuntimeEventCopyWithImpl<$Res>
    implements $RuntimeEventCopyWith<$Res> {
  _$RuntimeEventCopyWithImpl(this._self, this._then);

  final RuntimeEvent _self;
  final $Res Function(RuntimeEvent) _then;

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? runtimeInstanceId = null,Object? sequence = null,Object? occurredAtMs = null,Object? payload = null,}) {
  return _then(_self.copyWith(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,sequence: null == sequence ? _self.sequence : sequence // ignore: cast_nullable_to_non_nullable
as BigInt,occurredAtMs: null == occurredAtMs ? _self.occurredAtMs : occurredAtMs // ignore: cast_nullable_to_non_nullable
as BigInt,payload: null == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as RuntimeEventPayload,
  ));
}
/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RuntimeEventPayloadCopyWith<$Res> get payload {

  return $RuntimeEventPayloadCopyWith<$Res>(_self.payload, (value) {
    return _then(_self.copyWith(payload: value));
  });
}
}


/// Adds pattern-matching-related methods to [RuntimeEvent].
extension RuntimeEventPatterns on RuntimeEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RuntimeEvent value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RuntimeEvent() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RuntimeEvent value)  $default,){
final _that = this;
switch (_that) {
case _RuntimeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RuntimeEvent value)?  $default,){
final _that = this;
switch (_that) {
case _RuntimeEvent() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RuntimeInstanceId runtimeInstanceId,  BigInt sequence,  BigInt occurredAtMs,  RuntimeEventPayload payload)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RuntimeEvent() when $default != null:
return $default(_that.runtimeInstanceId,_that.sequence,_that.occurredAtMs,_that.payload);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RuntimeInstanceId runtimeInstanceId,  BigInt sequence,  BigInt occurredAtMs,  RuntimeEventPayload payload)  $default,) {final _that = this;
switch (_that) {
case _RuntimeEvent():
return $default(_that.runtimeInstanceId,_that.sequence,_that.occurredAtMs,_that.payload);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RuntimeInstanceId runtimeInstanceId,  BigInt sequence,  BigInt occurredAtMs,  RuntimeEventPayload payload)?  $default,) {final _that = this;
switch (_that) {
case _RuntimeEvent() when $default != null:
return $default(_that.runtimeInstanceId,_that.sequence,_that.occurredAtMs,_that.payload);case _:
  return null;

}
}

}

/// @nodoc


class _RuntimeEvent implements RuntimeEvent {
  const _RuntimeEvent({required this.runtimeInstanceId, required this.sequence, required this.occurredAtMs, required this.payload});


@override final  RuntimeInstanceId runtimeInstanceId;
@override final  BigInt sequence;
@override final  BigInt occurredAtMs;
@override final  RuntimeEventPayload payload;

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RuntimeEventCopyWith<_RuntimeEvent> get copyWith => __$RuntimeEventCopyWithImpl<_RuntimeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RuntimeEvent&&(identical(other.runtimeInstanceId, runtimeInstanceId) || other.runtimeInstanceId == runtimeInstanceId)&&(identical(other.sequence, sequence) || other.sequence == sequence)&&(identical(other.occurredAtMs, occurredAtMs) || other.occurredAtMs == occurredAtMs)&&(identical(other.payload, payload) || other.payload == payload));
}


@override
int get hashCode => Object.hash(runtimeType,runtimeInstanceId,sequence,occurredAtMs,payload);

@override
String toString() {
  return 'RuntimeEvent(runtimeInstanceId: $runtimeInstanceId, sequence: $sequence, occurredAtMs: $occurredAtMs, payload: $payload)';
}


}

/// @nodoc
abstract mixin class _$RuntimeEventCopyWith<$Res> implements $RuntimeEventCopyWith<$Res> {
  factory _$RuntimeEventCopyWith(_RuntimeEvent value, $Res Function(_RuntimeEvent) _then) = __$RuntimeEventCopyWithImpl;
@override @useResult
$Res call({
 RuntimeInstanceId runtimeInstanceId, BigInt sequence, BigInt occurredAtMs, RuntimeEventPayload payload
});


@override $RuntimeEventPayloadCopyWith<$Res> get payload;

}
/// @nodoc
class __$RuntimeEventCopyWithImpl<$Res>
    implements _$RuntimeEventCopyWith<$Res> {
  __$RuntimeEventCopyWithImpl(this._self, this._then);

  final _RuntimeEvent _self;
  final $Res Function(_RuntimeEvent) _then;

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runtimeInstanceId = null,Object? sequence = null,Object? occurredAtMs = null,Object? payload = null,}) {
  return _then(_RuntimeEvent(
runtimeInstanceId: null == runtimeInstanceId ? _self.runtimeInstanceId : runtimeInstanceId // ignore: cast_nullable_to_non_nullable
as RuntimeInstanceId,sequence: null == sequence ? _self.sequence : sequence // ignore: cast_nullable_to_non_nullable
as BigInt,occurredAtMs: null == occurredAtMs ? _self.occurredAtMs : occurredAtMs // ignore: cast_nullable_to_non_nullable
as BigInt,payload: null == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as RuntimeEventPayload,
  ));
}

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RuntimeEventPayloadCopyWith<$Res> get payload {

  return $RuntimeEventPayloadCopyWith<$Res>(_self.payload, (value) {
    return _then(_self.copyWith(payload: value));
  });
}
}

// dart format on
