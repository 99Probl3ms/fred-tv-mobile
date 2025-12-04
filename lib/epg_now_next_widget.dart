import 'package:flutter/material.dart';
import 'package:open_tv/models/epg_now_next.dart';

class EpgNowNextWidget extends StatelessWidget {
  final EpgNowNext epgData;

  const EpgNowNextWidget({super.key, required this.epgData});

  @override
  Widget build(BuildContext context) {
    if (!epgData.hasData) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (epgData.now != null) ...[
          Row(
            children: [
              Text(
                'NOW: ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Expanded(
                child: Text(
                  epgData.now!.title,
                  style: const TextStyle(fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              Text(
                epgData.now!.remainingTimeString,
                style: TextStyle(
                  fontSize: 9,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: epgData.now!.progressPercentage,
              minHeight: 3,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
        if (epgData.next != null) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              Text(
                'NEXT: ',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              Expanded(
                child: Text(
                  epgData.next!.title,
                  style: TextStyle(
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
