import 'foreground_execution_host_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'foreground_execution_host_composition.g.dart';

/// Optional app-composition foreground host; desktop and tests leave it null.
@Riverpod(keepAlive: true)
ForegroundExecutionHostApi? foregroundExecutionHostApi(Ref ref) => null;
