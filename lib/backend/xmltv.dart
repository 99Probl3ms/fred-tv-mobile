import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/backend/utils.dart';
import 'package:open_tv/models/epg_program.dart';
import 'package:open_tv/models/source.dart';
import 'package:xml/xml_events.dart';

/// Parse XMLTV date format: "20231215143000 +0000" or "20231215143000"
DateTime? parseXmltvDate(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return null;

  try {
    // Split date and timezone
    final parts = dateStr.trim().split(' ');
    final dateTimePart = parts[0];

    if (dateTimePart.length < 14) return null;

    final year = int.parse(dateTimePart.substring(0, 4));
    final month = int.parse(dateTimePart.substring(4, 6));
    final day = int.parse(dateTimePart.substring(6, 8));
    final hour = int.parse(dateTimePart.substring(8, 10));
    final minute = int.parse(dateTimePart.substring(10, 12));
    final second = int.parse(dateTimePart.substring(12, 14));

    var dateTime = DateTime.utc(year, month, day, hour, minute, second);

    // Handle timezone offset if present
    if (parts.length > 1) {
      final tzStr = parts[1];
      if (tzStr.length >= 5) {
        final sign = tzStr[0] == '-' ? -1 : 1;
        final tzHour = int.parse(tzStr.substring(1, 3));
        final tzMinute = int.parse(tzStr.substring(3, 5));
        final offset = Duration(hours: tzHour, minutes: tzMinute) * sign;
        dateTime = dateTime.subtract(offset);
      }
    }

    return dateTime.toLocal();
  } catch (e) {
    return null;
  }
}

/// Process EPG URL for a source
Future<void> processEpgUrl(Source source, bool wipe) async {
  if (source.epgUrl == null || source.epgUrl!.isEmpty) return;
  if (source.id == null) return;

  debugPrint('EPG: Starting download from ${source.epgUrl}');

  // Download EPG file
  final path = await _downloadEpg(source.epgUrl!);
  debugPrint('EPG: Downloaded to $path');

  // Parse and store EPG data
  final count = await _parseXmltvFile(path, source.id!, wipe);
  debugPrint('EPG: Parsed and stored $count programs for source ${source.name}');

  // Clean up temp file
  try {
    await File(path).delete();
  } catch (_) {}
}

Future<String> _downloadEpg(String urlStr) async {
  final url = Uri.parse(urlStr);
  final client = http.Client();
  final request = http.Request('GET', url);
  final response = await client.send(request);

  if (response.statusCode != 200) {
    client.close();
    throw Exception('Failed to download EPG: ${response.statusCode}');
  }

  final path = await Utils.getTempPath("epg.xml");
  final file = File(path);
  final sink = file.openWrite();

  await for (var chunk in response.stream) {
    sink.add(chunk);
  }

  await sink.close();
  client.close();
  return path;
}

Future<int> _parseXmltvFile(String path, int sourceId, bool wipe) async {
  final file = File(path);
  if (!await file.exists()) return 0;

  int totalCount = 0;

  // Wipe existing EPG data for this source
  if (wipe) {
    await Sql.wipeEpgData(sourceId);
  }

  // Read file content and parse events
  final content = await file.readAsString();
  final events = parseEvents(content);

  List<EpgProgram> batch = [];
  const batchSize = 500;

  String? currentChannel;
  String? currentStart;
  String? currentStop;
  String? currentTitle;
  String? currentDesc;
  String? currentCategory;
  String? currentEpisode;
  String? currentElement;
  bool inProgramme = false;

  for (final event in events) {
    if (event is XmlStartElementEvent) {
      final name = event.name;

      if (name == 'programme') {
        inProgramme = true;
        currentChannel = null;
        currentStart = null;
        currentStop = null;
        currentTitle = null;
        currentDesc = null;
        currentCategory = null;
        currentEpisode = null;

        for (final attr in event.attributes) {
          switch (attr.name) {
            case 'channel':
              currentChannel = attr.value;
              break;
            case 'start':
              currentStart = attr.value;
              break;
            case 'stop':
              currentStop = attr.value;
              break;
          }
        }
      } else if (inProgramme) {
        currentElement = name;
      }
    } else if (event is XmlTextEvent && inProgramme) {
      final text = event.value.trim();
      if (text.isNotEmpty) {
        switch (currentElement) {
          case 'title':
            currentTitle = (currentTitle ?? '') + text;
            break;
          case 'desc':
            currentDesc = (currentDesc ?? '') + text;
            break;
          case 'category':
            currentCategory = (currentCategory ?? '') + text;
            break;
          case 'episode-num':
            currentEpisode = (currentEpisode ?? '') + text;
            break;
        }
      }
    } else if (event is XmlEndElementEvent) {
      if (event.name == 'programme' && inProgramme) {
        inProgramme = false;

        // Create program if we have required fields
        if (currentChannel != null &&
            currentStart != null &&
            currentStop != null &&
            currentTitle != null) {
          final startTime = parseXmltvDate(currentStart);
          final endTime = parseXmltvDate(currentStop);

          if (startTime != null && endTime != null) {
            batch.add(EpgProgram(
              channelTvgId: currentChannel,
              title: currentTitle,
              description: currentDesc,
              startTime: startTime,
              endTime: endTime,
              sourceId: sourceId,
              category: currentCategory,
              episodeInfo: currentEpisode,
            ));

            // Commit batch when full
            if (batch.length >= batchSize) {
              await Sql.insertEpgProgramsBatch(batch);
              totalCount += batch.length;
              batch = [];
            }
          }
        }
      } else if (inProgramme) {
        currentElement = null;
      }
    }
  }

  // Commit remaining batch
  if (batch.isNotEmpty) {
    await Sql.insertEpgProgramsBatch(batch);
    totalCount += batch.length;
  }

  // Clean up old EPG data (older than 24 hours ago)
  await Sql.cleanupOldEpgData(sourceId);

  return totalCount;
}
