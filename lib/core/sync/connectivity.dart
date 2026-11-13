import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether the phone has any network (Wi-Fi, mobile data, ethernet) at all,
/// emitting only when that changes.
///
/// This says nothing about whether the POS server can be reached — a Wi-Fi
/// network without the server still counts as connected. It is only a quick
/// signal that a connection came back (time to upload) or vanished entirely
/// (no point waiting for a timeout). Created lazily, so nothing is listened
/// to until the app subscribes.
Stream<bool> deviceConnectivity() => Connectivity().onConnectivityChanged
    .map((results) => results.any((r) => r != ConnectivityResult.none))
    .distinct();
