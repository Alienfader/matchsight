# CopaHUD AI proxy

A Cloudflare Worker that holds the Meta Model API key, so the CopaHUD iPhone app never ships it.

```
iPhone (CopaHUD) ──X-CopaHUD-Token──▶ Worker ──Bearer MODEL_API_KEY──▶ api.meta.ai/v1/chat/completions   (Muse Spark)
                                                                    └─▶ api.meta.ai/v1/asr/transcribe     (Muse Voice Transcribe)
```

## What it allows

- Only `POST /v1/chat/completions` and `POST /v1/asr/transcribe`.
- Only with the app token, compared in constant time.
- Chat: only model `muse-spark-1.3`, `max_completion_tokens` ≤ 1500 (default 1500; Muse Spark counts reasoning tokens here), one completion, no streaming, body ≤ 32 KB. The request is rebuilt from allowed fields (`model`, `messages`, `max_completion_tokens`, `temperature`, `reasoning_effort`, `response_format`); anything else is dropped.
- Transcribe: only `muse-voice-transcribe-1.0`, `PUSH_TO_TALK`, WAV ≤ 1 MB (body ≤ 2 MB); settings are rebuilt to `{model, audioEncoding, mode, keywords}` with ≤ 50 string keywords of ≤ 64 characters.
- About 30 requests per minute per token. This is Cloudflare's soft, per-location limit, shared by every device that uses the token.

Meta's status code and JSON error body pass through (a 401/403 body is replaced with a generic message, in case it echoes the key), so the app still reports "key rejected" or a billing error accurately. Upstream headers are dropped, and nothing is logged.

## Test

```
cd proxy
node --test
```
Node 22 is enough; there are no dependencies.

## Deploy (one time, about 5 minutes)

```
cd proxy
npx wrangler login                      # opens the browser for your Cloudflare account
npx wrangler secret put MODEL_API_KEY   # paste the Meta key (LLM_…)
openssl rand -hex 24                    # copy the output: this is the app token
npx wrangler secret put APP_TOKEN       # paste that token
npx wrangler deploy                     # prints https://copahud-ai.<your-subdomain>.workers.dev
```

Smoke test (replace the URL and token):
```
curl -s https://copahud-ai.<sub>.workers.dev/v1/chat/completions \
  -H "X-CopaHUD-Token: <token>" -H "Content-Type: application/json" \
  -d '{"model":"muse-spark-1.3","max_completion_tokens":50,"messages":[{"role":"user","content":"Say hi"}]}'
```

## Point the app at it

In the app, open Settings → AI proxy:
- **Proxy URL:** `https://copahud-ai.<sub>.workers.dev`
- **Proxy token:** the `APP_TOKEN` value

When a proxy is set, it takes priority over a direct Meta key.

## Rotating

- **The Meta key:** run `npx wrangler secret put MODEL_API_KEY` again. No app change is needed.
- **The app token:** run `npx wrangler secret put APP_TOKEN`, then update it in the app's Settings.
