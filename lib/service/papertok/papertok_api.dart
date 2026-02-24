import 'package:dio/dio.dart';

import 'models.dart';

class PaperTokApi {
  PaperTokApi._internal();

  static final PaperTokApi instance = PaperTokApi._internal();

  static const String defaultBaseUrl = 'https://papertok.ai';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: defaultBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
      },
    ),
  );

  String resolveUrl(String? url) {
    final u = (url ?? '').trim();
    if (u.isEmpty) return '';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('/')) return '$defaultBaseUrl$u';
    return '$defaultBaseUrl/$u';
  }

  Future<List<PaperTokCard>> fetchRandomPapers({
    int limit = 20,
    String lang = 'zh',
  }) async {
    final resp = await _dio.get(
      '/api/papers/random',
      queryParameters: {
        'limit': limit,
        'lang': lang,
      },
    );

    final data = resp.data;
    if (data is! List) return [];

    final out = <PaperTokCard>[];
    for (final item in data) {
      if (item is Map) {
        out.add(PaperTokCard.fromJson(
            item.map((k, v) => MapEntry(k.toString(), v))));
      }
    }
    return out;
  }

  Future<PaperTokDetail> fetchPaperDetail(
    int paperId, {
    String lang = 'zh',
  }) async {
    final resp = await _dio.get(
      '/api/papers/$paperId',
      queryParameters: {
        'lang': lang,
      },
    );
    final data = resp.data;
    if (data is Map) {
      return PaperTokDetail.fromJson(
          data.map((k, v) => MapEntry(k.toString(), v)));
    }
    throw Exception('Invalid response');
  }
}
