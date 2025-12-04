class EpgProgram {
  int? id;
  String channelTvgId;
  String title;
  String? description;
  DateTime startTime;
  DateTime endTime;
  int sourceId;
  String? category;
  String? episodeInfo;

  EpgProgram({
    this.id,
    required this.channelTvgId,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    required this.sourceId,
    this.category,
    this.episodeInfo,
  });

  bool get isCurrentlyAiring {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  Duration get remainingDuration {
    final now = DateTime.now();
    if (now.isBefore(startTime)) return endTime.difference(startTime);
    if (now.isAfter(endTime)) return Duration.zero;
    return endTime.difference(now);
  }

  double get progressPercentage {
    final now = DateTime.now();
    if (now.isBefore(startTime)) return 0.0;
    if (now.isAfter(endTime)) return 1.0;
    final total = endTime.difference(startTime).inSeconds;
    final elapsed = now.difference(startTime).inSeconds;
    if (total == 0) return 0.0;
    return elapsed / total;
  }

  String get remainingTimeString {
    final remaining = remainingDuration;
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m';
    }
    return '${remaining.inMinutes}m';
  }
}
