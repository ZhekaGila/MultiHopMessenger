class RouteEntry {
  final String destinationId;
  final String nextHopAddress;
  final int hopCount;

  const RouteEntry({
    required this.destinationId,
    required this.nextHopAddress,
    required this.hopCount,
  });

  Map<String, dynamic> toMap() {
    return {'destinationId': destinationId, 'hopCount': hopCount};
  }

  factory RouteEntry.fromMap(Map<String, dynamic> map, String nextHopAddress) {
    return RouteEntry(
      destinationId: map['destinationId'] as String,
      nextHopAddress: nextHopAddress,
      hopCount: map['hopCount'] as int,
    );
  }
}
