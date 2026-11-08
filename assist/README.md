# Assist backend

A Cloudflare Worker that answers questions from the app's Assist tab using
Claude Haiku 5.5 (`claude-haiku-5-5`). The app sends the conversation to
`POST /chat`, and the Worker calls the Claude API and returns:

```json
{ "answer": "...", "recommendProfessional": false, "professionalReason": null }
```

Errors come back as `{ "error": "..." }` with a matching HTTP status, and the
app shows that message on screen.

The Anthropic API key and the assistant's instructions live only here, never
in the app. Each request must carry `Authorization: Bearer <APP_TOKEN>`, and
each IP address can ask 10 questions a minute.

## What you need

- [Node.js](https://nodejs.org/) (the LTS version).
- A free [Cloudflare](https://dash.cloudflare.com/sign-up) account.
- An [Anthropic Console](https://console.anthropic.com/) account with
  credits and an API key.

## First deploy

From this folder:

```sh
npm install
npx wrangler login                         # opens a browser to sign in to Cloudflare
npx wrangler secret put ANTHROPIC_API_KEY  # paste the key from the Anthropic Console
npx wrangler secret put APP_TOKEN          # paste a long random string, see below
npm run deploy
```

For `APP_TOKEN`, any long random string works. To make one:

```sh
node -e "console.log(crypto.randomUUID())"
```

`npm run deploy` prints the Worker's address, such as
`https://capstone-assist.<your-subdomain>.workers.dev`. The app needs
that address with `/chat` on the end, plus the same `APP_TOKEN`. See
"Assist tab" in the main [README](../README.md).

After changing `index.ts`, run `npm run deploy` again. Secrets stay set
between deploys.

## Watching it

- `npx wrangler tail` streams the Worker's logs, including any errors from
  the Claude API.
- The Anthropic Console's Usage page shows tokens and cost. Set a monthly
  spend limit there so a mistake can't run up a large bill.

## Nearby services

The same Worker searches Google Places for the app's Nearby services
screen, so the Google API key also stays out of the app:

- `POST /places` takes `{ "textQuery": "plumber", "location": ... }`, where
  `location` is `{ "latitude": 39.8, "longitude": -89.6 }` or
  `{ "zipCode": "62701" }`. It returns `{ "origin": ..., "places": [...] }`:
  the point searched around and Google's places. The app works out each
  business's city, hours and distance from them.
- `GET /places/photo?name=places/.../photos/...` returns one business photo.

Both need the same `Authorization: Bearer <APP_TOKEN>` as `/chat`. Each IP
address can search 30 times a minute and load 120 photos a minute.

### Setting up Google

1. In the [Google Cloud console](https://console.cloud.google.com/), create
   a project and link a billing account to it.
2. Under **APIs & Services > Library**, enable **Places API (New)** (not the
   older "Places API") and **Geocoding API**, which finds the middle of a
   ZIP code.
3. Under **APIs & Services > Credentials**, create an API key. Edit it and
   set **API restrictions** to those two APIs. Leave application
   restrictions off: the Worker calls Google, not the phone.
4. Set a daily limit under each API's **Quotas** page, and a budget alert
   under **Billing > Budgets & alerts**, so a mistake can't run up a bill.
5. From this folder:

   ```sh
   npx wrangler secret put GOOGLE_PLACES_API_KEY   # paste the key
   npm run deploy
   ```

Each search is billed as Text Search Enterprise, since it asks for ratings,
opening hours, phone numbers and websites. Google gives 1,000 of those free
each month. Each photo shown is a separate Place Photos request, and each ZIP
code search also makes one Geocoding request. Check Google's
[pricing list](https://developers.google.com/maps/billing-and-pricing/pricing)
for current prices.

`npx wrangler tail` shows Google's error messages. `REQUEST_DENIED` from the
Geocoding API usually means it isn't enabled, or the key's restrictions
leave it out.
