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

  test('monthDayOrdinal gives the day with st, nd, rd or th', () {
    String on(int month, int day) =>
        monthDayOrdinal(DateTime(2026, month, day));
    expect(on(10, 28), 'October 28th');
    expect(on(5, 1), 'May 1st');
    expect(on(6, 2), 'June 2nd');
    expect(on(7, 3), 'July 3rd');
    expect(on(8, 4), 'August 4th');
    expect(on(1, 11), 'January 11th');
    expect(on(2, 12), 'February 12th');
    expect(on(3, 13), 'March 13th');
    expect(on(12, 21), 'December 21st');
    expect(on(12, 22), 'December 22nd');
    expect(on(12, 23), 'December 23rd');
    expect(on(12, 31), 'December 31st');
  });
}
