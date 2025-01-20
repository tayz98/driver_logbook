import 'dart:convert';
import 'package:flutter/material.dart';

import 'secrets.dart' as secret;

import 'package:http/http.dart' as http;

enum ServiceType { log, trip, driver }

class HttpService {
  static final HttpService _singleton = HttpService._internal();
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
    String url = '';
    switch (type) {
      case ServiceType.log:
        url = secret.log;
        break;
      case ServiceType.trip:
        url = secret.trip;
        break;
      case ServiceType.driver:
        url = secret.driver;
        break;
    }
    try {
      return await http.post(Uri.parse(url),
          headers: _postHeaders, body: jsonEncode(body));
    } catch (e) {
      debugPrint('Error: $e');
      return http.Response('Error: $e', 500);
    }
  }
}
