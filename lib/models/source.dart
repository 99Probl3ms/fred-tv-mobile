import 'package:open_tv/models/source_type.dart';

class Source {
  int? id;
  String name;
  String? url;
  String? urlOrigin;
  String? username;
  String? password;
  String? epgUrl;
  SourceType sourceType;
  bool enabled;

  Source({
    this.id,
    required this.name,
    this.url,
    this.urlOrigin,
    this.username,
    this.password,
    this.epgUrl,
    required this.sourceType,
    this.enabled = true,
  });
}
