import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owns the single application-level Riverpod scope.
class ArgusBootstrap extends StatelessWidget {
  /// Creates the application bootstrap root.
  const ArgusBootstrap({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(child: ArgusApp());
  }
}

/// Starts the application with its root dependency scope.
void bootstrapArgus() {
  runApp(const ArgusBootstrap());
}
