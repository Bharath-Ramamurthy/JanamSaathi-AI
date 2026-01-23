// lib/services/api.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  late final String baseUrl;
  late final String backendHost;
  final Duration _defaultTimeout = const Duration(seconds: 12);

  ApiService({String? overrideBaseUrl, String? overrideBackendHost}) {
    if (overrideBaseUrl != null && overrideBackendHost != null) {
      baseUrl = overrideBaseUrl;
      backendHost = overrideBackendHost;
    } else if (kIsWeb) {
      baseUrl = 'http://127.0.0.1:8000';
      backendHost = '127.0.0.1';
    } else if (Platform.isAndroid) {
      baseUrl = 'http://10.0.2.2:8000';
      backendHost = '10.0.2.2';
    } else {
      baseUrl = 'http://127.0.0.1:8000';
      backendHost = '127.0.0.1';
    }
  }

  /// Always fetch the latest access token
  Future<Map<String, String>> _authHeaders({bool jsonContent = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString('authToken');
    if (access == null) {
      throw Exception('No access token found. User not authenticated.');
    }
    final headers = <String, String>{
      if (jsonContent) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $access',
    };
    return headers;
  }

  /// Refresh access token
  Future<void> refreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString('refreshToken');
    if (refresh == null) throw Exception('No refresh token found.');

    final uri = Uri.parse('$baseUrl/auth/refresh');
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $refresh',
          },
        )
        .timeout(_defaultTimeout);

    if (response.statusCode == 200) {
      final data = Map<String, dynamic>.from(jsonDecode(response.body));
      if (data.containsKey('access_token')) {
        await prefs.setString('authToken', data['access_token']);
      }
      if (data.containsKey('refresh_token')) {
        await prefs.setString('refreshToken', data['refresh_token']);
      }
    } else {
      await prefs.remove('authToken');
      await prefs.remove('refreshToken');
      throw Exception(
        'Failed to refresh token: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Build full Uri from path or absolute URL
  Uri _buildUri(String pathOrUrl, [Map<String, String>? queryParameters]) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return Uri.parse(pathOrUrl);
    }
    return Uri.parse(baseUrl + pathOrUrl)
        .replace(queryParameters: queryParameters);
  }

  /// Generic GET with automatic refresh on 401
  Future<http.Response> _get(String pathOrUrl,
      {Map<String, String>? extraHeaders,
      Map<String, String>? queryParameters}) async {
    final headers = await _authHeaders();
    if (extraHeaders != null) headers.addAll(extraHeaders);

    Uri uri = _buildUri(pathOrUrl, queryParameters);
    http.Response resp =
        await http.get(uri, headers: headers).timeout(_defaultTimeout);

    if (resp.statusCode == 401) {
      await refreshToken();
      final retryHeaders = await _authHeaders();
      if (extraHeaders != null) retryHeaders.addAll(extraHeaders);
      resp =
          await http.get(uri, headers: retryHeaders).timeout(_defaultTimeout);
    }
    return resp;
  }

  /// Generic POST with automatic refresh on 401
  Future<http.Response> _post(String pathOrUrl, dynamic body,
      {Map<String, String>? extraHeaders, bool encodeJson = true}) async {
    final headers = await _authHeaders(jsonContent: encodeJson);
    if (extraHeaders != null) headers.addAll(extraHeaders);

    Uri uri = _buildUri(pathOrUrl);
    final payload = encodeJson ? jsonEncode(body) : body;

    http.Response resp =
        await http.post(uri, headers: headers, body: payload).timeout(_defaultTimeout);

    if (resp.statusCode == 401) {
      await refreshToken();
      final retryHeaders = await _authHeaders(jsonContent: encodeJson);
      if (extraHeaders != null) retryHeaders.addAll(extraHeaders);
      resp = await http
          .post(uri, headers: retryHeaders, body: payload)
          .timeout(_defaultTimeout);
    }
    return resp;
  }

  /// Generic PUT with automatic refresh on 401
  Future<http.Response> _put(String pathOrUrl, dynamic body,
      {Map<String, String>? extraHeaders, bool encodeJson = true}) async {
    final headers = await _authHeaders(jsonContent: encodeJson);
    if (extraHeaders != null) headers.addAll(extraHeaders);

    Uri uri = _buildUri(pathOrUrl);
    final payload = encodeJson ? jsonEncode(body) : body;

    http.Response resp = await http
        .put(uri, headers: headers, body: payload)
        .timeout(_defaultTimeout);

    if (resp.statusCode == 401) {
      await refreshToken();
      final retryHeaders = await _authHeaders(jsonContent: encodeJson);
      if (extraHeaders != null) retryHeaders.addAll(extraHeaders);
      resp = await http
          .put(uri, headers: retryHeaders, body: payload)
          .timeout(_defaultTimeout);
    }
    return resp;
  }

  /// Generic DELETE with automatic refresh on 401
  Future<http.Response> _delete(String pathOrUrl,
      {Map<String, String>? extraHeaders}) async {
    final headers = await _authHeaders();
    if (extraHeaders != null) headers.addAll(extraHeaders);

    Uri uri = _buildUri(pathOrUrl);
    http.Response resp =
        await http.delete(uri, headers: headers).timeout(_defaultTimeout);

    if (resp.statusCode == 401) {
      await refreshToken();
      final retryHeaders = await _authHeaders();
      if (extraHeaders != null) retryHeaders.addAll(extraHeaders);
      resp = await http
          .delete(uri, headers: retryHeaders)
          .timeout(_defaultTimeout);
    }
    return resp;
  }

  /// Multipart POST helper (useful for file uploads)
  Future<http.Response> _multipartPost(
    String pathOrUrl, {
    required Map<String, String> fields,
    File? file,
    Uint8List? fileBytes,
    String fileField = 'photo',
    String? filename,
    Map<String, String>? extraHeaders,
  }) async {
    Uri uri = _buildUri(pathOrUrl);

    final request = http.MultipartRequest('POST', uri);

    fields.forEach((k, v) {
      request.fields[k] = v;
    });

    if (file != null && !kIsWeb) {
      final multipartFile = await http.MultipartFile.fromPath(
        fileField,
        file.path,
        filename: filename ?? file.path.split('/').last,
      );
      request.files.add(multipartFile);
    } else if (fileBytes != null) {
      request.files.add(http.MultipartFile.fromBytes(
        fileField,
        fileBytes,
        filename: filename ?? 'upload.jpg',
      ));
    }

    if (extraHeaders != null) {
      request.headers.addAll(extraHeaders);
    }

    try {
      final tokenHeaders = await _authHeaders(jsonContent: false);
      request.headers.addAll(tokenHeaders);
    } catch (_) {}

    final streamed = await request.send().timeout(_defaultTimeout);
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode == 401) {
      try {
        await refreshToken();
        final retryRequest = http.MultipartRequest('POST', uri);
        retryRequest.fields.addAll(fields);
        if (file != null && !kIsWeb) {
          final multipartFile = await http.MultipartFile.fromPath(
            fileField,
            file.path,
            filename: filename ?? file.path.split('/').last,
          );
          retryRequest.files.add(multipartFile);
        } else if (fileBytes != null) {
          retryRequest.files.add(http.MultipartFile.fromBytes(
            fileField,
            fileBytes,
            filename: filename ?? 'upload.jpg',
          ));
        }
        final retryHeaders = await _authHeaders(jsonContent: false);
        if (extraHeaders != null) retryHeaders.addAll(extraHeaders);
        retryRequest.headers.addAll(retryHeaders);

        final streamedRetry = await retryRequest.send().timeout(_defaultTimeout);
        final respRetry = await http.Response.fromStream(streamedRetry);
        return respRetry;
      } catch (e) {}
    }

    return resp;
  }


  /// Signup 
  Future<Map<String, dynamic>> signupWithPhoto(
    Map<String, dynamic> profile, {
    File? file,
    Uint8List? fileBytes,
    String? filename,
  }) async {
    if (file == null && fileBytes == null) {
      final uri = '$baseUrl/auth/signup';
      final response = await http
          .post(Uri.parse(uri),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode(profile))
          .timeout(_defaultTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));
        final prefs = await SharedPreferences.getInstance();
        if (data.containsKey("access_token")) {
          await prefs.setString("authToken", data["access_token"]);
        }
        if (data.containsKey("refresh_token")) {
          await prefs.setString("refreshToken", data["refresh_token"]);
        }
        return data;
      } else {
        throw Exception('Signup failed: ${response.statusCode} ${response.body}');
      }
    }

    final fields = <String, String>{};
    profile.forEach((k, v) {
      fields[k] = v == null ? '' : v.toString();
    });

    final resp = await _multipartPost(
      '/auth/signup',
      fields: fields,
      file: file,
      fileBytes: fileBytes,
      filename: filename,
      fileField: 'photo',
    );

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      final data = Map<String, dynamic>.from(jsonDecode(resp.body));
      final prefs = await SharedPreferences.getInstance();
      if (data.containsKey("access_token")) {
        await prefs.setString("authToken", data["access_token"]);
      }
      if (data.containsKey("refresh_token")) {
        await prefs.setString("refreshToken", data["refresh_token"]);
      }
      return data;
    } else {
      throw Exception('Signup with photo failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<Map<String, dynamic>> loginUser(String email, String password) async {
    final uri = '$baseUrl/auth/login';
    final response = await http
        .post(Uri.parse(uri),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"email_id": email, "password": password}))
        .timeout(_defaultTimeout);

    if (response.statusCode == 200) {
      final data = Map<String, dynamic>.from(jsonDecode(response.body));
      final prefs = await SharedPreferences.getInstance();

      if (data.containsKey("access_token")) {
        await prefs.setString("authToken", data["access_token"]);
      }
      if (data.containsKey("refresh_token")) {
        await prefs.setString("refreshToken", data["refresh_token"]);
      }

      if (data.containsKey("user") && data["user"] is Map) {
        final userMap = Map<String, dynamic>.from(data["user"]);
        await prefs.setString("user_profile", jsonEncode(userMap));

        // Save userId separately to simplify fetching
        final userId = userMap['id'] ?? userMap['user_id'] ?? userMap['userId'];
        if (userId != null) {
          await prefs.setString("userId", userId.toString());
        }
      }

      return data;
    } else {
      throw Exception('Login failed: ${response.statusCode} ${response.body}');
    }
  }

  Future<List<Map<String, dynamic>>> recommendMatches() async {
    final resp = await _get('/recommend');
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);

      // data is a Map, extract the list
      final List<dynamic> profiles = data['recommended_profiles'] ?? [];

      // convert each item to Map<String, dynamic>
      return profiles.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
    } else {
      throw Exception('Failed to fetch matches: ${resp.statusCode}');
    }
  }

  /// Fetch 1:1 chat conversations
  Future<List<dynamic>> fetchConversations() async {
    final resp = await _get('/fetch_conversations');
    if (resp.statusCode == 200) {
      return List<dynamic>.from(jsonDecode(resp.body));
    } else {
      throw Exception('Failed to fetch conversations: ${resp.statusCode}');
    }
  }
}
