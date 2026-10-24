import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:io';

/// Default validating HTTP client. Certificates are verified by the
/// platform; no custom [HttpClient.badCertificateCallback] is installed.
http.BaseClient getCustomClient() {
  final ioClient = HttpClient();
  return IOClient(ioClient);
}
