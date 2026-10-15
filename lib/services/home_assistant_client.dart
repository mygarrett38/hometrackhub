import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A conversation turn sent to and returned from the Home Assistant service.
class AssistantMessage {
  const AssistantMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class AssistantReply {
  const AssistantReply({
    required this.answer,
    this.recommendProfessional = false,
    this.professionalReason,
  });

  final String answer;
  final bool recommendProfessional;
  final String? professionalReason;
}

/// Calls a server-side AI proxy. The model API key must remain on that server,
/// never in this mobile app. Configure with --dart-define=HOME_ASSISTANT_API_URL.
class HomeAssistantClient {
  HomeAssistantClient({String endpoint = _configuredEndpoint})
    : _endpoint = endpoint.trim();

  static const String _configuredEndpoint = String.fromEnvironment(
    'HOME_ASSISTANT_API_URL',
  );

  static const _safetyInstructions = '''
You are HomeTrack Hub's home maintenance assistant. Give clear, basic next
steps and explain simple maintenance in plain language. Ask a short follow-up
question if the symptoms are unclear. Do not claim certainty from limited
information. Recommend a properly licensed professional when diagnosis or
repair involves gas, electrical wiring, refrigerant, structural work, or any
uncertain safety risk. Tell the user to stop using affected equipment when it
may be unsafe. Never provide instructions for bypassing safety devices or
working on live electrical or gas systems. For a gas smell, fire, smoke, or a
carbon monoxide alarm, advise leaving the area and contacting emergency
services or the relevant utility from a safe location. Return JSON with
"answer" (string), "recommendProfessional" (boolean), and
"professionalReason" (string or null).
''';

  final String _endpoint;

  bool get isConfigured => _endpoint.isNotEmpty;

  Future<AssistantReply> ask(List<AssistantMessage> conversation) async {
    if (!isConfigured) {
      throw const AssistantConnectionException(
        'The secure AI service has not been configured yet.',
      );
    }

    final uri = Uri.tryParse(_endpoint);
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw const AssistantConnectionException(
        'The assistant service must use a valid HTTPS endpoint.',
      );
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'systemInstructions': _safetyInstructions,
          'messages': [for (final message in conversation) message.toJson()],
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 45),
      );
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AssistantConnectionException(
          'The assistant service returned status ${response.statusCode}.',
        );
      }
      final payload = jsonDecode(responseBody) as Map<String, dynamic>;
      final answer = payload['answer'] as String?;
      if (answer == null || answer.trim().isEmpty) {
        throw const AssistantConnectionException(
          'The assistant service returned an empty answer.',
        );
      }
      return AssistantReply(
        answer: answer,
        recommendProfessional:
            payload['recommendProfessional'] as bool? ?? false,
        professionalReason: payload['professionalReason'] as String?,
      );
    } on AssistantConnectionException {
      rethrow;
    } on TimeoutException {
      throw const AssistantConnectionException(
        'The assistant took too long to respond. Please try again.',
      );
    } on SocketException {
      throw const AssistantConnectionException(
        'Could not reach the assistant service. Check your connection.',
      );
    } on FormatException {
      throw const AssistantConnectionException(
        'The assistant service returned an invalid response.',
      );
    } finally {
      client.close(force: true);
    }
  }
}

class AssistantConnectionException implements Exception {
  const AssistantConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}
