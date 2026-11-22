import '../models/route_entry.dart';

class RoutingService {
  RoutingService._();

  static final RoutingService instance = RoutingService._();

  String? findDirectAddress({
    required String deviceId,
    required Map<String, String> peerIdsByAddress,
    required List<String> connectedAddresses,
  }) {
    for (final entry in peerIdsByAddress.entries) {
      if (entry.value == deviceId && connectedAddresses.contains(entry.key)) {
        return entry.key;
      }
    }

    return null;
  }

  String? findNextHop({
    required String destinationId,
    required Map<String, String> peerIdsByAddress,
    required Map<String, String> reachablePeers,
    required List<String> connectedAddresses,
  }) {
    final directAddress = findDirectAddress(
      deviceId: destinationId,
      peerIdsByAddress: peerIdsByAddress,
      connectedAddresses: connectedAddresses,
    );

    if (directAddress != null) {
      return directAddress;
    }

    final relayAddress = reachablePeers[destinationId];

    if (relayAddress != null && connectedAddresses.contains(relayAddress)) {
      return relayAddress;
    }

    return null;
  }

  Map<String, String>? processPeersPacket({
    required String senderAddress,
    required String? senderDeviceId,
    required dynamic receivedPeers,
    required String localDeviceId,
    required Map<String, String> peerIdsByAddress,
    required Map<String, String> reachablePeers,
    required List<String> connectedAddresses,
  }) {
    if (!connectedAddresses.contains(senderAddress) ||
        senderDeviceId == null ||
        peerIdsByAddress[senderAddress] != senderDeviceId ||
        receivedPeers is! List) {
      return null;
    }

    final peerIds = receivedPeers
        .whereType<String>()
        .where(
          (id) => id.isNotEmpty && id != localDeviceId && id != senderDeviceId,
        )
        .toSet();

    final updatedRoutes = Map<String, String>.from(reachablePeers);

    updatedRoutes.removeWhere(
      (deviceId, nextHopAddress) => nextHopAddress == senderAddress,
    );

    for (final peerId in peerIds) {
      final directAddress = findDirectAddress(
        deviceId: peerId,
        peerIdsByAddress: peerIdsByAddress,
        connectedAddresses: connectedAddresses,
      );

      if (directAddress == null) {
        updatedRoutes[peerId] = senderAddress;
      }
    }

    return updatedRoutes;
  }

  Map<String, dynamic> createHelloPacket(String deviceId) {
    return {'type': 'hello', 'deviceId': deviceId};
  }

  Map<String, dynamic> createPeersPacket({
    required String localDeviceId,
    required String targetAddress,
    required Map<String, String> peerIdsByAddress,
    required List<String> connectedAddresses,
  }) {
    final peers = peerIdsByAddress.entries
        .where(
          (entry) =>
              connectedAddresses.contains(entry.key) &&
              entry.key != targetAddress &&
              entry.value.isNotEmpty,
        )
        .map((entry) => entry.value)
        .toList();

    return {'type': 'peers', 'deviceId': localDeviceId, 'peers': peers};
  }

  Map<String, RouteEntry>? processRoutePacket({
    required String senderAddress,
    required String? senderDeviceId,
    required dynamic receivedRoutes,
    required String localDeviceId,
    required Map<String, String> peerIdsByAddress,
    required Map<String, RouteEntry> knownRoutes,
    required List<String> connectedAddresses,
    required int maxHopCount,
  }) {
    if (!connectedAddresses.contains(senderAddress) ||
        senderDeviceId == null ||
        peerIdsByAddress[senderAddress] != senderDeviceId ||
        receivedRoutes is! List) {
      return null;
    }

    final updatedRoutes = Map<String, RouteEntry>.from(knownRoutes);

    updatedRoutes.removeWhere(
      (_, route) => route.nextHopAddress == senderAddress,
    );

    for (final item in receivedRoutes) {
      if (item is! Map) continue;

      final destinationId = item['destinationId'];
      final advertisedHops = item['hopCount'];

      if (destinationId is! String ||
          destinationId.isEmpty ||
          advertisedHops is! int ||
          advertisedHops < 1) {
        continue;
      }

      final hopCount = advertisedHops + 1;

      if (destinationId == localDeviceId ||
          destinationId == senderDeviceId ||
          hopCount > maxHopCount) {
        continue;
      }

      final directAddress = findDirectAddress(
        deviceId: destinationId,
        peerIdsByAddress: peerIdsByAddress,
        connectedAddresses: connectedAddresses,
      );

      if (directAddress != null) continue;

      final existingRoute = updatedRoutes[destinationId];

      if (existingRoute == null || hopCount < existingRoute.hopCount) {
        updatedRoutes[destinationId] = RouteEntry(
          destinationId: destinationId,
          nextHopAddress: senderAddress,
          hopCount: hopCount,
        );
      }
    }

    return updatedRoutes;
  }

  Map<String, dynamic> createRoutesPacket({
    required String localDeviceId,
    required String targetAddress,
    required Map<String, String> peerIdsByAddress,
    required Map<String, RouteEntry> knownRoutes,
    required List<String> connectedAddresses,
    required int maxHopCount,
  }) {
    final routes = <Map<String, dynamic>>[];

    for (final entry in peerIdsByAddress.entries) {
      if (!connectedAddresses.contains(entry.key) ||
          entry.key == targetAddress ||
          entry.value.isEmpty ||
          entry.value == localDeviceId) {
        continue;
      }

      routes.add({'destinationId': entry.value, 'hopCount': 1});
    }

    for (final route in knownRoutes.values) {
      if (route.nextHopAddress == targetAddress ||
          route.hopCount >= maxHopCount) {
        continue;
      }

      final directAddress = findDirectAddress(
        deviceId: route.destinationId,
        peerIdsByAddress: peerIdsByAddress,
        connectedAddresses: connectedAddresses,
      );

      if (directAddress != null) continue;

      routes.add(route.toMap());
    }

    return {'type': 'routes', 'deviceId': localDeviceId, 'routes': routes};
  }
}
