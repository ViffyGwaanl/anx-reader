[English](#English)
[简体中文](#简体中文)
[Русский](#русский)

# English

## Developer: build fails / analyzer errors about generated files

If you see errors like:

- `Target of URI doesn't exist: package:anx_reader/l10n/generated/L10n.dart`
- missing `*.g.dart` / `toJson()` not found

you likely need to regenerate code:

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
```

## iOS: Archive shows old build number (TestFlight)

If you changed `pubspec.yaml` `version: x.y.z+BUILD` but Xcode Archive still shows the old build number:

- Check `ios/Flutter/Generated.xcconfig` contains the new `FLUTTER_BUILD_NUMBER`.
- This file is generated and may not refresh with `flutter pub get` alone.

Suggested fix:

```bash
flutter clean
flutter pub get
flutter build ios --release --no-codesign
```

Then Archive again.

## Translation: AI full-text translation looks weird or fails

- Full-text translation works best for reflowable formats (ePub, txt). PDF text layers are often fragmented or missing.
- If you use **AI** translation for full-text translation:
  - prefer translating a **short selection** first to confirm the provider works
  - if long paragraphs fail, reduce the translated chunk size (or try a non-AI provider)
- For scanned PDFs (no selectable text): OCR is required before translation can be reliable.

## Unable to Import Books
- Ensure the book format is supported. Please check the supported formats in the [README](../README.md).
- Ensure the book file is not corrupted. You can try using other readers to confirm if the file is normal.
- Ensure the file path does not contain special characters (such as spaces, “/”, etc.).
- Check the device's webview version. If importing books fails, click the bottom right corner of the interface -> Settings -> More Settings -> Advanced -> Logs, scroll down, and in the last few entries, you can see something like `INFO^*^ 2024-08-09 17:51:22.573971^*^ [Webview: Mozilla/5.0 (Linux; Android 13; *** Build/TKQ1.220829.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/128.0.6613.25 Mobile Safari/537.36]:null`, where Chrome/128.0.6613.25 is the webview version. If the version number is relatively low, it may cause import failures. You can try upgrading the webview version.

## How to Obtain Log Files
After **reproducing the issue**, click on the bottom right corner of the interface: Settings -> More Settings -> Advanced -> Logs. Click the button in the top right corner to export the log file. Send the log file to the developers to help them better assist you in resolving the issue.

For some issues, you may need to first disable the "Clear logs on startup" option in the "Advanced" interface to export the log file after reproducing the issue.

# 简体中文

## 开发者：编译失败 / 分析器提示缺少生成文件

如果你遇到类似错误：

- `Target of URI doesn't exist: package:anx_reader/l10n/generated/L10n.dart`
- 缺少 `*.g.dart` / 提示 `toJson()` 不存在

通常是因为尚未生成代码。可执行：

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
```

## iOS：Archive 仍显示旧的 Build Number（TestFlight）

如果你改了 `pubspec.yaml` 的 `version: x.y.z+BUILD`，但 Xcode Archive 里仍然显示旧的 Build Number：

- 检查 `ios/Flutter/Generated.xcconfig` 中的 `FLUTTER_BUILD_NUMBER` 是否已更新。
- 该文件是 Flutter 自动生成的，仅 `flutter pub get` 有时不会刷新。

建议执行：

```bash
flutter clean
flutter pub get
flutter build ios --release --no-codesign
```

然后再 Archive。

## 翻译：AI 全文翻译效果怪 / 无法翻译

- 全文翻译对可重排格式（EPUB、TXT）效果更好；PDF 的文字层常常是碎片化或缺失的。
- 如果你使用 **AI** 作为全文翻译服务：
  - 建议先用“选中翻译”翻译一小段，确认服务商配置可用
  - 如果长段落容易失败，可降低单次翻译长度（或切换到非 AI 翻译服务）
- 扫描版 PDF（不可选中文字）需要 OCR 才能获得可靠的翻译/问答效果。

## 无法导入书籍

- 确保书籍格式支持，请从[README](../README_zh.md)中查看支持的格式。
- 确保书籍文件没有损坏，可以尝试使用其他阅读器确认文件是否正常。
- 确保文件路径没有特殊字符(如空格、”/“ 等)。
- 检查设备 webview 版本，导入书籍失败后，点击界面右下角设置 -> 更多设置 -> 高级 -> 日志，向下滑动，在最后几条中可以看到类似`INFO^*^ 2024-08-09 17:51:22.573971^*^ [Webview: Mozilla/5.0 (Linux; Android 13; *** Build/TKQ1.220829.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/128.0.6613.25 Mobile Safari/537.36]:null` ，其中`Chrome/128.0.6613.25` 为 webview 版本，如果版本号较低，可能会导致导入失败，可以尝试升级到最新 webview 版本。

## 如何得到日志文件
在**重现问题后**，点击界面右下角设置 -> 更多设置 -> 高级 -> 日志，点击右上角按钮即可导出日志文件，将日志文件发送给开发者，以便更好地帮助您解决问题。

部分问题可能需要先关闭“高级”界面的“启动时清空日志”选项，以便在重现问题后导出日志文件。

# Русский
## Не удаётся импортировать книги
- Убедитесь, что формат книги поддерживается. Пожалуйста, проверьте поддерживаемые форматы в [README](../README.md).
- Проверьте, что файл книги не повреждён. Вы можете попробовать открыть его в других приложениях для чтения, чтобы убедиться, что файл в порядке.
- Убедитесь, что путь к файлу не содержит специальных символов (например, пробелов, «/» и т.д.).
- Проверьте версию WebView на устройстве. Если импорт книг не удаётся, нажмите в правом нижнем углу интерфейса: Настройки -> Дополнительные настройки -> Расширенные -> Логи, пролистайте вниз и в последних записях вы увидите что-то вроде `INFO^*^ 2024-08-09 17:51:22.573971^*^ [Webview: Mozilla/5.0 (Linux; Android 13; *** Build/TKQ1.220829.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/128.0.6613.25 Mobile Safari/537.36]:null`, где Chrome/128.0.6613.25 — это версия WebView. Если номер версии низкий, это может вызывать сбои при импорте. Попробуйте обновить WebView до последней версии.

## Как получить файлы логов
После **повторения проблемы** нажмите в правом нижнем углу интерфейса: Настройки -> Дополнительные настройки -> Расширенные -> Логи. В правом верхнем углу нажмите кнопку экспорта файла лога. Отправьте этот файл разработчикам, чтобы им было легче помочь вам решить проблему.

Для некоторых проблем может потребоваться сначала отключить опцию "Очистка логов при запуске" в разделе "Расширенные", чтобы после повторения проблемы можно было экспортировать файл логов.
