import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/service_type.dart';
import '../models/technical_level.dart';
import 'server_response.dart';

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
    this.professionalService,
  });

  final String answer;
  final bool recommendProfessional;
  final String? professionalReason;

  /// The kind of business to hire, when the assistant recommends a
  /// professional and says which, so one can be found nearby.
  final ServiceType? professionalService;
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

  /// Asks the assistant to answer the last question in [conversation],
  /// pitched at the user's [technicalLevel].
  Future<AssistantReply> ask(
    List<AssistantMessage> conversation, {
    TechnicalLevel technicalLevel = TechnicalLevel.someExperience,
  }) async {
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
          'technicalLevel': technicalLevel.name,
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 45),
      );
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AssistantConnectionException(
          serverErrorIn(responseBody) ??
              'The assistant service returned status ${response.statusCode}.',
        );
      }
      return replyFrom(responseBody);
    } on AssistantConnectionException {
      rethrow;
    } on TimeoutException {
      throw const AssistantConnectionException(
        'The assistant took too long to respond. Please try again.',
      );
    } on IOException {
      // Any problem with the connection, such as having none, it dropping
      // partway through the answer, or a secure connection failing.
      throw const AssistantConnectionException(
        'Could not reach the assistant service. Check your connection.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// The answer in the server's [body].
  ///
  /// Throws an [AssistantConnectionException] if it isn't laid out as
  /// expected or has no answer.
  @visibleForTesting
  static AssistantReply replyFrom(String body) {
    try {
      final payload = jsonDecode(body);
      if (payload is! Map<String, dynamic>) throw const FormatException();
      final answer = payload['answer'];
      if (answer is! String) throw const FormatException();
      if (answer.trim().isEmpty) {
        throw const AssistantConnectionException(
          'The assistant service returned an empty answer.',
        );
      }
      final reason = payload['professionalReason'];
      final recommendProfessional = payload['recommendProfessional'] == true;
      return AssistantReply(
        answer: answer,
        recommendProfessional: recommendProfessional,
        professionalReason: reason is String ? reason : null,
        // Anything the app doesn't know, such as from a newer server, is
        // left out.
        professionalService: recommendProfessional
            ? ServiceType.values.asNameMap()[payload['professionalService']]
            : null,
      );
    } on FormatException {
      throw const AssistantConnectionException(
        'The assistant service returned an invalid response.',
      );
    }
  }
}

class AssistantConnectionException implements Exception {
  const AssistantConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}
