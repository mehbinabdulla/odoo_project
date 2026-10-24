import 'package:http/http.dart' as http;
import 'io_client.dart' if (dart.library.js_interop) 'web_client.dart';

http.BaseClient buildHttpClient() {
  return getCustomClient();
}
