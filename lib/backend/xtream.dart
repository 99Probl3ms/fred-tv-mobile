import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/backend/xmltv.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/channel_preserve.dart';
import 'package:open_tv/models/media_type.dart';
import 'package:open_tv/models/source.dart';
import 'package:open_tv/models/xtream_types.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:http/http.dart' as http;

const String getLiveStreams = "get_live_streams";
const String getVods = "get_vod_streams";
const String getSeries = "get_series";
const String getSeriesInfo = "get_series_info";
const String getSeriesCategories = "get_series_categories";
const String getLiveStreamCategories = "get_live_categories";
const String getVodCategories = "get_vod_categories";
const String liveStreamExtension = "ts";

Future<void> getXtream(Source source, bool wipe) async {
  List<Future<void> Function(SqliteWriteContext, Map<String, String>)>
      statements = [];
  List<ChannelPreserve>? preserve;
  statements.add(Sql.getOrCreateSourceByName(source));
  if (wipe) {
    preserve = await Sql.getChannelsPreserve(source.id!);
    statements.add(Sql.wipeSource(source.id!));
  }
  source.urlOrigin = Uri.parse(source.url!).origin;
  var results = await Future.wait([
    getXtreamHttpData(getLiveStreams, source),
    getXtreamHttpData(getLiveStreamCategories, source),
    getXtreamHttpData(getVods, source),
    getXtreamHttpData(getVodCategories, source),
    getXtreamHttpData(getSeries, source),
    getXtreamHttpData(getSeriesCategories, source),
  ]);
  int failCount = 0;
  if (results[0] != null && results[1] != null) {
    try {
      debugPrint('Channels: Starting to process livestream channels');
      processXtream(
          statements,
          processJsonList(results[0], XtreamStream.fromJson),
          processJsonList(results[1], XtreamCategory.fromJson),
          source,
          MediaType.livestream);
      debugPrint('Channels: Finished processing livestream channels');
    } catch (e) {
      failCount++;
      debugPrint('Channels: Error processing livestream channels: $e');
    }
  } else {
    debugPrint('Channels: Skipping livestream channels (missing data)');
  }
  if (results[2] != null && results[3] != null) {
    try {
      debugPrint('Channels: Starting to process VOD/movie channels');
      processXtream(
          statements,
          processJsonList(results[2], XtreamStream.fromJson),
          processJsonList(results[3], XtreamCategory.fromJson),
          source,
          MediaType.movie);
      debugPrint('Channels: Finished processing VOD/movie channels');
    } catch (e) {
      failCount++;
      debugPrint('Channels: Error processing VOD/movie channels: $e');
    }
  } else {
    debugPrint('Channels: Skipping VOD/movie channels (missing data)');
  }
  if (results[4] != null && results[5] != null) {
    try {
      debugPrint('Channels: Starting to process series channels');
      processXtream(
          statements,
          processJsonList(results[4], XtreamStream.fromJson),
          processJsonList(results[5], XtreamCategory.fromJson),
          source,
          MediaType.serie);
      debugPrint('Channels: Finished processing series channels');
    } catch (e) {
      failCount++;
      debugPrint('Channels: Error processing series channels: $e');
    }
  } else {
    debugPrint('Channels: Skipping series channels (missing data)');
  }
  if (failCount > 1) {
    return;
  }
  statements.add(Sql.updateGroups());
  if (preserve != null) {
    statements.add(Sql.restorePreserve(preserve));
  }
  await Sql.commitWrite(statements);
  
  // Automatically fetch EPG from Xtream XMLTV endpoint if no manual EPG URL was provided
  // Retrieve the source from database to get its ID (which was set during commit)
  final savedSource = await Sql.getSourceByName(source.name);
  if (savedSource != null && 
      (savedSource.epgUrl == null || savedSource.epgUrl!.isEmpty)) {
    try {
      final xmltvUrl = buildXtreamXmltvUrl(savedSource);
      debugPrint('EPG: Auto-fetching EPG from Xtream XMLTV endpoint: $xmltvUrl');
      
      // Update source with the XMLTV URL
      savedSource.epgUrl = xmltvUrl.toString();
      await Sql.updateSource(savedSource);
      
      // Fetch and process EPG data
      await processEpgUrl(savedSource, true);
      final count = await Sql.getEpgCount(savedSource.id);
      debugPrint('EPG: Auto-fetched and stored $count programs for source ${savedSource.name}');
    } catch (e) {
      // EPG fetch failure should not block source processing
      // User can still use the app without EPG data
      debugPrint('EPG: Failed to auto-fetch EPG from Xtream XMLTV endpoint: $e');
    }
  }
}

List<T> processJsonList<T>(
    List<dynamic> jsonList, T Function(Map<String, dynamic>) fromJson) {
  debugPrint('Channels: Parsing ${jsonList.length} items from JSON');
  final result = jsonList
      .map((json) => fromJson(json as Map<String, dynamic>))
      .toList();
  debugPrint('Channels: Successfully parsed ${result.length} items');
  return result;
}

Future<dynamic> getXtreamHttpData(String action, Source source,
    [Map<String, String>? extraQueryParams]) async {
  try {
    var url = buildXtreamUrl(source, action, extraQueryParams);
    final response = await http.get(url);
    if (response.statusCode != 200) {
      return null;
    }
    return jsonDecode(response.body);
  } catch (_) {}
  return null;
}

void processXtream(
    List<Future<void> Function(SqliteWriteContext, Map<String, String>)>
        statements,
    List<XtreamStream> streams,
    List<XtreamCategory> cats,
    Source source,
    MediaType mediaType) {
  debugPrint('Channels: Processing ${streams.length} ${mediaType.name} streams with ${cats.length} categories');
  Map<String, String> catsMap =
      Map.fromEntries(cats.map((x) => MapEntry(x.categoryId, x.categoryName)));
  int successCount = 0;
  int failCount = 0;
  for (var live in streams) {
    var cname = catsMap[live.categoryId];
    try {
      var channel = xtreamToChannel(live, source, mediaType, cname);
      statements.add(Sql.insertChannel(channel));
      successCount++;
    } catch (e) {
      failCount++;
      debugPrint('Channels: Failed to convert stream "${live.name}" to channel: $e');
    }
  }
  debugPrint('Channels: Successfully converted $successCount/${streams.length} ${mediaType.name} streams to channels (${failCount} failed)');
}

Channel xtreamToChannel(XtreamStream stream, Source source,
    MediaType streamType, String? categoryName) {
  return Channel(
      name: stream.name!,
      mediaType: streamType,
      sourceId: -1,
      favorite: false,
      group: categoryName,
      image: stream.streamIcon?.trim() ?? stream.cover?.trim(),
      url: streamType == MediaType.serie
          ? stream.seriesId.toString()
          : getUrl(stream.streamId?.trim(), source, streamType,
              stream.containerExtension),
      streamId: int.tryParse(stream.streamId ?? "") ?? -1);
}

String getUrl(
    String? streamId, Source source, MediaType streamType, String? extension) {
  return "${source.urlOrigin}/${getXtreamMediaTypeStr(streamType)}/${source.username}/${source.password}/$streamId.${extension ?? liveStreamExtension}";
}

String getXtreamMediaTypeStr(MediaType type) {
  switch (type) {
    case MediaType.livestream:
      return "live";
    case MediaType.movie:
      return "movie";
    case MediaType.serie:
      return "series";
    default:
      return "";
  }
}

Uri buildXtreamUrl(Source source, String action,
    [Map<String, String>? extraQueryParams]) {
  var params = {
    'username': source.username,
    'password': source.password,
    'action': action,
  };
  if (extraQueryParams != null) {
    params.addAll(extraQueryParams);
  }
  var url = Uri.parse(source.url!).replace(queryParameters: params);
  return url;
}

/// Build Xtream XMLTV endpoint URL
/// Format: {base_url}/xmltv.php?username={username}&password={password}
Uri buildXtreamXmltvUrl(Source source) {
  final baseUrl = Uri.parse(source.url!);
  final xmltvPath = baseUrl.path.replaceAll('/player_api.php', '/xmltv.php');
  
  // If the path is empty or just "/", use /xmltv.php
  final finalPath = xmltvPath.isEmpty || xmltvPath == '/' ? '/xmltv.php' : xmltvPath;
  
  final params = {
    'username': source.username!,
    'password': source.password!,
  };
  
  return baseUrl.replace(path: finalPath, queryParameters: params);
}

Future<void> getEpisodes(Channel channel) async {
  List<Future<void> Function(SqliteWriteContext, Map<String, String>)>
      statements = [];
  var seriesId = int.parse(channel.url!);
  var source = await Sql.getSourceFromId(channel.sourceId);
  source.urlOrigin = Uri.parse(source.url!).origin;
  var episodes = XtreamSeries.fromJson(await getXtreamHttpData(
          getSeriesInfo, source, {'series_id': seriesId.toString()}))
      .episodes;
  episodes.sort((a, b) {
    int seasonComparison = a.season.compareTo(b.season);
    if (seasonComparison != 0) {
      return seasonComparison;
    }
    return a.episodeNum.compareTo(b.episodeNum);
  });
  for (var episode in episodes) {
    try {
      statements
          .add(Sql.insertChannel(episodeToChannel(episode, source, seriesId)));
    } catch (_) {}
  }
  await Sql.commitWrite(statements);
}

Channel episodeToChannel(XtreamEpisode episode, Source source, int seriesId) {
  return Channel(
      image: episode.info?.movieImage,
      mediaType: MediaType.movie,
      name: episode.title.trim(),
      sourceId: source.id!,
      favorite: false,
      url: getUrl(
          episode.id, source, MediaType.serie, episode.containerExtension),
      seriesId: seriesId);
}
