import Anthropic from "@anthropic-ai/sdk";

// The Assist tab's backend. The app sends the conversation here, and this
// Worker asks Claude for the next answer. The Anthropic API key stays in
// this Worker's secrets so it never ships inside the app.

interface Env {
  ANTHROPIC_API_KEY: string;
  /** Shared with the app so random visitors can't use the endpoint. */
  APP_TOKEN: string;
  RATE_LIMITER: RateLimit;
}

const MODEL = "claude-haiku-5-5";

// Limits on what one request may contain, so a single caller can't run up
// the bill. The app keeps its own messages well under these.
const MAX_MESSAGES = 40;
const MAX_MESSAGE_CHARS = 4_000;
const MAX_TOTAL_CHARS = 40_000;

const SYSTEM_PROMPT = `You are HomeTrack Hub's home maintenance assistant. \
HomeTrack Hub is a mobile app people use to track maintenance for their home, \
appliances, vehicles and smart devices.

Give clear, basic next steps and explain simple maintenance in plain language. \
Keep answers short enough to read comfortably on a phone. Ask a short \
follow-up question if the symptoms are unclear. Do not claim certainty from \
limited information.

Recommend a properly licensed professional when diagnosis or repair involves \
gas, electrical wiring, refrigerant, structural work, or any uncertain safety \
risk. Tell the user to stop using affected equipment when it may be unsafe. \
Never provide instructions for bypassing safety devices or working on live \
electrical or gas systems. For a gas smell, fire, smoke, or a carbon monoxide \
alarm, advise leaving the area and contacting emergency services or the \
relevant utility from a safe location.

Only help with maintaining, repairing and caring for a home and the things in \
it, vehicles included. If asked about anything else, say in one sentence that \
you can only help with home maintenance.

Write "answer" as plain text: the app does not render Markdown, so use no \
headings, bold or tables. Short lists starting with "- " or "1. " are fine. \
Set "recommendProfessional" to true when the user should hire a professional \
for this problem, and put the reason in one sentence in "professionalReason". \
Otherwise set it to false and leave "professionalReason" empty.`;

const REPLY_SCHEMA = {
  type: "object",
  properties: {
    answer: { type: "string" },
    recommendProfessional: { type: "boolean" },
    professionalReason: { type: "string" },
  },
  required: ["answer", "recommendProfessional", "professionalReason"],
  additionalProperties: false,
};

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname !== "/chat") return error(404, "Not found.");
    if (request.method !== "POST") return error(405, "Use POST.");

    if (!env.ANTHROPIC_API_KEY || !env.APP_TOKEN) {
      console.error("ANTHROPIC_API_KEY or APP_TOKEN secret is not set.");
      return error(500, "The assistant is not set up yet.");
    }
    if (!tokenMatches(request.headers.get("Authorization"), env.APP_TOKEN)) {
      return error(401, "This app is not allowed to use the assistant.");
    }

    // Keyed by IP address: simple, and a caller can't change it per request.
    const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
    const { success } = await env.RATE_LIMITER.limit({ key: ip });
    if (!success) {
      return error(
        429,
        "You're sending questions too quickly. Wait a minute and try again.",
      );
    }

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return error(400, "The request was not valid JSON.");
    }
    const messages = parseMessages(body);
    if (typeof messages === "string") return error(400, messages);

    const client = new Anthropic({
      apiKey: env.ANTHROPIC_API_KEY,
      // Finish before the app gives up waiting, which is after 45 seconds.
      timeout: 30_000,
      maxRetries: 1,
    });

    try {
      const response = await client.messages.create({
        model: MODEL,
        // Room for the model's thinking plus the answer.
        max_tokens: 8_000,
        output_config: {
          // Low effort is fast and plenty for maintenance questions.
          effort: "low",
          format: { type: "json_schema", schema: REPLY_SCHEMA },
        },
        system: SYSTEM_PROMPT,
        messages,
      });

      if (response.stop_reason === "refusal") {
        return json({
          answer: "Sorry, I can't help with that question.",
          recommendProfessional: false,
          professionalReason: null,
        });
      }
      if (response.stop_reason === "max_tokens") {
        return error(502, "The answer was too long. Try a narrower question.");
      }

      // The response can start with thinking blocks; the answer is the text.
      const text = response.content
        .flatMap((block) => (block.type === "text" ? [block.text] : []))
        .join("");
      const reply = JSON.parse(text) as {
        answer: string;
        recommendProfessional: boolean;
        professionalReason: string;
      };
      return json({
        answer: reply.answer,
        recommendProfessional: reply.recommendProfessional,
        professionalReason: reply.professionalReason.trim() || null,
      });
    } catch (err) {
      if (err instanceof Anthropic.RateLimitError) {
        return error(503, "The assistant is busy right now. Try again soon.");
      }
      if (
        err instanceof Anthropic.AuthenticationError ||
        err instanceof Anthropic.PermissionDeniedError
      ) {
        console.error("Anthropic rejected the API key:", err.message);
        return error(500, "The assistant is not set up correctly.");
      }
      if (err instanceof Anthropic.APIConnectionError) {
        console.error("Could not reach Anthropic:", err.message);
        return error(502, "The assistant could not be reached. Try again.");
      }
      if (err instanceof Anthropic.APIError) {
        console.error(`Anthropic API error ${err.status}:`, err.message);
        return error(502, "The assistant ran into a problem. Try again.");
      }
      if (err instanceof SyntaxError) {
        console.error("Claude's reply was not valid JSON:", err.message);
        return error(502, "The assistant ran into a problem. Try again.");
      }
      throw err;
    }
  },
} satisfies ExportedHandler<Env>;

/**
 * Checks the request body and turns it into messages for Claude, or returns
 * what's wrong with it.
 */
function parseMessages(body: unknown): Anthropic.MessageParam[] | string {
  if (typeof body !== "object" || body === null) {
    return "The request must be a JSON object.";
  }
  const raw = (body as { messages?: unknown }).messages;
  if (!Array.isArray(raw) || raw.length === 0) {
    return '"messages" must be a non-empty list.';
  }
  if (raw.length > MAX_MESSAGES) {
    return "This conversation is too long. Start a new one.";
  }

  const messages: Anthropic.MessageParam[] = [];
  let totalChars = 0;
  for (const item of raw) {
    const { role, content } = (item ?? {}) as {
      role?: unknown;
      content?: unknown;
    };
    if (typeof content !== "string" || content.trim() === "") {
      return "Each message needs some text.";
    }
    if (content.length > MAX_MESSAGE_CHARS) {
      return "A message is too long. Shorten it and try again.";
    }
    totalChars += content.length;
    if (role === "user") {
      messages.push({ role: "user", content });
    } else if (role === "assistant") {
      messages.push({ role: "assistant", content });
    } else {
      return 'Each message\'s role must be "user" or "assistant".';
    }
  }
  if (totalChars > MAX_TOTAL_CHARS) {
    return "This conversation is too long. Start a new one.";
  }
  if (messages[0].role !== "user" || messages.at(-1)!.role !== "user") {
    return "The conversation must start and end with the user's message.";
  }
  return messages;
}

/**
 * Compares the "Bearer <token>" header with the expected token in constant
 * time, so the token can't be guessed from how long a check takes.
 */
function tokenMatches(header: string | null, expected: string): boolean {
  const encoder = new TextEncoder();
  const given = encoder.encode(header ?? "");
  const wanted = encoder.encode(`Bearer ${expected}`);
  if (given.byteLength !== wanted.byteLength) return false;
  return crypto.subtle.timingSafeEqual(given, wanted);
}

function json(data: unknown, status = 200): Response {
  return Response.json(data, { status });
}

function error(status: number, message: string): Response {
  return json({ error: message }, status);
}
