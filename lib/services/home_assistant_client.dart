import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A conversation turn sent to and returned from the Home Assistant service.
class AssistantMessage {
  const AssistantMessage({required this.role, required this.content});

  const AssistantMessage.user(this.content) : role = 'user';

  const AssistantMessage.assistant(this.content) : role = 'assistant';

  final String role;
  final String content;

  bool get isUser => role == 'user';

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

/// Calls the server-side AI proxy in `assist/`. The model API key and the
/// assistant's instructions stay on that server, never in this mobile app.
/// Configure with --dart-define=HOME_ASSISTANT_API_URL and
/// --dart-define=HOME_ASSISTANT_API_TOKEN.
class HomeAssistantClient {
  HomeAssistantClient({
    String endpoint = _configuredEndpoint,
    String token = _configuredToken,
  }) : _endpoint = endpoint.trim(),
       _token = token.trim();

  static const String _configuredEndpoint = String.fromEnvironment(
    'HOME_ASSISTANT_API_URL',
  );

  /// Must match the APP_TOKEN secret on the server.
  static const String _configuredToken = String.fromEnvironment(
    'HOME_ASSISTANT_API_TOKEN',
  );

  final String _endpoint;
  final String _token;

  bool get isConfigured => _endpoint.isNotEmpty && _token.isNotEmpty;

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
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      request.write(
        jsonEncode({
          'messages': [for (final message in conversation) message.toJson()],
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 45),
      );
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // The server explains what went wrong in "error" when it can.
        String? serverMessage;
        try {
          final payload = jsonDecode(responseBody);
          if (payload is Map<String, dynamic>) {
            serverMessage = payload['error'] as String?;
          }
        } on FormatException {
          // Not JSON, for example a proxy's error page.
        }
        throw AssistantConnectionException(
          serverMessage ??
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
