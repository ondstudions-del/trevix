import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';

/// Error de la API con el mensaje en español listo para mostrar y los errores de cada campo.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.fields = const {}, this.retryAfter]);

  final int status;
  final String code;
  final String message;
  final Map<String, String> fields;
  final int? retryAfter;

  String? field(String key) => fields[key];

  @override
  String toString() => message;
}

String errorText(Object error) =>
    error is ApiException ? error.message : 'Ocurrió un error inesperado. Inténtalo de nuevo.';

class ApiResponse {
  ApiResponse(this.data, this.meta);

  final dynamic data;
  final Map<String, dynamic> meta;

  Map<String, dynamic> get map => data is Map ? Map<String, dynamic>.from(data as Map) : <String, dynamic>{};

  List<Map<String, dynamic>> get list => data is List
      ? (data as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  Map<String, dynamic>? get next => meta['next'] is Map ? Map<String, dynamic>.from(meta['next'] as Map) : null;
}

/// Archivo para un envío multipart.
class Upload {
  const Upload(this.field, this.path, {this.filename});

  final String field;
  final String path;
  final String? filename;
}

/// Cliente de la API v1 (token Bearer, JSON y multipart).
class Api {
  Api._();

  static final Api instance = Api._();

  final http.Client _client = http.Client();
  String? token;

  /// Se llama cuando el servidor rechaza el token (sesión cerrada o vencida).
  void Function()? onUnauthorized;

  Uri _uri(String path, Map<String, dynamic>? query) {
    final base = Uri.parse(AppConfig.apiBase + path);
    if (query == null || query.isEmpty) return base;
    final params = Map<String, String>.from(base.queryParameters);
    query.forEach((key, value) {
      if (value != null && '$value' != '') params[key] = '$value';
    });
    return base.replace(queryParameters: params);
  }

  Future<ApiResponse> request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    Map<String, String>? fields,
    List<Upload> files = const [],
  }) async {
    final uri = _uri(path, query);
    final http.BaseRequest req;
    final multipart = files.isNotEmpty || fields != null;
    if (multipart) {
      final m = http.MultipartRequest(method, uri);
      if (fields != null) m.fields.addAll(fields);
      for (final f in files) {
        m.files.add(await http.MultipartFile.fromPath(f.field, f.path, filename: f.filename));
      }
      req = m;
    } else {
      final r = http.Request(method, uri);
      if (body != null) {
        r.headers['Content-Type'] = 'application/json';
        r.body = jsonEncode(body);
      }
      req = r;
    }
    req.headers['Accept'] = 'application/json';
    final t = token;
    if (t != null) req.headers['Authorization'] = 'Bearer $t';

    final http.Response res;
    try {
      final streamed = await _client.send(req).timeout(Duration(seconds: multipart ? 300 : 30));
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException(0, 'timeout', 'La conexión tardó demasiado. Inténtalo de nuevo.');
    } on SocketException {
      throw ApiException(0, 'offline', 'Sin conexión a internet. Revisa tu red e inténtalo de nuevo.');
    } on http.ClientException {
      throw ApiException(0, 'offline', 'No pudimos conectar con TREVIX. Inténtalo de nuevo.');
    }

    dynamic json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      json = null;
    }
    if (json is Map && json['ok'] == true) {
      final meta = json['meta'] is Map ? Map<String, dynamic>.from(json['meta'] as Map) : <String, dynamic>{};
      return ApiResponse(json['data'], meta);
    }

    final err = json is Map && json['error'] is Map ? Map<String, dynamic>.from(json['error'] as Map) : <String, dynamic>{};
    final fieldErrors = <String, String>{};
    if (err['fields'] is Map) {
      (err['fields'] as Map).forEach((k, v) => fieldErrors['$k'] = '$v');
    }
    if (res.statusCode == 401 && t != null) {
      onUnauthorized?.call();
    }
    throw ApiException(
      res.statusCode,
      '${err['code'] ?? 'server_error'}',
      '${err['message'] ?? 'Ocurrió un error en el servidor (${res.statusCode}).'}',
      fieldErrors,
      int.tryParse(res.headers['retry-after'] ?? ''),
    );
  }

  Future<ApiResponse> get(String path, [Map<String, dynamic>? query]) => request('GET', path, query: query);

  Future<ApiResponse> post(String path, [Map<String, dynamic>? body]) => request('POST', path, body: body ?? {});

  Future<ApiResponse> patch(String path, Map<String, dynamic> body) => request('PATCH', path, body: body);

  Future<ApiResponse> put(String path, Map<String, dynamic> body) => request('PUT', path, body: body);

  Future<ApiResponse> delete(String path, [Map<String, dynamic>? body]) => request('DELETE', path, body: body);

  /// Multipart: siempre POST (el servidor solo recibe archivos por POST).
  Future<ApiResponse> upload(String path, {Map<String, String> fields = const {}, List<Upload> files = const []}) =>
      request('POST', path, fields: Map<String, String>.from(fields), files: files);
}

final api = Api.instance;
