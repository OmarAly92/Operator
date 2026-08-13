import 'package:equatable/equatable.dart';

class BuildInfo extends Equatable {
  const BuildInfo({this.version, this.build});

  final String? version;
  final String? build;

  @override
  List<Object?> get props => [version, build];
}

String formatVersion(BuildInfo info) {
  final version = info.version?.trim();
  final build = info.build?.trim();
  if (version == null || version.isEmpty) {
    return build == null || build.isEmpty ? 'unknown' : 'build $build';
  }
  if (build == null || build.isEmpty || build == version) return version;
  return '$version ($build)';
}

String bugReportBody(BuildInfo info, String platform, String osVersion) => [
  '',
  '',
  '---',
  'Operator mobile: ${formatVersion(info)}',
  'Platform: $platform $osVersion',
].join('\n');
