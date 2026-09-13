class BoardChange {
  const BoardChange({this.eventType, this.sessionId, this.projectId});

  final String? eventType;
  final String? sessionId;
  final String? projectId;

  bool get requiresFullRefresh => eventType == null || eventType!.startsWith('project_');
}
