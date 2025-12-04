import 'dart:async';
import 'package:flutter/material.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/epg_program.dart';
import 'package:open_tv/models/filters.dart';
import 'package:open_tv/models/media_type.dart';
import 'package:open_tv/models/view_type.dart';
import 'package:open_tv/player.dart';

class TvGuide extends StatefulWidget {
  final List<int>? sourceIds;

  const TvGuide({super.key, this.sourceIds});

  @override
  State<TvGuide> createState() => _TvGuideState();
}

class _TvGuideState extends State<TvGuide> {
  static const double channelWidth = 120.0;
  static const double timeHeaderHeight = 40.0;
  static const double channelRowHeight = 60.0;
  static const double pixelsPerMinute = 3.0;

  List<Channel> channels = [];
  Map<String, List<EpgProgram>> programsByChannel = {};
  late DateTime viewStartTime;
  late DateTime viewEndTime;
  bool isLoading = true;

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  Timer? _currentTimeTimer;

  @override
  void initState() {
    super.initState();
    // Start 30 minutes before current time
    final now = DateTime.now();
    viewStartTime = DateTime(now.year, now.month, now.day, now.hour)
        .subtract(const Duration(minutes: 30));
    viewEndTime = viewStartTime.add(const Duration(hours: 6));
    _loadData();

    // Refresh every minute to update current time indicator
    _currentTimeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    _currentTimeTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);

    try {
      // Load livestream channels
      final filters = Filters(
        viewType: ViewType.all,
        mediaTypes: [MediaType.livestream],
        sourceIds: widget.sourceIds,
      );
      filters.page = 1;

      // Load more channels to have a reasonable list
      List<Channel> allChannels = [];
      do {
        final batch = await Sql.search(filters);
        allChannels.addAll(batch);
        filters.page++;
        if (batch.length < 36) break;
      } while (allChannels.length < 200);

      // Filter to channels with tvgId
      channels =
          allChannels.where((c) => c.tvgId != null && c.tvgId!.isNotEmpty).toList();

      if (channels.isNotEmpty) {
        // Load EPG programs for visible time range
        final tvgIds = channels.map((c) => c.tvgId!).toList();
        final programs = await Sql.getProgramsForTimeRange(
          tvgIds,
          viewStartTime,
          viewEndTime,
        );

        // Group by channel
        programsByChannel = {};
        for (final program in programs) {
          programsByChannel.putIfAbsent(program.channelTvgId, () => []);
          programsByChannel[program.channelTvgId]!.add(program);
        }
      }

      if (mounted) {
        setState(() => isLoading = false);

        // Scroll to current time after loading
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToCurrentTime();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _scrollToCurrentTime() {
    final now = DateTime.now();
    final offset = now.difference(viewStartTime).inMinutes * pixelsPerMinute;
    final screenWidth = MediaQuery.of(context).size.width;
    final targetOffset = (offset - screenWidth / 3).clamp(0.0, double.infinity);

    _horizontalController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _shiftTime(Duration duration) {
    setState(() {
      viewStartTime = viewStartTime.add(duration);
      viewEndTime = viewEndTime.add(duration);
    });
    _loadData();
  }

  double get totalWidth =>
      viewEndTime.difference(viewStartTime).inMinutes * pixelsPerMinute;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TV Guide'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shiftTime(const Duration(hours: -3)),
            tooltip: 'Earlier',
          ),
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              final now = DateTime.now();
              viewStartTime = DateTime(now.year, now.month, now.day, now.hour)
                  .subtract(const Duration(minutes: 30));
              viewEndTime = viewStartTime.add(const Duration(hours: 6));
              _loadData();
            },
            tooltip: 'Now',
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shiftTime(const Duration(hours: 3)),
            tooltip: 'Later',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : channels.isEmpty
              ? const Center(
                  child: Text('No channels with EPG data found'),
                )
              : Column(
                  children: [
                    // Time header
                    _buildTimeHeader(),
                    // Channel list with programs
                    Expanded(
                      child: _buildGuideGrid(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildTimeHeader() {
    return SizedBox(
      height: timeHeaderHeight,
      child: Row(
        children: [
          // Channel column header
          Container(
            width: channelWidth,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Text(
              'Channel',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          // Time slots
          Expanded(
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: Stack(
                  children: [
                    // Time slot labels
                    ..._buildTimeSlotLabels(),
                    // Current time indicator
                    _buildCurrentTimeIndicator(timeHeaderHeight),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTimeSlotLabels() {
    final labels = <Widget>[];
    var current = viewStartTime;
    while (current.isBefore(viewEndTime)) {
      final offset = current.difference(viewStartTime).inMinutes * pixelsPerMinute;
      labels.add(
        Positioned(
          left: offset,
          top: 0,
          bottom: 0,
          child: Container(
            width: 60 * pixelsPerMinute, // 1 hour width
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                ),
              ),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            alignment: Alignment.center,
            child: Text(
              '${current.hour.toString().padLeft(2, '0')}:${current.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      );
      current = current.add(const Duration(hours: 1));
    }
    return labels;
  }

  Widget _buildCurrentTimeIndicator(double height) {
    final now = DateTime.now();
    if (now.isBefore(viewStartTime) || now.isAfter(viewEndTime)) {
      return const SizedBox.shrink();
    }

    final offset = now.difference(viewStartTime).inMinutes * pixelsPerMinute;
    return Positioned(
      left: offset - 1,
      top: 0,
      bottom: 0,
      child: Container(
        width: 2,
        color: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Widget _buildGuideGrid() {
    return Row(
      children: [
        // Channel names column
        SizedBox(
          width: channelWidth,
          child: ListView.builder(
            controller: _verticalController,
            itemCount: channels.length,
            itemBuilder: (context, index) => _buildChannelLabel(channels[index]),
          ),
        ),
        // Programs grid
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // Sync vertical scroll
              if (notification is ScrollUpdateNotification) {
                _verticalController.jumpTo(notification.metrics.pixels);
              }
              return false;
            },
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: ListView.builder(
                  itemCount: channels.length,
                  itemBuilder: (context, index) =>
                      _buildProgramRow(channels[index]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChannelLabel(Channel channel) {
    return Container(
      height: channelRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: Row(
        children: [
          if (channel.image != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Image.network(
                channel.image!,
                width: 30,
                height: 30,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(width: 30),
              ),
            ),
          Expanded(
            child: Text(
              channel.name,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgramRow(Channel channel) {
    final programs = programsByChannel[channel.tvgId] ?? [];
    final now = DateTime.now();

    return Container(
      height: channelRowHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Stack(
        children: [
          // Programs
          ...programs.map((program) => _buildProgramBlock(program, channel, now)),
          // Current time indicator
          _buildCurrentTimeIndicator(channelRowHeight),
        ],
      ),
    );
  }

  Widget _buildProgramBlock(EpgProgram program, Channel channel, DateTime now) {
    // Calculate position and width
    var start = program.startTime;
    var end = program.endTime;

    // Clamp to visible range
    if (start.isBefore(viewStartTime)) start = viewStartTime;
    if (end.isAfter(viewEndTime)) end = viewEndTime;

    final left = start.difference(viewStartTime).inMinutes * pixelsPerMinute;
    final width = end.difference(start).inMinutes * pixelsPerMinute;

    if (width <= 0) return const SizedBox.shrink();

    final isCurrentlyAiring = program.isCurrentlyAiring;

    return Positioned(
      left: left,
      top: 2,
      bottom: 2,
      child: GestureDetector(
        onTap: () {
          // Show program details
          _showProgramDetails(program, channel);
        },
        child: Container(
          width: width - 2,
          margin: const EdgeInsets.only(right: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isCurrentlyAiring
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isCurrentlyAiring
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline.withOpacity(0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                program.title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isCurrentlyAiring ? FontWeight.bold : FontWeight.normal,
                  color: isCurrentlyAiring
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (width > 100) ...[
                const SizedBox(height: 2),
                Text(
                  '${_formatTime(program.startTime)} - ${_formatTime(program.endTime)}',
                  style: TextStyle(
                    fontSize: 9,
                    color: isCurrentlyAiring
                        ? Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _showProgramDetails(EpgProgram program, Channel channel) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              program.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatTime(program.startTime)} - ${_formatTime(program.endTime)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (program.category != null) ...[
              const SizedBox(height: 4),
              Chip(
                label: Text(program.category!),
                visualDensity: VisualDensity.compact,
              ),
            ],
            if (program.description != null && program.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                program.description!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 16),
            if (program.isCurrentlyAiring)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Watch Now'),
                  onPressed: () {
                    Navigator.pop(context);
                    Sql.addToHistory(channel.id!);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Player(channel: channel),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
