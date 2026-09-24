import 'package:operator_mobile/feature/sessions/data/model/project_model.dart';
import 'package:operator_mobile/feature/spawn/data/model/claude_account_model.dart';
import 'package:operator_mobile/feature/spawn/logic/agent_picker.dart';

enum SpawnOption { project, agent, account }

sealed class SpawnOptionValues {
  static ProjectModel? projectById(List<ProjectModel> projects, String? id) {
    if (id == null) return null;
    for (final project in projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  static RankedAgent? agentById(List<RankedAgent> agents, String id) {
    for (final agent in agents) {
      if (agent.id == id) return agent;
    }
    return null;
  }

  static String projectValue(List<ProjectModel> projects, String? id) =>
      projectById(projects, id)?.name ?? 'Choose a project';

  static String agentValue(List<RankedAgent> agents, String harness, {required bool loading}) {
    final selected = agentById(agents, harness);
    if (selected != null) return selected.label;
    if (loading) return 'Loading…';
    return 'Choose an agent';
  }

  static bool showsAccount(String harness, List<ClaudeAccountModel> accounts) =>
      harness == 'claude-code' && accounts.isNotEmpty;

  static String accountValue(List<ClaudeAccountModel> accounts, String id) {
    for (final account in accounts) {
      if (account.id == id) return account.displayLabel;
    }
    return 'Default';
  }
}
