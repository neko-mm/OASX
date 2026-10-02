import 'package:oasx/modules/server/models/deploy_yaml_document.dart';

/// The two OAS Git values shown by the quick source switcher.
class OasSourceConfig {
  const OasSourceConfig({required this.repository, required this.branch});

  final String repository;
  final String branch;

  static OasSourceConfig read(String content) {
    final values = _gitValues(DeployYamlDocument.parse(content));
    return OasSourceConfig(
      repository: _unquote(values.repository.value),
      branch: _unquote(values.branch.value),
    );
  }

  /// Changes only Deploy.Git.Repository and Deploy.Git.Branch.
  static String update(
    String content, {
    required String repository,
    required String branch,
  }) {
    final cleanRepository = repository.trim();
    final cleanBranch = branch.trim();
    if (!_validRepository(cleanRepository) || !_validBranch(cleanBranch)) {
      throw const FormatException('仓库地址或分支名称无效');
    }
    final document = DeployYamlDocument.parse(content);
    final values = _gitValues(document);
    document.updateValue(
      values.repository.index,
      _preserveQuotes(values.repository.value, cleanRepository),
    );
    document.updateValue(
      values.branch.index,
      _preserveQuotes(values.branch.value, cleanBranch),
    );
    final result = document.serialize();
    return content.contains('\r\n') ? result.replaceAll('\n', '\r\n') : result;
  }

  static bool _validRepository(String value) {
    if (value.contains(RegExp(r'[\r\n\s]'))) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  static bool _validBranch(String value) {
    if (value.isEmpty || value.startsWith('-') || value.contains('..')) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/-]*$').hasMatch(value);
  }

  static _GitValues _gitValues(DeployYamlDocument document) {
    if (document.hasError) throw const FormatException('无法读取 deploy.yaml');
    final deploy = _child(document.roots, 'Deploy');
    final git = _child(deploy.children, 'Git');
    final repository = _child(git.children, 'Repository').valueLine;
    final branch = _child(git.children, 'Branch').valueLine;
    if (repository == null || branch == null) {
      throw const FormatException('deploy.yaml 缺少 Git 配置');
    }
    return _GitValues(repository, branch);
  }

  static DeployYamlNode _child(Iterable<DeployYamlNode> nodes, String key) {
    for (final node in nodes) {
      if (node.key == key) return node;
    }
    throw FormatException('deploy.yaml 缺少 $key');
  }

  static String _unquote(String value) {
    final clean = value.trim();
    if (clean.length >= 2 &&
        ((clean.startsWith("'") && clean.endsWith("'")) ||
            (clean.startsWith('"') && clean.endsWith('"')))) {
      return clean.substring(1, clean.length - 1);
    }
    return clean;
  }

  static String _preserveQuotes(String original, String value) {
    final clean = original.trim();
    if (clean.startsWith("'") && clean.endsWith("'")) return "'$value'";
    if (clean.startsWith('"') && clean.endsWith('"')) return '"$value"';
    return value;
  }
}

class _GitValues {
  const _GitValues(this.repository, this.branch);

  final DeployYamlValueLine repository;
  final DeployYamlValueLine branch;
}
