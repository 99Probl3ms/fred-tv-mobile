import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/backend/xtream.dart';
import 'package:open_tv/epg_now_next_widget.dart';
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

class _ChannelTileState extends State<ChannelTile> {
  final FocusNode _focusNode = FocusNode();
  EpgNowNext? _epgData;
  Timer? _epgRefreshTimer;
  Size? _imageSize;
  bool _isLoadingImageSize = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {});
    });
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
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(4),
          boxShadow: _focusNode.hasFocus
              ? [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.error.withOpacity(0.6),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'LIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteIndicator() {
    if (!widget.channel.favorite) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.star,
          color: Theme.of(context).colorScheme.primary,
          size: 16,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasEpg = _epgData?.hasData == true;

    return Card(
      elevation: _focusNode.hasFocus ? 8.0 : 4.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: _focusNode.hasFocus
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        focusNode: _focusNode,
        onLongPress: favorite,
        onTap: () async => await play(),
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image section with badges
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background container with theme color
                    Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainer,
                      child: widget.channel.image != null
                          ? _needsPadding()
                              ? Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: CachedNetworkImage(
                                    imageUrl: widget.channel.image!,
                                    fit: BoxFit.contain,
                                    errorWidget: (_, __, ___) => Image.asset(
                                      "assets/icon.png",
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                )
                              : CachedNetworkImage(
                                  imageUrl: widget.channel.image!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Container(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainer,
                                    child: Image.asset(
                                      "assets/icon.png",
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                )
                          : Image.asset(
                              "assets/icon.png",
                              fit: BoxFit.contain,
                            ),
                    ),
                    // Live badge
                    _buildLiveBadge(),
                    // Favorite indicator
                    _buildFavoriteIndicator(),
                  ],
                ),
              ),
            ),
            // Text section below image
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.channel.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  if (hasEpg) ...[
                    const SizedBox(height: 6),
                    EpgNowNextWidget(epgData: _epgData!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
