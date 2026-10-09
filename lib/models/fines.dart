import 'expense.dart';
import 'shared_budget.dart';

/// A judge's vote: everyone but the offender decides whether the fine
/// stands.
const kVoteYes = 'yes';
const kVoteNo = 'no';

/// The offender's answer.
const kOffenderAccept = 'accept';
const kOffenderDispute = 'dispute';

enum FineStatus { voting, active, cancelled }

/// Everyone who votes on [fine]: the flat minus the offender.
List<String> fineJudges(Expense fine) => [
      for (final name in kRoommates)
        if (name != fine.offender) name
    ];

/// Where a fine stands.
///
/// Any judge saying no cancels it. It takes effect once every judge has
/// said yes and the offender has answered: accepting, or disputing -- a
/// dispute clears the judges' votes, so the yeses that follow it are a
/// second, deliberate confirmation over the offender's objection.
FineStatus fineStatus(Expense fine) {
  if (fine.votes.values.contains(kVoteNo)) return FineStatus.cancelled;
  final allYes = fineJudges(fine).every((n) => fine.votes[n] == kVoteYes);
  if (allYes && fine.offenderVote != null) return FineStatus.active;
  return FineStatus.voting;
}

/// Who still has to act on [fine], in [kRoommates] order. Empty once it is
/// decided.
List<String> fineAwaiting(Expense fine) {
  if (fineStatus(fine) != FineStatus.voting) return const [];
  return [
    for (final name in kRoommates)
      if (name == fine.offender
          ? fine.offenderVote == null
          : fine.votes[name] == null)
        name,
  ];
}

bool fineIsDisputed(Expense fine) => fine.offenderVote == kOffenderDispute;

/// Who voted the fine down, in [kRoommates] order. Empty unless cancelled.
List<String> fineCancelledBy(Expense fine) => [
      for (final name in kRoommates)
        if (fine.votes[name] == kVoteNo) name,
    ];
