import 'dart:convert';
import 'dart:core';

import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/enums/bgimg_alignment.dart';
import 'package:anx_reader/enums/bgimg_type.dart';
import 'package:anx_reader/enums/bookshelf_folder_style.dart';
import 'package:anx_reader/enums/convert_chinese_mode.dart';
import 'package:anx_reader/enums/excerpt_share_template.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/enums/sort_field.dart';
import 'package:anx_reader/enums/sort_order.dart';
import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:anx_reader/enums/translation_mode.dart';
import 'package:anx_reader/enums/writing_mode.dart';
import 'package:anx_reader/enums/text_alignment.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/enums/ai_dock_side.dart';
import 'package:anx_reader/enums/ai_pad_panel_mode.dart';
import 'package:anx_reader/enums/code_highlight_theme.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/bgimg.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/models/ai_input_quick_prompt.dart';
import 'package:anx_reader/models/chapter_split_presets.dart';
import 'package:anx_reader/models/chapter_split_rule.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/models/book_notes_state.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/models/reading_info.dart';
import 'package:anx_reader/models/reading_rules.dart';
import 'package:anx_reader/models/user_prompt.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:anx_reader/models/window_info.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/utils/get_current_language_code.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String prefsBackupVersionKey = '__prefsBackupVersion';
const int prefsBackupSchemaVersion = 1;
const String _prefsBackupEntryTypeKey = 'type';
const String _prefsBackupEntryValueKey = 'value';

const Set<String> _prefsImportSkipKeys = {
  'iapPurchaseStatus',
  'iapLastCheckTime',
};

class Prefs extends ChangeNotifier {
  late SharedPreferences prefs;
  static final Prefs _instance = Prefs._internal();

  factory Prefs() {
    return _instance;
  }

  Prefs._internal() {
    initPrefs();
  }

  static const String _chapterSplitSelectedRuleKey =
      'chapterSplitSelectedRuleId';
  static const String _chapterSplitCustomRulesKey = 'chapterSplitCustomRules';
  static const String _statisticsDashboardTilesKey = 'statisticsDashboardTiles';
  static const String _enabledAiToolsKey = 'enabledAiTools';
  static const String _userPromptsKey = 'userPrompts';

  // Home tabs config (order + enable), backed by SharedPreferences.
  // papers + settings are mandatory and cannot be disabled.
  static const int _homeTabsSchemaVersion = 1;
  static const String _homeTabsSchemaVersionKey = 'homeTabsSchemaVersion';
  static const String _homeTabsOrderKey = 'homeTabsOrder';
  static const String _homeTabsEnabledKey = 'homeTabsEnabled';

  static const String homeTabPapers = 'papers';
  static const String homeTabBookshelf = 'bookshelf';
  static const String homeTabStatistics = 'statistics';
  static const String homeTabAI = 'ai';
  static const String homeTabNotes = 'notes';
  static const String homeTabSettings = 'settings';

  static const List<String> _homeTabAll = [
    homeTabPapers,
    homeTabBookshelf,
    homeTabStatistics,
    homeTabAI,
    homeTabNotes,
    homeTabSettings,
  ];

  static const Set<String> _homeTabMandatory = {
    homeTabPapers,
    homeTabSettings,
  };

  Future<void> initPrefs() async {
    prefs = await SharedPreferences.getInstance();
    saveBeginDate();
    _migrateHomeTabsIfNeeded();
    _normalizeAndPersistHomeTabsConfig();
    notifyListeners();
  }

  Future<Map<String, dynamic>> buildPrefsBackupMap() async {
    Map<String, Object?>? encodePrefsBackupEntry(Object? value) {
      if (value is bool) {
        return <String, Object?>{
          _prefsBackupEntryTypeKey: 'bool',
          _prefsBackupEntryValueKey: value,
        };
      }
      if (value is int) {
        return <String, Object?>{
          _prefsBackupEntryTypeKey: 'int',
          _prefsBackupEntryValueKey: value,
        };
      }
      if (value is double) {
        return <String, Object?>{
          _prefsBackupEntryTypeKey: 'double',
          _prefsBackupEntryValueKey: value,
        };
      }
      if (value is String) {
        return <String, Object?>{
          _prefsBackupEntryTypeKey: 'string',
          _prefsBackupEntryValueKey: value,
        };
      }
      if (value is List) {
        final bool allStrings =
            value.every((dynamic element) => element is String);
        if (allStrings) {
          return <String, Object?>{
            _prefsBackupEntryTypeKey: 'stringList',
            _prefsBackupEntryValueKey:
                List<String>.from(value, growable: false),
          };
        }
      }
      return null;
    }

    final Map<String, dynamic> backup = <String, dynamic>{
      prefsBackupVersionKey: prefsBackupSchemaVersion,
    };
    for (final String key in prefs.getKeys()) {
      // Skip ephemeral caches.
      if (key.startsWith(_aiModelsCacheV1Prefix)) {
        continue;
      }

      Object? value = prefs.get(key);

      // Never include AI API keys in plain backups.
      if (key.startsWith('aiConfig_') && value is String) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map<String, dynamic>) {
            decoded.remove('api_key');
            value = jsonEncode(decoded);
          } else if (decoded is Map) {
            final map = decoded.cast<String, dynamic>();
            map.remove('api_key');
            value = jsonEncode(map);
          }
        } catch (_) {
          // ignore parse errors
        }
      }

      final Map<String, Object?>? encoded = encodePrefsBackupEntry(value);
      if (encoded != null) {
        backup[key] = encoded;
      }
    }
    return backup;
  }

  Future<void> applyPrefsBackupMap(Map<String, dynamic> backup) async {
    for (final MapEntry<String, dynamic> entry in backup.entries) {
      final String key = entry.key;
      if (key == prefsBackupVersionKey ||
          _prefsImportSkipKeys.contains(key) ||
          key.startsWith(_aiModelsCacheV1Prefix)) {
        continue;
      }
      final dynamic entryValue = entry.value;
      if (entryValue is! Map) continue;
      final dynamic type = entryValue[_prefsBackupEntryTypeKey];
      final dynamic value = entryValue[_prefsBackupEntryValueKey];
      if (type is! String) continue;
      switch (type) {
        case 'bool':
          if (value is bool) await prefs.setBool(key, value);
          break;
        case 'int':
          if (value is int) await prefs.setInt(key, value);
          break;
        case 'double':
          if (value is num) await prefs.setDouble(key, value.toDouble());
          break;
        case 'string':
          if (value is String) {
            // Preserve local-only secrets.
            if (key.startsWith('aiConfig_')) {
              try {
                final incoming = jsonDecode(value);
                final existingRaw = prefs.getString(key);
                final existing =
                    existingRaw == null ? null : jsonDecode(existingRaw);

                String? existingApiKey;
                if (existing is Map) {
                  existingApiKey = existing['api_key']?.toString();
                }

                if (incoming is Map) {
                  final map = incoming.cast<String, dynamic>();

                  // Never import api keys from plain backup.
                  map.remove('api_key');

                  if (existingApiKey != null && existingApiKey.isNotEmpty) {
                    map['api_key'] = existingApiKey;
                  }

                  await prefs.setString(key, jsonEncode(map));
                  break;
                }
              } catch (_) {
                // fallthrough
              }
            }

            await prefs.setString(key, value);
          }
          break;
        case 'stringList':
          if (value is List) {
            final List<String> list =
                value.map((dynamic v) => v as String).toList();
            await prefs.setStringList(key, list);
          }
          break;
        default:
          continue;
      }
    }
    notifyListeners();
  }

  Color get themeColor {
    final colorValue = prefs.getInt('themeColor') ?? Colors.blue.toARGB32();
    return Color(colorValue);
  }

  Future<void> saveThemeToPrefs(int colorValue) async {
    await prefs.setInt('themeColor', colorValue);
    notifyListeners();
  }

  Locale? get locale {
    String? localeCode = prefs.getString('locale');
    if (localeCode == null || localeCode == 'System') return null;
    if (localeCode.contains('-')) {
      List<String> codes = localeCode.split('-');
      return Locale(codes[0], codes[1]);
    }
    return Locale(localeCode);
  }

  Future<void> saveLocaleToPrefs(String localeCode) async {
    await prefs.setString('locale', localeCode);
    notifyListeners();
  }

  ThemeMode get themeMode {
    String themeMode = prefs.getString('themeMode') ?? 'system';
    switch (themeMode) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> saveThemeModeToPrefs(String themeMode) async {
    await prefs.setString('themeMode', themeMode);
    notifyListeners();
  }

  Future<void> saveBookStyleToPrefs(BookStyle bookStyle) async {
    await prefs.setString('readStyle', bookStyle.toJson());
    notifyListeners();
  }

  BookStyle get bookStyle {
    String? bookStyleJson = prefs.getString('readStyle');
    if (bookStyleJson == null) return BookStyle();
    return BookStyle.fromJson(bookStyleJson);
  }

  void removeBookStyle() {
    prefs.remove('readStyle');
    notifyListeners();
  }

  void saveReadThemeToPrefs(ReadTheme readTheme) {
    prefs.setString('readTheme', readTheme.toJson());
    notifyListeners();
  }

  ReadTheme get readTheme {
    String? readThemeJson = prefs.getString('readTheme');
    if (readThemeJson == null) {
      return ReadTheme(
          backgroundColor: 'FFFBFBF3',
          textColor: 'FF343434',
          backgroundImagePath: '');
    }
    return ReadTheme.fromJson(readThemeJson);
  }

  void saveBeginDate() {
    String? beginDate = prefs.getString('beginDate');
    if (beginDate == null) {
      prefs.setString('beginDate', DateTime.now().toIso8601String());
    }
  }

  DateTime? get beginDate {
    String? beginDateStr = prefs.getString('beginDate');
    if (beginDateStr == null) return null;
    return DateTime.parse(beginDateStr);
  }

  // void saveWebdavInfo(Map webdavInfo) {
  //   prefs.setString('webdavInfo', jsonEncode(webdavInfo));
  //   notifyListeners();
  // }

  // Map get webdavInfo {
  //   String? webdavInfoJson = prefs.getString('webdavInfo');
  //   if (webdavInfoJson == null) {
  //     return {};
  //   }
  //   return jsonDecode(webdavInfoJson);
  // }

  // Sync protocol selection
  String? get syncProtocol {
    return prefs.getString('syncProtocol');
  }

  set syncProtocol(String? protocol) {
    if (protocol != null) {
      prefs.setString('syncProtocol', protocol);
    } else {
      prefs.remove('syncProtocol');
    }
    notifyListeners();
  }

  Map<String, dynamic> getSyncInfo(SyncProtocol protocol) {
    String? syncInfoJson = prefs.getString('${protocol.name}Info');
    if (syncInfoJson == null) return {};
    return Map<String, dynamic>.from(jsonDecode(syncInfoJson));
  }

  setSyncInfo(SyncProtocol protocol, Map<String, dynamic>? info) {
    if (info != null) {
      prefs.setString('${protocol.name}Info', jsonEncode(info));
    } else {
      prefs.remove('${protocol.name}Info');
    }
    notifyListeners();
  }

  void saveWebdavStatus(bool status) {
    prefs.setBool('webdavStatus', status);
    notifyListeners();
  }

  bool get webdavStatus {
    return prefs.getBool('webdavStatus') ?? false;
  }

  void saveClearLogWhenStart(bool status) {
    prefs.setBool('clearLogWhenStart', status);
    notifyListeners();
  }

  bool get reduceVibrationFeedback {
    return prefs.getBool('reduceVibrationFeedback') ?? false;
  }

  set reduceVibrationFeedback(bool value) {
    prefs.setBool('reduceVibrationFeedback', value);
    notifyListeners();
  }

  bool get developerOptionsEnabled {
    return prefs.getBool("developerOptionsEnabled") ?? false;
  }

  set developerOptionsEnabled(bool value) {
    prefs.setBool("developerOptionsEnabled", value);
    notifyListeners();
  }

  List<StatisticsDashboardTileType> get statisticsDashboardTiles {
    final stored = prefs.getStringList(_statisticsDashboardTilesKey);
    if (stored == null || stored.isEmpty) {
      return List<StatisticsDashboardTileType>.from(
        defaultStatisticsDashboardTiles,
      );
    }
    final mapped = stored
        .map(_statisticsDashboardTileFromName)
        .whereType<StatisticsDashboardTileType>()
        .toList();
    if (mapped.isEmpty) {
      return List<StatisticsDashboardTileType>.from(
        defaultStatisticsDashboardTiles,
      );
    }
    return mapped;
  }

  set statisticsDashboardTiles(List<StatisticsDashboardTileType> tiles) {
    prefs.setStringList(
      _statisticsDashboardTilesKey,
      tiles.map((e) => e.name).toList(),
    );
    notifyListeners();
  }

  StatisticsDashboardTileType? _statisticsDashboardTileFromName(String name) {
    try {
      return StatisticsDashboardTileType.values
          .firstWhere((element) => element.name == name);
    } catch (_) {
      return null;
    }
  }

  bool get clearLogWhenStart {
    return prefs.getBool('clearLogWhenStart') ?? true;
  }

  bool get useOriginalCoverRatio {
    return prefs.getBool('useOriginalCoverRatio') ?? false;
  }

  set useOriginalCoverRatio(bool value) {
    prefs.setBool('useOriginalCoverRatio', value);
    notifyListeners();
  }

  void saveHideStatusBar(bool status) {
    prefs.setBool('hideStatusBar', status);
    notifyListeners();
  }

  bool get hideStatusBar {
    return prefs.getBool('hideStatusBar') ?? true;
  }

  set autoHideBottomBar(bool status) {
    prefs.setBool('autoHideBottomBar', status);
    notifyListeners();
  }

  bool get autoHideBottomBar {
    return prefs.getBool('autoHideBottomBar') ?? false;
  }

  set awakeTime(int minutes) {
    prefs.setInt('awakeTime', minutes);
    notifyListeners();
  }

  int get awakeTime {
    return prefs.getInt('awakeTime') ?? 5;
  }

  set lastShowUpdate(DateTime time) {
    prefs.setString('lastShowUpdate', time.toIso8601String());
    notifyListeners();
  }

  DateTime get lastShowUpdate {
    String? lastShowUpdateStr = prefs.getString('lastShowUpdate');
    if (lastShowUpdateStr == null) return DateTime(1970, 1, 1);
    return DateTime.parse(lastShowUpdateStr);
  }

  set pageTurningType(int type) {
    prefs.setInt('pageTurningType', type);
    notifyListeners();
  }

  int get pageTurningType {
    return prefs.getInt('pageTurningType') ?? 0;
  }

  set annotationType(String style) {
    prefs.setString('annotationType', style);
    notifyListeners();
  }

  String get annotationType {
    return prefs.getString('annotationType') ?? 'highlight';
  }

  set annotationColor(String color) {
    prefs.setString('annotationColor', color);
    notifyListeners();
  }

  String get annotationColor {
    return prefs.getString('annotationColor') ?? '66CCFF';
  }

  set ttsVolume(double volume) {
    prefs.setDouble('ttsVolume', volume);
    notifyListeners();
  }

  double get ttsVolume {
    return prefs.getDouble('ttsVolume') ?? 1.0;
  }

  set ttsPitch(double pitch) {
    prefs.setDouble('ttsPitch', pitch);
    notifyListeners();
  }

  double get ttsPitch {
    return prefs.getDouble('ttsPitch') ?? 1.0;
  }

  set ttsRate(double rate) {
    prefs.setDouble('ttsRate', rate);
    notifyListeners();
  }

  double get ttsRate {
    return prefs.getDouble('ttsRate') ?? 0.6;
  }

  void setTtsVoiceModel(String serviceId, String shortName) {
    prefs.setString('ttsVoiceModel_$serviceId', shortName);
    notifyListeners();
  }

  void removeTtsVoiceModel(String serviceId) {
    prefs.remove('ttsVoiceModel_$serviceId');
    notifyListeners();
  }

  String getTtsVoiceModel(String serviceId) {
    return prefs.getString('ttsVoiceModel_$serviceId') ?? '';
  }

  set ttsService(String serviceId) {
    prefs.setString('ttsService', serviceId);
    notifyListeners();
  }

  String get ttsService {
    String? service = prefs.getString('ttsService');
    if (service != null) return service;

    // Migration/Fallback
    bool isSystem = prefs.getBool('isSystemTts') ??
        true; // Default to system if nothing set
    if (!isSystem) {
      // Check if there was an online service set
      String? online = prefs.getString('onlineTtsService');
      if (online != null) return online;
    }
    return 'system';
  }

  Map<String, dynamic> getOnlineTtsConfig(String serviceId) {
    String? json = prefs.getString('onlineTtsConfig_$serviceId');
    if (json == null) return {};
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  Future<void> saveOnlineTtsConfig(
      String serviceId, Map<String, dynamic> config) async {
    await prefs.setString('onlineTtsConfig_$serviceId', jsonEncode(config));
    notifyListeners();
  }

  set pageTurnStyle(PageTurn style) {
    prefs.setString('pageTurnStyle', style.name);
    notifyListeners();
  }

  PageTurn get pageTurnStyle {
    String? style = prefs.getString('pageTurnStyle');
    if (style == null) return PageTurn.slide;
    return PageTurn.values.firstWhere((element) => element.name == style);
  }

  set font(FontModel font) {
    prefs.setString('font', font.toJson());
    notifyListeners();
  }

  FontModel get font {
    String? fontJson = prefs.getString('font');
    BuildContext context = navigatorKey.currentContext!;
    if (fontJson == null) {
      return FontModel(
          label: L10n.of(context).followBook, name: 'book', path: 'book');
    }
    return FontModel.fromJson(fontJson);
  }

  set trueDarkMode(bool status) {
    prefs.setBool('trueDarkMode', status);
    notifyListeners();
  }

  bool get trueDarkMode {
    return prefs.getBool('trueDarkMode') ?? false;
  }

  set eInkMode(bool status) {
    prefs.setBool('eInkMode', status);
    notifyListeners();
  }

  bool get eInkMode {
    return prefs.getBool('eInkMode') ?? false;
  }

  set translateService(TranslateService service) {
    prefs.setString('translateService', service.name);
    notifyListeners();
  }

  TranslateService get translateService {
    return getTranslateService(
        prefs.getString('translateService') ?? 'bingWeb');
  }

  set translateFrom(LangListEnum from) {
    prefs.setString('translateFrom', from.code);
    notifyListeners();
  }

  LangListEnum get translateFrom {
    return getLang(prefs.getString('translateFrom') ?? 'auto');
  }

  set translateTo(LangListEnum to) {
    prefs.setString('translateTo', to.code);
    notifyListeners();
  }

  LangListEnum get translateTo {
    return getLang(prefs.getString('translateTo') ?? getCurrentLanguageCode());
  }

  set autoTranslateSelection(bool status) {
    prefs.setBool('autoTranslateSelection', status);
    notifyListeners();
  }

  bool get autoTranslateSelection {
    return prefs.getBool('autoTranslateSelection') ?? false;
  }

  set autoMarkSelection(bool status) {
    prefs.setBool('autoMarkSelection', status);
    notifyListeners();
  }

  bool get autoMarkSelection {
    return prefs.getBool('autoMarkSelection') ?? false;
  }

  set fullTextTranslateService(TranslateService service) {
    prefs.setString('fullTextTranslateService', service.name);
    notifyListeners();
  }

  TranslateService get fullTextTranslateService {
    return getTranslateService(
        prefs.getString('fullTextTranslateService') ?? 'microsoft');
  }

  // Inline full-text translation concurrency (global).
  // Default = 4 (previous hard-coded behavior).
  int get inlineFullTextTranslateConcurrency {
    final v = prefs.getInt('inlineFullTextTranslateConcurrency') ?? 4;
    if (v < 1) return 1;
    if (v > 8) return 8;
    return v;
  }

  set inlineFullTextTranslateConcurrency(int value) {
    final v = value.clamp(1, 8);
    if (inlineFullTextTranslateConcurrency != v) {
      touchAiSettingsUpdatedAt();
    }
    prefs.setInt('inlineFullTextTranslateConcurrency', v);
    notifyListeners();
  }

  set fullTextTranslateFrom(LangListEnum from) {
    prefs.setString('fullTextTranslateFrom', from.code);
    notifyListeners();
  }

  LangListEnum get fullTextTranslateFrom {
    return getLang(prefs.getString('fullTextTranslateFrom') ?? 'auto');
  }

  set fullTextTranslateTo(LangListEnum to) {
    prefs.setString('fullTextTranslateTo', to.code);
    notifyListeners();
  }

  LangListEnum get fullTextTranslateTo {
    return getLang(
        prefs.getString('fullTextTranslateTo') ?? getCurrentLanguageCode());
  }

  // --- AI Translation (provider/model override) ---

  static const String _aiTranslateProviderIdKey = 'aiTranslateProviderIdV1';
  static const String _aiTranslateModelKey = 'aiTranslateModelV1';

  /// AI provider id used for translation features (underline + inline full-text).
  ///
  /// Empty means "follow current AI chat provider".
  String get aiTranslateProviderId {
    return prefs.getString(_aiTranslateProviderIdKey) ?? '';
  }

  set aiTranslateProviderId(String id) {
    final v = id.trim();
    if (aiTranslateProviderId.trim() != v) {
      touchAiSettingsUpdatedAt();
    }
    prefs.setString(_aiTranslateProviderIdKey, v);
    notifyListeners();
  }

  /// Effective provider id for AI translation.
  ///
  /// Rules:
  /// - If user-selected provider is enabled, use it.
  /// - Else fallback to selectedAiService (if enabled).
  /// - Else fallback to the first enabled provider.
  String get aiTranslateProviderIdEffective {
    final preferred = aiTranslateProviderId.trim();
    if (preferred.isNotEmpty) {
      final meta = getAiProviderMeta(preferred);
      if (meta != null && meta.enabled) return preferred;
    }

    final fallback = selectedAiService.trim();
    final fallbackMeta = getAiProviderMeta(fallback);
    if (fallback.isNotEmpty && fallbackMeta != null && fallbackMeta.enabled) {
      return fallback;
    }

    for (final p in aiProvidersV1) {
      if (p.enabled) return p.id;
    }

    // Last resort: keep app usable even if provider list is empty/corrupt.
    return fallback.isNotEmpty ? fallback : preferred;
  }

  /// Model id used for AI translation.
  ///
  /// Empty means "follow provider config".
  String get aiTranslateModel {
    return prefs.getString(_aiTranslateModelKey) ?? '';
  }

  set aiTranslateModel(String model) {
    final v = model.trim();
    if (aiTranslateModel.trim() != v) {
      touchAiSettingsUpdatedAt();
    }
    prefs.setString(_aiTranslateModelKey, v);
    notifyListeners();
  }

  // set convertChineseMode(ConvertChineseMode mode) {
  //   prefs.setString('convertChineseMode', mode.name);
  //   notifyListeners();
  // }

  // ConvertChineseMode get convertChineseMode {
  //   return getConvertChineseMode(
  //       prefs.getString('convertChineseMode') ?? 'none');
  // }

  set readingRules(ReadingRules rules) {
    prefs.setString('readingRules', rules.toJson().toString());
    notifyListeners();
  }

  ReadingRules get readingRules {
    String? rulesJson = prefs.getString('readingRules');
    if (rulesJson == null) {
      return ReadingRules(
        convertChineseMode: ConvertChineseMode.none,
        bionicReading: false,
      );
    }
    return ReadingRules.fromJson(rulesJson);
  }

  List<ChapterSplitRule> get chapterSplitCustomRules {
    final raw = prefs.getString(_chapterSplitCustomRulesKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((entry) {
        if (entry is Map<String, dynamic>) {
          return ChapterSplitRule.fromMap(entry);
        }
        if (entry is Map) {
          return ChapterSplitRule.fromMap(Map<String, dynamic>.from(entry));
        }
        throw const FormatException('Invalid chapter split rule entry');
      }).toList();
    } catch (e) {
      AnxLog.warning('Prefs: Failed to decode custom chapter split rules. $e');

      return const [];
    }
  }

  set chapterSplitCustomRules(List<ChapterSplitRule> rules) {
    final encoded = jsonEncode(rules.map((rule) => rule.toMap()).toList());
    prefs.setString(_chapterSplitCustomRulesKey, encoded);
    notifyListeners();
  }

  List<ChapterSplitRule> get allChapterSplitRules {
    return [
      ...builtinChapterSplitRules,
      ...chapterSplitCustomRules,
    ];
  }

  String? get _storedChapterSplitRuleId {
    return prefs.getString(_chapterSplitSelectedRuleKey);
  }

  set _storedChapterSplitRuleId(String? id) {
    if (id == null) {
      prefs.remove(_chapterSplitSelectedRuleKey);
    } else {
      prefs.setString(_chapterSplitSelectedRuleKey, id);
    }
    notifyListeners();
  }

  ChapterSplitRule get activeChapterSplitRule {
    final selectedId = _storedChapterSplitRuleId;

    if (selectedId != null) {
      final builtin = findBuiltinChapterSplitRuleById(selectedId);
      if (builtin != null) {
        try {
          builtin.buildRegExp();
          return builtin;
        } catch (_) {}
      }

      final custom = chapterSplitCustomRules
          .where((rule) => rule.id == selectedId)
          .toList();
      if (custom.isNotEmpty) {
        final rule = custom.first;
        try {
          rule.buildRegExp();
          return rule;
        } catch (_) {}
      }
    }

    return getDefaultChapterSplitRule();
  }

  void selectChapterSplitRule(String id) {
    _storedChapterSplitRuleId = id;
  }

  String? get chapterSplitSelectedRuleId => _storedChapterSplitRuleId;

  void saveCustomChapterSplitRule(ChapterSplitRule rule) {
    if (rule.isBuiltin) {
      return;
    }

    final rules = List<ChapterSplitRule>.from(chapterSplitCustomRules);
    final index = rules.indexWhere((existing) => existing.id == rule.id);

    if (index >= 0) {
      rules[index] = rule;
    } else {
      rules.add(rule);
    }

    chapterSplitCustomRules = rules;
  }

  void deleteCustomChapterSplitRule(String id) {
    final rules = chapterSplitCustomRules
        .where((rule) => rule.id != id)
        .toList(growable: false);

    chapterSplitCustomRules = rules;

    if (_storedChapterSplitRuleId == id) {
      _storedChapterSplitRuleId = kDefaultChapterSplitRuleId;
    }
  }

  set windowInfo(WindowInfo info) {
    prefs.setString('windowInfo', jsonEncode(info.toJson()));
    notifyListeners();
  }

  WindowInfo get windowInfo {
    String? windowInfoJson = prefs.getString('windowInfo');
    if (windowInfoJson == null) {
      return const WindowInfo(x: 0, y: 0, width: 0, height: 0);
    }
    return WindowInfo.fromJson(jsonDecode(windowInfoJson));
  }

  /// Custom storage path for Windows/macOS
  String? get customStoragePath => prefs.getString('customStoragePath');

  set customStoragePath(String? value) {
    if (value == null) {
      prefs.remove('customStoragePath');
    } else {
      prefs.setString('customStoragePath', value);
    }
    notifyListeners();
  }

  int get aiSettingsUpdatedAt {
    return prefs.getInt('aiSettingsUpdatedAt') ?? 0;
  }

  set aiSettingsUpdatedAt(int value) {
    prefs.setInt('aiSettingsUpdatedAt', value);
  }

  void touchAiSettingsUpdatedAt() {
    prefs.setInt('aiSettingsUpdatedAt', DateTime.now().millisecondsSinceEpoch);
  }

  bool _safeAiConfigEquals(
    Map<String, String> a,
    Map<String, String> b,
  ) {
    final keys = <String>{...a.keys, ...b.keys};
    for (final k in keys) {
      if ((a[k] ?? '').trim() != (b[k] ?? '').trim()) {
        return false;
      }
    }
    return true;
  }

  void saveAiConfig(String identifier, Map<String, String> config) {
    final before = getAiConfig(identifier);
    final beforeSafe = Map<String, String>.from(before)..remove('api_key');
    final afterSafe = Map<String, String>.from(config)..remove('api_key');
    if (!_safeAiConfigEquals(beforeSafe, afterSafe)) {
      touchAiSettingsUpdatedAt();
    }

    prefs.setString('aiConfig_$identifier', jsonEncode(config));
    notifyListeners();
  }

  Map<String, String> getAiConfig(String identifier) {
    String? aiConfigJson = prefs.getString('aiConfig_$identifier');
    if (aiConfigJson == null) {
      return {};
    }
    Map<String, dynamic> decoded = jsonDecode(aiConfigJson);
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  set selectedAiService(String identifier) {
    if ((prefs.getString('selectedAiService') ?? 'openai') != identifier) {
      touchAiSettingsUpdatedAt();
    }
    prefs.setString('selectedAiService', identifier);
    notifyListeners();
  }

  String get selectedAiService {
    return prefs.getString('selectedAiService') ?? 'openai';
  }

  // --- Provider Center (Cherry-style) ---

  static const String _aiProvidersV1Key = 'aiProvidersV1';

  bool get hasAiProvidersV1 => prefs.containsKey(_aiProvidersV1Key);

  List<AiProviderMeta> get aiProvidersV1 {
    final raw = prefs.getString(_aiProvidersV1Key);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    try {
      return AiProviderMeta.decodeList(raw);
    } catch (e) {
      // Corrupted value - keep app usable.
      AnxLog.severe('Failed to decode aiProvidersV1: $e');
      return const [];
    }
  }

  set aiProvidersV1(List<AiProviderMeta> providers) {
    prefs.setString(_aiProvidersV1Key, AiProviderMeta.encodeList(providers));
    notifyListeners();
  }

  /// Initialize provider metadata storage with the given built-in providers.
  ///
  /// - Only runs if the key is missing or empty.
  /// - Ensures built-ins are always present (without touching secrets).
  void ensureAiProvidersV1Initialized({
    required List<AiProviderMeta> builtIns,
  }) {
    final existing = aiProvidersV1;
    if (existing.isEmpty) {
      aiProvidersV1 = builtIns;
      return;
    }

    final byId = <String, AiProviderMeta>{
      for (final p in existing) p.id: p,
    };

    final merged = <AiProviderMeta>[];

    // Keep built-ins in a stable, well-known order.
    for (final builtIn in builtIns) {
      final current = byId.remove(builtIn.id);
      if (current == null) {
        merged.add(builtIn);
        continue;
      }

      // Refresh non-sensitive display fields, but preserve user toggles.
      merged.add(
        current.copyWith(
          name: builtIn.name,
          type: builtIn.type,
          isBuiltIn: true,
          logoKey: builtIn.logoKey,
        ),
      );
    }

    // Append remaining providers (custom) in their existing order.
    for (final p in existing) {
      if (byId.containsKey(p.id)) {
        merged.add(p);
      }
    }

    // Write back only if changed.
    if (AiProviderMeta.encodeList(merged) !=
        AiProviderMeta.encodeList(existing)) {
      aiProvidersV1 = merged;
    }
  }

  AiProviderMeta? getAiProviderMeta(String id) {
    for (final p in aiProvidersV1) {
      if (p.id == id) return p;
    }
    return null;
  }

  void upsertAiProviderMeta(AiProviderMeta meta) {
    final existing = List<AiProviderMeta>.from(aiProvidersV1);
    final index = existing.indexWhere((p) => p.id == meta.id);
    if (index >= 0) {
      existing[index] = meta;
    } else {
      existing.add(meta);
    }
    aiProvidersV1 = existing;
  }

  void deleteAiProviderMeta(String id) {
    final existing = aiProvidersV1;
    if (existing.isEmpty) return;
    aiProvidersV1 = existing.where((p) => p.id != id).toList(growable: false);
  }

  void deleteAiConfig(String identifier) {
    // Removing config affects syncable settings.
    if (prefs.containsKey('aiConfig_$identifier')) {
      touchAiSettingsUpdatedAt();
    }
    prefs.remove('aiConfig_$identifier');
    // Also clear caches bound to this provider.
    prefs.remove(_aiModelsCacheKey(identifier));
    notifyListeners();
  }

  // --- Provider models cache (per-provider, local-only) ---

  static const String _aiModelsCacheV1Prefix = 'aiModelsCacheV1_';

  static String _aiModelsCacheKey(String providerId) {
    return '$_aiModelsCacheV1Prefix$providerId';
  }

  ({int updatedAt, List<String> models})? getAiModelsCacheV1(
      String providerId) {
    final raw = prefs.getString(_aiModelsCacheKey(providerId));
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final updatedAt = decoded['updatedAt'] is int
          ? decoded['updatedAt'] as int
          : DateTime.now().millisecondsSinceEpoch;
      final modelsRaw = decoded['models'];
      if (modelsRaw is! List) return null;
      final models = modelsRaw
          .map((e) => e?.toString())
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
      return (updatedAt: updatedAt, models: models);
    } catch (_) {
      return null;
    }
  }

  void saveAiModelsCacheV1(String providerId, List<String> models) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final sanitized = models
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();

    prefs.setString(
      _aiModelsCacheKey(providerId),
      jsonEncode({
        'updatedAt': now,
        'models': sanitized,
      }),
    );
    notifyListeners();
  }

  void clearAiModelsCacheV1(String providerId) {
    prefs.remove(_aiModelsCacheKey(providerId));
    notifyListeners();
  }

  void saveAiPrompt(AiPrompts identifier, String prompt) {
    final key = 'aiPrompt_${identifier.name}';
    if ((prefs.getString(key) ?? '') != prompt) {
      touchAiSettingsUpdatedAt();
    }
    prefs.setString(key, prompt);
    notifyListeners();
  }

  String getAiPrompt(AiPrompts identifier) {
    String? aiPrompt = prefs.getString('aiPrompt_${identifier.name}');
    if (aiPrompt == null) {
      return identifier.getPrompt();
    }
    return aiPrompt;
  }

  void deleteAiPrompt(AiPrompts identifier) {
    final key = 'aiPrompt_${identifier.name}';
    if (prefs.containsKey(key)) {
      touchAiSettingsUpdatedAt();
    }
    prefs.remove(key);
    notifyListeners();
  }

  List<String> get enabledAiToolIds {
    final stored = prefs.getStringList(_enabledAiToolsKey);
    if (stored == null) {
      return AiToolRegistry.defaultEnabledToolIds();
    }
    if (stored.isEmpty) {
      return const [];
    }
    final sanitized = AiToolRegistry.sanitizeIds(stored);
    if (sanitized.isEmpty && stored.isNotEmpty) {
      return AiToolRegistry.defaultEnabledToolIds();
    }
    return sanitized;
  }

  set enabledAiToolIds(List<String> ids) {
    prefs.setStringList(
      _enabledAiToolsKey,
      AiToolRegistry.sanitizeIds(ids),
    );
    notifyListeners();
  }

  bool isAiToolEnabled(String id) {
    return enabledAiToolIds.contains(id);
  }

  void resetEnabledAiTools() {
    prefs.remove(_enabledAiToolsKey);
    notifyListeners();
  }

  bool shouldShowHint(HintKey key) {
    return prefs.getBool('hint_${key.code}') ?? true;
  }

  void setShowHint(HintKey key, bool value) {
    prefs.setBool('hint_${key.code}', value);
    notifyListeners();
  }

  void resetHints() {
    for (final hint in HintKey.values) {
      prefs.remove('hint_${hint.code}');
    }
    notifyListeners();
  }

  set autoSummaryPreviousContent(bool status) {
    prefs.setBool('autoSummaryPreviousContent', status);
    notifyListeners();
  }

  bool get autoSummaryPreviousContent {
    return prefs.getBool('autoSummaryPreviousContent') ?? false;
  }

  set autoAdjustReadingTheme(bool status) {
    prefs.setBool('autoAdjustReadingTheme', status);
    notifyListeners();
  }

  bool get autoAdjustReadingTheme {
    return prefs.getBool('autoAdjustReadingTheme') ?? false;
  }

  // User prompts - simple read/write methods
  List<UserPrompt> get userPrompts {
    final jsonString = prefs.getString(_userPromptsKey);
    if (jsonString == null || jsonString.isEmpty) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((json) => UserPrompt.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AnxLog.severe('Error loading user prompts: $e');
      return [];
    }
  }

  set userPrompts(List<UserPrompt> prompts) {
    touchAiSettingsUpdatedAt();
    final jsonList = prompts.map((p) => p.toJson()).toList();
    prefs.setString(_userPromptsKey, jsonEncode(jsonList));
    notifyListeners();
  }

  set maxAiCacheCount(int count) {
    prefs.setInt('maxAiCacheCount', count);
    notifyListeners();
  }

  int get maxAiCacheCount {
    return prefs.getInt('maxAiCacheCount') ?? 300;
  }

  set volumeKeyTurnPage(bool status) {
    prefs.setBool('volumeKeyTurnPage', status);
    notifyListeners();
  }

  bool get volumeKeyTurnPage {
    return prefs.getBool('volumeKeyTurnPage') ?? false;
  }

  set swapPageTurnArea(bool status) {
    prefs.setBool('swapPageTurnArea', status);
  }

  bool get swapPageTurnArea {
    return prefs.getBool('swapPageTurnArea') ?? false;
  }

  set showMenuOnHover(bool status) {
    prefs.setBool('showMenuOnHover', status);
    notifyListeners();
  }

  bool get showMenuOnHover {
    return prefs.getBool('showMenuOnHover') ?? true;
  }

  set pageTurnMode(String mode) {
    prefs.setString('pageTurnMode', mode);
    notifyListeners();
  }

  String get pageTurnMode {
    return prefs.getString('pageTurnMode') ?? 'simple';
  }

  set customPageTurnConfig(List<int> config) {
    prefs.setString('customPageTurnConfig', config.join(','));
    notifyListeners();
  }

  List<int> get customPageTurnConfig {
    String? configStr = prefs.getString('customPageTurnConfig');
    if (configStr == null) {
      // Default: left column = prev (1), middle column = menu (3), right column = next (2)
      // Index mapping: 0=none, 1=next, 2=prev, 3=menu
      // Grid layout: 0,1,2,3,4,5,6,7,8 (row by row)
      return [2, 3, 1, 2, 3, 1, 2, 3, 1]; // prev, menu, next for all rows
    }
    return configStr.split(',').map((e) => int.parse(e)).toList();
  }

  set bookCoverWidth(double width) {
    prefs.setDouble('bookCoverWidth', width);
    notifyListeners();
  }

  double get bookCoverWidth {
    return prefs.getDouble('bookCoverWidth') ?? 120;
  }

  set bookshelfFolderStyle(BookshelfFolderStyle style) {
    prefs.setString('bookshelfFolderStyle', style.code);
    notifyListeners();
  }

  BookshelfFolderStyle get bookshelfFolderStyle {
    return BookshelfFolderStyle.fromCode(
      prefs.getString('bookshelfFolderStyle') ??
          BookshelfFolderStyle.stacked.code,
    );
  }

  set showBookTitleOnDefaultCover(bool status) {
    prefs.setBool('showBookTitleOnDefaultCover', status);
    notifyListeners();
  }

  bool get showBookTitleOnDefaultCover {
    return prefs.getBool('showBookTitleOnDefaultCover') ?? true;
  }

  set showAuthorOnDefaultCover(bool status) {
    prefs.setBool('showAuthorOnDefaultCover', status);
    notifyListeners();
  }

  bool get showAuthorOnDefaultCover {
    return prefs.getBool('showAuthorOnDefaultCover') ?? true;
  }

  set openBookAnimation(bool status) {
    prefs.setBool('openBookAnimation', status);
    notifyListeners();
  }

  bool get openBookAnimation {
    return prefs.getBool('openBookAnimation') ?? true;
  }

  set onlySyncWhenWifi(bool status) {
    prefs.setBool('onlySyncWhenWifi', status);
    notifyListeners();
  }

  bool get onlySyncWhenWifi {
    return prefs.getBool('onlySyncWhenWifi') ?? false;
  }

  set useBookStyles(bool status) {
    prefs.setBool('useBookStyles', status);
    notifyListeners();
  }

  bool get useBookStyles {
    return prefs.getBool('useBookStyles') ?? false;
  }

  set bottomNavigatorShowNote(bool status) {
    prefs.setBool('bottomNavigatorShowNote', status);
    notifyListeners();
  }

  bool get bottomNavigatorShowNote {
    // Default: hidden (new default UX).
    return prefs.getBool('bottomNavigatorShowNote') ?? false;
  }

  set bottomNavigatorShowStatistics(bool status) {
    prefs.setBool('bottomNavigatorShowStatistics', status);
    notifyListeners();
  }

  bool get bottomNavigatorShowStatistics {
    // Default: hidden (new default UX).
    return prefs.getBool('bottomNavigatorShowStatistics') ?? false;
  }

  bool get bottomNavigatorShowAI {
    return prefs.getBool('bottomNavigatorShowAI') ?? true;
  }

  set bottomNavigatorShowAI(bool status) {
    prefs.setBool('bottomNavigatorShowAI', status);
    notifyListeners();
  }

  // --- Home tabs config (order + enable) ---

  void _migrateHomeTabsIfNeeded() {
    final v = prefs.getInt(_homeTabsSchemaVersionKey);
    final hasOrder = prefs.getStringList(_homeTabsOrderKey) != null;
    final hasEnabled = prefs.getString(_homeTabsEnabledKey) != null;

    if (v == _homeTabsSchemaVersion && hasOrder && hasEnabled) {
      return;
    }

    // Migrate from legacy bottom navigator switches.
    // New default UX: Statistics + Notes are hidden unless the user explicitly
    // enabled them (legacy prefs present).
    final legacyShowStatistics =
        prefs.getBool('bottomNavigatorShowStatistics') ?? false;
    final legacyShowAI = prefs.getBool('bottomNavigatorShowAI') ?? true;
    final legacyShowNotes = prefs.getBool('bottomNavigatorShowNote') ?? false;

    final defaultOrder = <String>[
      homeTabPapers,
      homeTabBookshelf,
      homeTabStatistics,
      homeTabAI,
      homeTabNotes,
      homeTabSettings,
    ];

    final enabled = <String, bool>{
      homeTabPapers: true,
      homeTabBookshelf: true,
      homeTabStatistics: legacyShowStatistics,
      homeTabAI: legacyShowAI,
      homeTabNotes: legacyShowNotes,
      homeTabSettings: true,
    };

    prefs.setInt(_homeTabsSchemaVersionKey, _homeTabsSchemaVersion);
    prefs.setStringList(_homeTabsOrderKey, defaultOrder);
    prefs.setString(_homeTabsEnabledKey, jsonEncode(enabled));
  }

  List<String> _normalizeHomeTabsOrder(List<String> raw) {
    final out = <String>[];
    final seen = <String>{};

    for (final id in raw) {
      if (!_homeTabAll.contains(id)) continue;
      if (seen.contains(id)) continue;
      seen.add(id);
      out.add(id);
    }

    // Ensure mandatory tabs exist even if the config is corrupted.
    if (!seen.contains(homeTabPapers)) {
      out.insert(0, homeTabPapers);
      seen.add(homeTabPapers);
    }
    if (!seen.contains(homeTabSettings)) {
      out.add(homeTabSettings);
      seen.add(homeTabSettings);
    }

    // Append any newly added tabs.
    for (final id in _homeTabAll) {
      if (!seen.contains(id)) out.add(id);
    }

    return out;
  }

  Map<String, bool> _normalizeHomeTabsEnabled(Map<String, bool> raw) {
    final out = <String, bool>{};
    for (final id in _homeTabAll) {
      out[id] = raw[id] ?? true;
    }
    // Mandatory tabs cannot be disabled.
    for (final id in _homeTabMandatory) {
      out[id] = true;
    }
    return out;
  }

  void _normalizeAndPersistHomeTabsConfig() {
    final order = _normalizeHomeTabsOrder(
        prefs.getStringList(_homeTabsOrderKey) ?? const []);

    Map<String, bool> enabled;
    final enabledStr = prefs.getString(_homeTabsEnabledKey);
    if (enabledStr == null || enabledStr.trim().isEmpty) {
      enabled = <String, bool>{};
    } else {
      try {
        final dynamic decoded = jsonDecode(enabledStr);
        if (decoded is Map) {
          enabled = decoded
              .map((key, value) => MapEntry(key.toString(), value == true));
        } else {
          enabled = <String, bool>{};
        }
      } catch (_) {
        enabled = <String, bool>{};
      }
    }

    final enabledNormalized = _normalizeHomeTabsEnabled(enabled);

    prefs.setInt(_homeTabsSchemaVersionKey, _homeTabsSchemaVersion);
    prefs.setStringList(_homeTabsOrderKey, order);
    prefs.setString(_homeTabsEnabledKey, jsonEncode(enabledNormalized));
  }

  List<String> get homeTabsOrder {
    return _normalizeHomeTabsOrder(
        prefs.getStringList(_homeTabsOrderKey) ?? const []);
  }

  Map<String, bool> get homeTabsEnabled {
    final enabledStr = prefs.getString(_homeTabsEnabledKey);
    Map<String, bool> enabled;
    if (enabledStr == null || enabledStr.trim().isEmpty) {
      enabled = <String, bool>{};
    } else {
      try {
        final dynamic decoded = jsonDecode(enabledStr);
        if (decoded is Map) {
          enabled = decoded
              .map((key, value) => MapEntry(key.toString(), value == true));
        } else {
          enabled = <String, bool>{};
        }
      } catch (_) {
        enabled = <String, bool>{};
      }
    }
    return _normalizeHomeTabsEnabled(enabled);
  }

  void setHomeTabsOrder(List<String> order) {
    final normalized = _normalizeHomeTabsOrder(order);
    prefs.setStringList(_homeTabsOrderKey, normalized);
    notifyListeners();
  }

  void setHomeTabEnabled(String tabId, bool enabled) {
    final map0 = Map<String, bool>.from(homeTabsEnabled);
    if (_homeTabMandatory.contains(tabId)) {
      map0[tabId] = true;
    } else {
      map0[tabId] = enabled;
    }
    final normalized = _normalizeHomeTabsEnabled(map0);
    prefs.setString(_homeTabsEnabledKey, jsonEncode(normalized));
    notifyListeners();
  }

  void resetHomeTabsConfigToDefault() {
    final defaultOrder = <String>[
      homeTabPapers,
      homeTabBookshelf,
      homeTabStatistics,
      homeTabAI,
      homeTabNotes,
      homeTabSettings,
    ];

    // Reset to the current *default* UX.
    // Notes + Statistics are hidden by default.
    final enabled = <String, bool>{
      homeTabPapers: true,
      homeTabBookshelf: true,
      homeTabStatistics: false,
      homeTabAI: true,
      homeTabNotes: false,
      homeTabSettings: true,
    };

    prefs.setInt(_homeTabsSchemaVersionKey, _homeTabsSchemaVersion);
    prefs.setStringList(_homeTabsOrderKey, defaultOrder);
    prefs.setString(
        _homeTabsEnabledKey, jsonEncode(_normalizeHomeTabsEnabled(enabled)));
    notifyListeners();
  }

  set syncCompletedToast(bool status) {
    prefs.setBool('syncCompletedToast', status);
    notifyListeners();
  }

  bool get syncCompletedToast {
    return prefs.getBool('syncCompletedToast') ?? true;
  }

  set autoSync(bool status) {
    prefs.setBool('autoSync', status);
    notifyListeners();
  }

  bool get autoSync {
    return prefs.getBool('autoSync') ?? true;
  }

  set readingInfo(ReadingInfoModel info) {
    prefs.setString('readingInfo', jsonEncode(info.toJson()));
    notifyListeners();
  }

  ReadingInfoModel get readingInfo {
    String? readingInfoJson = prefs.getString('readingInfo');
    if (readingInfoJson == null) {
      return ReadingInfoModel();
    }
    return ReadingInfoModel.fromJson(jsonDecode(readingInfoJson));
  }

  set isSystemTts(bool status) {
    prefs.setBool('isSystemTts', status);
    notifyListeners();
  }

  bool get showTextUnderIconButton {
    return prefs.getBool('showTextUnderIconButton') ?? true;
  }

  set showTextUnderIconButton(bool show) {
    prefs.setBool('showTextUnderIconButton', show);
    notifyListeners();
  }

  DateTime? get lastUploadBookDate {
    String? lastUploadBookDateStr = prefs.getString('lastUploadBookDate');
    if (lastUploadBookDateStr == null) return null;
    return DateTime.parse(lastUploadBookDateStr);
  }

  set lastUploadBookDate(DateTime? date) {
    if (date == null) {
      prefs.remove('lastUploadBookDate');
    } else {
      prefs.setString('lastUploadBookDate', date.toIso8601String());
    }
    notifyListeners();
  }

  int get lastServerPort {
    return prefs.getInt('lastServerPort') ?? 0;
  }

  set lastServerPort(int port) {
    prefs.setInt('lastServerPort', port);
    notifyListeners();
  }

  SortFieldEnum get sortField {
    return SortFieldEnum.values.firstWhere(
      (element) => element.name == prefs.getString('sortField'),
      orElse: () => SortFieldEnum.lastReadTime,
    );
  }

  set sortField(SortFieldEnum field) {
    prefs.setString('sortField', field.name);
    notifyListeners();
  }

  SortOrderEnum get sortOrder {
    return SortOrderEnum.values.firstWhere(
      (element) => element.name == prefs.getString('sortOrder'),
      orElse: () => SortOrderEnum.descending,
    );
  }

  set sortOrder(SortOrderEnum order) {
    prefs.setString('sortOrder', order.name);
    notifyListeners();
  }

  bool get notesExportMergeChapters {
    return prefs.getBool('notesExportMergeChapters') ?? true;
  }

  set notesExportMergeChapters(bool value) {
    prefs.setBool('notesExportMergeChapters', value);
    notifyListeners();
  }

  NotesSortField get notesViewSortFieldPref {
    final stored = prefs.getString('notesViewSortField');
    return NotesSortField.values.firstWhere(
      (field) => field.name == stored,
      orElse: () => NotesSortField.cfi,
    );
  }

  set notesViewSortFieldPref(NotesSortField field) {
    prefs.setString('notesViewSortField', field.name);
    notifyListeners();
  }

  SortDirection get notesViewSortDirectionPref {
    final stored = prefs.getString('notesViewSortDirection');
    return SortDirection.values.firstWhere(
      (dir) => dir.name == stored,
      orElse: () => SortDirection.asc,
    );
  }

  set notesViewSortDirectionPref(SortDirection direction) {
    prefs.setString('notesViewSortDirection', direction.name);
    notifyListeners();
  }

  NotesSortField get notesExportSortFieldPref {
    final stored = prefs.getString('notesExportSortField');
    return NotesSortField.values.firstWhere(
      (field) => field.name == stored,
      orElse: () => NotesSortField.cfi,
    );
  }

  set notesExportSortFieldPref(NotesSortField field) {
    prefs.setString('notesExportSortField', field.name);
    notifyListeners();
  }

  SortDirection get notesExportSortDirectionPref {
    final stored = prefs.getString('notesExportSortDirection');
    return SortDirection.values.firstWhere(
      (dir) => dir.name == stored,
      orElse: () => SortDirection.asc,
    );
  }

  set notesExportSortDirectionPref(SortDirection direction) {
    prefs.setString('notesExportSortDirection', direction.name);
    notifyListeners();
  }

  ExcerptShareTemplateEnum get excerptShareTemplate {
    return ExcerptShareTemplateEnum.values.firstWhere(
      (element) => element.name == prefs.getString('excerptShareTemplate'),
      orElse: () => ExcerptShareTemplateEnum.defaultTemplate,
    );
  }

  set excerptShareTemplate(ExcerptShareTemplateEnum template) {
    prefs.setString('excerptShareTemplate', template.name);
    notifyListeners();
  }

  FontModel get excerptShareFont {
    String? fontJson = prefs.getString('excerptShareFont');
    if (fontJson == null) {
      return FontModel(
          label: L10n.of(navigatorKey.currentContext!).systemFont,
          name: 'customFont0',
          path: 'SourceHanSerifSC-Regular.otf');
    }
    return FontModel.fromJson(fontJson);
  }

  set excerptShareFont(FontModel font) {
    prefs.setString('excerptShareFont', font.toJson());
    notifyListeners();
  }

  int get excerptShareColorIndex {
    return prefs.getInt('excerptShareColorIndex') ?? 0;
  }

  set excerptShareColorIndex(int index) {
    prefs.setInt('excerptShareColorIndex', index);
    notifyListeners();
  }

  int get excerptShareBgimgIndex {
    return prefs.getInt('excerptShareBgimgIndex') ?? 1;
  }

  set excerptShareBgimgIndex(int index) {
    prefs.setInt('excerptShareBgimgIndex', index);
    notifyListeners();
  }

  void saveTranslateServiceConfig(
      TranslateService service, Map<String, dynamic> config) {
    prefs.setString(
        'translateServiceConfig_${service.name}', jsonEncode(config));
    notifyListeners();
  }

  Map<String, dynamic>? getTranslateServiceConfig(TranslateService service) {
    String? configJson =
        prefs.getString('translateServiceConfig_${service.name}');
    if (configJson == null) {
      return null;
    }
    return jsonDecode(configJson) as Map<String, dynamic>;
  }

  set iapPurchaseStatus(bool isPurchased) {
    prefs.setBool('iapPurchaseStatus', isPurchased);
    // notifyListeners();
  }

  bool get iapPurchaseStatus {
    return prefs.getBool('iapPurchaseStatus') ?? false;
  }

  set iapLastCheckTime(DateTime checkTime) {
    prefs.setString('iapLastCheckTime', checkTime.toIso8601String());
    // notifyListeners();
  }

  DateTime get iapLastCheckTime {
    String? lastCheckTimeStr = prefs.getString('iapLastCheckTime');
    if (lastCheckTimeStr == null) {
      return DateTime(1970, 1, 1);
    }
    return DateTime.parse(lastCheckTimeStr);
  }

  WritingModeEnum get writingMode {
    return WritingModeEnum.fromCode(prefs.getString('writingMode') ?? 'auto');
  }

  set writingMode(WritingModeEnum mode) {
    prefs.setString('writingMode', mode.code);
    notifyListeners();
  }

  TranslationModeEnum get translationMode {
    return TranslationModeEnum.fromCode(
        prefs.getString('translationMode') ?? 'off');
  }

  set translationMode(TranslationModeEnum mode) {
    prefs.setString('translationMode', mode.code);
    notifyListeners();
  }

  BgimgModel get bgimg {
    String? bgimgJson = prefs.getString('bgimg');
    if (bgimgJson == null) {
      return BgimgModel(
          type: BgimgType.none, path: 'none', alignment: BgimgAlignment.center);
    }
    return BgimgModel.fromJson(jsonDecode(bgimgJson));
  }

  set bgimg(BgimgModel bgimg) {
    prefs.setString('bgimg', jsonEncode(bgimg.toJson()));
    notifyListeners();
  }

  bool get enableJsForEpub {
    return prefs.getBool('enableJsForEpub') ?? false;
  }

  set enableJsForEpub(bool enable) {
    prefs.setBool('enableJsForEpub', enable);
    notifyListeners();
  }

  double get pageHeaderMargin {
    return prefs.getDouble('pageHeaderMargin') ??
        MediaQuery.of(navigatorKey.currentContext!).padding.bottom;
  }

  set pageHeaderMargin(double margin) {
    prefs.setDouble('pageHeaderMargin', margin);
    notifyListeners();
  }

  double get pageFooterMargin {
    return prefs.getDouble('pageFooterMargin') ??
        MediaQuery.of(navigatorKey.currentContext!).padding.bottom;
  }

  set pageFooterMargin(double margin) {
    prefs.setDouble('pageFooterMargin', margin);
    notifyListeners();
  }

  String? get lastAppVersion {
    return prefs.getString('lastAppVersion');
  }

  set lastAppVersion(String? version) {
    if (version != null) {
      prefs.setString('lastAppVersion', version);
    } else {
      prefs.remove('lastAppVersion');
    }
    notifyListeners();
  }

  set customCSSEnabled(bool enabled) {
    prefs.setBool('customCSSEnabled', enabled);
    notifyListeners();
  }

  bool get customCSSEnabled {
    return prefs.getBool('customCSSEnabled') ?? false;
  }

  set customCSS(String css) {
    prefs.setString('customCSS', css);
    notifyListeners();
  }

  String get customCSS {
    return prefs.getString('customCSS') ?? '';
  }

  Map<String, TranslationModeEnum> get bookTranslationModes {
    String? modesJson = prefs.getString('bookTranslationModes');
    if (modesJson == null) return {};

    Map<String, dynamic> decoded = jsonDecode(modesJson);
    return decoded.map((key, value) =>
        MapEntry(key, TranslationModeEnum.fromCode(value as String)));
  }

  set bookTranslationModes(Map<String, TranslationModeEnum> modes) {
    Map<String, String> encoded =
        modes.map((key, value) => MapEntry(key, value.code));
    prefs.setString('bookTranslationModes', jsonEncode(encoded));
    notifyListeners();
  }

  TranslationModeEnum getBookTranslationMode(int bookId) {
    return bookTranslationModes[bookId.toString()] ?? TranslationModeEnum.off;
  }

  void setBookTranslationMode(int bookId, TranslationModeEnum mode) {
    Map<String, TranslationModeEnum> modes = bookTranslationModes;
    String bookIdStr = bookId.toString();

    if (mode == TranslationModeEnum.off) {
      modes.remove(bookIdStr); // 默认状态不保存，节省空间
    } else {
      modes[bookIdStr] = mode;
    }
    bookTranslationModes = modes;
  }

  bool get allowMixWithOtherAudio {
    return prefs.getBool('allowMixWithOtherAudio') ?? false;
  }

  set allowMixWithOtherAudio(bool allow) {
    prefs.setBool('allowMixWithOtherAudio', allow);
    notifyListeners();
  }

  TextAlignmentEnum get textAlignment {
    return TextAlignmentEnum.fromCode(
        prefs.getString('textAlignment') ?? 'auto');
  }

  set textAlignment(TextAlignmentEnum alignment) {
    prefs.setString('textAlignment', alignment.code);
    notifyListeners();
  }

  AiPanelPositionEnum get aiPanelPosition {
    return AiPanelPositionEnum.fromCode(
        prefs.getString('aiPanelPosition') ?? 'right');
  }

  set aiPanelPosition(AiPanelPositionEnum position) {
    if ((prefs.getString('aiPanelPosition') ?? 'right') != position.code) {
      touchAiSettingsUpdatedAt();
    }
    prefs.setString('aiPanelPosition', position.code);
    notifyListeners();
  }

  /// AI panel width (dock mode)
  double get aiPanelWidth {
    return prefs.getDouble('aiPanelWidth') ?? 300;
  }

  set aiPanelWidth(double width) {
    if ((prefs.getDouble('aiPanelWidth') ?? 300) != width) {
      touchAiSettingsUpdatedAt();
    }
    prefs.setDouble('aiPanelWidth', width);
    notifyListeners();
  }

  /// AI panel height (dock mode when positioned at bottom)
  double get aiPanelHeight {
    return prefs.getDouble('aiPanelHeight') ?? 300;
  }

  set aiPanelHeight(double height) {
    if ((prefs.getDouble('aiPanelHeight') ?? 300) != height) {
      touchAiSettingsUpdatedAt();
    }
    prefs.setDouble('aiPanelHeight', height);
    notifyListeners();
  }

  /// Initial height of AI chat bottom sheet (0-1, relative to screen height).
  double get aiSheetInitialSize {
    return prefs.getDouble('aiSheetInitialSize') ?? 0.6;
  }

  set aiSheetInitialSize(double size) {
    if ((prefs.getDouble('aiSheetInitialSize') ?? 0.6) != size) {
      touchAiSettingsUpdatedAt();
    }
    prefs.setDouble('aiSheetInitialSize', size);
    notifyListeners();
  }

  /// Font scale for AI chat UI (markdown + input). 1.0 = system default.
  double get aiChatFontScale {
    return prefs.getDouble('aiChatFontScale') ?? 1.0;
  }

  /// AI dev mode diagnostic logging.
  ///
  /// When enabled, extra AI streaming / tool calling debug logs will be written
  /// to the app log file (Settings -> Advanced -> Log).
  bool get aiDebugLogsEnabled {
    return prefs.getBool('aiDebugLogsEnabled') ?? false;
  }

  set aiDebugLogsEnabled(bool enabled) {
    if ((prefs.getBool('aiDebugLogsEnabled') ?? false) != enabled) {
      touchAiSettingsUpdatedAt();
    }
    prefs.setBool('aiDebugLogsEnabled', enabled);
    notifyListeners();
  }

  set aiChatFontScale(double scale) {
    if ((prefs.getDouble('aiChatFontScale') ?? 1.0) != scale) {
      touchAiSettingsUpdatedAt();
    }
    prefs.setDouble('aiChatFontScale', scale);
    notifyListeners();
  }

  /// Configurable quick prompts shown in AI chat input area.
  /// Returns default prompts (localized) if never customized.
  List<AiInputQuickPrompt> get aiInputQuickPrompts {
    final stored = prefs.getString('aiInputQuickPrompts');
    if (stored != null && stored.isNotEmpty) {
      final list = AiInputQuickPrompt.fromJsonList(stored);
      if (list.isNotEmpty) return list;
    }
    // Return empty list; AiChatStream will use localized defaults.
    return [];
  }

  set aiInputQuickPrompts(List<AiInputQuickPrompt> prompts) {
    touchAiSettingsUpdatedAt();
    prefs.setString(
        'aiInputQuickPrompts', AiInputQuickPrompt.toJsonList(prompts));
    notifyListeners();
  }

  /// Whether user has customized quick prompts (used to decide seeding).
  bool get hasCustomAiInputQuickPrompts {
    return prefs.containsKey('aiInputQuickPrompts');
  }

  /// Clear custom quick prompts to revert to defaults.
  void clearAiInputQuickPrompts() {
    if (prefs.containsKey('aiInputQuickPrompts')) {
      touchAiSettingsUpdatedAt();
    }
    prefs.remove('aiInputQuickPrompts');
    notifyListeners();
  }

  /// iPad AI panel mode: dock (split panel) or bottomSheet.
  AiPadPanelModeEnum get aiPadPanelMode {
    return AiPadPanelModeEnum.fromCode(
        prefs.getString('aiPadPanelMode') ?? 'dock');
  }

  set aiPadPanelMode(AiPadPanelModeEnum mode) {
    if ((prefs.getString('aiPadPanelMode') ?? 'dock') != mode.code) {
      touchAiSettingsUpdatedAt();
    }
    prefs.setString('aiPadPanelMode', mode.code);
    notifyListeners();
  }

  /// AI panel dock side when in dock mode (left or right). Affects iPad primarily.
  AiDockSideEnum get aiDockSide {
    return AiDockSideEnum.fromCode(prefs.getString('aiDockSide') ?? 'right');
  }

  set aiDockSide(AiDockSideEnum side) {
    if ((prefs.getString('aiDockSide') ?? 'right') != side.code) {
      touchAiSettingsUpdatedAt();
    }
    prefs.setString('aiDockSide', side.code);
    notifyListeners();
  }

  CodeHighlightThemeEnum get codeHighlightTheme {
    return CodeHighlightThemeEnum.fromCode(
        prefs.getString('codeHighlightTheme') ?? 'default');
  }

  set codeHighlightTheme(CodeHighlightThemeEnum theme) {
    prefs.setString('codeHighlightTheme', theme.code);
    notifyListeners();
  }
}
