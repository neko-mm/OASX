import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:oasx/api/api_client.dart';
import 'package:oasx/modules/common/models/config_drag_payload.dart';
import 'package:oasx/modules/home/models/config_model.dart';
import 'package:oasx/modules/home/models/home_workbench_layout.dart';
import 'package:oasx/modules/settings/controllers/settings_controller.dart';
import 'package:oasx/modules/common/models/storage_key.dart';
import 'package:oasx/service/script_service.dart';
import 'package:oasx/service/locale_service.dart';
import 'package:oasx/translation/i18n_content.dart';
import 'package:oasx/utils/platform_utils.dart';
import 'package:oasx/utils/time_utils.dart';
import 'package:oasx/modules/args/index.dart';
import 'package:oasx/modules/server/index.dart';

part 'dashboard_controller_linking.dart';
part 'dashboard_controller_drag_copy.dart';
part 'dashboard_controller_layout.dart';
part 'dashboard_controller_startup.dart';
part 'dashboard_controller_workspace.dart';

/// Abstracts dashboard persistence so tests can avoid platform storage.
abstract class HomeDashboardStorage {
  /// Reads one persisted value.
  dynamic read(String key);

  /// Writes one persisted value.
  void write(String key, dynamic value);
}

/// Default storage backed by GetStorage.
class GetStorageHomeDashboardStorage implements HomeDashboardStorage {
  /// Creates one GetStorage-backed adapter.
  GetStorageHomeDashboardStorage() : _storage = GetStorage();

  /// Underlying persistent store.
  final GetStorage _storage;

  @override
  dynamic read(String key) {
    return _storage.read(key);
  }

  @override
  void write(String key, dynamic value) {
    _storage.write(key, value);
  }
}

/// Defines the visible dashboard health state for a script.
enum HomeScriptStateFilter {
  all,
  running,
  abnormal,
  stopped,
  offline,
}

/// Defines the visible page when the workbench collapses to a single pane.
enum HomeWorkbenchPage {
  scripts,
  workspace,
}

/// Defines the visible home workbench tab for the active script.
enum HomeWorkbenchTab {
  status,
  tasks,
  stats,
  logs,
  clicks,
}

/// Returns whether the tab belongs to the right desktop sidebar.
bool isHomeWorkbenchSidebarTab(HomeWorkbenchTab value) {
  return value == HomeWorkbenchTab.stats ||
      value == HomeWorkbenchTab.logs ||
      value == HomeWorkbenchTab.clicks;
}

/// Records which workbench tab opened the task parameter editor.
enum HomeTaskParameterEntrySource {
  overview,
  tasks,
}

/// Defines the task catalog filter shown in the active script workspace.
enum HomeTaskCatalogFilter {
  all,
  enabled,
  disabled,
}

/// 一条任务操作结果；左侧状态带逐条显示，不合并。
class HomeTaskFeedback {
  const HomeTaskFeedback({
    required this.taskName,
    required this.success,
    required this.time,
    this.resultText,
  });

  final String taskName;
  final bool success;
  final DateTime time;
  final String? resultText;
}

/// Returns the visible workbench tabs for the active layout mode.
List<HomeWorkbenchTab> resolveHomeWorkbenchTabs(
  HomeWorkbenchLayoutMode mode,
) {
  if (mode == HomeWorkbenchLayoutMode.threePane) {
    return const [
      HomeWorkbenchTab.status,
      HomeWorkbenchTab.tasks,
    ];
  }
  return const [
    HomeWorkbenchTab.status,
    HomeWorkbenchTab.tasks,
    HomeWorkbenchTab.logs,
    HomeWorkbenchTab.stats,
    HomeWorkbenchTab.clicks,
  ];
}

/// Returns the visible right-sidebar tabs for the active layout mode.
List<HomeWorkbenchTab> resolveHomeWorkbenchSidebarTabs(
  HomeWorkbenchLayoutMode mode,
) {
  if (mode != HomeWorkbenchLayoutMode.threePane) {
    return const [];
  }
  return const [
    HomeWorkbenchTab.logs,
    HomeWorkbenchTab.stats,
    HomeWorkbenchTab.clicks,
  ];
}

class HomeDashboardController extends GetxController {
  HomeDashboardController({
    HomeDashboardStorage? storage,
  }) : _storage = storage ?? GetStorageHomeDashboardStorage();

  final HomeDashboardStorage _storage;
  static bool _hasCheckedStartupConnection = false;
  Worker? _workspaceSyncWorker;
  final controlScriptList = <String>[].obs;
  final isBatchSwitching = false.obs;
  final isStartupChecking = false.obs;
  final isStartupConnectionFailed = false.obs;
  final isStartupAutoDeploying = false.obs;
  final startupLoadingMessage = ''.obs;
  final isLinkModeEnabled = false.obs;
  final linkedScriptList = <String>[].obs;
  final searchQuery = ''.obs;
  final stateFilter = HomeScriptStateFilter.all.obs;
  final activeScriptName = ''.obs;
  final selectedScriptList = <String>[].obs;
  final workbenchPage = HomeWorkbenchPage.scripts.obs;
  final workbenchCollectionWidth = kHomeWorkbenchDefaultCollectionWidth.obs;
  final workbenchSplitRatio = kHomeWorkbenchDefaultSplitRatio.obs;
  final workbenchLayoutMode = HomeWorkbenchLayoutMode.singlePane.obs;
  final activeWorkbenchTab = HomeWorkbenchTab.status.obs;
  final _lastPrimaryWorkbenchTab = HomeWorkbenchTab.status.obs;
  final activeWorkbenchSidebarTab = HomeWorkbenchTab.logs.obs;
  final taskCatalogFilter = HomeTaskCatalogFilter.all.obs;
  final activeTaskName = ''.obs;
  final activeDragPayload = Rxn<ConfigDragPayload>();
  final pendingDragCopyTargets = <String>[].obs;
  final taskFeedbacks = <HomeTaskFeedback>[].obs;
  final Queue<HomeTaskFeedback> _taskFeedbackQueue = Queue<HomeTaskFeedback>();
  final Map<HomeTaskFeedback, Timer> _taskFeedbackTimers = {};
  final _taskParameterEntrySource = Rxn<HomeTaskParameterEntrySource>();
  final _taskAvailabilityCache = <String, bool>{};

  ScriptService get _scriptService => Get.find<ScriptService>();

  @override
  void onInit() {
    _loadSelection();
    _loadWorkbenchCollectionWidth();
    _loadWorkbenchSplitRatio();
    syncWorkspaceState();
    _workspaceSyncWorker = everAll([
      _scriptService.scriptOrderList,
      _scriptService.scriptModelMap,
    ], (_) {
      syncWorkspaceState();
    });
    super.onInit();
  }

  @override
  void onClose() {
    for (final timer in _taskFeedbackTimers.values) {
      timer.cancel();
    }
    _taskFeedbackTimers.clear();
    _taskFeedbackQueue.clear();
    taskFeedbacks.clear();
    _workspaceSyncWorker?.dispose();
    _workspaceSyncWorker = null;
    super.onClose();
  }

  void showTaskFeedback(
    String taskName, {
    required bool success,
    String? resultText,
  }) {
    _taskFeedbackQueue.add(HomeTaskFeedback(
      taskName: taskName,
      success: success,
      time: DateTime.now(),
      resultText: resultText,
    ));
    _fillTaskFeedbackSlots();
  }

  void _fillTaskFeedbackSlots() {
    while (taskFeedbacks.length < 2 && _taskFeedbackQueue.isNotEmpty) {
      final next = _taskFeedbackQueue.removeFirst();
      taskFeedbacks.add(next);
      _taskFeedbackTimers[next] = Timer(
        Duration(milliseconds: next.success ? 1800 : 3200),
        () {
          _taskFeedbackTimers.remove(next);
          taskFeedbacks.remove(next);
          _fillTaskFeedbackSlots();
        },
      );
    }
  }

  void setControlScripts(Iterable<String> scripts) {
    final normalized = scripts
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    controlScriptList.value = normalized;
    _storage.write(
      StorageKey.homeControlScriptList.name,
      jsonEncode(controlScriptList.toList()),
    );
  }

  void _loadSelection() {
    final raw = _storage.read(StorageKey.homeControlScriptList.name);
    if (raw == null) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }
      setControlScripts(decoded.map((e) => e.toString()));
    } catch (_) {}
  }

  bool isAllControlScriptsRunning() {
    final scripts = validControlScripts;
    if (scripts.isEmpty) {
      return false;
    }
    return scripts.every(
      (name) =>
          _scriptService.scriptModelMap.containsKey(name) &&
          _scriptService.isRunning(name),
    );
  }

  Future<void> toggleAllControlScripts(bool enable) async {
    if (isBatchSwitching.value) {
      return;
    }
    final scripts = validControlScripts;
    if (scripts.isEmpty) {
      return;
    }

    isBatchSwitching.value = true;
    try {
      if (enable) {
        for (final name in scripts) {
          await _scriptService.startScript(name);
        }
      } else {
        for (final name in scripts) {
          await _scriptService.stopScript(name);
        }
      }
    } finally {
      isBatchSwitching.value = false;
    }
  }

  List<String> get validControlScripts => controlScriptList
      .where((name) => _scriptService.scriptModelMap.containsKey(name))
      .toList();

  int get validControlScriptCount => validControlScripts.length;
}
