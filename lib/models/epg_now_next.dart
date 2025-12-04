import 'package:open_tv/models/epg_program.dart';

class EpgNowNext {
  final EpgProgram? now;
  final EpgProgram? next;

  EpgNowNext({this.now, this.next});

  bool get hasData => now != null || next != null;
}
