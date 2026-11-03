# CopaHUD AI proxy

A Cloudflare Worker that holds the Meta Model API key and the ElevenLabs key, so the CopaHUD iPhone app never ships either.

```
iPhone (CopaHUD) ──X-CopaHUD-Token──▶ Worker ──Bearer MODEL_API_KEY──▶ api.meta.ai/v1/chat/completions   (Muse Spark)
                                                                    └─▶ api.meta.ai/v1/asr/transcribe     (Muse Voice Transcribe)
                                    └──xi-api-key ELEVENLABS_API_KEY──▶ api.elevenlabs.io/v1/text-to-speech (spoken answers)
```

## What it allows

- Only `POST /v1/chat/completions`, `POST /v1/asr/transcribe` and `POST /v1/tts`.
- Only with the app token, compared in constant time.
- Chat: only model `muse-spark-1.3`, `max_completion_tokens` ≤ 1500 (default 1500; Muse Spark counts reasoning tokens here), one completion, no streaming, body ≤ 32 KB. The request is rebuilt from allowed fields (`model`, `messages`, `max_completion_tokens`, `temperature`, `reasoning_effort`, `response_format`); anything else is dropped.
- Transcribe: only `muse-voice-transcribe-1.0`, `PUSH_TO_TALK`, WAV ≤ 1 MB (body ≤ 2 MB); settings are rebuilt to `{model, audioEncoding, mode, keywords}` with ≤ 50 string keywords of ≤ 64 characters.
- Text to speech: only `{"text": …}` from the app, 1–800 characters. The voice (`ELEVENLABS_VOICE_ID`), model (`eleven_flash_v2_5`) and format (MP3, 44.1 kHz, 64 kbps) are fixed by the Worker; the reply is the MP3. Needs `ELEVENLABS_API_KEY` and `ELEVENLABS_VOICE_ID`, not the Meta key.
- About 30 requests per minute per token. This is Cloudflare's soft, per-location limit, shared by every device that uses the token.

Meta's status code and JSON error body pass through (a 401/403 body is replaced with a generic message, in case it echoes the key; ElevenLabs errors keep their status with a generic message), so the app still reports "key rejected" or a billing error accurately. Upstream headers are dropped, and nothing is logged.

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

Optional, for spoken answers in an ElevenLabs voice:
```
npx wrangler secret put ELEVENLABS_API_KEY    # paste the ElevenLabs key
npx wrangler secret put ELEVENLABS_VOICE_ID   # a voice ID from your ElevenLabs account
```
Free ElevenLabs plans can only use the built-in voices through the API; Voice Library voices need a paid plan.

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
- **The ElevenLabs key or voice:** run `npx wrangler secret put ELEVENLABS_API_KEY` (or `ELEVENLABS_VOICE_ID`) again. No app change is needed.
- **The app token:** run `npx wrangler secret put APP_TOKEN`, then update it in the app's Settings.
