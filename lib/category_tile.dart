import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/media_type.dart';
import 'package:open_tv/models/node.dart';
import 'package:open_tv/models/node_type.dart';

class CategoryTile extends StatefulWidget {
  final Channel channel;
  final Function(Node node) setNode;
  const CategoryTile({
    super.key,
    required this.channel,
    required this.setNode,
  });

  @override
  State<CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<CategoryTile> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();  
    _focusNode.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void navigate() {
    if (widget.channel.mediaType == MediaType.group) {
      widget.setNode(Node(
          id: widget.channel.id!,
          name: widget.channel.name,
          type: NodeType.category));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focusNode.hasFocus
                  ? Colors.white.withOpacity(0.3)
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              focusNode: _focusNode,
              onTap: navigate,
              borderRadius: BorderRadius.circular(10),
              splashColor: Colors.white.withOpacity(0.1),
              highlightColor: Colors.white.withOpacity(0.05),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                      flex: 7,
                      child: Center(
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: widget.channel.image != null
                                ? CachedNetworkImage(
                                    fit: BoxFit.contain,
                                    errorWidget: (_, __, ___) =>
                                        Image.asset("assets/icon.png"),
                                    imageUrl: widget.channel.image!,
                                  )
                                : Image.asset(
                                    "assets/icon.png",
                                    fit: BoxFit.contain,
                                  ),
                          ))),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Text(
                      widget.channel.name,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                ],
              ),
            ),
          )),
    );
  }
}

