import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/papers/paper_detail_page.dart';
import 'package:anx_reader/service/papertok/models.dart';
import 'package:anx_reader/service/papertok/papertok_api.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class PapersPage extends StatefulWidget {
  const PapersPage({super.key, this.controller});

  final ScrollController? controller;

  @override
  State<PapersPage> createState() => _PapersPageState();
}

class _PapersPageState extends State<PapersPage> {
  final _cards = <PaperTokCard>[];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final next =
          await PaperTokApi.instance.fetchRandomPapers(limit: 20, lang: 'zh');
      // De-dup by id (random API may repeat).
      final existing = _cards.map((e) => e.id).toSet();
      for (final c in next) {
        if (!existing.contains(c.id)) {
          _cards.add(c);
          existing.add(c.id);
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cards.isEmpty && _loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_cards.isEmpty && _error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).navBarPapers)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadMore,
                child: Text(L10n.of(context).commonRetry),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: _cards.length,
        onPageChanged: (index) {
          if (index >= _cards.length - 3) {
            _loadMore();
          }
        },
        itemBuilder: (context, index) {
          final c = _cards[index];
          final api = PaperTokApi.instance;
          final img = api.resolveUrl(c.thumbnail ??
              (c.thumbnails.isNotEmpty ? c.thumbnails.first : ''));

          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PaperDetailPage(paperId: c.id),
                ),
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (img.trim().isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: img,
                    fit: BoxFit.cover,
                    placeholder: (context, _) => Container(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                    ),
                    errorWidget: (context, _, __) => Container(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: const Icon(Icons.broken_image_outlined, size: 40),
                    ),
                  )
                else
                  Container(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: const Icon(Icons.article_outlined, size: 60),
                  ),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x66000000),
                        Color(0x00000000),
                        Color(0xAA000000),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      24 + MediaQuery.of(context).padding.bottom + 96,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          L10n.of(context).navBarPapers,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const Spacer(),
                        Text(
                          c.bestTitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          c.extract,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        if ((c.day ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            c.day!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                        if (_loading && index >= _cards.length - 2) ...[
                          const SizedBox(height: 12),
                          const LinearProgressIndicator(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
