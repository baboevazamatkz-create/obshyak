import 'package:cloud_firestore/cloud_firestore.dart';

import 'shared_budget.dart';

const kAwayYes = 'yes';
const kAwayNo = 'no';

enum AwayStatus { home, pending, away, rejected }

/// One flatmate's request to be counted out while they live elsewhere.
///
/// Going away needs the others' agreement: everyone who was home when it
/// was asked must say yes, and a single no turns it down. Coming back
/// needs nobody's: the request is simply removed.
class AwayRequest {
  final String name;
  final DateTime since;

  /// Who has to agree: everyone home at the moment it was asked.
  final List<String> approvers;

  /// Each approver's answer, keyed by name.
  final Map<String, String> votes;

  const AwayRequest({
    required this.name,
    required this.since,
    required this.approvers,
    this.votes = const {},
  });

  /// Where the request stands. An approver who has since gone away
  /// themselves no longer has a say, so [away] are not waited on.
  AwayStatus status([Set<String> away = const {}]) {
    if (votes.values.contains(kAwayNo)) return AwayStatus.rejected;
    final needed = approvers.where((n) => !away.contains(n));
    if (needed.every((n) => votes[n] == kAwayYes)) return AwayStatus.away;
    return AwayStatus.pending;
  }

  /// Approvers who have not answered yet, in [kRoommates] order, leaving
  /// out any who are [away].
  List<String> awaiting([Set<String> away = const {}]) => [
        for (final n in kRoommates)
          if (approvers.contains(n) && !away.contains(n) && votes[n] == null) n,
      ];

  /// Who turned it down, in [kRoommates] order.
  List<String> get rejectedBy => [
        for (final n in kRoommates)
          if (votes[n] == kAwayNo) n,
      ];

  Map<String, dynamic> toJson() => {
        'since': Timestamp.fromDate(since),
        'approvers': approvers,
        'votes': votes,
      };

  static AwayRequest? fromJson(String name, Object? json) {
    if (json is! Map) return null;
    final since = json['since'];
    return AwayRequest(
      name: name,
      since: since is Timestamp ? since.toDate() : DateTime.now(),
      approvers: (json['approvers'] as List?)?.cast<String>() ?? const [],
      votes: (json['votes'] as Map?)?.map(
            (key, value) => MapEntry(key as String, value as String),
          ) ??
          const {},
    );
  }
}

/// Who is away, who has asked to be, and so who is living in the flat.
class AwayBook {
  final Map<String, AwayRequest> requests;

  AwayBook([this.requests = const {}]);

  factory AwayBook.fromJson(Map<String, dynamic>? json) => AwayBook({
        for (final name in kRoommates)
          if (AwayRequest.fromJson(name, json?[name]) case final request?)
            name: request,
      });

  /// Everyone away right now. Worked out in rounds: someone going away
  /// stops being waited on for anybody else's request, which can complete
  /// that one in turn.
  late final Set<String> awayNames = () {
    final away = <String>{};
    var grew = true;
    while (grew) {
      grew = false;
      for (final request in requests.values) {
        if (away.contains(request.name)) continue;
        if (request.status(away) == AwayStatus.away) {
          away.add(request.name);
          grew = true;
        }
      }
    }
    return away;
  }();

  AwayStatus statusOf(String name) =>
      requests[name]?.status(awayNames) ?? AwayStatus.home;

  bool isAway(String name) => awayNames.contains(name);

  /// Who [request] still waits on.
  List<String> awaiting(AwayRequest request) => request.awaiting(awayNames);

  /// Everyone living in the flat right now: new purchases and fines are
  /// split between them only. Someone whose request is still waiting is
  /// home until it is agreed.
  List<String> get present => [
        for (final name in kRoommates)
          if (!isAway(name)) name,
      ];

  /// Requests still waiting on someone.
  List<AwayRequest> get pending => [
        for (final name in kRoommates)
          if (statusOf(name) == AwayStatus.pending) requests[name]!,
      ];
}
