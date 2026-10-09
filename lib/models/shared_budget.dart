import 'currency.dart';

/// The four people in the flat. Each one picks their name once on their
/// phone, and it is written into every record they enter.
const kRoommates = ['Азамат', 'Аслан', 'Мухаммад', 'Имран'];

/// The one flatmate who may delete records and clear the budget.
const kAdminName = 'Азамат';

/// The code each flatmate types to sign in as themselves. It keeps people
/// from picking someone else's name by mistake; it is not a secret, since
/// it ships in the web build.
const kRoommateCodes = {
  'Азамат': '2807',
  'Аслан': '1101',
  'Мухаммад': '1102',
  'Имран': '1103',
};

/// How many people the shared total is split between.
const kRoommateCount = 4;

/// The one budget the flat shares. It is public on purpose: there is no
/// sign-in for the flat, and anyone holding this code can read the budget.
const kSharedBudgetCode = 'CT65H6DKC55M';

/// Tenge is the only currency the flat records and shows.
const kBudgetCurrency = AppCurrency.kzt;
