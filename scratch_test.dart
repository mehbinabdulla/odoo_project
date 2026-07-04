import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  try {
    final resp = await http.post(
      Uri.parse('http://15.207.7.177/web/database/list'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'params': {}}),
    );
    // ignore: avoid_print
    print('Status: ${resp.statusCode}');
    // ignore: avoid_print
    print('Body: ${resp.body}');
  } catch (e) {
    // ignore: avoid_print
    print('Error: $e');
  }
}
