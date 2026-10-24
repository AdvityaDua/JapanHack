import 'package:flutter_test/flutter_test.dart';

import 'package:hushit_crew_tablet/main.dart';

void main() {
  testWidgets('crew dashboard renders the tablet overview', (tester) async {
    await tester.pumpWidget(const HushitCrewApp());
    expect(find.text('HUSHIT'), findsOneWidget);
    expect(find.text('Live Requests'), findsAtLeastNWidgets(1));
    expect(find.text('Request Details'), findsOneWidget);
    expect(find.text('Cabin Seat Map'), findsOneWidget);
  });
}
