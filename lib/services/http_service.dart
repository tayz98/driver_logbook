import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:http/http.dart' as http;

enum ServiceType { log, trip, driver }

class HttpService {
  static final HttpService _singleton = HttpService._internal();
  static final String log = dotenv.get('LOG', fallback: '');
  static final String trip = dotenv.get('TRIP', fallback: '');
  static final String driver = dotenv.get('DRIVER', fallback: '');
  static final String apiKey = dotenv.get('API_KEY', fallback: '');
  static final _postHeaders = {
    'Content-Type': 'application/json; charset=UTF-8',
    'Accept': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'x-api-key': apiKey
  };

  factory HttpService() {
    return _singleton;
  }
  HttpService._internal();

  Future<http.Response> get(String url) async {
    return await http.get(Uri.parse(url));
  }

  Future<http.Response> post(
      {required ServiceType type, Map<String, dynamic>? body}) async {
    String url = '';
    switch (type) {
      case ServiceType.log:
        url = log;
        break;
      case ServiceType.trip:
        url = trip;
        break;
      case ServiceType.driver:
        url = driver;
        break;
    }
    try {
      if (url.isEmpty) {
        throw Exception('URL is empty');
      }
      return await http.post(Uri.parse(url),
          headers: _postHeaders, body: jsonEncode(body));
    } catch (e) {
      rethrow;
    }
  }
}
