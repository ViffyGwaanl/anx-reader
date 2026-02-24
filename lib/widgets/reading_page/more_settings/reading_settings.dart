import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/convert_chinese_mode.dart';
import 'package:anx_reader/enums/reading_info.dart';
import 'package:anx_reader/enums/translation_mode.dart';
import 'package:anx_reader/enums/writing_mode.dart';
import 'package:anx_reader/enums/code_highlight_theme.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/page/settings_page/subpage/fonts.dart';
import 'package:anx_reader/service/translate/fulltext_translate_runtime.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/enums/inline_fulltext_translate_failure_reason.dart';
import 'package:anx_reader/models/inline_fulltext_translation_progress.dart';
import 'package:anx_reader/service/translate/inline_fulltext_translation_status.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';

class ReadingMoreSettings extends StatefulWidget {
  const ReadingMoreSettings({super.key});

  @override
  State<ReadingMoreSettings> createState() => _ReadingMoreSettingsState();
}

class _ReadingMoreSettingsState extends State<ReadingMoreSettings> {
  final isReading =
      epubPlayerKey.currentState != null && epubPlayerKey.currentState!.mounted;

  @override
  Widget build(BuildContext context) {
    Widget convertChinese() {
      const iconStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
      return StatefulBuilder(
        builder: (context, setState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.of(context).readingPageConvertChinese,
                  style: Theme.of(context).textTheme.titleMedium),
              Row(
                children: [
                  Expanded(
                    child: AnxSegmentedButton<ConvertChineseMode>(
                      segments: [
                        SegmentButtonItem(
                          label: L10n.of(context).readingPageOriginal,
                          value: ConvertChineseMode.none,
                          icon: const Text("原", style: iconStyle),
                        ),
                        SegmentButtonItem(
                          label: L10n.of(context).readingPageSimplified,
                          value: ConvertChineseMode.t2s,
                          icon: const Text("简", style: iconStyle),
                        ),
                        SegmentButtonItem(
                          label: L10n.of(context).readingPageTraditional,
                          value: ConvertChineseMode.s2t,
                          icon: const Text("繁", style: iconStyle),
                        ),
                      ],
                      selected: {Prefs().readingRules.convertChineseMode},
                      onSelectionChanged: (value) {
                        setState(() {
                          // Prefs().readingRules.convertChineseMode =
                          //     ConvertChineseMode.values.byName(value.first);
                          Prefs().readingRules = Prefs()
                              .readingRules
                              .copyWith(convertChineseMode: value.first);
                          epubPlayerKey.currentState
                              ?.changeReadingRules(Prefs().readingRules);
                        });
                      },
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.error_outline),
                  Expanded(
                    child: Text(
                      L10n.of(context).readingPageConvertChineseTips,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
    }

    // Widget bionicReading() {
    //   return StatefulBuilder(
    //     builder: (context, setState) => ListTile(
    //       contentPadding: EdgeInsets.zero,
    //       title: Text(L10n.of(context).readingPageBionicReading,
    //           style: Theme.of(context).textTheme.titleMedium),
    //       subtitle: GestureDetector(
    //         child: Text(
    //           textAlign: TextAlign.start,
    //           L10n.of(context).readingPageBionicReadingTips,
    //           style: const TextStyle(
    //             fontSize: 12,
    //             color: Color(0xFF666666),
    //             decoration: TextDecoration.underline,
    //           ),
    //         ),
    //         onTap: () {
    //           launchUrl(
    //             Uri.parse('https://github.com/Anxcye/anx-reader/issues/49'),
    //             mode: LaunchMode.externalApplication,
    //           );
    //         },
    //       ),
    //       trailing: Switch(
    //         value: Prefs().readingRules.bionicReading,
    //         onChanged: (value) {
    //           setState(() {
    //             Prefs().readingRules =
    //                 Prefs().readingRules.copyWith(bionicReading: value);
    //             epubPlayerKey.currentState?
    //                 .changeReadingRules(Prefs().readingRules);
    //           });
    //         },
    //       ),
    //     ),
    //   );
    // }

    Widget columnCount() {
      return StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.of(context).readingPageColumnCount,
                style: Theme.of(context).textTheme.titleMedium),
            Row(
              children: [
                Expanded(
                  child: AnxSegmentedButton<int>(
                    segments: [
                      SegmentButtonItem(
                        label: L10n.of(context).readingPageAuto,
                        value: 0,
                        icon: const Icon(Icons.auto_awesome),
                      ),
                      SegmentButtonItem(
                        label: L10n.of(context).readingPageSingle,
                        value: 1,
                        icon: const Icon(EvaIcons.book),
                      ),
                      SegmentButtonItem(
                        label: L10n.of(context).readingPageDouble,
                        value: 2,
                        icon: const Icon(EvaIcons.book_open),
                      ),
                    ],
                    selected: {Prefs().bookStyle.maxColumnCount},
                    onSelectionChanged: (value) {
                      setState(() {
                        final newBookStyle = Prefs()
                            .bookStyle
                            .copyWith(maxColumnCount: value.first);
                        Prefs().saveBookStyleToPrefs(newBookStyle);
                        epubPlayerKey.currentState?.changeStyle(newBookStyle);
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    Widget columnThreshold() {
      return StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(L10n.of(context).readingPageColumnThreshold,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 8),
                Text(
                  '${Prefs().bookStyle.columnThreshold.toInt()}px',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (Prefs().bookStyle.maxColumnCount == 0)
              Text(
                L10n.of(context).readingPageColumnThresholdTip,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            Slider(
              value: Prefs().bookStyle.columnThreshold,
              min: 400,
              max: 1200,
              divisions: 40,
              label: '${Prefs().bookStyle.columnThreshold.toInt()}px',
              onChanged: Prefs().bookStyle.maxColumnCount == 0
                  ? (value) {
                      setState(() {
                        final newBookStyle =
                            Prefs().bookStyle.copyWith(columnThreshold: value);
                        Prefs().saveBookStyleToPrefs(newBookStyle);
                        epubPlayerKey.currentState?.changeStyle(newBookStyle);
                      });
                    }
                  : null,
            ),
          ],
        ),
      );
    }

    Widget writingMode() {
      return StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.of(context).readingPageWritingDirection,
                style: Theme.of(context).textTheme.titleMedium),
            Row(
              children: [
                Expanded(
                  child: AnxSegmentedButton<WritingModeEnum>(
                    segments: [
                      SegmentButtonItem(
                        label: L10n.of(context).readingPageWritingDirectionAuto,
                        value: WritingModeEnum.auto,
                        icon: const Icon(EvaIcons.activity_outline),
                      ),
                      SegmentButtonItem(
                        label: L10n.of(context)
                            .readingPageWritingDirectionVertical,
                        value: WritingModeEnum.verticalRl,
                        icon: const Icon(Bootstrap.arrows_vertical),
                      ),
                      SegmentButtonItem(
                        label: L10n.of(context)
                            .readingPageWritingDirectionHorizontal,
                        value: WritingModeEnum.horizontalTb,
                        icon: const Icon(Bootstrap.arrows),
                      ),
                    ],
                    selected: {Prefs().writingMode},
                    onSelectionChanged: (value) {
                      setState(() {
                        final newBookStyle =
                            Prefs().bookStyle.copyWith(maxColumnCount: 1);
                        Prefs().saveBookStyleToPrefs(newBookStyle);
                        Prefs().writingMode = value.first;
                        epubPlayerKey.currentState?.changeStyle(newBookStyle);
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    Widget translationMode() {
      return StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.of(context).translationMode,
                style: Theme.of(context).textTheme.titleMedium),
            if (!isReading)
              Text(L10n.of(context).readingPageTranslationModeTip,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey)),
            Row(
              children: [
                Expanded(
                  child: AnxSegmentedButton<TranslationModeEnum>(
                    enabled: isReading,
                    segments: [
                      SegmentButtonItem(
                        label: L10n.of(context).readingPageOriginal,
                        value: TranslationModeEnum.off,
                        icon: const Icon(Icons.translate_outlined),
                      ),
                      SegmentButtonItem(
                        label: L10n.of(context).translationOnly,
                        value: TranslationModeEnum.translationOnly,
                        icon: const Icon(Icons.g_translate),
                      ),
                      SegmentButtonItem(
                        label: L10n.of(context).bilingual,
                        value: TranslationModeEnum.bilingual,
                        icon: const Icon(Icons.compare),
                      ),
                    ],
                    selected: {
                      epubPlayerKey.currentState != null
                          ? Prefs().getBookTranslationMode(
                              epubPlayerKey.currentState!.widget.book.id)
                          : TranslationModeEnum.off
                    },
                    onSelectionChanged: (value) {
                      setState(() {
                        final currentBookId =
                            epubPlayerKey.currentState!.widget.book.id;
                        final newMode = value.first;

                        Prefs().setBookTranslationMode(currentBookId, newMode);

                        epubPlayerKey.currentState?.setTranslationMode(newMode);
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: isReading
                    ? () async {
                        final currentBookId =
                            epubPlayerKey.currentState!.widget.book.id;
                        await FullTextTranslateRuntime.instance
                            .clearBook(currentBookId);

                        // Also clear current DOM overlays so user sees immediate effect.
                        await epubPlayerKey.currentState?.webViewController
                            .evaluateJavascript(source: '''
if (typeof reader !== 'undefined' && reader.view && reader.view.clearTranslations) {
  reader.view.clearTranslations();
}
''');

                        AnxToast.show(
                          L10n.of(context)
                              .readingPageFullTextTranslationCacheCleared,
                        );
                      }
                    : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(
                  L10n.of(context).readingPageClearFullTextTranslationCache,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: isReading
                    ? () async {
                        // Reset counters to avoid stacking on repeated retries.
                        epubPlayerKey.currentState?.resetInlineTranslateHudStats();

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

                        // Retry current viewport translations.
                        try {
                          final result = await epubPlayerKey
                              .currentState?.webViewController
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

                            AnxToast.show(
                              L10n.of(context).readingPageTranslateRetryTriggered(
                                stats.started,
                                stats.candidates,
                              ),
                            );
                          }
                        } catch (_) {}

                        // Show HUD when not in scroll mode.
                        epubPlayerKey.currentState?.showInlineTranslateHud();
                      }
                    : null,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(L10n.of(context).readingPageRetryTranslation),
              ),
            ),

            // Live background status (reading-page only)
            if (isReading)
              ValueListenableBuilder<InlineFullTextTranslationProgress>(
                valueListenable:
                    InlineFullTextTranslationStatusBus.instance.progress,
                builder: (context, p, _) {
                  final status = p.active
                      ? L10n.of(context).settingsTranslateBackgroundStatusActive(
                          p.done,
                          p.total,
                          p.inflight,
                          p.pending,
                          p.failed,
                        )
                      : L10n.of(context).settingsTranslateBackgroundStatusIdle;

                  return ValueListenableBuilder<
                      Map<InlineFullTextTranslateFailureReason, int>>(
                    valueListenable:
                        InlineFullTextTranslationStatusBus.instance.failureReasons,
                    builder: (context, reasons, _) {
                      String? reasonText;
                      if (p.failed > 0 && reasons.isNotEmpty) {
                        final sorted = reasons.entries.toList(growable: false)
                          ..sort((a, b) => b.value.compareTo(a.value));

                        final top = sorted.take(3).map((e) {
                          final label = switch (e.key) {
                            InlineFullTextTranslateFailureReason.rateLimit =>
                              L10n.of(context)
                                  .readingPageTranslateFailureReasonRateLimit,
                            InlineFullTextTranslateFailureReason.auth =>
                              L10n.of(context)
                                  .readingPageTranslateFailureReasonAuth,
                            InlineFullTextTranslateFailureReason.notConfigured =>
                              L10n.of(context)
                                  .readingPageTranslateFailureReasonNotConfigured,
                            InlineFullTextTranslateFailureReason.untranslatedEcho =>
                              L10n.of(context)
                                  .readingPageTranslateFailureReasonUntranslated,
                            InlineFullTextTranslateFailureReason.translateError =>
                              L10n.of(context)
                                  .readingPageTranslateFailureReasonTranslateError,
                            InlineFullTextTranslateFailureReason.exception =>
                              L10n.of(context)
                                  .readingPageTranslateFailureReasonException,
                            InlineFullTextTranslateFailureReason.unknown =>
                              L10n.of(context)
                                  .readingPageTranslateFailureReasonUnknown,
                          };
                          return '$label×${e.value}';
                        }).join(' · ');

                        reasonText =
                            '${L10n.of(context).readingPageTranslateFailureReasons}: $top';
                      }

                      String? retryText;
                      final started = p.lastRetryStarted;
                      final candidates = p.lastRetryCandidates;
                      if (started != null && candidates != null) {
                        retryText =
                            L10n.of(context).readingPageTranslateLastRetryStats(
                          started,
                          candidates,
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${L10n.of(context).settingsTranslateBackgroundStatus}: $status',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.grey),
                            ),
                            if (reasonText != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  reasonText,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey),
                                ),
                              ),
                            if (retryText != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  retryText,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: isReading
                    ? () async {

                  final current = Prefs().inlineFullTextTranslateConcurrency;
                  final selected = await showModalBottomSheet<int>(
                    context: context,
                    builder: (context) {
                      return SafeArea(
                        child: ListView(
                          children: [
                            for (var i = 1; i <= 8; i++)
                              ListTile(
                                title: Text(
                                  L10n.of(context)
                                      .readingPageTranslateConcurrencyValue(i),
                                ),
                                trailing:
                                    i == current ? const Icon(Icons.check) : null,
                                onTap: () => Navigator.pop(context, i),
                              ),
                          ],
                        ),
                      );
                    },
                  );

                  if (selected != null) {
                    Prefs().inlineFullTextTranslateConcurrency = selected;
                    setState(() {});
                  }
                }
                    : null,
                icon: const Icon(Icons.speed, size: 18),
                label: Text(
                  L10n.of(context).readingPageTranslateConcurrencyValue(
                        Prefs().inlineFullTextTranslateConcurrency,
                      ),
                ),
              ),
            ),
            if (Prefs().pageTurnStyle != PageTurn.scroll)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: isReading
                      ? () {
                          epubPlayerKey.currentState?.showInlineTranslateHud();
                        }
                      : null,
                  icon: const Icon(Icons.visibility, size: 18),
                  label: Text(
                    L10n.of(context).readingPageShowTranslateHud,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    Widget buildInfoDropdown(
      BuildContext context,
      String label,
      ReadingInfoEnum currentValue,
      Function(ReadingInfoEnum) onChanged,
    ) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          DropdownButton<ReadingInfoEnum>(
            isDense: true,
            isExpanded: true,
            value: currentValue,
            onChanged: (value) {
              if (value != null) {
                onChanged(value);
              }
            },
            underline: Container(),
            dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            items: ReadingInfoEnum.values.map((info) {
              return DropdownMenuItem<ReadingInfoEnum>(
                value: info,
                child: Text(
                  info.getL10n(context),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
          ),
        ],
      );
    }

    Widget readingInfo() {
      return StatefulBuilder(
        builder: (context, setState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.of(context).readingPageHeaderSettings,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: buildInfoDropdown(
                      context,
                      L10n.of(context).readingPageLeft,
                      Prefs().readingInfo.headerLeft,
                      (value) {
                        setState(() {
                          final newRules = Prefs().readingInfo.copyWith(
                                headerLeft: value,
                              );
                          Prefs().readingInfo = newRules;
                          epubPlayerKey.currentState?.changeReadingInfo();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: buildInfoDropdown(
                      context,
                      L10n.of(context).readingPageCenter,
                      Prefs().readingInfo.headerCenter,
                      (value) {
                        setState(() {
                          final newRules = Prefs().readingInfo.copyWith(
                                headerCenter: value,
                              );
                          Prefs().readingInfo = newRules;
                          // epubPlayerKey.currentState
                          //     ?.changeReadingInfo(newRules);
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: buildInfoDropdown(
                      context,
                      L10n.of(context).readingPageRight,
                      Prefs().readingInfo.headerRight,
                      (value) {
                        setState(() {
                          final newRules = Prefs().readingInfo.copyWith(
                                headerRight: value,
                              );
                          Prefs().readingInfo = newRules;
                          epubPlayerKey.currentState?.changeReadingInfo();
                        });
                      },
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(L10n.of(context).readingSettingsMargin),
                  Expanded(
                    child: Slider(
                      value: Prefs().pageHeaderMargin.toDouble(),
                      min: 0,
                      max: 80,
                      divisions: 40,
                      label: Prefs().pageHeaderMargin.toStringAsFixed(0),
                      onChanged: (value) {
                        setState(() {
                          Prefs().pageHeaderMargin = value;
                          epubPlayerKey.currentState?.changeReadingInfo();
                        });
                      },
                    ),
                  ),
                ],
              ),
              const Divider(),
              Text(L10n.of(context).readingPageFooterSettings,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: buildInfoDropdown(
                      context,
                      L10n.of(context).readingPageLeft,
                      Prefs().readingInfo.footerLeft,
                      (value) {
                        setState(() {
                          final newRules = Prefs().readingInfo.copyWith(
                                footerLeft: value,
                              );
                          Prefs().readingInfo = newRules;
                          epubPlayerKey.currentState?.changeReadingInfo();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: buildInfoDropdown(
                      context,
                      L10n.of(context).readingPageCenter,
                      Prefs().readingInfo.footerCenter,
                      (value) {
                        setState(() {
                          final newRules = Prefs().readingInfo.copyWith(
                                footerCenter: value,
                              );
                          Prefs().readingInfo = newRules;
                          epubPlayerKey.currentState?.changeReadingInfo();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: buildInfoDropdown(
                      context,
                      L10n.of(context).readingPageRight,
                      Prefs().readingInfo.footerRight,
                      (value) {
                        setState(() {
                          final newRules = Prefs().readingInfo.copyWith(
                                footerRight: value,
                              );
                          Prefs().readingInfo = newRules;
                          epubPlayerKey.currentState?.changeReadingInfo();
                        });
                      },
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(L10n.of(context).readingSettingsMargin),
                  Expanded(
                    child: Slider(
                      value: Prefs().pageFooterMargin.toDouble(),
                      min: 0,
                      max: 80,
                      divisions: 40,
                      label: Prefs().pageFooterMargin.toStringAsFixed(0),
                      onChanged: (value) {
                        setState(() {
                          // final newRules = Prefs().readingInfo.copyWith(
                          //       headerFontSize: value.toInt(),
                          //     );
                          // Prefs().readingInfo = newRules;
                          // epubPlayerKey.currentState?.changeReadingInfo();
                          Prefs().pageFooterMargin = value;
                          epubPlayerKey.currentState?.changeReadingInfo();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
    }

    Widget downloadFonts() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.of(context).downloadFonts),
        leading: const Icon(Icons.font_download_outlined),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const FontsSettingPage(),
            ),
          );
        },
      );
    }

    Widget codeHighlightTheme() {
      return StatefulBuilder(
        builder: (context, setState) {
          final lightThemes = [
            CodeHighlightThemeEnum.defaultTheme,
            CodeHighlightThemeEnum.github,
            CodeHighlightThemeEnum.oneLight,
            CodeHighlightThemeEnum.materialLight,
          ];

          final darkThemes = [
            CodeHighlightThemeEnum.vsDark,
            CodeHighlightThemeEnum.oneDark,
            CodeHighlightThemeEnum.dracula,
            CodeHighlightThemeEnum.materialDark,
            CodeHighlightThemeEnum.nord,
            CodeHighlightThemeEnum.nightOwl,
            CodeHighlightThemeEnum.solarizedDark,
            CodeHighlightThemeEnum.atomDark,
          ];

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.of(context).codeHighlightTheme,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              // Quick toggle: Off / Light / Dark
              Row(
                children: [
                  Expanded(
                    child: AnxSegmentedButton<String>(
                      segments: [
                        SegmentButtonItem(
                          label: L10n.of(context).codeHighlightOff,
                          value: 'off',
                          icon: const Icon(Icons.code_off),
                        ),
                        SegmentButtonItem(
                          label: L10n.of(context).codeHighlightLight,
                          value: 'light',
                          icon: const Icon(Icons.light_mode),
                        ),
                        SegmentButtonItem(
                          label: L10n.of(context).codeHighlightDark,
                          value: 'dark',
                          icon: const Icon(Icons.dark_mode),
                        ),
                      ],
                      selected: {
                        Prefs().codeHighlightTheme == CodeHighlightThemeEnum.off
                            ? 'off'
                            : Prefs().codeHighlightTheme.isLight
                                ? 'light'
                                : 'dark'
                      },
                      onSelectionChanged: (value) {
                        setState(() {
                          if (value.first == 'off') {
                            Prefs().codeHighlightTheme =
                                CodeHighlightThemeEnum.off;
                          } else if (value.first == 'light') {
                            Prefs().codeHighlightTheme =
                                CodeHighlightThemeEnum.defaultTheme;
                          } else {
                            Prefs().codeHighlightTheme =
                                CodeHighlightThemeEnum.vsDark;
                          }
                          epubPlayerKey.currentState?.changeStyle(null);
                        });
                      },
                    ),
                  ),
                ],
              ),
              // Detailed theme selection (only show if not off)
              if (Prefs().codeHighlightTheme != CodeHighlightThemeEnum.off) ...[
                const SizedBox(height: 16),
                // Light themes section
                if (Prefs().codeHighlightTheme.isLight) ...[
                  Text(L10n.of(context).codeHighlightLightThemes,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: lightThemes.map((theme) {
                      final isSelected = Prefs().codeHighlightTheme == theme;
                      return ChoiceChip(
                        label: Text(theme.displayName),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              Prefs().codeHighlightTheme = theme;
                              epubPlayerKey.currentState?.changeStyle(null);
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
                // Dark themes section
                if (Prefs().codeHighlightTheme.isDark) ...[
                  Text(L10n.of(context).codeHighlightDarkThemes,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: darkThemes.map((theme) {
                      final isSelected = Prefs().codeHighlightTheme == theme;
                      return ChoiceChip(
                        label: Text(theme.displayName),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              Prefs().codeHighlightTheme = theme;
                              epubPlayerKey.currentState?.changeStyle(null);
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ],
          );
        },
      );
    }

    return Container(
      padding: const EdgeInsets.all(18.0),
      child: Column(
        children: [
          downloadFonts(),
          const Divider(height: 20),
          writingMode(),
          translationMode(),
          columnCount(),
          columnThreshold(),
          convertChinese(),
          const Divider(height: 15),
          codeHighlightTheme(),
          const Divider(height: 15),
          readingInfo(),
          // const Divider(height: 8),
          // bionicReading(),
        ],
      ),
    );
  }
}
