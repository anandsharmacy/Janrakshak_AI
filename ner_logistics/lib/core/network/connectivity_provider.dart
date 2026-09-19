import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when the device reports at least one usable network interface.
///
/// This is a *hint*, not proof of reachability: the location uploader still
/// treats a failed RPC as "offline" and keeps its queue. Screens use it for
/// the offline banner and the rider's sync card.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  yield _online(await connectivity.checkConnectivity());
  await for (final results in connectivity.onConnectivityChanged) {
    yield _online(results);
  }
});

bool _online(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);
