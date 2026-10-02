import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/service/oas_source_service.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/translation/i18n_content.dart';

class OasSourceButton extends StatelessWidget {
  const OasSourceButton({super.key});

  @override
  Widget build(BuildContext context) {
    final service = Get.find<OasSourceService>();
    return Obx(() {
      final branch = service.branch.value;
      return OutlinedButton(
        onPressed: () => Get.dialog<void>(
          const OasSourceDialog(),
          barrierDismissible: false,
        ),
        child: Text(branch.isEmpty
            ? I18n.oasSource.tr
            : '${I18n.oasSource.tr} · $branch'),
      );
    });
  }
}

class OasSourceDialog extends StatefulWidget {
  const OasSourceDialog({super.key});

  @override
  State<OasSourceDialog> createState() => _OasSourceDialogState();
}

class _OasSourceDialogState extends State<OasSourceDialog> {
  final _service = Get.find<OasSourceService>();
  final _repository = TextEditingController();
  String _path = '';
  String _branch = 'mine';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _path = _service.path.value;
    if (_path.isNotEmpty) _load(_path);
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  Future<void> _load(String path) async {
    try {
      final source = await _service.read(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _repository.text = source.repository;
        _branch = source.branch;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _chooseFile() async {
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['yaml'],
    );
    final path = selected?.files.single.path;
    if (path != null) await _load(path);
  }

  Future<bool> _confirmRunningTasks() async {
    final scripts = Get.find<ScriptService>().scriptModelMap.values;
    if (!scripts.any((script) => script.state.value == ScriptState.running)) {
      return true;
    }
    return await Get.dialog<bool>(
          AlertDialog(
            content: Text(I18n.oasRunningConfirm.tr),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: false),
                child: Text(I18n.cancel.tr),
              ),
              FilledButton(
                onPressed: () => Get.back(result: true),
                child: Text(I18n.confirm.tr),
              ),
            ],
          ),
          barrierDismissible: false,
        ) ??
        false;
  }

  Future<void> _save({required bool restart}) async {
    if (_busy) return;
    if (restart && !await _confirmRunningTasks()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.save(
        _path,
        repository: _repository.text,
        branch: _branch,
      );
      if (!mounted) return;
      Get.back();
      if (!restart) {
        Get.snackbar(I18n.oasSource.tr, I18n.oasSourceSaved.tr);
        return;
      }
      final started = await _service.restartBoth(_path);
      if (!started) {
        Get.snackbar(I18n.oasSource.tr, I18n.oasRestartFailed.tr);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      } else {
        Get.snackbar(I18n.oasSource.tr, e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branches = <String>{'mine', 'personal', _branch}.toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 630),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(I18n.oasSource.tr,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              Text(I18n.oasDeployPath.tr),
              const SizedBox(height: 7),
              Row(children: [
                Expanded(
                  child: Text(
                    _path.isEmpty ? '—' : _path,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _chooseFile,
                  child: Text(I18n.oasChooseFile.tr),
                ),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: _repository,
                enabled: !_busy && _path.isNotEmpty,
                decoration: InputDecoration(
                  labelText: I18n.oasRepository.tr,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
      DropdownButtonFormField<String>(
                initialValue: _branch,
                decoration: InputDecoration(
                  labelText: I18n.oasBranch.tr,
                  border: const OutlineInputBorder(),
                ),
                items: branches
                    .map((branch) => DropdownMenuItem(
                          value: branch,
                          child: Text(branch),
                        ))
                    .toList(),
                onChanged: _busy ? null : (value) {
                  if (value != null) setState(() => _branch = value);
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                )),
              ],
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Get.back(),
                    child: Text(I18n.cancel.tr),
                  ),
                  OutlinedButton(
                    onPressed: _busy || _path.isEmpty
                        ? null
                        : () => _save(restart: false),
                    child: Text(I18n.oasSaveOnly.tr),
                  ),
                  FilledButton(
                    onPressed: _busy || _path.isEmpty
                        ? null
                        : () => _save(restart: true),
                    child: Text(I18n.oasSaveAndRestart.tr),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
