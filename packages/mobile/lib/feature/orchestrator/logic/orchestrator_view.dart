import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/feature/sessions/data/model/orchestrator_model.dart';
import 'package:operator_mobile/feature/sessions/data/model/session_model.dart';
import 'package:operator_mobile/feature/sessions/logic/session_status.dart';
import 'package:operator_mobile/feature/sessions/logic/status_visual.dart';

enum OrchestratorState { missing, stopped, running }

OrchestratorState orchestratorStateOf(OrchestratorModel? link) {
  final id = link?.id;
  if (id == null || id.isEmpty) return OrchestratorState.missing;
  if (link!.hasRuntime == false || link.isTerminal == true) return OrchestratorState.stopped;
  return OrchestratorState.running;
}

class OrchestratorStatus {
  const OrchestratorStatus({required this.label, required this.color, required this.breathing});

  final String label;
  final Color color;
  final bool breathing;
}

OrchestratorStatus orchestratorStatus(AppSkin skin, OrchestratorModel? link) {
  switch (orchestratorStateOf(link)) {
    case OrchestratorState.missing:
      return OrchestratorStatus(label: 'Not started', color: skin.textFaint, breathing: false);
    case OrchestratorState.stopped:
      return OrchestratorStatus(label: 'Stopped', color: skin.textTertiary, breathing: false);
    case OrchestratorState.running:
      final status = link?.status;
      if (status == null || status.isEmpty) {
        return OrchestratorStatus(label: 'Online', color: skin.blue, breathing: false);
      }
      final visual = statusVisual(skin, status);
      return OrchestratorStatus(label: visual.label, color: visual.color, breathing: visual.breathing);
  }
}

class LaunchIntent {
  const LaunchIntent({required this.clean, required this.label, required this.confirm});

  final bool clean;
  final String label;
  final bool confirm;
}

LaunchIntent launchIntent(OrchestratorState state) => state == OrchestratorState.running
    ? const LaunchIntent(clean: true, label: 'Restart orchestrator', confirm: true)
    : const LaunchIntent(clean: false, label: 'Start orchestrator', confirm: false);

Map<AttentionLevel, int> zoneCounts(List<SessionModel> sessions) {
  final counts = <AttentionLevel, int>{};
  for (final session in sessions) {
    final level = attentionOf(session);
    counts[level] = (counts[level] ?? 0) + 1;
  }
  return counts;
}

List<SessionModel> workersOf(List<SessionModel> sessions, String projectId, OrchestratorModel? link) =>
    sessions.where((s) => s.projectId == projectId && s.id != link?.id).toList();
