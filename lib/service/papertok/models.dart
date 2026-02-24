class PaperTokCard {
  final int id;
  final String title;
  final String? displayTitle;
  final String extract;
  final String? day;
  final String? thumbnail;
  final List<String> thumbnails;
  final String? url;

  String get bestTitle =>
      (displayTitle != null && displayTitle!.trim().isNotEmpty)
          ? displayTitle!
          : title;

  PaperTokCard({
    required this.id,
    required this.title,
    required this.extract,
    this.displayTitle,
    this.day,
    this.thumbnail,
    this.thumbnails = const [],
    this.url,
  });

  factory PaperTokCard.fromJson(Map<String, dynamic> json) {
    final thumb = json['thumbnail'];
    String? thumbSrc;
    if (thumb is Map) {
      final src = thumb['source'];
      if (src is String && src.trim().isNotEmpty) thumbSrc = src;
    }

    final thumbs = <String>[];
    final rawThumbs = json['thumbnails'];
    if (rawThumbs is List) {
      for (final x in rawThumbs) {
        if (x is String && x.trim().isNotEmpty) thumbs.add(x);
      }
    }

    return PaperTokCard(
      id: (json['pageid'] as num).toInt(),
      title: (json['title'] as String?) ?? '',
      displayTitle: json['displaytitle'] as String?,
      extract: (json['extract'] as String?) ?? '',
      day: json['day'] as String?,
      thumbnail: thumbSrc,
      thumbnails: thumbs,
      url: json['url'] as String?,
    );
  }
}

class PaperTokGeneratedImage {
  final String url;
  final String? provider;
  final String? lang;

  PaperTokGeneratedImage({
    required this.url,
    this.provider,
    this.lang,
  });

  factory PaperTokGeneratedImage.fromJson(Map<String, dynamic> json) {
    return PaperTokGeneratedImage(
      url: (json['url'] as String?) ?? '',
      provider: json['provider'] as String?,
      lang: json['lang'] as String?,
    );
  }
}

class PaperTokDetail {
  final int id;
  final String title;
  final String? displayTitle;
  final String? externalId;
  final String? url;
  final String? oneLiner;
  final String? contentExplain;
  final String? pdfUrl;
  final String? pdfLocalUrl;
  final String? epubUrl;
  final String? epubUrlEn;
  final String? epubUrlZh;
  final String? epubUrlBilingual;
  final List<String> images;
  final List<PaperTokGeneratedImage> generatedImages;

  PaperTokDetail({
    required this.id,
    required this.title,
    this.displayTitle,
    this.externalId,
    this.url,
    this.oneLiner,
    this.contentExplain,
    this.pdfUrl,
    this.pdfLocalUrl,
    this.epubUrl,
    this.epubUrlEn,
    this.epubUrlZh,
    this.epubUrlBilingual,
    this.images = const [],
    this.generatedImages = const [],
  });

  factory PaperTokDetail.fromJson(Map<String, dynamic> json) {
    final images = <String>[];
    final rawImages = json['images'];
    if (rawImages is List) {
      for (final x in rawImages) {
        if (x is String && x.trim().isNotEmpty) images.add(x);
      }
    }

    final gen = <PaperTokGeneratedImage>[];
    final rawGen = json['generated_images'];
    if (rawGen is List) {
      for (final x in rawGen) {
        if (x is Map) {
          gen.add(PaperTokGeneratedImage.fromJson(
              x.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }

    return PaperTokDetail(
      id: (json['id'] as num).toInt(),
      title: (json['title'] as String?) ?? '',
      displayTitle: json['display_title'] as String?,
      externalId: json['external_id'] as String?,
      url: json['url'] as String?,
      oneLiner: json['one_liner'] as String?,
      contentExplain: json['content_explain'] as String?,
      pdfUrl: json['pdf_url'] as String?,
      pdfLocalUrl: json['pdf_local_url'] as String?,
      epubUrl: json['epub_url'] as String?,
      epubUrlEn: json['epub_url_en'] as String?,
      epubUrlZh: json['epub_url_zh'] as String?,
      epubUrlBilingual: json['epub_url_bilingual'] as String?,
      images: images,
      generatedImages: gen,
    );
  }

  String? get bestEpubUrl {
    String? pick(String? s) {
      if (s == null) return null;
      final t = s.trim();
      return t.isEmpty ? null : t;
    }

    // Prefer the API's primary epub_url (usually language-scoped),
    // then fall back to zh/en/bilingual fields.
    return pick(epubUrl) ??
        pick(epubUrlZh) ??
        pick(epubUrlEn) ??
        pick(epubUrlBilingual);
  }

  List<String> get carouselImages {
    final out = <String>[];
    for (final g in generatedImages) {
      if (g.url.trim().isNotEmpty) out.add(g.url);
    }
    if (out.isNotEmpty) return out;
    return images;
  }
}
