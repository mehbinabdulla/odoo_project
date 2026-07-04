import 'package:http/http.dart' as http;
import 'io_client.dart' if (dart.library.html) 'web_client.dart';

http.BaseClient buildHttpClient() {
  return getCustomClient();
}
