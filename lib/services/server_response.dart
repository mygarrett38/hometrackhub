import 'dart:convert';

/// What went wrong, as the server in `assist/` explains it in the "error"
/// of an error response's [body], or `null` if it doesn't, for example
/// because the body is a proxy's error page.
String? serverErrorIn(String body) {
  try {
    if (jsonDecode(body) case {'error': final String message}) return message;
  } on FormatException {
    // Not JSON.
  }
  return null;
}
