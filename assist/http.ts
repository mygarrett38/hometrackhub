// Helpers shared by the Worker's routes.

/**
 * Compares the "Bearer <token>" header with the expected token in constant
 * time, so the token can't be guessed from how long a check takes.
 */
export function tokenMatches(header: string | null, expected: string): boolean {
  const encoder = new TextEncoder();
  const given = encoder.encode(header ?? "");
  const wanted = encoder.encode(`Bearer ${expected}`);
  if (given.byteLength !== wanted.byteLength) return false;
  return crypto.subtle.timingSafeEqual(given, wanted);
}

export function json(data: unknown, status = 200): Response {
  return Response.json(data, { status });
}

export function error(status: number, message: string): Response {
  return json({ error: message }, status);
}
