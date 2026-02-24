import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_input_quick_prompt.dart';
import 'package:anx_reader/widgets/delete_confirm.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class AiQuickPromptsEditor extends StatefulWidget {
  const AiQuickPromptsEditor({super.key});

  @override
  State<AiQuickPromptsEditor> createState() => _AiQuickPromptsEditorState();
}

class _AiQuickPromptsEditorState extends State<AiQuickPromptsEditor> {
  late List<AiInputQuickPrompt> _prompts;

  @override
  void initState() {
    super.initState();
    _prompts = List.from(Prefs().aiInputQuickPrompts);
  }

  void _save() {
    Prefs().aiInputQuickPrompts = _prompts;
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final item = _prompts.removeAt(oldIndex);
    _prompts.insert(newIndex, item);
    // Update order values.
    for (var i = 0; i < _prompts.length; i++) {
      _prompts[i] = _prompts[i].copyWith(order: i);
    }
    _save();
    setState(() {});
  }

  void _toggleEnabled(int index) {
    _prompts[index] = _prompts[index].copyWith(
      enabled: !_prompts[index].enabled,
    );
    _save();
    setState(() {});
  }

  void _delete(int index) {
    _prompts.removeAt(index);
    for (var i = 0; i < _prompts.length; i++) {
      _prompts[i] = _prompts[i].copyWith(order: i);
    }
    _save();
    setState(() {});
  }

  void _edit(int index) async {
    final prompt = _prompts[index];
    final labelController = TextEditingController(text: prompt.label);
    final textController = TextEditingController(text: prompt.prompt);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.of(context).settingsAiQuickPromptsEdit),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: InputDecoration(
                  labelText: L10n.of(context).settingsAiQuickPromptsLabel,
                  border: const OutlineInputBorder(),
                ),
                maxLength: 20,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                decoration: InputDecoration(
                  labelText: L10n.of(context).settingsAiQuickPromptsText,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
                minLines: 2,
                maxLength: 500,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(L10n.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L10n.of(context).commonSave),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      _prompts[index] = prompt.copyWith(
        label: labelController.text.trim(),
        prompt: textController.text.trim(),
      );
      _save();
      setState(() {});
    }
    labelController.dispose();
    textController.dispose();
  }

  void _add() async {
    final labelController = TextEditingController();
    final textController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.of(context).settingsAiQuickPromptsAdd),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: InputDecoration(
                  labelText: L10n.of(context).settingsAiQuickPromptsLabel,
                  border: const OutlineInputBorder(),
                ),
                maxLength: 20,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                decoration: InputDecoration(
                  labelText: L10n.of(context).settingsAiQuickPromptsText,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
                minLines: 2,
                maxLength: 500,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(L10n.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L10n.of(context).commonAdd),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final newPrompt = AiInputQuickPrompt(
        id: const Uuid().v4(),
        label: labelController.text.trim(),
        prompt: textController.text.trim(),
        enabled: true,
        order: _prompts.length,
      );
      _prompts.add(newPrompt);
      _save();
      setState(() {});
    }
    labelController.dispose();
    textController.dispose();
  }

  void _resetToDefaults() {
    Prefs().clearAiInputQuickPrompts();
    _prompts = [];
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsAiQuickPrompts),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.commonReset,
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l10n.commonConfirm),
                  content: Text(l10n.settingsAiQuickPromptsResetConfirm),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l10n.commonCancel),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _resetToDefaults();
                      },
                      child: Text(l10n.commonConfirm),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _prompts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.settingsAiQuickPromptsEmpty,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.settingsAiQuickPromptsAdd),
                  ),
                ],
              ),
            )
          : ReorderableListView(
              header: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.settingsAiQuickPromptsHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              onReorder: _reorder,
              children: [
                for (var i = 0; i < _prompts.length; i++)
                  ListTile(
                    key: ValueKey(_prompts[i].id),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle),
                    ),
                    title: Text(
                      _prompts[i].label,
                      style: _prompts[i].enabled
                          ? null
                          : const TextStyle(
                              color: Colors.grey,
                              decoration: TextDecoration.lineThrough,
                            ),
                    ),
                    subtitle: Text(
                      _prompts[i].prompt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: _prompts[i].enabled,
                          onChanged: (_) => _toggleEnabled(i),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _edit(i),
                        ),
                        DeleteConfirm(
                          delete: () => _delete(i),
                          useTextButton: true,
                        ),
                      ],
                    ),
                    onTap: () => _edit(i),
                  ),
              ],
            ),
      floatingActionButton: _prompts.isNotEmpty
          ? FloatingActionButton(
              onPressed: _add,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
