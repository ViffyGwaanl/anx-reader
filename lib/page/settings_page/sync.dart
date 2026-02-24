import 'dart:convert';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/get_path/databases_path.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/sync_test_helper.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/webdav/test_webdav.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:anx_reader/widgets/settings/webdav_switch.dart';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as path;
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:anx_reader/utils/crypto/backup_crypto.dart';

const String _prefsBackupFileName = 'anx_shared_prefs.json';
const String _backupManifestFileName = 'manifest.json';

class SyncSetting extends ConsumerStatefulWidget {
  const SyncSetting({super.key});

  @override
  ConsumerState<SyncSetting> createState() => _SyncSettingState();
}

class _SyncSettingState extends ConsumerState<SyncSetting> {
  @override
  Widget build(BuildContext context) {
    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(L10n.of(context).settingsSyncWebdav),
          tiles: [
            webdavSwitch(context, setState, ref),
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsSyncWebdav),
                leading: const Icon(Icons.cloud),
                value: Text(Prefs().getSyncInfo(SyncProtocol.webdav)['url'] ??
                    'Not set'),
                // enabled: Prefs().webdavStatus,
                onPressed: (context) async {
                  showWebdavDialog(context);
                }),
            CustomSettingsTile(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 20, 10),
                child: GestureDetector(
                  onTap: () async {
                    if (!await launchUrl(
                        Uri.parse('https://anx.anxcye.com/docs/sync/webdav'),
                        mode: LaunchMode.externalApplication)) {
                      AnxToast.show(L10n.of(context).commonFailed);
                    }
                  },
                  child: Text(
                    L10n.of(context).settingsNarrateClickForHelp,
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      decoration: TextDecoration.underline,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsSyncWebdavSyncNow),
                leading: const Icon(Icons.sync_alt),
                // value: Text(Prefs().syncDirection),
                enabled: Prefs().webdavStatus,
                onPressed: (context) {
                  chooseDirection(ref);
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).webdavOnlyWifi),
                leading: const Icon(Icons.wifi),
                initialValue: Prefs().onlySyncWhenWifi,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().onlySyncWhenWifi = value;
                  });
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncCompletedToast),
                leading: const Icon(Icons.notifications),
                initialValue: Prefs().syncCompletedToast,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().syncCompletedToast = value;
                  });
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncAutoSync),
                leading: const Icon(Icons.sync),
                initialValue: Prefs().autoSync,
                enabled: Prefs().webdavStatus,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().autoSync = value;
                  });
                }),
            SettingsTile.navigation(
                title: Text(L10n.of(context).restoreBackup),
                leading: const Icon(Icons.restore),
                onPressed: (context) {
                  ref.read(syncProvider.notifier).showBackupManagementDialog();
                })
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).exportAndImport),
          tiles: [
            SettingsTile.navigation(
                title: Text(L10n.of(context).exportAndImportExport),
                leading: const Icon(Icons.cloud_upload),
                onPressed: (context) {
                  _showExportBackupDialog(context);
                }),
            SettingsTile.navigation(
                title: Text(L10n.of(context).exportAndImportImport),
                leading: const Icon(Icons.cloud_download),
                onPressed: (context) {
                  importData();
                }),
          ],
        ),
      ],
    );
  }

  void _showDataDialog(String title) {
    Future.microtask(() {
      SmartDialog.show(
        builder: (BuildContext context) => SimpleDialog(
          title: Center(child: Text(title)),
          children: const [
            Center(
              child: CircularProgressIndicator(),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _showExportBackupDialog(BuildContext context) async {
    final l10n = L10n.of(context);

    bool includeEncryptedApiKeys = false;
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    final confirmed = await SmartDialog.show<bool>(
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text(l10n.exportAndImportExport),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: Text(l10n.backupIncludeApiKeyEncrypted),
                      value: includeEncryptedApiKeys,
                      onChanged: (value) {
                        setState(() {
                          includeEncryptedApiKeys = value;
                        });
                      },
                    ),
                    if (includeEncryptedApiKeys) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l10n.backupPassword,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l10n.backupPasswordConfirm,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.backupPasswordTip,
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => SmartDialog.dismiss(result: false),
                  child: Text(l10n.commonCancel),
                ),
                TextButton(
                  onPressed: () {
                    if (includeEncryptedApiKeys) {
                      final p1 = passwordController.text;
                      final p2 = confirmController.text;
                      if (p1.isEmpty || p1 != p2) {
                        AnxToast.show(l10n.backupPasswordMismatch);
                        return;
                      }
                    }
                    SmartDialog.dismiss(result: true);
                  },
                  child: Text(l10n.commonConfirm),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      passwordController.dispose();
      confirmController.dispose();
      return;
    }

    final password = includeEncryptedApiKeys ? passwordController.text : null;
    passwordController.dispose();
    confirmController.dispose();

    await exportData(
      context,
      includeEncryptedApiKeys: includeEncryptedApiKeys,
      password: password,
    );
  }

  Future<void> exportData(BuildContext context,
      {bool includeEncryptedApiKeys = false, String? password}) async {
    AnxLog.info('exportData: start');
    if (!mounted) return;

    _showDataDialog(L10n.of(context).exporting);

    final File prefsBackupFile = await _createPrefsBackupFile();

    final tempDir = await getAnxTempDir();
    final manifestPath = '${tempDir.path}/$_backupManifestFileName';

    Map<String, dynamic> manifest = {
      'schemaVersion': 4,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'containsEncryptedApiKeys': false,
    };

    if (includeEncryptedApiKeys) {
      try {
        final apiKeys = <String, String>{};
        for (final option in buildDefaultAiServices()) {
          final cfg = Prefs().getAiConfig(option.identifier);
          final key = (cfg['api_key'] ?? '').trim();
          if (key.isEmpty || key == 'YOUR_API_KEY') continue;
          apiKeys[option.identifier] = key;
        }

        final plaintext = jsonEncode(apiKeys);
        final secret = await encryptString(
          plaintext: plaintext,
          password: password ?? '',
        );

        manifest['containsEncryptedApiKeys'] = true;
        manifest['encryptedApiKeys'] = secret.toJson();
      } catch (e) {
        SmartDialog.dismiss();
        AnxToast.show(L10n.of(context).backupEncryptFailed);
        AnxLog.info('exportData: failed to encrypt api keys: $e');
        return;
      }
    }

    await File(manifestPath).writeAsString(jsonEncode(manifest));

    RootIsolateToken token = RootIsolateToken.instance!;
    final zipPath = await compute(createZipFile, {
      'token': token,
      'prefsBackupFilePath': prefsBackupFile.path,
      'manifestFilePath': manifestPath,
    });

    final file = File(zipPath);
    SmartDialog.dismiss();
    if (await file.exists()) {
      // SaveFileDialogParams params = SaveFileDialogParams(
      //   sourceFilePath: file.path,
      //   mimeTypesFilter: ['application/zip'],
      // );
      // final filePath = await FlutterFileDialog.saveFile(params: params);
      String fileName =
          'AnxReader-Backup-${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}-v4.zip';

      String? filePath = await saveFileToDownload(
          sourceFilePath: file.path,
          fileName: fileName,
          mimeType: 'application/zip');

      await file.delete();

      if (filePath != null) {
        AnxLog.info('exportData: Saved to: $filePath');
        AnxToast.show(L10n.of(navigatorKey.currentContext!).exportTo(filePath));
      } else {
        AnxLog.info('exportData: Cancelled');
        AnxToast.show(L10n.of(navigatorKey.currentContext!).commonCanceled);
      }
    }
  }

  Future<Map<String, String>?> _loadEncryptedApiKeysFromBackup(
      String extractPath) async {
    final l10n = L10n.of(navigatorKey.currentContext!);
    final manifestFile = File('$extractPath/$_backupManifestFileName');
    if (!await manifestFile.exists()) {
      return null;
    }

    try {
      final decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map) return null;
      final map = decoded.cast<String, dynamic>();
      final contains = map['containsEncryptedApiKeys'] == true;
      if (!contains) return null;
      final secretRaw = map['encryptedApiKeys'];
      if (secretRaw is! Map) return null;

      final secret =
          EncryptedBackupSecret.fromJson(secretRaw.cast<String, dynamic>());

      final passwordController = TextEditingController();
      final ok = await SmartDialog.show<bool>(
        builder: (ctx) => AlertDialog(
          title: Text(l10n.backupPassword),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: l10n.backupPasswordHint,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => SmartDialog.dismiss(result: false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => SmartDialog.dismiss(result: true),
              child: Text(l10n.commonConfirm),
            ),
          ],
        ),
      );

      final password = passwordController.text;
      passwordController.dispose();

      if (ok != true || password.isEmpty) {
        return null;
      }

      final plaintext = await decryptString(secret: secret, password: password);
      final keysDecoded = jsonDecode(plaintext);
      if (keysDecoded is! Map) return null;

      return keysDecoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (e) {
      AnxLog.info('importData: failed to decrypt api keys: $e');
      AnxToast.show(l10n.backupDecryptFailed);
      return null;
    }
  }

  void _applyApiKeysToPrefs(Map<String, String> apiKeys) {
    for (final entry in apiKeys.entries) {
      final id = entry.key;
      final apiKey = entry.value.trim();
      if (apiKey.isEmpty) continue;
      final cfg = Prefs().getAiConfig(id);
      cfg['api_key'] = apiKey;
      Prefs().saveAiConfig(id, cfg);
    }
  }

  Future<void> importData() async {
    AnxLog.info('importData: start');
    if (!mounted) return;

    final l10n = L10n.of(navigatorKey.currentContext!);
    final confirmed = await SmartDialog.show<bool>(
      builder: (ctx) => AlertDialog(
        title: Text(l10n.backupImportConfirmTitle),
        content: Text(l10n.backupImportConfirmBody),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(result: false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => SmartDialog.dismiss(result: true),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null) {
      return;
    }

    String? filePath = result.files.single.path;
    if (filePath == null) {
      AnxLog.info('importData: cannot get file path');
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importCannotGetFilePath);
      return;
    }

    File zipFile = File(filePath);
    if (!await zipFile.exists()) {
      AnxLog.info('importData: zip file not found');
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importCannotGetFilePath);
      return;
    }

    // Import confirmation handled before file picking.

    _showDataDialog(L10n.of(navigatorKey.currentContext!).importing);

    String pathSeparator = Platform.pathSeparator;

    Directory cacheDir = await getAnxTempDir();
    String cachePath = cacheDir.path;
    String extractPath = '$cachePath${pathSeparator}anx_reader_import';

    try {
      await Directory(extractPath).create(recursive: true);

      await compute(extractZipFile, {
        'zipFilePath': zipFile.path,
        'destinationPath': extractPath,
      });

      final decryptedApiKeys =
          await _loadEncryptedApiKeysFromBackup(extractPath);

      final ts = DateTime.now().millisecondsSinceEpoch;
      final bakSuffix = '.bak.$ts';

      String docPath = await getAnxDocumentsPath();
      final fileDir = getFileDir(path: docPath);
      final coverDir = getCoverDir(path: docPath);
      final fontDir = getFontDir(path: docPath);
      final bgimgDir = getBgimgDir(path: docPath);

      final srcFileDir = Directory('$extractPath${pathSeparator}file');
      final srcCoverDir = Directory('$extractPath${pathSeparator}cover');
      final srcFontDir = Directory('$extractPath${pathSeparator}font');
      final srcBgimgDir = Directory('$extractPath${pathSeparator}bgimg');
      final srcDbDir = Directory('$extractPath${pathSeparator}databases');

      Directory? fileBak;
      Directory? coverBak;
      Directory? fontBak;
      Directory? bgimgBak;
      Directory? dbBak;

      try {
        if (srcFileDir.existsSync()) {
          fileBak = _backupDirIfExists(fileDir, bakSuffix);
          _copyDirectorySync(srcFileDir, fileDir);
        }
        if (srcCoverDir.existsSync()) {
          coverBak = _backupDirIfExists(coverDir, bakSuffix);
          _copyDirectorySync(srcCoverDir, coverDir);
        }
        if (srcFontDir.existsSync()) {
          fontBak = _backupDirIfExists(fontDir, bakSuffix);
          _copyDirectorySync(srcFontDir, fontDir);
        }
        if (srcBgimgDir.existsSync()) {
          bgimgBak = _backupDirIfExists(bgimgDir, bakSuffix);
          _copyDirectorySync(srcBgimgDir, bgimgDir);
        }

        if (srcDbDir.existsSync()) {
          DBHelper.close();
          final dbDir = await getAnxDataBasesDir();
          dbBak = _backupDirIfExists(dbDir, bakSuffix);
          _copyDirectorySync(srcDbDir, dbDir);
          DBHelper().initDB();
        }

        await _restorePrefsFromBackup(extractPath);

        if (decryptedApiKeys != null && decryptedApiKeys.isNotEmpty) {
          _applyApiKeysToPrefs(decryptedApiKeys);
        }

        // Cleanup backups only after everything succeeds.
        _deleteDirIfExists(fileBak);
        _deleteDirIfExists(coverBak);
        _deleteDirIfExists(fontBak);
        _deleteDirIfExists(bgimgBak);
        _deleteDirIfExists(dbBak);

        AnxLog.info('importData: import success');
        AnxToast.show(
            L10n.of(navigatorKey.currentContext!).importSuccessRestartApp);
      } catch (e) {
        // Rollback best-effort.
        _rollbackDir(fileBak, fileDir);
        _rollbackDir(coverBak, coverDir);
        _rollbackDir(fontBak, fontDir);
        _rollbackDir(bgimgBak, bgimgDir);
        // Databases directory is not under documents path.
        if (dbBak != null) {
          final dbDir = await getAnxDataBasesDir();
          _rollbackDir(dbBak, dbDir);
        }
        rethrow;
      }
    } catch (e) {
      AnxLog.info('importData: error while unzipping or copying files: $e');
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).importFailed(e.toString()));
    } finally {
      SmartDialog.dismiss();
      await Directory(extractPath).delete(recursive: true);
    }
  }

  Directory? _backupDirIfExists(Directory dir, String suffix) {
    if (!dir.existsSync()) return null;
    final bakPath = '${dir.path}$suffix';
    final bakDir = Directory(bakPath);

    if (bakDir.existsSync()) {
      bakDir.deleteSync(recursive: true);
    }

    try {
      dir.renameSync(bakPath);
      return bakDir;
    } catch (e) {
      AnxLog.info('importData: failed to backup ${dir.path} -> $bakPath: $e');
      rethrow;
    }
  }

  void _rollbackDir(Directory? bakDir, Directory targetDir) {
    if (bakDir == null) return;

    try {
      if (targetDir.existsSync()) {
        targetDir.deleteSync(recursive: true);
      }
      if (bakDir.existsSync()) {
        bakDir.renameSync(targetDir.path);
      }
    } catch (e) {
      AnxLog.info('importData: rollback failed for ${targetDir.path}: $e');
    }
  }

  void _deleteDirIfExists(Directory? dir) {
    if (dir == null) return;
    try {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    } catch (e) {
      // Best effort; do not fail the import.
      AnxLog.info('importData: failed to delete backup ${dir.path}: $e');
    }
  }

  void _copyDirectorySync(Directory source, Directory destination) {
    if (!source.existsSync()) {
      return;
    }
    if (destination.existsSync()) {
      destination.deleteSync(recursive: true);
    }
    destination.createSync(recursive: true);
    source.listSync(recursive: false).forEach((entity) {
      final newPath = destination.path +
          Platform.pathSeparator +
          path.basename(entity.path);
      if (entity is File) {
        entity.copySync(newPath);
      } else if (entity is Directory) {
        _copyDirectorySync(entity, Directory(newPath));
      }
    });
  }
}

Future<String> createZipFile(Map<String, dynamic> params) async {
  RootIsolateToken token = params['token'];
  final String prefsBackupFilePath = params['prefsBackupFilePath'];
  final String? manifestFilePath = params['manifestFilePath'] as String?;
  final File prefsBackupFile = File(prefsBackupFilePath);
  final File? manifestFile =
      manifestFilePath == null ? null : File(manifestFilePath);
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final date =
      '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
  final zipPath = '${(await getAnxTempDir()).path}/AnxReader-Backup-$date.zip';
  final docPath = await getAnxDocumentsPath();
  final directoryList = [
    getFileDir(path: docPath),
    getCoverDir(path: docPath),
    getFontDir(path: docPath),
    getBgimgDir(path: docPath),
    if (!AnxPlatform.isOhos) await getAnxDataBasesDir(),
    // await getAnxSharedPrefsDir(),
    // await getAnxShredPrefsFile(),
    prefsBackupFile,
  ];

  AnxLog.info('exportData: directoryList: $directoryList');

  final encoder = ZipFileEncoder();
  encoder.create(zipPath);

  if (AnxPlatform.isOhos) {
    final dbDir = await getAnxDataBasesDir();
    final dbFile = File('${dbDir.path}/app_database.db');
    if (await dbFile.exists()) {
      await encoder.addFile(dbFile, 'databases/app_database.db');
    }
  } else {
    final dbDir = await getAnxDataBasesDir();
    await encoder.addDirectory(dbDir);
  }

  for (final dir in directoryList) {
    if (dir is Directory) {
      await encoder.addDirectory(dir);
    } else if (dir is File) {
      await encoder.addFile(dir);
    }
  }

  if (manifestFile != null && await manifestFile.exists()) {
    await encoder.addFile(manifestFile, _backupManifestFileName);
  }

  encoder.close();
  if (await prefsBackupFile.exists()) {
    await prefsBackupFile.delete();
  }
  if (manifestFile != null && await manifestFile.exists()) {
    await manifestFile.delete();
  }
  return zipPath;
}

Future<void> extractZipFile(Map<String, String> params) async {
  final zipFilePath = params['zipFilePath']!;
  final destinationPath = params['destinationPath']!;

  final input = InputFileStream(zipFilePath);
  try {
    final archive = ZipDecoder().decodeBuffer(input);
    extractArchiveToDiskSync(archive, destinationPath);
    archive.clearSync();
  } finally {
    await input.close();
  }
}

Future<File> _createPrefsBackupFile() async {
  final Directory tempDir = await getAnxTempDir();
  final File backupFile = File('${tempDir.path}/$_prefsBackupFileName');
  final Map<String, dynamic> prefsMap = await Prefs().buildPrefsBackupMap();
  await backupFile.writeAsString(jsonEncode(prefsMap));
  return backupFile;
}

Future<bool> _restorePrefsFromBackup(String extractPath) async {
  final File backupFile = File('$extractPath/$_prefsBackupFileName');
  if (!await backupFile.exists()) {
    return false;
  }
  try {
    final dynamic decoded = jsonDecode(await backupFile.readAsString());
    if (decoded is Map<String, dynamic>) {
      await Prefs().applyPrefsBackupMap(decoded);
      return true;
    }
    AnxLog.info('importData: prefs backup has unexpected format');
  } catch (e) {
    AnxLog.info('importData: failed to restore prefs backup: $e');
  }
  return false;
}

void showWebdavDialog(BuildContext context) {
  final title = L10n.of(context).settingsSyncWebdav;
  // final prefs = Prefs().saveWebdavInfo;
  final webdavInfo = Prefs().getSyncInfo(SyncProtocol.webdav);
  final webdavUrlController = TextEditingController(text: webdavInfo['url']);
  final webdavUsernameController =
      TextEditingController(text: webdavInfo['username']);
  final webdavPasswordController =
      TextEditingController(text: webdavInfo['password']);
  Widget buildTextField(String labelText, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        obscureText: labelText == L10n.of(context).settingsSyncWebdavPassword
            ? true
            : false,
        controller: controller,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: labelText,
        ),
      ),
    );
  }

  showDialog(
    context: context,
    builder: (context) {
      return SimpleDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.all(20),
        children: [
          buildTextField(
              L10n.of(context).settingsSyncWebdavUrl, webdavUrlController),
          buildTextField(L10n.of(context).settingsSyncWebdavUsername,
              webdavUsernameController),
          buildTextField(L10n.of(context).settingsSyncWebdavPassword,
              webdavPasswordController),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => SyncTestHelper.handleFullTestConnection(
                  context,
                  protocol: SyncProtocol.webdav,
                  config: {
                    'url': webdavUrlController.text.trim(),
                    'username': webdavUsernameController.text,
                    'password': webdavPasswordController.text,
                  },
                ),
                icon: const Icon(Icons.wifi_find),
                label: Text(L10n.of(context).settingsSyncWebdavTestConnection),
              ),
              TextButton(
                onPressed: () {
                  webdavInfo['url'] = webdavUrlController.text.trim();
                  webdavInfo['username'] = webdavUsernameController.text;
                  webdavInfo['password'] = webdavPasswordController.text;
                  Prefs().setSyncInfo(SyncProtocol.webdav, webdavInfo);
                  SyncClientFactory.initializeCurrentClient();
                  Navigator.pop(context);
                },
                child: Text(L10n.of(context).commonSave),
              ),
            ],
          ),
        ],
      );
    },
  );
}
