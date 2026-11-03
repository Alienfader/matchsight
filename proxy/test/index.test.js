// CopaHUD AI proxy — the Worker that holds the Meta key so the iPhone app
// never ships it. Run: `node --test` (Node 22, no dependencies).
import { test } from "node:test";
import assert from "node:assert/strict";
import { handle } from "../src/index.js";

const URL_OK = "https://copahud-ai.example.workers.dev/v1/chat/completions";
const env = { APP_TOKEN: "app-token", MODEL_API_KEY: "test-key" };

const validBody = {
  model: "muse-spark-1.3",
  messages: [{ role: "user", content: "F1: Score: Brazil 2–1 Morocco" }],
  max_completion_tokens: 300,
};

function req({ url = URL_OK, method = "POST", token = "app-token", body = validBody } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (token !== null) headers["X-CopaHUD-Token"] = token;
  const init = { method, headers };
  if (method !== "GET") init.body = typeof body === "string" ? body : JSON.stringify(body);
  return new Request(url, init);
}

/** Records upstream calls; answers with `status`/`body`. */
function upstream(status = 200, body = { choices: [] }) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    return new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json", "X-Upstream-Secret": "leak" },
    });
  };
  return { calls, fetchImpl };
}

test("rejects wrong path", async () => {
  const u = upstream();
  const res = await handle(req({ url: "https://x.workers.dev/v1/models" }), env, u.fetchImpl);
  assert.equal(res.status, 404);
  assert.equal(u.calls.length, 0);
});

test("rejects GET", async () => {
  const u = upstream();
  const res = await handle(req({ method: "GET" }), env, u.fetchImpl);
  assert.equal(res.status, 405);
});

test("rejects missing token without calling upstream", async () => {
  const u = upstream();
  const res = await handle(req({ token: null }), env, u.fetchImpl);
  assert.equal(res.status, 401);
  assert.deepEqual(await res.json(), { error: { message: "invalid app token" } });
  assert.equal(u.calls.length, 0);
});

test("rejects wrong token", async () => {
  const u = upstream();
  const res = await handle(req({ token: "app-tokem" }), env, u.fetchImpl);
  assert.equal(res.status, 401);
  assert.equal(u.calls.length, 0);
});

test("rejects empty APP_TOKEN env", async () => {
  const u = upstream();
  const res = await handle(req({ token: "" }), { ...env, APP_TOKEN: "" }, u.fetchImpl);
  assert.equal(res.status, 401);
  assert.equal(u.calls.length, 0);
});

test("rejects disallowed model", async () => {
  const u = upstream();
  const res = await handle(req({ body: { ...validBody, model: "muse-wonder-1.0" } }), env, u.fetchImpl);
  assert.equal(res.status, 400);
  assert.equal(u.calls.length, 0);
});

test("rejects oversized max tokens", async () => {
  const u = upstream();
  const res = await handle(req({ body: { ...validBody, max_completion_tokens: 1501 } }), env, u.fetchImpl);
  assert.equal(res.status, 400);
});

test("rejects stream", async () => {
  const u = upstream();
  const res = await handle(req({ body: { ...validBody, stream: true } }), env, u.fetchImpl);
  assert.equal(res.status, 400);
});

test("rejects malformed JSON", async () => {
  const u = upstream();
  const res = await handle(req({ body: "{not json" }), env, u.fetchImpl);
  assert.equal(res.status, 400);
});

test("rejects oversized body", async () => {
  const u = upstream();
  const big = { ...validBody, messages: [{ role: "user", content: "x".repeat(33000) }] };
  const res = await handle(req({ body: big }), env, u.fetchImpl);
  assert.equal(res.status, 413);
  assert.equal(u.calls.length, 0);
});

test("rate limited", async () => {
  const u = upstream();
  const limiter = { limit: async ({ key }) => ({ success: key !== "app-token" }) };
  const res = await handle(req(), { ...env, RATE_LIMITER: limiter }, u.fetchImpl);
  assert.equal(res.status, 429);
  assert.equal(u.calls.length, 0);
});

test("forwards with server key", async () => {
  const u = upstream(200, { choices: [{ message: { content: "{}" } }] });
  const res = await handle(req(), env, u.fetchImpl);
  assert.equal(res.status, 200);
  assert.equal(u.calls.length, 1);
  const { url, init } = u.calls[0];
  assert.equal(url, "https://api.meta.ai/v1/chat/completions");
  assert.equal(init.method, "POST");
  assert.equal(init.headers["Authorization"], "Bearer test-key");
  assert.deepEqual(JSON.parse(init.body), { ...validBody, n: 1, stream: false });
  assert.equal(init.headers["X-CopaHUD-Token"], undefined);   // app token never leaves
  assert.equal(res.headers.get("X-Upstream-Secret"), null);   // upstream headers stripped
  assert.equal(res.headers.get("Content-Type"), "application/json");
});

test("passes upstream 402 through", async () => {
  const body = { error: { message: "Billing verification failed." } };
  const u = upstream(402, body);
  const res = await handle(req(), env, u.fetchImpl);
  assert.equal(res.status, 402);
  assert.deepEqual(await res.json(), body);
});

test("upstream failure is 502", async () => {
  const res = await handle(req(), env, async () => { throw new Error("dns"); });
  assert.equal(res.status, 502);
  assert.deepEqual(await res.json(), { error: { message: "upstream unreachable" } });
});

// Review fixes: the upstream body is rebuilt from allowlisted fields, so the
// cost caps can't be sidestepped with aliases, junk values or extra fields.

test("sanitises body: drops unknown fields, forces n:1 and no stream", async () => {
  const u = upstream();
  const res = await handle(req({ body: { ...validBody, max_tokens: 100000, n: 50, tools: [], extra: 1 } }),
                           env, u.fetchImpl);
  assert.equal(res.status, 200);
  const sent = JSON.parse(u.calls[0].init.body);
  assert.deepEqual(Object.keys(sent).sort(),
                   ["max_completion_tokens", "messages", "model", "n", "stream"]);
  assert.equal(sent.n, 1);
  assert.equal(sent.stream, false);
  assert.equal(sent.max_completion_tokens, 300);
});

test("defaults max tokens to 1500 when absent", async () => {
  const u = upstream();
  const { max_completion_tokens, ...noCap } = validBody;
  await handle(req({ body: noCap }), env, u.fetchImpl);
  assert.equal(JSON.parse(u.calls[0].init.body).max_completion_tokens, 1500);
});

test("rejects non-integer or non-positive max tokens", async () => {
  for (const bad of ["abc", -5, 0, 12.5, "300"]) {
    const u = upstream();
    const res = await handle(req({ body: { ...validBody, max_completion_tokens: bad } }), env, u.fetchImpl);
    assert.equal(res.status, 400, `value ${JSON.stringify(bad)}`);
    assert.equal(u.calls.length, 0);
  }
});

test("rejects non-object body and non-array messages", async () => {
  for (const bad of [null, [], 42, { model: "muse-spark-1.3", messages: "hi" }]) {
    const u = upstream();
    const res = await handle(req({ body: JSON.stringify(bad) }), env, u.fetchImpl);
    assert.equal(res.status, 400, `body ${JSON.stringify(bad)}`);
    assert.equal(u.calls.length, 0);
  }
});

test("keeps allowlisted optional fields", async () => {
  const u = upstream();
  const extras = { temperature: 0.3, reasoning_effort: "low",
                   response_format: { type: "json_schema", json_schema: { name: "x", schema: {} } } };
  await handle(req({ body: { ...validBody, ...extras } }), env, u.fetchImpl);
  const sent = JSON.parse(u.calls[0].init.body);
  assert.equal(sent.temperature, 0.3);
  assert.equal(sent.reasoning_effort, "low");
  assert.deepEqual(sent.response_format, extras.response_format);
});

test("missing MODEL_API_KEY is 500 without calling upstream", async () => {
  const u = upstream();
  const res = await handle(req(), { APP_TOKEN: "app-token" }, u.fetchImpl);
  assert.equal(res.status, 500);
  assert.deepEqual(await res.json(), { error: { message: "proxy misconfigured: MODEL_API_KEY not set" } });
  assert.equal(u.calls.length, 0);
});

test("upstream 401/403 bodies are replaced so nothing about the key leaks", async () => {
  for (const status of [401, 403]) {
    const u = upstream(status, { error: { message: "Invalid key LLM_1234…abcd" } });
    const res = await handle(req(), env, u.fetchImpl);
    assert.equal(res.status, status);
    assert.deepEqual(await res.json(), { error: { message: "upstream rejected the proxy's Meta key" } });
  }
});

// ---- Muse Voice Transcribe route: POST /v1/asr/transcribe -----------------

const ASR_URL = "https://copahud-ai.example.workers.dev/v1/asr/transcribe";
const WAV = new Uint8Array([82, 73, 70, 70, 1, 2, 3, 4]);   // bytes only; Meta validates WAV

function asrReq({ token = "app-token", settings = { model: "muse-voice-transcribe-1.0",
                  audioEncoding: "WAV", mode: "PUSH_TO_TALK", keywords: ["Paquetá", "Rodrygo"] },
                  audio = WAV } = {}) {
  const form = new FormData();
  if (settings !== null) {
    form.append("request", new Blob([JSON.stringify(settings)], { type: "application/json" }));
  }
  if (audio !== null) form.append("audio", new Blob([audio], { type: "audio/wav" }), "question.wav");
  const headers = {};
  if (token !== null) headers["X-CopaHUD-Token"] = token;
  return new Request(ASR_URL, { method: "POST", headers, body: form });
}

/** Parses the multipart body the Worker forwarded upstream. */
async function forwardedForm(call) {
  return new Request("https://x/", { method: "POST", headers: call.init.headers, body: call.init.body }).formData();
}

test("transcribe: rejects missing token", async () => {
  const u = upstream();
  const res = await handle(asrReq({ token: null }), env, u.fetchImpl);
  assert.equal(res.status, 401);
  assert.equal(u.calls.length, 0);
});

test("transcribe: rejects wrong model", async () => {
  const u = upstream();
  const res = await handle(asrReq({ settings: { model: "muse-spark-1.3" } }), env, u.fetchImpl);
  assert.equal(res.status, 400);
  assert.equal(u.calls.length, 0);
});

test("transcribe: rejects missing audio or settings", async () => {
  for (const r of [asrReq({ audio: null }), asrReq({ settings: null })]) {
    const u = upstream();
    const res = await handle(r, env, u.fetchImpl);
    assert.equal(res.status, 400);
    assert.equal(u.calls.length, 0);
  }
});

test("transcribe: rejects oversized audio", async () => {
  const u = upstream();
  const res = await handle(asrReq({ audio: new Uint8Array(1_048_577) }), env, u.fetchImpl);
  assert.equal(res.status, 413);
  assert.equal(u.calls.length, 0);
});

test("transcribe: forwards rebuilt form with server key", async () => {
  const u = upstream(200, { sessionId: "s", transcript: "hi", audioDurationMs: 900, turns: [] });
  const junk = ["ok", 42, "x".repeat(65), ...Array.from({ length: 60 }, (_, i) => `P${i}`)];
  const res = await handle(asrReq({ settings: { model: "muse-voice-transcribe-1.0", mode: "DIARIZATION",
                                                keywords: junk, extra: true } }), env, u.fetchImpl);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { sessionId: "s", transcript: "hi", audioDurationMs: 900, turns: [] });
  const call = u.calls[0];
  assert.equal(call.url, "https://api.meta.ai/v1/asr/transcribe");
  assert.equal(call.init.headers["Authorization"], "Bearer test-key");
  assert.equal(call.init.headers["X-CopaHUD-Token"], undefined);
  const form = await forwardedForm(call);
  const settings = JSON.parse(await (async (v) => typeof v === "string" ? v : v.text())(form.get("request")));
  assert.deepEqual(Object.keys(settings).sort(), ["audioEncoding", "keywords", "mode", "model"]);
  assert.equal(settings.mode, "PUSH_TO_TALK");
  assert.equal(settings.audioEncoding, "WAV");
  assert.equal(settings.keywords.length, 50);
  assert.ok(settings.keywords.every((k) => typeof k === "string" && k.length <= 64));
  assert.deepEqual(new Uint8Array(await form.get("audio").arrayBuffer()), WAV);
});

test("transcribe: passes upstream status through", async () => {
  const u = upstream(400, { error: { message: "Unsupported WAV" } });
  const res = await handle(asrReq(), env, u.fetchImpl);
  assert.equal(res.status, 400);
  assert.deepEqual(await res.json(), { error: { message: "Unsupported WAV" } });
});

test("transcribe: GET is 405", async () => {
  const res = await handle(new Request(ASR_URL, { headers: { "X-CopaHUD-Token": "app-token" } }), env, upstream().fetchImpl);
  assert.equal(res.status, 405);
});

test("transcribe: oversized body is 413 even without Content-Length", async () => {
  const u = upstream();
  // Stream the body so no Content-Length is set: the cap must hold while reading.
  const big = new Uint8Array(2 * 1024 * 1024 + 10);
  const stream = new ReadableStream({ start(c) { c.enqueue(big); c.close(); } });
  const r = new Request(ASR_URL, {
    method: "POST", body: stream, duplex: "half",
    headers: { "X-CopaHUD-Token": "app-token", "Content-Type": "multipart/form-data; boundary=x" },
  });
  assert.equal(r.headers.get("Content-Length"), null);
  const res = await handle(r, env, u.fetchImpl);
  assert.equal(res.status, 413);
  assert.equal(u.calls.length, 0);
});

// ---- Text to speech (spoken answers, ElevenLabs) ----

const TTS_URL = "https://copahud-ai.example.workers.dev/v1/tts";
const ttsEnv = { ...env, ELEVENLABS_API_KEY: "el-key", ELEVENLABS_VOICE_ID: "voice123" };

/** Answers like ElevenLabs: MP3 bytes. */
function audioUpstream(status = 200) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    const body = status === 200 ? new Uint8Array([0x49, 0x44, 0x33, 1, 2, 3]) : JSON.stringify({ detail: "x" });
    return new Response(body, {
      status,
      headers: { "Content-Type": status === 200 ? "audio/mpeg" : "application/json", "X-Upstream-Secret": "leak" },
    });
  };
  return { calls, fetchImpl };
}

test("tts: forwards the text to the server's voice and returns MP3", async () => {
  const u = audioUpstream();
  const res = await handle(req({ url: TTS_URL, body: { text: "Two nil to United." } }), ttsEnv, u.fetchImpl);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("Content-Type"), "audio/mpeg");
  assert.equal(res.headers.get("X-Upstream-Secret"), null);
  assert.deepEqual([...new Uint8Array(await res.arrayBuffer())], [0x49, 0x44, 0x33, 1, 2, 3]);
  assert.equal(u.calls.length, 1);
  const { url, init } = u.calls[0];
  assert.ok(url.startsWith("https://api.elevenlabs.io/v1/text-to-speech/voice123"));
  assert.ok(url.includes("output_format=mp3_44100_64"));
  assert.equal(init.headers["xi-api-key"], "el-key");
  const sent = JSON.parse(init.body);
  assert.deepEqual(Object.keys(sent).sort(), ["model_id", "text"]);
  assert.equal(sent.text, "Two nil to United.");
});

test("tts: the app can't pick the voice, the model or extra settings", async () => {
  const u = audioUpstream();
  await handle(req({ url: TTS_URL, body: { text: "Hi", voice_id: "other", model_id: "x", seed: 1 } }),
               ttsEnv, u.fetchImpl);
  assert.ok(u.calls[0].url.includes("/voice123"));
  const sent = JSON.parse(u.calls[0].init.body);
  assert.equal(sent.model_id, "eleven_flash_v2_5");
  assert.equal(sent.seed, undefined);
});

test("tts: needs the app token", async () => {
  const u = audioUpstream();
  const res = await handle(req({ url: TTS_URL, token: "nope", body: { text: "Hi" } }), ttsEnv, u.fetchImpl);
  assert.equal(res.status, 401);
  assert.equal(u.calls.length, 0);
});

test("tts: empty or overlong text is refused", async () => {
  const u = audioUpstream();
  for (const text of ["", "   ", 42, "x".repeat(801)]) {
    const res = await handle(req({ url: TTS_URL, body: { text } }), ttsEnv, u.fetchImpl);
    assert.equal(res.status, 400, String(text).slice(0, 10));
  }
  assert.equal(u.calls.length, 0);
});

test("tts: a missing ElevenLabs key or voice is a clear 500", async () => {
  const u = audioUpstream();
  const res = await handle(req({ url: TTS_URL, body: { text: "Hi" } }), env, u.fetchImpl);
  assert.equal(res.status, 500);
  assert.match((await res.json()).error.message, /ELEVENLABS/);
  assert.equal(u.calls.length, 0);
});

test("tts: works without the Meta key", async () => {
  const u = audioUpstream();
  const { MODEL_API_KEY, ...noMeta } = ttsEnv;
  const res = await handle(req({ url: TTS_URL, body: { text: "Hi" } }), noMeta, u.fetchImpl);
  assert.equal(res.status, 200);
});

test("tts: a rejected key is reported without the upstream body", async () => {
  const u = audioUpstream(401);
  const res = await handle(req({ url: TTS_URL, body: { text: "Hi" } }), ttsEnv, u.fetchImpl);
  assert.equal(res.status, 401);
  assert.deepEqual(await res.json(), { error: { message: "upstream rejected the proxy's ElevenLabs key" } });
});

test("tts: other upstream errors keep their status", async () => {
  const u = audioUpstream(429);
  const res = await handle(req({ url: TTS_URL, body: { text: "Hi" } }), ttsEnv, u.fetchImpl);
  assert.equal(res.status, 429);
  assert.equal(res.headers.get("Content-Type"), "application/json");
});
