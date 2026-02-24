import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/enums/inline_fulltext_translate_failure_reason.dart';
import 'package:anx_reader/enums/page_turn_mode.dart';
import 'package:anx_reader/enums/reading_info.dart';
import 'package:anx_reader/enums/translation_mode.dart';
import 'package:anx_reader/enums/writing_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/models/bookmark.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/models/reading_rules.dart';
import 'package:anx_reader/models/search_result_model.dart';
import 'package:anx_reader/models/toc_item.dart';
import 'package:anx_reader/page/book_player/image_viewer.dart';
import 'package:anx_reader/page/home_page.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/book_toc.dart';
import 'package:anx_reader/providers/bookmark.dart';
import 'package:anx_reader/providers/chapter_content_bridge.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/service/translate/fulltext_translate_runtime.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/service/translate/inline_fulltext_translation_status.dart';
import 'package:anx_reader/providers/toc_search.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/utils/coordinates_to_part.dart';
import 'package:anx_reader/utils/js/convert_dart_color_to_js.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/webView/gererate_url.dart';
import 'package:anx_reader/utils/webView/webview_console_message.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/context_menu/context_menu.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/page_turning/diagram.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/page_turning/types_and_icons.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';

import 'minute_clock.dart';

class EpubPlayer extends ConsumerStatefulWidget {
  final Book book;
  final String? cfi;
  final Function showOrHideAppBarAndBottomBar;
  final Function onLoadEnd;
  final List<ReadTheme> initialThemes;
  final Function updateParent;

  const EpubPlayer(
      {super.key,
      required this.showOrHideAppBarAndBottomBar,
      required this.book,
      this.cfi,
      required this.onLoadEnd,
      required this.initialThemes,
      required this.updateParent});

  @override
  ConsumerState<EpubPlayer> createState() => EpubPlayerState();
}

class EpubPlayerState extends ConsumerState<EpubPlayer>
    with TickerProviderStateMixin {
  late InAppWebViewController webViewController;
  late ContextMenu contextMenu;
  String cfi = '';
  double percentage = 0.0;
  String chapterTitle = '';
  String chapterHref = '';
  int chapterCurrentPage = 0;
  int chapterTotalPages = 0;
  OverlayEntry? contextMenuEntry;
  AnimationController? _animationController;
  Animation<double>? _animation;
  bool showHistory = false;
  bool canGoBack = false;
  bool canGoForward = false;
  late Book book;
  String? backgroundColor;
  String? textColor;
  Timer? styleTimer;
  String bookmarkCfi = '';
  bool bookmarkExists = false;
  WritingModeEnum writingMode = WritingModeEnum.horizontalTb;
  String? _lastSelectionContextText;
  bool _selectionClearLocked = false;
  bool _selectionClearPending = false;

  // Inline translation HUD (per relocated page)
  final ValueNotifier<_InlineTranslateHudState> _translateHud =
      ValueNotifier(const _InlineTranslateHudState());
  final Map<String, _InlineTranslateHudEntry> _translateHudItems =
      <String, _InlineTranslateHudEntry>{};
  bool _translateHudVisible = true;

  // to know anytime if we are on top of navigation stack
  bool get _isTopOfNavigationStack =>
      ModalRoute.of(context)?.isCurrent ?? false;

  void prevPage() {
    webViewController.evaluateJavascript(source: 'prevPage()');
  }

  void nextPage() {
    webViewController.evaluateJavascript(source: 'nextPage()');
  }

  void prevChapter() {
    webViewController.evaluateJavascript(source: '''
      prevSection()
      ''');
  }

  void nextChapter() {
    webViewController.evaluateJavascript(source: '''
      nextSection()
      ''');
  }

  void setTranslationMode(TranslationModeEnum mode) {
    webViewController.evaluateJavascript(source: '''
      if (typeof reader.view !== 'undefined' && reader.view.setTranslationMode) {
        reader.view.setTranslationMode('${mode.code}');
      }
      ''');

    // Reset HUD stats when toggling translation mode.
    _resetTranslateHud();
    if (mode != TranslationModeEnum.off) {
      _translateHudVisible = true;
    }
  }

  Future<void> goToPercentage(double value) async {
    await webViewController.evaluateJavascript(source: '''
      goToPercent($value); 
      ''');
  }

  void setSelectionClearLocked(bool locked) {
    _selectionClearLocked = locked;
    if (!locked && _selectionClearPending) {
      _selectionClearPending = false;
      _lastSelectionContextText = null;
      removeOverlay();
    }
  }

  void changeTheme(ReadTheme readTheme) {
    textColor = readTheme.textColor;
    backgroundColor = readTheme.backgroundColor;

    String bc = convertDartColorToJs(readTheme.backgroundColor);
    String tc = convertDartColorToJs(readTheme.textColor);

    webViewController.evaluateJavascript(source: '''
      changeStyle({
        backgroundColor: '#$bc',
        fontColor: '#$tc',
      })
      ''');
  }

  void changeStyle(BookStyle? bookStyle) {
    styleTimer?.cancel();
    String bgimgUrl = Prefs().bgimg.getEffectiveUrl(
          isDarkMode: isDarkMode,
          autoAdjust: Prefs().autoAdjustReadingTheme,
        );

    styleTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      BookStyle style = bookStyle ?? Prefs().bookStyle;
      webViewController.evaluateJavascript(source: '''
      changeStyle({
        fontSize: ${style.fontSize},
        spacing: ${style.lineHeight},
        fontWeight: ${style.fontWeight},
        paragraphSpacing: ${style.paragraphSpacing},
        topMargin: ${style.topMargin},
        bottomMargin: ${style.bottomMargin},
        sideMargin: ${style.sideMargin},
        letterSpacing: ${style.letterSpacing},
        textIndent: ${style.indent},
        maxColumnCount: ${style.maxColumnCount},
        columnThreshold: ${style.columnThreshold},
        writingMode: '${Prefs().writingMode.code}',
        textAlign: '${Prefs().textAlignment.code}',
        backgroundImage: '$bgimgUrl',
        customCSS: `${Prefs().customCSS.replaceAll('`', '\\`')}`,
        customCSSEnabled: ${Prefs().customCSSEnabled},
        useBookStyles: ${Prefs().useBookStyles},
        headingFontSize: ${style.headingFontSize},
        codeHighlightTheme: '${Prefs().codeHighlightTheme.code}',
      })
      ''');
    });
  }

  void changeReadingRules(ReadingRules readingRules) {
    webViewController.evaluateJavascript(source: '''
      readingFeatures({
        convertChineseMode: '${readingRules.convertChineseMode.name}',
        bionicReadingMode: ${readingRules.bionicReading},
      })
    ''');
  }

  void changeFont(FontModel font) {
    webViewController.evaluateJavascript(source: '''
      changeStyle({
        fontName: '${font.name}',
        fontPath: '${font.path}',
      })
    ''');
  }

  void changePageTurnStyle(PageTurn pageTurnStyle) {
    webViewController.evaluateJavascript(source: '''
      changeStyle({
        pageTurnStyle: '${pageTurnStyle.name}',
      })
    ''');
  }

  void goToHref(String href) =>
      webViewController.evaluateJavascript(source: "goToHref('$href')");

  void goToCfi(String cfi) =>
      webViewController.evaluateJavascript(source: "goToCfi('$cfi')");

  void addAnnotation(BookNote bookNote) {
    final noteContent =
        (bookNote.content).replaceAll('\n', ' ').replaceAll("'", "\\'");
    webViewController.evaluateJavascript(source: '''
      addAnnotation({
        id: ${bookNote.id},
        type: '${bookNote.type}',
        value: '${bookNote.cfi}',
        color: '#${bookNote.color}',
        note: '$noteContent',
      })
      ''');
  }

  void addBookmark(BookmarkModel bookmark) {
    webViewController.evaluateJavascript(source: '''
      addAnnotation({
        id: ${bookmark.id},
        type: 'bookmark',
        value: '${bookmark.cfi}',
        color: '#000000',
        note: 'None',
      })
      ''');
  }

  void addBookmarkHere() {
    webViewController.evaluateJavascript(source: '''
      addBookmarkHere()
      ''');
  }

  void removeAnnotation(String cfi) =>
      webViewController.evaluateJavascript(source: "removeAnnotation('$cfi')");

  void clearSearch() {
    ref.read(tocSearchProvider.notifier).clear();
    _clearSearchHighlights();
  }

  void search(String text) {
    final sanitized = text.trim();
    if (sanitized.isEmpty) {
      clearSearch();
      return;
    }
    _clearSearchHighlights();
    ref.read(tocSearchProvider.notifier).start(sanitized);
    webViewController.evaluateJavascript(source: '''
      search('$sanitized', {
        'scope': 'book',
        'matchCase': false,
        'matchDiacritics': false,
        'matchWholeWords': false,
      })
    ''');
  }

  void _clearSearchHighlights() {
    webViewController.evaluateJavascript(source: "clearSearch()");
  }

  Future<void> initTts() async =>
      await webViewController.evaluateJavascript(source: "window.ttsHere()");

  void ttsStop() => webViewController.evaluateJavascript(source: "ttsStop()");

  Future<String> ttsNext() async => (await webViewController
          .callAsyncJavaScript(functionBody: "return await ttsNext()"))
      ?.value;

  Future<String> ttsPrev() async => (await webViewController
          .callAsyncJavaScript(functionBody: "return await ttsPrev()"))
      ?.value;

  Future<String> ttsPrevSection() async => (await webViewController
          .callAsyncJavaScript(functionBody: "return await ttsPrevSection()"))
      ?.value;

  Future<String> ttsNextSection() async => (await webViewController
          .callAsyncJavaScript(functionBody: "return await ttsNextSection()"))
      ?.value;

  Future<String> ttsPrepare() async =>
      (await webViewController.evaluateJavascript(source: "ttsPrepare()"));

  TtsSentence? _parseTtsSentence(dynamic value) {
    if (value is Map<dynamic, dynamic>) {
      try {
        return TtsSentence.fromMap(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  List<TtsSentence> _parseTtsSentences(dynamic value) {
    if (value is! List) return const [];

    final sentences = <TtsSentence>[];
    for (final item in value) {
      final sentence = _parseTtsSentence(item);
      if (sentence != null) {
        sentences.add(sentence);
      }
    }
    return sentences;
  }

  Future<TtsSentence?> ttsCurrentDetail() async {
    final result = await webViewController.callAsyncJavaScript(
      functionBody: 'return ttsCurrentDetail()',
    );
    return _parseTtsSentence(result?.value);
  }

  Future<List<TtsSentence>> ttsCollectDetails({
    required int count,
    bool includeCurrent = false,
    int offset = 1,
  }) async {
    final result = await webViewController.callAsyncJavaScript(
      functionBody:
          'return ttsCollectDetails($count, ${includeCurrent ? 'true' : 'false'}, $offset)',
    );
    return _parseTtsSentences(result?.value);
  }

  Future<void> ttsHighlightByCfi(String cfi) async {
    await webViewController.callAsyncJavaScript(
      functionBody: 'return ttsHighlightByCfi(${jsonEncode(cfi)})',
    );
  }

  Future<bool> isFootNoteOpen() async => (await webViewController
      .evaluateJavascript(source: "window.isFootNoteOpen()"));

  void backHistory() {
    webViewController.evaluateJavascript(source: "back()");
  }

  void forwardHistory() {
    webViewController.evaluateJavascript(source: "forward()");
  }

  void refreshToc() {
    webViewController.evaluateJavascript(source: "refreshToc()");
  }

  Future<String> theChapterContent() async =>
      await webViewController.evaluateJavascript(
        source: "theChapterContent()",
      );

  Future<String> previousContent(int count) async =>
      await webViewController.evaluateJavascript(
        source: "previousContent($count)",
      );

  Future<String> _getCurrentChapterContent({int? maxCharacters}) async {
    final raw = await theChapterContent();
    return _normalizeChapterContent(raw, maxCharacters);
  }

  Future<String> _getChapterContentByHref(
    String href, {
    int? maxCharacters,
  }) async {
    if (href.isEmpty) {
      return '';
    }

    final result = await webViewController.callAsyncJavaScript(
      functionBody:
          'return await getChapterContentByHref("${href.replaceAll('"', '\\"')}")',
    );

    final value = result?.value;
    if (value is String) {
      return _normalizeChapterContent(value, maxCharacters);
    }
    return '';
  }

  String _normalizeChapterContent(String? content, int? maxCharacters) {
    if (content == null || content.isEmpty) {
      return '';
    }
    final trimmed = content.trim();
    if (maxCharacters != null &&
        maxCharacters > 0 &&
        trimmed.length > maxCharacters) {
      return trimmed.substring(0, maxCharacters);
    }
    return trimmed;
  }

  void _registerChapterContentBridge() {
    ref.read(chapterContentBridgeProvider.notifier).state =
        ChapterContentHandlers(
      fetchCurrentChapter: ({int? maxCharacters}) =>
          _getCurrentChapterContent(maxCharacters: maxCharacters),
      fetchChapterByHref: (href, {int? maxCharacters}) =>
          _getChapterContentByHref(href, maxCharacters: maxCharacters),
    );
  }

  Future<void> _handleExternalLink(dynamic rawLink) async {
    String? normalizeExternalLink(dynamic raw) {
      if (raw == null) {
        return null;
      }
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.trim();
      }
      if (raw is Map && raw['href'] is String) {
        final href = raw['href'].toString().trim();
        return href.isEmpty ? null : href;
      }
      return null;
    }

    final link = normalizeExternalLink(rawLink);
    if (!mounted || link == null) {
      return;
    }

    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme.isEmpty || uri.scheme == 'javascript') {
      AnxLog.warning('Ignored invalid external link: $link');
      return;
    }

    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = L10n.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.readingPageOpenExternalLinkTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.readingPageOpenExternalLinkMessage),
              const SizedBox(height: 8),
              SelectableText(link),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.readingPageOpenExternalLinkAction),
            ),
          ],
        );
      },
    );

    if (shouldOpen != true) {
      return;
    }

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      AnxLog.warning('Failed to open external link: $link');
    }
  }

  void onClick(Map<String, dynamic> location) {
    readingPageKey.currentState?.resetAwakeTimer();
    if (contextMenuEntry != null) {
      removeOverlay();
      return;
    }
    final x = location['x'];
    final y = location['y'];
    final part = coordinatesToPart(x, y);

    PageTurningType action;
    final pageTurnMode = PageTurnMode.fromCode(Prefs().pageTurnMode);

    if (pageTurnMode == PageTurnMode.simple) {
      // Use predefined page turning types
      final currentPageTurningType = Prefs().pageTurningType;
      final pageTurningType = pageTurningTypes[currentPageTurningType];
      action = pageTurningType[part];

      // Apply swap if enabled
      if (Prefs().swapPageTurnArea) {
        if (action == PageTurningType.prev) {
          action = PageTurningType.next;
        } else if (action == PageTurningType.next) {
          action = PageTurningType.prev;
        }
      }
    } else {
      // Use custom configuration
      final customConfig = Prefs().customPageTurnConfig;
      action = PageTurningType.values[customConfig[part]];
    }

    switch (action) {
      case PageTurningType.prev:
        prevPage();
        break;
      case PageTurningType.next:
        nextPage();
        break;
      case PageTurningType.menu:
        widget.showOrHideAppBarAndBottomBar(true);
        break;
      case PageTurningType.none:
        break;
    }
  }

  Future<void> renderAnnotations(InAppWebViewController controller) async {
    List<BookNote> annotationList =
        await bookNoteDao.selectBookNotesByBookId(widget.book.id);
    String allAnnotations =
        jsonEncode(annotationList.map((e) => e.toJson()).toList())
            .replaceAll('\'', '\\\'');
    controller.evaluateJavascript(source: '''
     const allAnnotations = $allAnnotations
     renderAnnotations()
    ''');
  }

  void getThemeColor() {
    if (Prefs().autoAdjustReadingTheme) {
      List<ReadTheme> themes = widget.initialThemes;
      final isDayMode =
          Theme.of(navigatorKey.currentContext!).brightness == Brightness.light;
      backgroundColor =
          isDayMode ? themes[0].backgroundColor : themes[1].backgroundColor;
      textColor = isDayMode ? themes[0].textColor : themes[1].textColor;
    } else {
      backgroundColor = Prefs().readTheme.backgroundColor;
      textColor = Prefs().readTheme.textColor;
    }
  }

  Future<void> setHandler(InAppWebViewController controller) async {
    controller.addJavaScriptHandler(
        handlerName: 'onLoadEnd',
        callback: (args) {
          widget.onLoadEnd();
        });

    controller.addJavaScriptHandler(
        handlerName: 'onRelocated',
        callback: (args) {
          Map<String, dynamic> location = args[0];
          if (cfi == location['cfi']) return;

          final newChapterHref = location['chapterHref'] ?? '';
          final chapterChanged = newChapterHref != chapterHref;

          // Keep HUD stats across page turns inside the same chapter.
          // Only reset when chapter changes (or when user toggles mode / presses retry).
          if (chapterChanged) {
            _resetTranslateHud();
          }

          // Keep HUD visible when translation is enabled.
          final mode = Prefs().getBookTranslationMode(widget.book.id);
          if (mode != TranslationModeEnum.off &&
              Prefs().pageTurnStyle != PageTurn.scroll) {
            _translateHudVisible = true;
          }

          // if (chapterHref != location['chapterHref']) {
          //   refreshToc();
          // }
          setState(() {
            cfi = location['cfi'] ?? '';
            percentage =
                double.tryParse(location['percentage'].toString()) ?? 0.0;
            chapterTitle = location['chapterTitle'] ?? '';
            chapterHref = location['chapterHref'] ?? '';
            chapterCurrentPage = location['chapterCurrentPage'] ?? 0;
            chapterTotalPages = location['chapterTotalPages'] ?? 0;
            bookmarkExists = location['bookmark']['exists'] ?? false;
            bookmarkCfi = location['bookmark']['cfi'] ?? '';
            writingMode =
                WritingModeEnum.fromCode(location['writingMode'] ?? '');
          });
          ref.read(currentReadingProvider.notifier).update(
                cfi: cfi,
                percentage: percentage,
                chapterTitle: chapterTitle,
                chapterHref: chapterHref,
                chapterCurrentPage: chapterCurrentPage,
                chapterTotalPages: chapterTotalPages,
              );
          widget.updateParent();
          saveReadingProgress();
          readingPageKey.currentState?.resetAwakeTimer();
        });
    controller.addJavaScriptHandler(
        handlerName: 'onClick',
        callback: (args) {
          Map<String, dynamic> location = args[0];
          onClick(location);
        });
    controller.addJavaScriptHandler(
      handlerName: 'onExternalLink',
      callback: (args) async {
        final payload = args.isNotEmpty ? args.first : null;
        await _handleExternalLink(payload);
      },
    );
    controller.addJavaScriptHandler(
        handlerName: 'onSetToc',
        callback: (args) {
          List<dynamic> t = args[0];
          final toc = t.map((i) => TocItem.fromJson(i)).toList();
          ref.read(bookTocProvider.notifier).setToc(toc);
        });
    controller.addJavaScriptHandler(
        handlerName: 'onSelectionEnd',
        callback: (args) {
          removeOverlay();
          Map<String, dynamic> location = args[0];
          String cfi = location['cfi'];
          String text = location['text'];
          bool footnote = location['footnote'];
          final rawContextText = location['contextText']?.toString();
          _lastSelectionContextText =
              (rawContextText?.trim().isEmpty ?? true) ? null : rawContextText;
          double left = (location['pos']['left'] as num).toDouble();
          double top = (location['pos']['top'] as num).toDouble();
          double right = (location['pos']['right'] as num).toDouble();
          double bottom = (location['pos']['bottom'] as num).toDouble();
          showContextMenu(
            context,
            left,
            top,
            right,
            bottom,
            text,
            cfi,
            null,
            footnote,
            writingMode.isVertical ? Axis.vertical : Axis.horizontal,
            contextText: _lastSelectionContextText,
          );
        });
    controller.addJavaScriptHandler(
        handlerName: 'onSelectionCleared',
        callback: (args) {
          if (_selectionClearLocked) {
            _selectionClearPending = true;
            return;
          }
          _lastSelectionContextText = null;
          removeOverlay();
        });
    controller.addJavaScriptHandler(
        handlerName: 'onAnnotationClick',
        callback: (args) {
          Map<String, dynamic> annotation = args[0];
          int id = annotation['annotation']['id'];
          String cfi = annotation['annotation']['value'];
          String note = annotation['annotation']['note'];
          final rawContextText = annotation['contextText']?.toString();
          _lastSelectionContextText =
              (rawContextText?.trim().isEmpty ?? true) ? null : rawContextText;
          double left = (annotation['pos']['left'] as num).toDouble();
          double top = (annotation['pos']['top'] as num).toDouble();
          double right = (annotation['pos']['right'] as num).toDouble();
          double bottom = (annotation['pos']['bottom'] as num).toDouble();
          showContextMenu(
            context,
            left,
            top,
            right,
            bottom,
            note,
            cfi,
            id,
            false,
            writingMode.isVertical ? Axis.vertical : Axis.horizontal,
            contextText: _lastSelectionContextText,
          );
        });
    controller.addJavaScriptHandler(
      handlerName: 'onSearch',
      callback: (args) {
        Map<String, dynamic> search = args[0];
        setState(() {
          final tocSearch = ref.read(tocSearchProvider.notifier);
          if (search['process'] != null) {
            final progress = search['process'].toDouble();
            tocSearch.updateProgress(progress);
          } else {
            tocSearch.addResult(SearchResultModel.fromJson(search));
          }
        });
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'renderAnnotations',
      callback: (args) {
        renderAnnotations(controller);
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onPushState',
      callback: (args) {
        Map<String, dynamic> state = args[0];
        if (!mounted) return;
        setState(() {
          canGoBack = state['canGoBack'];
          canGoForward = state['canGoForward'];
          showHistory = canGoBack || canGoForward;
        });
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onImageClick',
      callback: (args) {
        String image = args[0];
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => ImageViewer(
                      image: image,
                      bookName: widget.book.title,
                    )));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onFootnoteClose',
      callback: (args) {
        removeOverlay();
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onPullUp',
      callback: (args) {
        widget.showOrHideAppBarAndBottomBar(true);
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'handleBookmark',
      callback: (args) async {
        Map<String, dynamic> detail = args[0]['detail'];
        bool remove = args[0]['remove'];
        String cfi = detail['cfi'] ?? '';
        double percentage = double.parse(detail['percentage'].toString());
        String content = detail['content'];

        if (remove) {
          ref.read(bookmarkProvider(widget.book.id).notifier).removeBookmark(
                cfi: cfi,
              );
          bookmarkCfi = '';
          bookmarkExists = false;
        } else {
          BookmarkModel bookmark = await ref
              .read(BookmarkProvider(widget.book.id).notifier)
              .addBookmark(
                BookmarkModel(
                  bookId: widget.book.id,
                  cfi: cfi,
                  percentage: percentage,
                  content: content,
                  chapter: chapterTitle,
                  updateTime: DateTime.now(),
                  createTime: DateTime.now(),
                ),
              );
          bookmarkCfi = cfi;
          bookmarkExists = true;
          addBookmark(bookmark);
        }
        widget.updateParent();
        setState(() {});
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'translateText',
      callback: (args) async {
        final text =
            (args.isNotEmpty ? args[0]?.toString() : null)?.trim() ?? '';
        if (text.isEmpty) return '';

        // Translation settings are AI-only. Keep runtime stable regardless of
        // historical prefs.
        final service = TranslateService.aiFullText;
        final from = Prefs().fullTextTranslateFrom;
        final to = Prefs().fullTextTranslateTo;

        final cacheKey = FullTextTranslateRuntime.instance.buildCacheKey(
          bookId: widget.book.id,
          service: service,
          from: from,
          to: to,
          text: text,
        );

        // Update HUD stats
        _translateHudVisible = true;
        _hudMarkStart(cacheKey: cacheKey);

        try {
          final out = await FullTextTranslateRuntime.instance.translateWithMeta(
            service,
            text,
            from,
            to,
            bookId: widget.book.id,
          );

          if (out.text.trim().isEmpty || _looksLikeTranslateFailure(out.text)) {
            _hudMarkFail(
              cacheKey: cacheKey,
              reason: out.failureReason ??
                  InlineFullTextTranslateFailureReason.translateError,
            );
            return '';
          }

          _hudMarkDone(cacheKey: cacheKey);
          return out.text;
        } catch (e) {
          _hudMarkFail(
            cacheKey: cacheKey,
            reason: InlineFullTextTranslateFailureReason.exception,
          );
          AnxLog.severe('Translation error: $e');
          return '';
        } finally {
          _hudMarkFinishInflight(cacheKey: cacheKey);
        }
      },
    );

    // Structured translation for paragraphs that contain links.
    // Payload: { fullText: string, segments: [{type:'text'|'link', text, href?}] }
    // Response: string[] translated texts aligned to segments
    controller.addJavaScriptHandler(
      handlerName: 'translateRichSegments',
      callback: (args) async {
        try {
          if (args.isEmpty) return const <String>[];
          final payload = args[0];
          if (payload is! Map) return const <String>[];

          final fullText = payload['fullText']?.toString().trim() ?? '';
          final rawSegments = payload['segments'];
          if (fullText.isEmpty || rawSegments is! List) {
            return const <String>[];
          }

          // Translation settings are AI-only. Keep runtime stable regardless of
          // historical prefs.
          final service = TranslateService.aiFullText;
          final from = Prefs().fullTextTranslateFrom;
          final to = Prefs().fullTextTranslateTo;

          // HUD counts per paragraph (fullText key), not per segment.
          final cacheKey = FullTextTranslateRuntime.instance.buildCacheKey(
            bookId: widget.book.id,
            service: service,
            from: from,
            to: to,
            text: fullText,
          );

          _translateHudVisible = true;
          _hudMarkStart(cacheKey: cacheKey);

          final futures = <Future<({String text, InlineFullTextTranslateFailureReason? failureReason})>>[];
          for (final seg in rawSegments) {
            if (seg is! Map) {
              futures.add(
                Future.value(
                  (
                    text: '',
                    failureReason: InlineFullTextTranslateFailureReason.unknown,
                  ),
                ),
              );
              continue;
            }
            final segText = seg['text']?.toString() ?? '';
            futures.add(
              FullTextTranslateRuntime.instance.translateWithMeta(
                service,
                segText,
                from,
                to,
                bookId: widget.book.id,
              ),
            );
          }

          final outcomes = await Future.wait(futures);
          final results = outcomes.map((e) => e.text).toList(growable: false);

          final hasAny = results.any((e) => e.trim().isNotEmpty);
          if (!hasAny) {
            // Pick the most common failure reason among segments.
            final counts = <InlineFullTextTranslateFailureReason, int>{};
            for (final o in outcomes) {
              final r = o.failureReason ?? InlineFullTextTranslateFailureReason.unknown;
              counts[r] = (counts[r] ?? 0) + 1;
            }
            InlineFullTextTranslateFailureReason best =
                InlineFullTextTranslateFailureReason.unknown;
            var bestCount = -1;
            for (final entry in counts.entries) {
              if (entry.value > bestCount) {
                best = entry.key;
                bestCount = entry.value;
              }
            }

            _hudMarkFail(cacheKey: cacheKey, reason: best);
          } else {
            _hudMarkDone(cacheKey: cacheKey);
          }

          return results;
        } catch (e) {
          // Do not throw into JS.
          return const <String>[];
        }
      },
    );
  }

  Future<void> onWebViewCreated(InAppWebViewController controller) async {
    if (AnxPlatform.isAndroid) {
      await InAppWebViewController.setWebContentsDebuggingEnabled(true);
    }
    webViewController = controller;
    setHandler(controller);
    _registerChapterContentBridge();

    // Initialize translation mode based on book-specific settings
    Future.delayed(const Duration(milliseconds: 300), () {
      setTranslationMode(Prefs().getBookTranslationMode(widget.book.id));
    });
  }

  void removeOverlay() {
    _selectionClearLocked = false;
    _selectionClearPending = false;
    if (contextMenuEntry == null || contextMenuEntry?.mounted == false) return;
    contextMenuEntry?.remove();
    contextMenuEntry = null;
  }

  Future<void> _handlePointerEvents(PointerEvent event) async {
    if (await isFootNoteOpen() || Prefs().pageTurnStyle == PageTurn.scroll) {
      return;
    }
    if (event is PointerScrollEvent) {
      if (event.scrollDelta.dy > 0) {
        nextPage();
      } else {
        prevPage();
      }
    }
  }

  @override
  void initState() {
    book = widget.book;
    getThemeColor();

    contextMenu = ContextMenu(
      settings: ContextMenuSettings(hideDefaultSystemContextMenuItems: true),
      onCreateContextMenu: (hitTestResult) async {
        // webViewController.evaluateJavascript(source: "showContextMenu()");
      },
      onHideContextMenu: () {
        // removeOverlay();
      },
    );
    if (Prefs().openBookAnimation) {
      _animationController = AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      );
      _animation =
          Tween<double>(begin: 1.0, end: 0.0).animate(_animationController!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _animationController!.forward();
      });
    }
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> saveReadingProgress() async {
    if (cfi == '' || widget.cfi != null) return;
    Book book = widget.book;
    book.lastReadPosition = cfi;
    book.readingPercentage = percentage;
    await bookDao.updateBook(book);
    if (mounted) {
      ref.read(bookListProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    _translateHud.dispose();
    _animationController?.dispose();
    saveReadingProgress();
    removeOverlay();
    super.dispose();
  }

  InAppWebViewSettings initialSettings = InAppWebViewSettings(
    supportZoom: false,
    transparentBackground: true,
    isInspectable: kDebugMode,
    useHybridComposition: true,
  );

  bool get isDarkMode =>
      Theme.of(navigatorKey.currentContext!).brightness == Brightness.dark;

  void changeReadingInfo() {
    setState(() {});
  }

  Widget _buildHistoryCapsule() {
    final l10n = L10n.of(context);
    final buttonColor = Color(int.parse('0x$textColor')).withAlpha(200);

    // Common button style for all history navigation buttons
    final buttonStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
      ),
    );

    // Helper method to create history navigation buttons
    Widget createHistoryButton(
        IconData icon, String label, VoidCallback onPressed) {
      return TextButton.icon(
        icon: Icon(icon, size: 18, color: buttonColor),
        label: Text(label, style: TextStyle(color: buttonColor, fontSize: 14)),
        onPressed: onPressed,
        style: buttonStyle,
      );
    }

    // Build buttons list
    final List<Widget> buttons = [];

    if (canGoBack) {
      buttons.add(createHistoryButton(
        Icons.arrow_back,
        l10n.historyBack,
        backHistory,
      ));
    }

    buttons.add(createHistoryButton(
      Icons.close,
      l10n.historyClose,
      () => setState(() => showHistory = false),
    ));

    if (canGoForward) {
      buttons.add(createHistoryButton(
        Icons.arrow_forward,
        l10n.historyForward,
        forwardHistory,
      ));
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainer
                    .withAlpha(123),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: buttons,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget readingInfoWidget() {
    if (chapterCurrentPage == 0 && percentage == 0.0) {
      return const SizedBox();
    }

    TextStyle textStyle = TextStyle(
      color: Color(int.parse('0x$textColor')).withAlpha(150),
      fontSize: 10,
    );

    Widget chapterTitleWidget = Text(
      (chapterCurrentPage == 1 ? widget.book.title : chapterTitle),
      style: textStyle,
    );

    Widget chapterProgressWidget = Text(
      '$chapterCurrentPage/$chapterTotalPages',
      style: textStyle,
    );

    Widget bookProgressWidget =
        Text('${(percentage * 100).toStringAsFixed(2)}%', style: textStyle);

    Widget timeWidget = MinuteClock(textStyle: textStyle);

    Widget batteryWidget = FutureBuilder(
        future: Battery().batteryLevel,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0.8, 2, 0),
                  child: Text('${snapshot.data}',
                      style: TextStyle(
                        color: Color(int.parse('0x$textColor')),
                        fontSize: 9,
                      )),
                ),
                Icon(
                  HeroIcons.battery_0,
                  size: 27,
                  color: Color(int.parse('0x$textColor')),
                ),
              ],
            );
          } else {
            return const SizedBox();
          }
        });

    Widget batteryAndTimeWidget() => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            batteryWidget,
            const SizedBox(width: 5),
            timeWidget,
          ],
        );

    Widget getWidget(ReadingInfoEnum readingInfoEnum) {
      switch (readingInfoEnum) {
        case ReadingInfoEnum.chapterTitle:
          return chapterTitleWidget;
        case ReadingInfoEnum.chapterProgress:
          return chapterProgressWidget;
        case ReadingInfoEnum.bookProgress:
          return bookProgressWidget;
        case ReadingInfoEnum.battery:
          return batteryWidget;
        case ReadingInfoEnum.time:
          return timeWidget;
        case ReadingInfoEnum.batteryAndTime:
          return batteryAndTimeWidget();
        case ReadingInfoEnum.none:
          return const SizedBox(width: 30);
      }
    }

    List<Widget> headerWidgets = [
      getWidget(Prefs().readingInfo.headerLeft),
      getWidget(Prefs().readingInfo.headerCenter),
      getWidget(Prefs().readingInfo.headerRight),
    ];

    List<Widget> footerWidgets = [
      getWidget(Prefs().readingInfo.footerLeft),
      getWidget(Prefs().readingInfo.footerCenter),
      getWidget(Prefs().readingInfo.footerRight),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: Prefs().pageHeaderMargin),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: headerWidgets,
            ),
          ),
          const Spacer(),
          Padding(
            padding: EdgeInsets.only(bottom: Prefs().pageFooterMargin),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: footerWidgets,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildWebviewWithIOSWorkaround(
      BuildContext context, String url, String initialCfi) {
    final webView = InAppWebView(
      webViewEnvironment: webViewEnvironment,
      initialUrlRequest: URLRequest(
        url: WebUri(
          generateUrl(
            url,
            initialCfi,
            backgroundColor: backgroundColor,
            textColor: textColor,
            isDarkMode: Theme.of(context).brightness == Brightness.dark,
          ),
        ),
      ),
      initialSettings: initialSettings,
      contextMenu: contextMenu,
      onLoadStop: (controller, uri) => onWebViewCreated(controller),
      onConsoleMessage: webviewConsoleMessage,
    );

    if (!AnxPlatform.isIOS) {
      return SizedBox.expand(child: webView);
    }

    return SizedBox.expand(
      child: Stack(
        children: [
          webView,
          Positioned.fill(
            child: PointerInterceptor(
              intercepting: !_isTopOfNavigationStack,
              debug: false,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  bool _looksLikeTranslateFailure(String s) {
    final t = s.trim();
    if (t.isEmpty) return true;

    final lower = t.toLowerCase();
    if (lower.startsWith('error:')) return true;
    if (lower.contains('translate error') || lower.contains('翻译错误')) return true;
    if (lower.contains('authentication failed')) return true;
    if (lower.contains('rate limit') || lower.contains('429')) return true;
    if (lower.contains('ai service not configured')) return true;

    return false;
  }

  void _resetTranslateHud() {
    _translateHudItems.clear();
    _translateHud.value = const _InlineTranslateHudState();
    InlineFullTextTranslationStatusBus.instance.reset();
  }

  void _hudMarkStart({required String cacheKey}) {
    final item = _translateHudItems[cacheKey];
    if (item == null) {
      _translateHudItems[cacheKey] = _InlineTranslateHudEntry.inflight;
    } else {
      // If already inflight/done/failed, do not double-count inflight.
      if (item.status == _InlineTranslateHudItemStatus.inflight) return;
      if (item.status == _InlineTranslateHudItemStatus.done) return;
      // failed -> retry: move to inflight
      _translateHudItems[cacheKey] = _InlineTranslateHudEntry.inflight;
    }
    _recomputeHud();
  }

  void _hudMarkDone({required String cacheKey}) {
    final item = _translateHudItems[cacheKey];
    if (item == null) return;
    _translateHudItems[cacheKey] = _InlineTranslateHudEntry.done;
    _recomputeHud();
  }

  void _hudMarkFail({
    required String cacheKey,
    InlineFullTextTranslateFailureReason reason =
        InlineFullTextTranslateFailureReason.unknown,
  }) {
    final item = _translateHudItems[cacheKey];
    if (item == null) return;
    _translateHudItems[cacheKey] = _InlineTranslateHudEntry.failed(reason);
    _recomputeHud();
  }

  void _hudMarkFinishInflight({required String cacheKey}) {
    final item = _translateHudItems[cacheKey];
    if (item?.status == _InlineTranslateHudItemStatus.inflight) {
      // If we end inflight without marking done/fail, treat as failed.
      _translateHudItems[cacheKey] = _InlineTranslateHudEntry.failed(
        InlineFullTextTranslateFailureReason.unknown,
      );
      _recomputeHud();
    }
  }

  void _recomputeHud() {
    var inflight = 0;
    var done = 0;
    var failed = 0;

    final reasonCounts = <InlineFullTextTranslateFailureReason, int>{};

    for (final v in _translateHudItems.values) {
      switch (v.status) {
        case _InlineTranslateHudItemStatus.inflight:
          inflight++;
          break;
        case _InlineTranslateHudItemStatus.done:
          done++;
          break;
        case _InlineTranslateHudItemStatus.failed:
          failed++;
          final reason =
              v.failureReason ?? InlineFullTextTranslateFailureReason.unknown;
          reasonCounts[reason] = (reasonCounts[reason] ?? 0) + 1;
          break;
      }
    }

    final updatedAtMs = DateTime.now().millisecondsSinceEpoch;

    _translateHud.value = _InlineTranslateHudState(
      total: _translateHudItems.length,
      inflight: inflight,
      done: done,
      failed: failed,
      updatedAtMs: updatedAtMs,
    );

    InlineFullTextTranslationStatusBus.instance.update(
      total: _translateHudItems.length,
      inflight: inflight,
      done: done,
      failed: failed,
      failureReasons: reasonCounts,
    );
  }

  Widget _inlineTranslateHud() {
    if (!_translateHudVisible) return const SizedBox.shrink();

    // Do not show translation HUD in scroll mode (user preference).
    if (Prefs().pageTurnStyle == PageTurn.scroll) {
      return const SizedBox.shrink();
    }

    final mode = Prefs().getBookTranslationMode(widget.book.id);
    if (mode == TranslationModeEnum.off) return const SizedBox.shrink();

    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      right: 8,
      child: ValueListenableBuilder<_InlineTranslateHudState>(
        valueListenable: _translateHud,
        builder: (context, s, _) {
          final shouldShow = s.total > 0 || s.inflight > 0;
          if (!shouldShow) return const SizedBox.shrink();

          final text = '译 ${s.done}/${s.total}'
              '${s.inflight > 0 ? ' · ${s.inflight}中' : ''}'
              '${s.failed > 0 ? ' · 失败${s.failed}' : ''}';

          return Material(
            color: Theme.of(context).colorScheme.surface.withAlpha(230),
            elevation: 3,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (s.inflight > 0)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (s.inflight > 0) const SizedBox(width: 8),
                  Text(text, style: Theme.of(context).textTheme.bodySmall),
                  if (s.failed > 0 || s.inflight == 0) ...[
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () async {
                        // Manual retry: reset counters to avoid stacking, then
                        // force re-translate current + next viewport.
                        resetInlineTranslateHudStats();

                        ({int started, int candidates})? parseStats(dynamic v) {
                          try {
                            if (v is Map) {
                              final started = (v['started'] as num?)?.toInt();
                              final candidates =
                                  (v['candidates'] as num?)?.toInt();
                              if (started != null && candidates != null) {
                                return (started: started, candidates: candidates);
                              }
                            }
                          } catch (_) {}
                          return null;
                        }

                        try {
                          final result = await webViewController
                              .callAsyncJavaScript(functionBody: '''
if (typeof reader !== 'undefined' && reader.view && reader.view.forceTranslateForViewport) {
  return await reader.view.forceTranslateForViewport(true);
}
return null;
''');

                          final stats = parseStats(result?.value);
                          if (stats != null) {
                            InlineFullTextTranslationStatusBus.instance
                                .reportManualRetry(
                              started: stats.started,
                              candidates: stats.candidates,
                            );
                          }
                        } catch (_) {}
                      },
                      child: const Icon(Icons.refresh, size: 16),
                    ),
                  ],
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _translateHudVisible = false;
                      });
                    },
                    child: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void showInlineTranslateHud() {
    // Scroll mode explicitly hides the HUD.
    if (Prefs().pageTurnStyle == PageTurn.scroll) return;

    if (!_translateHudVisible) {
      setState(() {
        _translateHudVisible = true;
      });
    }
  }

  /// Reset HUD counters (used by manual retry).
  void resetInlineTranslateHudStats() {
    _resetTranslateHud();
    if (Prefs().pageTurnStyle != PageTurn.scroll) {
      _translateHudVisible = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    String uri = Uri.encodeComponent(widget.book.fileFullPath);
    String url = 'http://127.0.0.1:${Server().port}/book/$uri';
    String initialCfi = widget.cfi ?? widget.book.lastReadPosition;

    return Listener(
      onPointerSignal: (event) {
        _handlePointerEvents(event);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            buildWebviewWithIOSWorkaround(context, url, initialCfi),
            readingInfoWidget(),
            if (showHistory) _buildHistoryCapsule(),
            _inlineTranslateHud(),
            if (Prefs().openBookAnimation)
              SizedBox.expand(
                  child: IgnorePointer(
                ignoring: true,
                child: FadeTransition(
                    opacity: _animation!, child: BookCover(book: widget.book)),
              )),
          ],
        ),
      ),
    );
  }
}

enum _InlineTranslateHudItemStatus {
  inflight,
  done,
  failed,
}

class _InlineTranslateHudEntry {
  const _InlineTranslateHudEntry({
    required this.status,
    this.failureReason,
  });

  final _InlineTranslateHudItemStatus status;
  final InlineFullTextTranslateFailureReason? failureReason;

  static const inflight = _InlineTranslateHudEntry(
    status: _InlineTranslateHudItemStatus.inflight,
  );
  static const done = _InlineTranslateHudEntry(
    status: _InlineTranslateHudItemStatus.done,
  );

  static _InlineTranslateHudEntry failed(
    InlineFullTextTranslateFailureReason reason,
  ) {
    return _InlineTranslateHudEntry(
      status: _InlineTranslateHudItemStatus.failed,
      failureReason: reason,
    );
  }
}

class _InlineTranslateHudState {
  const _InlineTranslateHudState({
    this.total = 0,
    this.inflight = 0,
    this.done = 0,
    this.failed = 0,
    this.updatedAtMs = 0,
  });

  final int total;
  final int inflight;
  final int done;
  final int failed;
  final int updatedAtMs;

  _InlineTranslateHudState copyWith({
    int? total,
    int? inflight,
    int? done,
    int? failed,
    int? updatedAtMs,
  }) {
    return _InlineTranslateHudState(
      total: total ?? this.total,
      inflight: inflight ?? this.inflight,
      done: done ?? this.done,
      failed: failed ?? this.failed,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}
