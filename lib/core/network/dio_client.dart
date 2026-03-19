import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

Dio createDioClient() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 12),
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(_ApiLogInterceptor());
  dio.interceptors.add(_RetryInterceptor(dio: dio, maxRetries: 2));

  return dio;
}

final dioClient = createDioClient();

class _ApiLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      final params = Map<String, dynamic>.from(options.queryParameters);
      if (params.containsKey('serviceKey')) {
        final key = params['serviceKey'] as String;
        params['serviceKey'] = '${key.substring(0, 8)}...';
      }
      debugPrint('[API] >> ${options.method} ${options.uri.path}');
      debugPrint('[API]    params: $params');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('[API] << ${response.statusCode} ${response.requestOptions.uri.path}');
      _logDataGoKrError(response.data);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('[API] !! ${err.type} ${err.message}');
      debugPrint('[API]    status: ${err.response?.statusCode}');
      debugPrint('[API]    body: ${err.response?.data}');
    }
    handler.next(err);
  }

  void _logDataGoKrError(dynamic data) {
    if (data is! Map) return;
    final map = data as Map<String, dynamic>;

    final header = map['response']?['header'] ??
        map['header'] ??
        map['cmmMsgHeader'];
    if (header == null) return;

    final code = header['resultCode'] ?? header['returnReasonCode'];
    final msg = header['resultMsg'] ?? header['returnAuthMsg'] ?? header['errMsg'];
    if (code != null && code != '00' && code != '0') {
      debugPrint('[API] ⚠ data.go.kr error: [$code] $msg');
    }
  }
}

class _RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;

  _RetryInterceptor({required this.dio, this.maxRetries = 2});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final retryCount = err.requestOptions.extra['retryCount'] ?? 0;

    final shouldRetry = retryCount < maxRetries &&
        (err.type == DioExceptionType.connectionTimeout ||
            err.type == DioExceptionType.receiveTimeout ||
            err.type == DioExceptionType.connectionError ||
            (err.response?.statusCode != null && err.response!.statusCode! >= 500));

    if (shouldRetry) {
      final nextRetry = retryCount + 1;
      if (kDebugMode) {
        debugPrint('[API] Retry $nextRetry/$maxRetries: ${err.requestOptions.uri.path}');
      }
      await Future.delayed(Duration(seconds: nextRetry));
      err.requestOptions.extra['retryCount'] = nextRetry;
      try {
        final response = await dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } on DioException catch (e) {
        handler.next(e);
        return;
      }
    }

    handler.next(err);
  }
}
