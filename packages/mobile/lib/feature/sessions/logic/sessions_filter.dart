import 'package:operator_mobile/feature/sessions/logic/agents_view.dart';

/// The Agents-board filter row (`docs/design/sessions_board/sessions_board.md`):
/// All / Needs you / Working / Mergeable / Archive. There is no filter chip for
/// the `pending` ("In review") zone — a session in that zone is only reachable
/// via "All", matching the prototype's `agentFilters` array verbatim.
enum SessionsFilter { all, needsYou, working, mergeable, archive }

extension SessionsFilterLabel on SessionsFilter {
  String get label => switch (this) {
    SessionsFilter.all => 'All',
    SessionsFilter.needsYou => 'Needs you',
    SessionsFilter.working => 'Working',
    SessionsFilter.mergeable => 'Mergeable',
    SessionsFilter.archive => 'Archive',
  };
}

/// Whether a board section for [zone] should render under [filter].
bool sessionsFilterAllowsZone(SessionsFilter filter, BoardZone zone) => switch (filter) {
  SessionsFilter.all => true,
  SessionsFilter.needsYou => zone == BoardZone.action,
  SessionsFilter.working => zone == BoardZone.working,
  SessionsFilter.mergeable => zone == BoardZone.merge,
  SessionsFilter.archive => false,
};
