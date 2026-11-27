import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/models/maintenance_interval.dart';
import 'package:hometrackhub/models/service_type.dart';
import 'package:hometrackhub/services/home_assistant_client.dart';
import 'package:hometrackhub/services/server_response.dart';

void main() {
  group('HomeAssistantClient.replyFrom', () {
    test('reads the answer and whether to see a professional', () {
      final reply = HomeAssistantClient.replyFrom(
        '{"answer": "Call an electrician.", "recommendProfessional": true, '
        '"professionalReason": "It involves wiring."}',
      );

      expect(reply.answer, 'Call an electrician.');
      expect(reply.recommendProfessional, isTrue);
      expect(reply.professionalReason, 'It involves wiring.');
    });

    test('reads the kind of professional to find nearby', () {
      ServiceType? serviceIn(String body) =>
          HomeAssistantClient.replyFrom(body).professionalService;

      expect(
        serviceIn(
          '{"answer": "Call a plumber.", "recommendProfessional": true, '
          '"professionalService": "plumbing"}',
        ),
        ServiceType.plumbing,
      );
      // Only with a recommendation, and only kinds the app knows.
      expect(
        serviceIn(
          '{"answer": "Every 90 days.", "recommendProfessional": false, '
          '"professionalService": "plumbing"}',
        ),
        isNull,
      );
      for (final service in ['"none"', '"chimney"', '3', 'null']) {
        expect(
          serviceIn(
            '{"answer": "Call someone.", "recommendProfessional": true, '
            '"professionalService": $service}',
          ),
          isNull,
          reason: service,
        );
      }
    });

    test("reads suggested tasks, leaving out ones it can't use", () {
      final tasks = HomeAssistantClient.replyFrom('''{
        "answer": "Replace the filter.",
        "suggestedTasks": [
          {"title": " Replace furnace filter ", "description": "Swap it.",
           "every": 3, "unit": "months"},
          {"title": "Check the flame", "every": 1, "unit": "years"},
          {"title": "", "every": 1, "unit": "years"},
          {"title": "Dust it", "every": 0, "unit": "weeks"},
          {"title": "Polish it", "every": 2, "unit": "fortnights"},
          "Vacuum the coils"
        ]
      }''').suggestedTasks;

      expect(
        [for (final task in tasks) task.title],
        ['Replace furnace filter', 'Check the flame'],
      );
      expect(tasks.first.description, 'Swap it.');
      expect(tasks.first.interval, const MaintenanceInterval.months(3));
      expect(tasks.last.description, '');
      expect(tasks.last.interval, const MaintenanceInterval.years(1));

      // None when the server leaves them out.
      expect(
        HomeAssistantClient.replyFrom('{"answer": "Yes."}').suggestedTasks,
        isEmpty,
      );
    });

    test('ignores extras of the wrong type', () {
      final reply = HomeAssistantClient.replyFrom(
        '{"answer": "Every 90 days.", "recommendProfessional": "yes", '
        '"professionalReason": 3}',
      );

      expect(reply.recommendProfessional, isFalse);
      expect(reply.professionalReason, isNull);
    });

    test('a response laid out differently is an error', () {
      for (final body in ['not JSON', '[]', '{"answer": 42}', '{}']) {
        expect(
          () => HomeAssistantClient.replyFrom(body),
          throwsA(
            isA<AssistantConnectionException>().having(
              (error) => error.message,
              'message',
              'The assistant service returned an invalid response.',
            ),
          ),
          reason: body,
        );
      }
    });

    test('an empty answer is an error', () {
      expect(
        () => HomeAssistantClient.replyFrom('{"answer": "  "}'),
        throwsA(
          isA<AssistantConnectionException>().having(
            (error) => error.message,
            'message',
            'The assistant service returned an empty answer.',
          ),
        ),
      );
    });
  });

  group('serverErrorIn', () {
    test("reads the server's explanation", () {
      expect(serverErrorIn('{"error": "Too fast."}'), 'Too fast.');
    });

    test('is null for anything else', () {
      for (final body in ['<html>Bad gateway</html>', '{"error": 5}', '[]']) {
        expect(serverErrorIn(body), isNull, reason: body);
      }
    });
  });
}
