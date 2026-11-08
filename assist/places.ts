import { error, json, tokenMatches } from "./http";

// The Nearby services screen's backend. The app sends what to search for
// and where, and this Worker asks Google Places for matching businesses.
// The Google API key stays in this Worker's secrets so it never ships in the
// app, including in the addresses of business photos.

export interface PlacesEnv {
  GOOGLE_PLACES_API_KEY: string;
  /** Shared with the app so random visitors can't use the endpoint. */
  APP_TOKEN: string;
  PLACES_RATE_LIMITER: RateLimit;
  PHOTO_RATE_LIMITER: RateLimit;
}

const MAX_QUERY_CHARS = 100;

/** How far around the user to prefer businesses, in meters: about 15 miles. */
const SEARCH_RADIUS_METERS = 25_000;

/** Google's most per search. */
const RESULT_COUNT = 20;

/** Wide enough for the details sheet; the cards reuse the same image. */
const PHOTO_WIDTH_PX = 800;

/**
 * The only fields asked of Google. Google bills by the most expensive field
 * asked for, and ratings, hours, phone numbers and websites are all in its
 * Enterprise tier.
 */
const FIELD_MASK = [
  "places.id",
  "places.displayName",
  "places.formattedAddress",
  "places.addressComponents",
  "places.location",
  "places.types",
  "places.rating",
  "places.userRatingCount",
  "places.regularOpeningHours",
  "places.nationalPhoneNumber",
  "places.websiteUri",
  "places.googleMapsUri",
  "places.photos",
].join(",");

interface Point {
  latitude: number;
  longitude: number;
}

/** A problem calling Google, with the response status to send back. */
class GoogleError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

/**
 * POST /places with `{ textQuery, location }`, where location is either
 * `{ latitude, longitude }` or `{ zipCode }`. Returns `{ origin, places }`:
 * the point searched around and Google's places with the fields above.
 */
export async function handlePlaces(
  request: Request,
  env: PlacesEnv,
): Promise<Response> {
  if (request.method !== "POST") return error(405, "Use POST.");
  const problem = await checkRequest(request, env, env.PLACES_RATE_LIMITER);
  if (problem) return problem;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return error(400, "The request was not valid JSON.");
  }
  const search = parseSearch(body);
  if (typeof search === "string") return error(400, search);

  try {
    const origin =
      "zipCode" in search.location
        ? await locateZipCode(search.location.zipCode, env)
        : search.location;
    if (!origin) {
      return error(
        400,
        "That ZIP code couldn't be found. Check it in Nearby services settings.",
      );
    }

    const response = await fetch(
      "https://places.googleapis.com/v1/places:searchText",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": env.GOOGLE_PLACES_API_KEY,
          "X-Goog-FieldMask": FIELD_MASK,
        },
        body: JSON.stringify({
          textQuery: search.textQuery,
          pageSize: RESULT_COUNT,
          languageCode: "en",
          regionCode: "us",
          locationBias: {
            circle: { center: origin, radius: SEARCH_RADIUS_METERS },
          },
        }),
      },
    );
    if (!response.ok) throw await googleError("Text Search", response);
    const data = (await response.json()) as { places?: unknown[] };
    return json({ origin, places: data.places ?? [] });
  } catch (err) {
    if (err instanceof GoogleError) return error(err.status, err.message);
    throw err;
  }
}

/**
 * GET /places/photo?name=places/.../photos/... returns that photo of a
 * business, so the app can show it without knowing the Google API key.
 */
export async function handlePlacePhoto(
  request: Request,
  env: PlacesEnv,
  url: URL,
): Promise<Response> {
  if (request.method !== "GET") return error(405, "Use GET.");
  const problem = await checkRequest(request, env, env.PHOTO_RATE_LIMITER);
  if (problem) return problem;

  const name = url.searchParams.get("name") ?? "";
  if (!/^places\/[\w-]+\/photos\/[\w-]+$/.test(name)) {
    return error(400, "That is not a Google photo name.");
  }

  try {
    // Asks for the photo's temporary address rather than being redirected
    // to it, then fetches the image from there.
    const media = new URL(`https://places.googleapis.com/v1/${name}/media`);
    media.searchParams.set("maxWidthPx", String(PHOTO_WIDTH_PX));
    media.searchParams.set("skipHttpRedirect", "true");
    const response = await fetch(media, {
      headers: { "X-Goog-Api-Key": env.GOOGLE_PLACES_API_KEY },
    });
    if (!response.ok) throw await googleError("Place Photos", response);
    const { photoUri } = (await response.json()) as { photoUri?: string };
    if (!photoUri) throw new GoogleError(502, "The photo could not be loaded.");

    const image = await fetch(photoUri);
    if (!image.ok) throw new GoogleError(502, "The photo could not be loaded.");
    return new Response(image.body, {
      headers: {
        "Content-Type": image.headers.get("Content-Type") ?? "image/jpeg",
        "Cache-Control": "private, max-age=86400",
      },
    });
  } catch (err) {
    if (err instanceof GoogleError) return error(err.status, err.message);
    throw err;
  }
}

/**
 * Checks the Worker is set up, the app's token, and [limiter]'s rate limit.
 * Returns the response to send if any of them fail.
 */
async function checkRequest(
  request: Request,
  env: PlacesEnv,
  limiter: RateLimit,
): Promise<Response | null> {
  if (!env.GOOGLE_PLACES_API_KEY || !env.APP_TOKEN) {
    console.error("GOOGLE_PLACES_API_KEY or APP_TOKEN secret is not set.");
    return error(500, "Nearby services are not set up yet.");
  }
  if (!tokenMatches(request.headers.get("Authorization"), env.APP_TOKEN)) {
    return error(401, "This app is not allowed to search nearby services.");
  }
  // Keyed by IP address: simple, and a caller can't change it per request.
  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const { success } = await limiter.limit({ key: ip });
  if (!success) {
    return error(429, "You're searching too quickly. Wait a minute and try again.");
  }
  return null;
}

/** Checks the request body, or returns what's wrong with it. */
function parseSearch(
  body: unknown,
): { textQuery: string; location: Point | { zipCode: string } } | string {
  if (typeof body !== "object" || body === null) {
    return "The request must be a JSON object.";
  }
  const { textQuery, location } = body as {
    textQuery?: unknown;
    location?: unknown;
  };
  if (typeof textQuery !== "string" || textQuery.trim() === "") {
    return '"textQuery" must be some text.';
  }
  if (textQuery.length > MAX_QUERY_CHARS) {
    return "The search is too long. Shorten it and try again.";
  }

  const { latitude, longitude, zipCode } = (location ?? {}) as {
    latitude?: unknown;
    longitude?: unknown;
    zipCode?: unknown;
  };
  if (typeof zipCode === "string") {
    if (!/^\d{5}$/.test(zipCode)) return "A ZIP code must be 5 digits.";
    return { textQuery: textQuery.trim(), location: { zipCode } };
  }
  if (
    typeof latitude !== "number" ||
    typeof longitude !== "number" ||
    Math.abs(latitude) > 90 ||
    Math.abs(longitude) > 180
  ) {
    return '"location" must be a latitude and longitude, or a ZIP code.';
  }
  return { textQuery: textQuery.trim(), location: { latitude, longitude } };
}

/**
 * The middle of a US ZIP code, from Google's Geocoding API, or null if
 * there's no such ZIP code.
 */
async function locateZipCode(
  zipCode: string,
  env: PlacesEnv,
): Promise<Point | null> {
  const url = new URL("https://maps.googleapis.com/maps/api/geocode/json");
  url.searchParams.set("components", `postal_code:${zipCode}|country:US`);
  url.searchParams.set("key", env.GOOGLE_PLACES_API_KEY);
  const response = await fetch(url);
  const data = (await response.json()) as {
    status: string;
    error_message?: string;
    results?: { geometry: { location: { lat: number; lng: number } } }[];
  };
  if (data.status === "ZERO_RESULTS") return null;
  const location = data.results?.[0]?.geometry.location;
  if (data.status !== "OK" || !location) {
    // REQUEST_DENIED usually means the Geocoding API isn't enabled for the
    // key's project, or the key's API restrictions leave it out.
    console.error(`Geocoding API ${data.status}:`, data.error_message ?? "");
    throw new GoogleError(
      data.status === "OVER_QUERY_LIMIT" ? 503 : 500,
      data.status === "OVER_QUERY_LIMIT"
        ? "Nearby services are busy right now. Try again soon."
        : "Nearby services are not set up correctly.",
    );
  }
  return { latitude: location.lat, longitude: location.lng };
}

/** Logs what Google said was wrong, and picks the message for the app. */
async function googleError(api: string, response: Response): Promise<GoogleError> {
  console.error(`${api} error ${response.status}:`, await response.text());
  if (response.status === 401 || response.status === 403) {
    return new GoogleError(500, "Nearby services are not set up correctly.");
  }
  if (response.status === 429) {
    return new GoogleError(503, "Nearby services are busy right now. Try again soon.");
  }
  return new GoogleError(502, "Nearby services ran into a problem. Try again.");
}
