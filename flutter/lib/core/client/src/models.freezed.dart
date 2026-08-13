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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RuntimeEventPayloadRuntimeStateChanged value)?  runtimeStateChanged,TResult Function( RuntimeEventPayloadStartupFailed value)?  startupFailed,TResult Function( RuntimeEventPayloadAppearanceSettingsChanged value)?  appearanceSettingsChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadRuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that);case RuntimeEventPayloadStartupFailed() when startupFailed != null:
return startupFailed(_that);case RuntimeEventPayloadAppearanceSettingsChanged() when appearanceSettingsChanged != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RuntimeEventPayloadRuntimeStateChanged value)  runtimeStateChanged,required TResult Function( RuntimeEventPayloadStartupFailed value)  startupFailed,required TResult Function( RuntimeEventPayloadAppearanceSettingsChanged value)  appearanceSettingsChanged,}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadRuntimeStateChanged():
return runtimeStateChanged(_that);case RuntimeEventPayloadStartupFailed():
return startupFailed(_that);case RuntimeEventPayloadAppearanceSettingsChanged():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RuntimeEventPayloadRuntimeStateChanged value)?  runtimeStateChanged,TResult? Function( RuntimeEventPayloadStartupFailed value)?  startupFailed,TResult? Function( RuntimeEventPayloadAppearanceSettingsChanged value)?  appearanceSettingsChanged,}){
final _that = this;
switch (_that) {
case RuntimeEventPayloadRuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that);case RuntimeEventPayloadStartupFailed() when startupFailed != null:
return startupFailed(_that);case RuntimeEventPayloadAppearanceSettingsChanged() when appearanceSettingsChanged != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( RuntimeLifecycle lifecycle)?  runtimeStateChanged,TResult Function( StartupPhase phase)?  startupFailed,TResult Function()?  appearanceSettingsChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadRuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadStartupFailed() when startupFailed != null:
return startupFailed(_that.phase);case RuntimeEventPayloadAppearanceSettingsChanged() when appearanceSettingsChanged != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( RuntimeLifecycle lifecycle)  runtimeStateChanged,required TResult Function( StartupPhase phase)  startupFailed,required TResult Function()  appearanceSettingsChanged,}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadRuntimeStateChanged():
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadStartupFailed():
return startupFailed(_that.phase);case RuntimeEventPayloadAppearanceSettingsChanged():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( RuntimeLifecycle lifecycle)?  runtimeStateChanged,TResult? Function( StartupPhase phase)?  startupFailed,TResult? Function()?  appearanceSettingsChanged,}) {final _that = this;
switch (_that) {
case RuntimeEventPayloadRuntimeStateChanged() when runtimeStateChanged != null:
return runtimeStateChanged(_that.lifecycle);case RuntimeEventPayloadStartupFailed() when startupFailed != null:
return startupFailed(_that.phase);case RuntimeEventPayloadAppearanceSettingsChanged() when appearanceSettingsChanged != null:
return appearanceSettingsChanged();case _:
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
