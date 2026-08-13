import 'package:equatable/equatable.dart';

const List<String> _priority = ['claude-code', 'codex', 'cursor', 'opencode', 'aider'];

class AgentInfo extends Equatable {
  const AgentInfo({required this.id, required this.label, this.authStatus});

  final String id;
  final String label;
  final String? authStatus;

  factory AgentInfo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    return AgentInfo(
      id: id,
      label: json['label'] as String? ?? id,
      authStatus: json['authStatus'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, label, authStatus];
}

class AgentCatalog extends Equatable {
  const AgentCatalog({
    this.supported = const [],
    this.installed = const [],
    this.authorized = const [],
  });

  final List<AgentInfo> supported;
  final List<AgentInfo> installed;
  final List<AgentInfo> authorized;

  static List<AgentInfo> _agents(dynamic raw) => (raw as List<dynamic>? ?? const [])
      .map((a) => AgentInfo.fromJson(a as Map<String, dynamic>))
      .toList();

  factory AgentCatalog.fromJson(Map<String, dynamic> json) => AgentCatalog(
    supported: _agents(json['supported']),
    installed: _agents(json['installed']),
    authorized: _agents(json['authorized']),
  );

  @override
  List<Object?> get props => [supported, installed, authorized];
}

enum AgentAvailability { authorized, authUnknown, needsAuth, needsInstall }

AgentAvailability availabilityOf(AgentInfo agent, AgentCatalog catalog) {
  AgentInfo? installed;
  for (final candidate in catalog.installed) {
    if (candidate.id == agent.id) installed = candidate;
  }
  if (installed == null) return AgentAvailability.needsInstall;
  final isAuthorized = catalog.authorized.any((a) => a.id == agent.id) ||
      installed.authStatus == 'authorized';
  if (isAuthorized) return AgentAvailability.authorized;
  return installed.authStatus == 'unauthorized'
      ? AgentAvailability.needsAuth
      : AgentAvailability.authUnknown;
}

bool isSelectable(AgentAvailability availability) =>
    availability == AgentAvailability.authorized || availability == AgentAvailability.authUnknown;

String statusLabel(AgentAvailability availability) {
  switch (availability) {
    case AgentAvailability.authUnknown:
      return 'Auth unknown';
    case AgentAvailability.needsAuth:
      return 'Needs auth';
    case AgentAvailability.needsInstall:
      return 'Needs install';
    case AgentAvailability.authorized:
      return '';
  }
}

class RankedAgent extends Equatable {
  const RankedAgent({
    required this.id,
    required this.label,
    required this.availability,
    required this.status,
    required this.selectable,
  });

  final String id;
  final String label;
  final AgentAvailability availability;
  final String status;
  final bool selectable;

  @override
  List<Object?> get props => [id, label, availability, status, selectable];
}

int _priorityOf(String id) {
  final index = _priority.indexOf(id);
  return index == -1 ? _priority.length + 1 : index;
}

List<RankedAgent> rankAgents(AgentCatalog? catalog) {
  if (catalog == null) return const [];
  final ranked = catalog.supported.map((agent) {
    final availability = availabilityOf(agent, catalog);
    return RankedAgent(
      id: agent.id,
      label: agent.label,
      availability: availability,
      status: statusLabel(availability),
      selectable: isSelectable(availability),
    );
  }).toList();

  ranked.sort((a, b) {
    final rank = a.availability.index - b.availability.index;
    if (rank != 0) return rank;
    final priority = _priorityOf(a.id) - _priorityOf(b.id);
    if (priority != 0) return priority;
    return a.label.compareTo(b.label);
  });
  return ranked;
}

String? defaultAgent(List<RankedAgent> ranked) {
  for (final agent in ranked) {
    if (agent.selectable) return agent.id;
  }
  return null;
}
