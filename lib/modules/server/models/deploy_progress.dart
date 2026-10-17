enum DeployStageStatus { active, done, failed }

class DeployStage {
  const DeployStage(
    this.id,
    this.title,
    this.status, {
    this.detail = '',
    this.percent,
  });

  final String id;
  final String title;
  final DeployStageStatus status;
  final String detail;
  final int? percent;
}

class DeployProgress {
  final startup = <DeployStage>[];
  final update = <DeployStage>[];
  bool showUpdate = false;
  bool hasUpdate = false;
  bool _updating = false;
  int retry = 0;
  String summary = '准备启动 OAS';

  void beginAttempt(int attempt) {
    retry = attempt;
    startup.clear();
    update.clear();
    hasUpdate = false;
    _updating = false;
    summary = '读取启动配置';
    _stage(
      startup,
      'prepare',
      summary,
      detail: attempt == 0 ? '' : '正在进行第 $attempt / 5 次重试',
    );
  }

  void checkingUpdate() {
    _updating = true;
    summary = '检查 OAS 更新';
    _stage(startup, 'check', summary);
    if (showUpdate) _stage(update, 'check', '重新检查更新');
  }

  void updateAvailable() {
    if (hasUpdate) return;
    showUpdate = true;
    hasUpdate = true;
    _updating = true;
    summary = '正在更新 OAS，完成后继续启动';
    _stage(startup, 'check', '等待更新完成');
    _stage(update, 'check', '发现 OAS 更新', status: DeployStageStatus.done);
    _stage(update, 'fetch', '连接远程仓库');
  }

  void noUpdate({bool disabled = false}) {
    _updating = false;
    summary = disabled ? '已关闭自动更新，继续启动' : '当前已是最新版本，继续启动';
    _stage(
      startup,
      'check',
      disabled ? '跳过自动更新' : '当前已是最新版本',
      status: DeployStageStatus.done,
    );
    if (showUpdate) {
      _stage(
        update,
        'check',
        disabled ? '已跳过自动更新' : '检查完成，无需更新',
        status: DeployStageStatus.done,
      );
    }
  }

  void fetched() {
    if (!hasUpdate) return;
    _stage(update, 'fetch_done', '更新文件接收完成', status: DeployStageStatus.done);
  }

  void installing() {
    _updating = true;
    if (hasUpdate) {
      _stage(update, 'apply', '应用更新文件');
    } else {
      summary = '准备 OAS 运行环境';
      _stage(startup, 'environment', summary);
    }
  }

  void updateFinished() {
    _updating = false;
    if (hasUpdate) {
      _stage(update, 'finished', 'OAS 更新完成', status: DeployStageStatus.done);
      _stage(startup, 'check', 'OAS 更新完成', status: DeployStageStatus.done);
    }
  }

  void environment() {
    updateFinished();
    summary = '检查 OAS 运行环境';
    _stage(startup, 'environment', summary);
  }

  void startingService() {
    updateFinished();
    summary = '正在启动 OAS 后台服务';
    _stage(startup, 'service', summary);
  }

  void connecting() {
    summary = '等待 OAS 服务就绪并连接';
    // 发起进程不代表服务已经启动成功。
    _stage(startup, 'service', summary);
  }

  void connected() {
    summary = 'OAS 连接成功';
    _stage(startup, 'service', summary, status: DeployStageStatus.done);
  }

  void failed(String reason, {bool? duringUpdate}) {
    final isUpdate = duringUpdate ?? _updating;
    if (isUpdate) showUpdate = true;
    final target = isUpdate ? update : startup;
    final current = target.isEmpty ? null : target.last;
    _stage(
      target,
      current?.id ?? 'failure',
      current?.title ?? '检查 OAS 更新',
      status: DeployStageStatus.failed,
      detail: reason,
    );
    summary = isUpdate ? 'OAS 更新失败' : 'OAS 启动失败';
  }

  void retrying(int attempt, Duration delay) {
    retry = attempt;
    final target = showUpdate && _updating ? update : startup;
    final current = target.isEmpty ? null : target.last;
    _stage(
      target,
      current?.id ?? 'retry',
      current?.title ?? summary,
      status: DeployStageStatus.failed,
      detail: '${delay.inSeconds} 秒后进行第 $attempt / 5 次重试',
    );
    summary = '等待自动重试（$attempt / 5）';
  }

  bool consume(String raw) {
    final line = raw.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
    final lower = line.toLowerCase();
    if (_updating &&
        RegExp(r'\bUPDATE\s+FAILED\b', caseSensitive: false).hasMatch(line)) {
      failed('更新程序报告失败，将按设置自动重试', duringUpdate: true);
      return true;
    }
    if (_updating && lower.contains('show version')) {
      updateFinished();
      return true;
    }
    if (lower.contains('update dependencies') ||
        lower.contains('check python')) {
      environment();
      return true;
    }
    if (!hasUpdate || !_updating) return false;
    final matches = RegExp(
      r'(Counting objects|Compressing objects|Receiving objects|Resolving deltas|Updating files):\s*(\d{1,3})%',
      caseSensitive: false,
    ).allMatches(line);
    var changed = false;
    for (final match in matches) {
      final id = match.group(1)!.toLowerCase();
      final percent = int.parse(match.group(2)!);
      if (percent > 100) continue;
      const names = {
        'counting objects': '统计更新文件',
        'compressing objects': '远程准备文件',
        'receiving objects': '接收更新文件',
        'resolving deltas': '处理更新文件',
        'updating files': '应用更新文件',
      };
      final existing = update.where((stage) => stage.id == id).firstOrNull;
      if (existing?.percent != null && percent <= existing!.percent!) continue;
      _stage(
        update,
        id,
        names[id]!,
        percent: percent,
        status: percent == 100
            ? DeployStageStatus.done
            : DeployStageStatus.active,
      );
      changed = true;
    }
    return changed;
  }

  void _stage(
    List<DeployStage> stages,
    String id,
    String title, {
    DeployStageStatus status = DeployStageStatus.active,
    String detail = '',
    int? percent,
  }) {
    final index = stages.indexWhere((stage) => stage.id == id);
    if (index < 0) {
      for (var i = 0; i < stages.length; i++) {
        final previous = stages[i];
        if (previous.status == DeployStageStatus.active) {
          stages[i] = DeployStage(
            previous.id,
            previous.title,
            DeployStageStatus.done,
            detail: previous.detail,
            percent: previous.percent,
          );
        }
      }
      stages.add(
        DeployStage(id, title, status, detail: detail, percent: percent),
      );
    } else {
      stages[index] = DeployStage(
        id,
        title,
        status,
        detail: detail,
        percent: percent,
      );
    }
  }
}
