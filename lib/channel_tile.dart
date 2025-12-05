import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/backend/xtream.dart';
import 'package:open_tv/memory.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/models/epg_now_next.dart';
import 'package:open_tv/models/media_type.dart';
import 'package:open_tv/models/node.dart';
import 'package:open_tv/models/node_type.dart';
import 'package:open_tv/player.dart';

class ChannelTile extends StatefulWidget {
  final Channel channel;
  final BuildContext parentContext;
  final Function(Node node) setNode;
  const ChannelTile(
      {super.key,
      required this.channel,
      required this.setNode,
      required this.parentContext});

  @override
  State<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<ChannelTile>
    with SingleTickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();
  EpgNowNext? _epgData;
  Timer? _epgRefreshTimer;
  Size? _imageSize;
  bool _isLoadingImageSize = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {});
    });

    // Pulse animation for LIVE badge
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadEpgData();
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    if (widget.channel.image == null || _isLoadingImageSize) return;

    setState(() {
      _isLoadingImageSize = true;
    });

    try {
      final ImageProvider imageProvider =
          CachedNetworkImageProvider(widget.channel.image!);
      final ImageStream stream = imageProvider.resolve(const ImageConfiguration());
      
      final Completer<Size> completer = Completer<Size>();
      late ImageStreamListener listener;
      
      listener = ImageStreamListener((ImageInfo info, bool synchronousCall) {
        if (!completer.isCompleted) {
          completer.complete(Size(info.image.width.toDouble(), info.image.height.toDouble()));
        }
        stream.removeListener(listener);
      }, onError: (exception, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(exception);
        }
        stream.removeListener(listener);
      });

      stream.addListener(listener);
      
      final size = await completer.future;
      if (mounted) {
        setState(() {
          _imageSize = size;
          _isLoadingImageSize = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingImageSize = false;
        });
      }
    }
  }

  bool _needsPadding() {
    if (_imageSize == null) return false;
    
    final aspectRatio = _imageSize!.width / _imageSize!.height;
    const aspect16_9 = 16 / 9; // ~1.777
    const aspect4_3 = 4 / 3;   // ~1.333
    
    // Check if aspect ratio is close to 16:9 or 4:3 (within 0.05 tolerance)
    final is16_9 = (aspectRatio - aspect16_9).abs() < 0.05;
    final is4_3 = (aspectRatio - aspect4_3).abs() < 0.05;
    
    return !is16_9 && !is4_3;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _epgRefreshTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadEpgData() async {
    // Only load EPG for livestream channels with tvgId
    if (widget.channel.mediaType != MediaType.livestream ||
        widget.channel.tvgId == null ||
        widget.channel.tvgId!.isEmpty) {
      return;
    }

    try {
      final epgData = await Sql.getNowNext(widget.channel.tvgId);
      if (mounted) {
        setState(() {
          _epgData = epgData;
        });

        // Schedule refresh when current program ends
        _scheduleEpgRefresh();
      }
    } catch (_) {
      // Silently ignore EPG fetch errors
    }
  }

  void _scheduleEpgRefresh() {
    _epgRefreshTimer?.cancel();

    if (_epgData?.now != null) {
      final remaining = _epgData!.now!.remainingDuration;
      if (remaining.inSeconds > 0) {
        // Refresh 5 seconds after current program ends
        _epgRefreshTimer = Timer(
          remaining + const Duration(seconds: 5),
          _loadEpgData,
        );
      }
    } else {
      // No current program, refresh in 5 minutes
      _epgRefreshTimer = Timer(
        const Duration(minutes: 5),
        _loadEpgData,
      );
    }
  }

  Future<void> favorite() async {
    if (widget.channel.mediaType == MediaType.group) return;
    await Error.tryAsyncNoLoading(() async {
      await Sql.favoriteChannel(widget.channel.id!, !widget.channel.favorite);
      setState(() {
        widget.channel.favorite = !widget.channel.favorite;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Added to favorites"),
        duration: Duration(milliseconds: 500),
      ));
    }, context);
  }

  Future<void> play() async {
    if (widget.channel.mediaType == MediaType.group ||
        widget.channel.mediaType == MediaType.serie) {
      if (widget.channel.mediaType == MediaType.serie &&
          !refreshedSeries.contains(widget.channel.id)) {
        await Error.tryAsync(() async {
          await getEpisodes(widget.channel);
          refreshedSeries.add(widget.channel.id!);
        }, widget.parentContext, null, true, false);
      }
      widget.setNode(Node(
          id: widget.channel.mediaType == MediaType.group
              ? widget.channel.id!
              : int.parse(widget.channel.url!),
          name: widget.channel.name,
          type: fromMediaType(widget.channel.mediaType)));
    } else {
      Sql.addToHistory(widget.channel.id!);
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => Player(
                    channel: widget.channel,
                  )));
    }
  }

  Widget _buildLiveBadge() {
    if (widget.channel.mediaType != MediaType.livestream) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 10,
      right: 10,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFE53935),
                  const Color(0xFFC62828),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE53935)
                      .withOpacity(_focusNode.hasFocus ? 0.6 : 0.3),
                  blurRadius: _focusNode.hasFocus ? 12 : 6,
                  spreadRadius: _focusNode.hasFocus ? 2 : 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(_pulseAnimation.value),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white
                            .withOpacity(_pulseAnimation.value * 0.5),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFavoriteIndicator() {
    if (!widget.channel.favorite) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 10,
      left: 10,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(
          Icons.star_rounded,
          color: Colors.amber,
          size: 16,
        ),
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.transparent,
              Colors.black.withOpacity(0.3),
              Colors.black.withOpacity(0.85),
            ],
            stops: const [0.0, 0.4, 0.7, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelImage() {
    if (widget.channel.image == null) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surfaceContainerHigh,
              Theme.of(context).colorScheme.surfaceContainerLow,
            ],
          ),
        ),
        child: Center(
          child: Image.asset(
            "assets/icon.png",
            fit: BoxFit.contain,
            width: 64,
            height: 64,
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF121212),
      child: _needsPadding()
          ? Padding(
              padding: const EdgeInsets.all(12.0),
              child: CachedNetworkImage(
                imageUrl: widget.channel.image!,
                fit: BoxFit.contain,
                fadeInDuration: const Duration(milliseconds: 200),
                errorWidget: (_, __, ___) => Center(
                  child: Image.asset(
                    "assets/icon.png",
                    fit: BoxFit.contain,
                    width: 64,
                    height: 64,
                  ),
                ),
              ),
            )
          : CachedNetworkImage(
              imageUrl: widget.channel.image!,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 200),
              errorWidget: (_, __, ___) => Container(
                color: const Color(0xFF121212),
                child: Center(
                  child: Image.asset(
                    "assets/icon.png",
                    fit: BoxFit.contain,
                    width: 64,
                    height: 64,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildInfoOverlay() {
    final hasEpg = _epgData?.hasData == true;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.channel.name,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: Colors.white,
                shadows: [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 3,
                    color: Colors.black54,
                  ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            if (hasEpg) ...[
              const SizedBox(height: 6),
              _buildEpgOverlay(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEpgOverlay() {
    if (_epgData?.now == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _epgData!.now!.title,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.85),
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _epgData!.now!.remainingTimeString,
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Stack(
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: _epgData!.now!.progressPercentage,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.primary.withOpacity(0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color:
                            Theme.of(context).colorScheme.primary.withOpacity(0.5),
                        blurRadius: 4,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFocused = _focusNode.hasFocus;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return AnimatedScale(
      scale: isFocused ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isFocused ? primaryColor : Colors.white.withOpacity(0.08),
            width: isFocused ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isFocused
                  ? primaryColor.withOpacity(0.4)
                  : Colors.black.withOpacity(0.3),
              blurRadius: isFocused ? 24 : 8,
              spreadRadius: isFocused ? 2 : 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Material(
            color: const Color(0xFF1A1A1A),
            child: InkWell(
              focusNode: _focusNode,
              onLongPress: favorite,
              onTap: () async => await play(),
              splashColor: primaryColor.withOpacity(0.2),
              highlightColor: primaryColor.withOpacity(0.1),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Channel image
                    _buildChannelImage(),
                    // Gradient overlay for text legibility
                    _buildGradientOverlay(),
                    // Channel info (name + EPG)
                    _buildInfoOverlay(),
                    // Live badge
                    _buildLiveBadge(),
                    // Favorite indicator
                    _buildFavoriteIndicator(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
