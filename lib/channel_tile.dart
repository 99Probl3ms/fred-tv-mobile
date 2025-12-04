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

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {});
    });
    _loadEpgData();
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

  @override
  Widget build(BuildContext context) {
    return Card(
        elevation: _focusNode.hasFocus ? 8.0 : 4.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        color: widget.channel.favorite
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Theme.of(context).colorScheme.surfaceContainer,
        child: InkWell(
          focusNode: _focusNode,
          onLongPress: favorite,
          onTap: () async => await play(),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
              padding: const EdgeInsets.all(5),
              child: Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: widget.channel.image != null
                              ? CachedNetworkImage(
                                  width: 1000,
                                  fit: BoxFit.contain,
                                  errorWidget: (_, __, ___) =>
                                      Image.asset("assets/icon.png"),
                                  imageUrl: widget.channel.image!,
                                )
                              : Image.asset(
                                  "assets/icon.png",
                                  fit: BoxFit.contain,
                                ))),
                  const Expanded(flex: 1, child: SizedBox()),
                  Expanded(
                      flex: 8,
                      child: LayoutBuilder(builder: (context, constraints) {
                        final hasEpg = _epgData?.hasData == true;
                        final style = Theme.of(context).textTheme.bodyMedium!;
                        final fontSize = MediaQuery.of(context)
                            .textScaler
                            .scale(style.fontSize!);
                        final lineHeight = style.height! * fontSize;
                        // Reserve space for EPG info if available
                        final epgHeight = hasEpg ? 45.0 : 0.0;
                        final availableHeight =
                            constraints.maxHeight - epgHeight;
                        final maxLines =
                            (availableHeight / lineHeight).floor().clamp(1, 3);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              widget.channel.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: maxLines,
                            ),
                            if (hasEpg) ...[
                              const SizedBox(height: 4),
                              EpgNowNextWidget(epgData: _epgData!),
                            ],
                          ],
                        );
                      }))
                ],
              )),
        ));
  }
}
