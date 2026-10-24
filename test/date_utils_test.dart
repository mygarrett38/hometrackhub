import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/utils/date_utils.dart';

void main() {
  test('describeDueDateRoughly uses months, weeks or days', () {
    final today = DateTime(2026, 1, 1);
    String inDays(int days) =>
        describeDueDateRoughly(today.add(Duration(days: days)), today);
    expect(inDays(90), 'Due in 3 months');
    expect(inDays(20), 'Due in 3 weeks');
    expect(inDays(5), 'Due in 5 days');
    expect(inDays(-2), 'Overdue by 2 days');
  });

  test('describeCompletedRoughly uses months, weeks or days ago', () {
    final today = DateTime(2026, 6, 1);
    String daysAgo(int days) =>
        describeCompletedRoughly(today.subtract(Duration(days: days)), today);
    expect(daysAgo(0), 'Completed today');
    expect(daysAgo(1), 'Completed yesterday');
    expect(daysAgo(5), 'Completed 5 days ago');
    expect(daysAgo(20), 'Completed 3 weeks ago');
    expect(daysAgo(45), 'Completed 1 month ago');
    expect(daysAgo(90), 'Completed 3 months ago');
  });

  group('describeNextTaskDue', () {
    final today = DateTime(2026, 1, 1);
    String inDays(int days) =>
        describeNextTaskDue(today.add(Duration(days: days)), today);

    test('uses months past six weeks', () {
      expect(inDays(43), 'Next task due in 1 month');
      expect(inDays(90), 'Next task due in 3 months');
    });

    test('uses weeks past two weeks, up to six weeks', () {
      expect(inDays(15), 'Next task due in 2 weeks');
      expect(inDays(20), 'Next task due in 3 weeks');
      expect(inDays(42), 'Next task due in 6 weeks');
    });

    test('uses days for the next two weeks and when overdue', () {
      expect(inDays(14), 'Next task due in 14 days');
      expect(inDays(1), 'Next task due tomorrow');
      expect(inDays(0), 'Next task due today');
      expect(inDays(-2), 'Next task overdue by 2 days');
    });
  });
}
