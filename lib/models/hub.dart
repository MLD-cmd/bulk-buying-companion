enum HubType { dormitory, areaHub }

class Hub {
  const Hub({
    required this.id,
    required this.name,
    required this.type,
    required this.memberCount,
    required this.distanceLabel,
  });

  final String id;
  final String name;
  final HubType type;
  final int memberCount;
  final String distanceLabel;
}
