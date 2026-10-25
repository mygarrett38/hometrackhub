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
