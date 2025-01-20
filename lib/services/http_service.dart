import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:http/http.dart' as http;

enum ServiceType { log, trip, driver }

class HttpService {
  static final HttpService _singleton = HttpService._internal();
  static final String? log = dotenv.env['log'];
  static final String? trip = dotenv.env['trip'];
  static final String? driver = dotenv.env['driver'];
  static final _postHeaders = {
    'Content-Type': 'application/json; charset=UTF-8'
  };

  factory HttpService() {
    return _singleton;
  }
  HttpService._internal();

  Future<http.Response> get(String url) async {
    return await http.get(Uri.parse(url));
  }

  Future<http.Response> post(
      {required ServiceType type, Map<String, String>? body}) async {
    if (log == null || trip == null || driver == null) {
      debugPrint('Error: No URL found');
      return http.Response('Error: URL not found', 404);
    }
    String url = '';
    switch (type) {
      case ServiceType.log:
        url = log!;
        break;
      case ServiceType.trip:
        url = trip!;
        break;
      case ServiceType.driver:
        url = driver!;
        break;
    }
    try {
      return await http.post(Uri.parse(url),
          headers: _postHeaders, body: jsonEncode(body));
    } catch (e) {
      debugPrint('Error: $e');
      return http.Response('Error: $e', 500);
      // TODO: add more error handling (e.g. rethrow to caller and handle there)
    }
  }
}
