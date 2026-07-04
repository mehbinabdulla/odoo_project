import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:io';

http.BaseClient getCustomClient() {
  final ioClient = HttpClient()
    ..badCertificateCallback = (_, __, ___) => true;
  return IOClient(ioClient);
}
