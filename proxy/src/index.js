// CopaHUD AI proxy (Cloudflare Worker).
//
// The iPhone app sends the AI analyst's chat-completions request here with a
// per-app token; this Worker checks it, keeps the request inside tight limits,
// and forwards it to Meta Model API with the server-held key. The Meta key
// never ships in the app. Nothing here logs bodies, keys or tokens.

const META = "https://api.meta.ai";
const CHAT_PATH = "/v1/chat/completions";
const ASR_PATH = "/v1/asr/transcribe";
const ALLOWED_MODELS = new Set(["muse-spark-1.3"]);
const ASR_MODEL = "muse-voice-transcribe-1.0";
// Muse Spark counts reasoning tokens here (~250 at "minimal"); the app sends 1200.
const MAX_COMPLETION_TOKENS = 1500;
const MAX_BODY_BYTES = 32768;
const MAX_ASR_BODY_BYTES = 2 * 1024 * 1024;
const MAX_AUDIO_BYTES = 1024 * 1024;           // ~30 s of 16 kHz mono PCM
const MAX_KEYWORDS = 50;
const MAX_KEYWORD_LENGTH = 64;
// Optional request fields forwarded as-is; everything else is dropped so
// aliases like `max_tokens`, `n` or `tools` can't sidestep the caps.
const PASSTHROUGH_FIELDS = ["temperature", "reasoning_effort", "response_format"];

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function error(status, message) {
  return json(status, { error: { message } });
}

/** Length-independent comparison so the token can't be guessed by timing. */
function safeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || b.length === 0) return false;
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    diff |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  }
  return diff === 0;
}

export async function handle(request, env, fetchImpl = fetch) {
  const url = new URL(request.url);
  if (url.pathname !== CHAT_PATH && url.pathname !== ASR_PATH) return error(404, "not found");
  if (request.method !== "POST") return error(405, "method not allowed");

  const token = request.headers.get("X-CopaHUD-Token") ?? "";
  if (!safeEqual(token, env.APP_TOKEN ?? "")) return error(401, "invalid app token");
  if (!env.MODEL_API_KEY) return error(500, "proxy misconfigured: MODEL_API_KEY not set");

  if (env.RATE_LIMITER) {
    const { success } = await env.RATE_LIMITER.limit({ key: token });
    if (!success) return error(429, "rate limited");
  }

  return url.pathname === ASR_PATH
    ? transcribe(request, env, fetchImpl)
    : chat(request, env, fetchImpl);
}

/** Chat completions (AI insights): JSON body rebuilt from allowlisted fields. */
async function chat(request, env, fetchImpl) {
  const text = await request.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
    return error(413, "request too large");
  }

  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return error(400, "body is not JSON");
  }
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return error(400, "body must be a JSON object");
  }
  if (!ALLOWED_MODELS.has(body.model)) return error(400, "model not allowed");
  if (!Array.isArray(body.messages)) return error(400, "messages must be an array");
  const cap = body.max_completion_tokens ?? MAX_COMPLETION_TOKENS;
  if (!Number.isInteger(cap) || cap <= 0 || cap > MAX_COMPLETION_TOKENS) {
    return error(400, `max_completion_tokens must be an integer in 1…${MAX_COMPLETION_TOKENS}`);
  }
  if (body.stream) return error(400, "streaming not supported");

  // Rebuild from allowlisted fields: one completion, no streaming, capped.
  const outgoing = {
    model: body.model,
    messages: body.messages,
    max_completion_tokens: cap,
    n: 1,
    stream: false,
  };
  for (const field of PASSTHROUGH_FIELDS) {
    if (field in body) outgoing[field] = body[field];
  }

  return forward(fetchImpl, `${META}${CHAT_PATH}`, env, "application/json",
                 JSON.stringify(outgoing));
}

/** Muse Voice Transcribe (ask by voice): multipart rebuilt with only the
 *  settings CopaHUD uses and the WAV, size-capped. */
async function transcribe(request, env, fetchImpl) {
  if (Number(request.headers.get("Content-Length") ?? 0) > MAX_ASR_BODY_BYTES) {
    return error(413, "request too large");
  }
  // Count bytes while reading: Content-Length can be absent (chunked) or
  // wrong, and formData() would otherwise buffer whatever arrives.
  const bytes = await readCapped(request.body, MAX_ASR_BODY_BYTES);
  if (bytes === null) return error(413, "request too large");
  let form;
  try {
    form = await new Response(bytes, {
      headers: { "Content-Type": request.headers.get("Content-Type") ?? "" },
    }).formData();
  } catch {
    return error(400, "body must be multipart/form-data");
  }
  const audio = form.get("audio");
  const rawSettings = form.get("request");
  if (!audio || typeof audio === "string" || rawSettings === null) {
    return error(400, "request and audio parts are required");
  }
  if (audio.size > MAX_AUDIO_BYTES) return error(413, "audio too large");

  let settings;
  try {
    settings = JSON.parse(typeof rawSettings === "string" ? rawSettings : await rawSettings.text());
  } catch {
    return error(400, "request part is not JSON");
  }
  if (settings === null || typeof settings !== "object" || settings.model !== ASR_MODEL) {
    return error(400, "model not allowed");
  }
  const keywords = (Array.isArray(settings.keywords) ? settings.keywords : [])
    .filter((k) => typeof k === "string" && k.length > 0 && k.length <= MAX_KEYWORD_LENGTH)
    .slice(0, MAX_KEYWORDS);
  const outgoing = { model: ASR_MODEL, audioEncoding: "WAV", mode: "PUSH_TO_TALK", keywords };

  // Hand-built multipart: the settings part as a plain JSON field (as in
  // Meta's curl example), the audio part as question.wav.
  const boundary = `CopaHUD-${crypto.randomUUID()}`;
  const enc = new TextEncoder();
  const head = enc.encode(
    `--${boundary}\r\nContent-Disposition: form-data; name="request"\r\n` +
    `Content-Type: application/json\r\n\r\n${JSON.stringify(outgoing)}\r\n` +
    `--${boundary}\r\nContent-Disposition: form-data; name="audio"; filename="question.wav"\r\n` +
    `Content-Type: audio/wav\r\n\r\n`);
  const tail = enc.encode(`\r\n--${boundary}--\r\n`);
  const wav = new Uint8Array(await audio.arrayBuffer());
  const body = new Uint8Array(head.length + wav.length + tail.length);
  body.set(head, 0);
  body.set(wav, head.length);
  body.set(tail, head.length + wav.length);

  return forward(fetchImpl, `${META}${ASR_PATH}`, env,
                 `multipart/form-data; boundary=${boundary}`, body);
}

/** Reads a body stream up to `limit` bytes; null when it is larger. */
async function readCapped(stream, limit) {
  if (!stream) return new Uint8Array(0);
  const reader = stream.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > limit) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) { out.set(c, offset); offset += c.byteLength; }
  return out;
}

async function forward(fetchImpl, target, env, contentType, body) {
  let upstream;
  try {
    upstream = await fetchImpl(target, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${env.MODEL_API_KEY}`,
        "Content-Type": contentType,
        "Accept": "application/json",
      },
      body,
    });
  } catch {
    return error(502, "upstream unreachable");
  }

  // Status + body pass through so the app's error mapping (401/402/429/504)
  // keeps working; upstream headers do not. A key rejection's body is
  // replaced in case Meta echoes any part of the key back.
  if (upstream.status === 401 || upstream.status === 403) {
    return error(upstream.status, "upstream rejected the proxy's Meta key");
  }
  return new Response(await upstream.text(), {
    status: upstream.status,
    headers: { "Content-Type": "application/json" },
  });
}

export default {
  fetch(request, env) {
    return handle(request, env);
  },
};
