#!/usr/bin/env node
// Read-only MCP server (stdio) for TestFlight beta feedback from the App Store Connect API.
//
// No dependencies: Node 18+ only. It signs its own ES256 JWT with the App Store Connect API key
// that scripts/testflight.sh already uses, and only ever sends GET requests.
//
// Config (environment):
//   ASC_KEY_ID      key ID. Falls back to ~/.config/dogear/env, then to the only AuthKey_*.p8 in
//                   ~/.appstoreconnect/private_keys
//   ASC_ISSUER_ID   issuer ID. Falls back to ~/.config/dogear/env, then to the first line of
//                   ~/.appstoreconnect/issuer_id
//   ASC_KEY_PATH    defaults to ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
//   ASC_BUNDLE_ID   defaults to computer.srcery.dogear
//   ASC_FEEDBACK_DIR  where screenshots and crash logs are saved; defaults to <repo>/.build/testflight-feedback
//   ASC_API_BASE    defaults to https://api.appstoreconnect.apple.com (tests point it at a fake)

import { createPrivateKey, createSign } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const ASC_DIR = join(homedir(), ".appstoreconnect");
const API_BASE = (process.env.ASC_API_BASE || "https://api.appstoreconnect.apple.com").replace(/\/$/, "");
const BUNDLE_ID = process.env.ASC_BUNDLE_ID || "computer.srcery.dogear";
const FEEDBACK_DIR = process.env.ASC_FEEDBACK_DIR || join(REPO_ROOT, ".build", "testflight-feedback");
const MAX_INLINE_IMAGES = 3;

// ---------- Credentials and JWT ----------

// Local config file holding the ASC_ values. Claude Code starts this server without sourcing it,
// so read the two values from it directly: `[export ]NAME=value` lines only.
function dogearEnv() {
  const file = join(homedir(), ".config", "dogear", "env");
  const vars = {};
  if (!existsSync(file)) return vars;
  for (const line of readFileSync(file, "utf8").split("\n")) {
    const m = line.match(/^\s*(?:export\s+)?(ASC_KEY_ID|ASC_ISSUER_ID)=(.*)$/);
    if (m) vars[m[1]] = m[2].trim().replace(/^(['"])(.*)\1$/, "$2");
  }
  return vars;
}

function loadConfig() {
  const local = dogearEnv();
  let keyId = process.env.ASC_KEY_ID || local.ASC_KEY_ID;
  if (!keyId) {
    const dir = join(ASC_DIR, "private_keys");
    const keys = existsSync(dir) ? readdirSync(dir).filter((f) => /^AuthKey_.+\.p8$/.test(f)) : [];
    if (keys.length === 1) keyId = keys[0].slice("AuthKey_".length, -".p8".length);
    else throw new Error(keys.length ? `Several keys in ${dir}; set ASC_KEY_ID.` : "Set ASC_KEY_ID (no key found in ~/.appstoreconnect/private_keys).");
  }
  let issuerId = process.env.ASC_ISSUER_ID || local.ASC_ISSUER_ID;
  if (!issuerId && existsSync(join(ASC_DIR, "issuer_id"))) {
    issuerId = readFileSync(join(ASC_DIR, "issuer_id"), "utf8").split("\n")[0].trim();
  }
  if (!issuerId) throw new Error("Set ASC_ISSUER_ID (environment or ~/.config/dogear/env), or put it in ~/.appstoreconnect/issuer_id.");
  const keyPath = process.env.ASC_KEY_PATH || join(ASC_DIR, "private_keys", `AuthKey_${keyId}.p8`);
  if (!existsSync(keyPath)) throw new Error(`API key not found at ${keyPath}`);
  return { keyId, issuerId, key: createPrivateKey(readFileSync(keyPath)) };
}

let config;
let token = { value: null, exp: 0 };

const b64url = (buf) => Buffer.from(buf).toString("base64url");

function jwt() {
  const now = Math.floor(Date.now() / 1000);
  if (token.value && token.exp - 60 > now) return token.value;
  config ??= loadConfig();
  const exp = now + 15 * 60; // Apple allows up to 20 minutes.
  const header = b64url(JSON.stringify({ alg: "ES256", kid: config.keyId, typ: "JWT" }));
  const payload = b64url(JSON.stringify({ iss: config.issuerId, iat: now, exp, aud: "appstoreconnect-v1" }));
  const signer = createSign("SHA256");
  signer.update(`${header}.${payload}`);
  const sig = signer.sign({ key: config.key, dsaEncoding: "ieee-p1363" });
  token = { value: `${header}.${payload}.${b64url(sig)}`, exp };
  return token.value;
}

// ---------- API ----------

async function api(path, params = {}) {
  const url = new URL(API_BASE + path);
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== null && v !== "") url.searchParams.set(k, String(v));
  const res = await fetch(url, { headers: { Authorization: `Bearer ${jwt()}`, Accept: "application/json" } });
  const text = await res.text();
  if (!res.ok) {
    let detail = text;
    try {
      detail = JSON.parse(text).errors.map((e) => `${e.title}: ${e.detail}`).join("; ");
    } catch {}
    throw new Error(`App Store Connect ${res.status} on GET ${url.pathname}: ${detail}`);
  }
  return JSON.parse(text);
}

let appId = process.env.ASC_APP_ID || null;
async function getAppId() {
  if (appId) return appId;
  const res = await api("/v1/apps", { "filter[bundleId]": BUNDLE_ID, "fields[apps]": "bundleId,name" });
  const app = res.data.find((a) => a.attributes?.bundleId === BUNDLE_ID) || res.data[0];
  if (!app) throw new Error(`No app with bundle ID ${BUNDLE_ID} is visible to this API key.`);
  appId = app.id;
  return appId;
}

const KINDS = {
  screenshot: { type: "betaFeedbackScreenshotSubmissions" },
  crash: { type: "betaFeedbackCrashSubmissions" },
};

function indexIncluded(included = []) {
  const map = new Map();
  for (const r of included) map.set(`${r.type}/${r.id}`, r);
  return map;
}

function summarize(item, kind, included) {
  const a = item.attributes || {};
  const buildRef = item.relationships?.build?.data;
  const testerRef = item.relationships?.tester?.data;
  const build = buildRef && included.get(`${buildRef.type}/${buildRef.id}`);
  const tester = testerRef && included.get(`${testerRef.type}/${testerRef.id}`);
  const testerName = tester ? [tester.attributes?.firstName, tester.attributes?.lastName].filter(Boolean).join(" ") : null;
  return {
    id: item.id,
    kind,
    createdDate: a.createdDate,
    comment: a.comment ?? null,
    tester: testerName || a.email || tester?.attributes?.email || null,
    build: build ? { id: build.id, version: build.attributes?.version, uploadedDate: build.attributes?.uploadedDate } : buildRef ? { id: buildRef.id } : null,
    device: [a.deviceModel, a.osVersion && `iOS ${a.osVersion}`].filter(Boolean).join(", ") || null,
    screenshotCount: Array.isArray(a.screenshots) ? a.screenshots.length : undefined,
  };
}

async function listFeedback({ kind = "all", limit = 20, build_id, since }) {
  const id = await getAppId();
  const kinds = kind === "all" ? ["screenshot", "crash"] : [kind];
  const n = Math.max(1, Math.min(Number(limit) || 20, 200));
  const results = [];
  for (const k of kinds) {
    const res = await api(`/v1/apps/${id}/${KINDS[k].type}`, {
      sort: "-createdDate",
      limit: n,
      include: "build,tester",
      "filter[build]": build_id,
    });
    const inc = indexIncluded(res.included);
    for (const item of res.data) results.push(summarize(item, k, inc));
  }
  let out = results.sort((x, y) => String(y.createdDate).localeCompare(String(x.createdDate)));
  if (since) out = out.filter((r) => r.createdDate && r.createdDate >= since);
  return out.slice(0, n);
}

function safeName(s) {
  return String(s).replace(/[^A-Za-z0-9._-]/g, "_");
}

async function getFeedback({ id, kind }) {
  if (!id) throw new Error("id is required");
  const kindsToTry = kind ? [kind] : ["screenshot", "crash"];
  let res, k;
  let lastErr;
  for (k of kindsToTry) {
    try {
      res = await api(`/v1/${KINDS[k].type}/${encodeURIComponent(id)}`, { include: "build,tester" });
      break;
    } catch (e) {
      lastErr = e;
      res = null;
    }
  }
  if (!res) throw lastErr;
  const item = res.data;
  const a = item.attributes || {};
  const inc = indexIncluded(res.included);
  const dir = join(FEEDBACK_DIR, safeName(item.id));
  mkdirSync(dir, { recursive: true });

  const detail = { ...summarize(item, k, inc), attributes: { ...a } };
  delete detail.attributes.screenshots;
  delete detail.attributes.email;

  const images = [];
  const saved = [];
  for (const [i, shot] of (a.screenshots || []).entries()) {
    // Screenshot URLs are signed CDN links; they need no auth header and expire.
    const r = await fetch(shot.url);
    if (!r.ok) {
      saved.push({ index: i, error: `download failed (${r.status}); link expires ${shot.expirationDate}` });
      continue;
    }
    const mime = r.headers.get("content-type")?.split(";")[0] || "image/jpeg";
    const buf = Buffer.from(await r.arrayBuffer());
    const file = join(dir, `screenshot-${i + 1}.${mime.includes("png") ? "png" : "jpg"}`);
    writeFileSync(file, buf);
    saved.push({ index: i, path: file, width: shot.width, height: shot.height });
    if (images.length < MAX_INLINE_IMAGES) images.push({ type: "image", data: buf.toString("base64"), mimeType: mime });
  }
  if (saved.length) detail.screenshots = saved;

  if (k === "crash") {
    try {
      const log = await api(`/v1/betaFeedbackCrashSubmissions/${encodeURIComponent(item.id)}/crashLog`);
      const text = log.data?.attributes?.logText || "";
      const file = join(dir, "crash.log");
      writeFileSync(file, text);
      detail.crashLog = { path: file, bytes: text.length, head: text.slice(0, 6000) };
    } catch (e) {
      detail.crashLog = { error: e.message };
    }
  }
  writeFileSync(join(dir, "feedback.json"), JSON.stringify(detail, null, 2));
  return { detail, images };
}

// ---------- MCP plumbing ----------

const TOOLS = [
  {
    name: "list_testflight_feedback",
    description:
      "List recent TestFlight beta feedback for Dogear, newest first: screenshot feedback (tester comment plus screenshots) and crash feedback. Returns ids, comments, tester, build and device. Use get_testflight_feedback for screenshots and crash logs.",
    inputSchema: {
      type: "object",
      properties: {
        kind: { type: "string", enum: ["all", "screenshot", "crash"], default: "all" },
        limit: { type: "integer", minimum: 1, maximum: 200, default: 20 },
        build_id: { type: "string", description: "Only feedback for this App Store Connect build id." },
        since: { type: "string", description: "ISO 8601 date; only feedback created at or after it." },
      },
    },
  },
  {
    name: "get_testflight_feedback",
    description:
      "Get one TestFlight feedback submission in full: all device details, the screenshots (shown inline and saved under .build/testflight-feedback/<id>/), and for crash feedback the crash log (saved as crash.log, first part returned).",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", description: "Submission id from list_testflight_feedback." },
        kind: { type: "string", enum: ["screenshot", "crash"], description: "Optional; speeds up the lookup." },
      },
      required: ["id"],
    },
  },
];

async function callTool(name, args = {}) {
  if (name === "list_testflight_feedback") {
    const items = await listFeedback(args);
    return { content: [{ type: "text", text: JSON.stringify({ count: items.length, items }, null, 2) }] };
  }
  if (name === "get_testflight_feedback") {
    const { detail, images } = await getFeedback(args);
    return { content: [{ type: "text", text: JSON.stringify(detail, null, 2) }, ...images] };
  }
  throw new Error(`Unknown tool ${name}`);
}

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + "\n");
}

async function handle(msg) {
  const { id, method, params } = msg;
  if (id === undefined) return; // notification
  try {
    let result;
    if (method === "initialize") {
      result = {
        protocolVersion: params?.protocolVersion || "2025-06-18",
        capabilities: { tools: {} },
        serverInfo: { name: "testflight-feedback", version: "1.0.0" },
      };
    } else if (method === "ping") result = {};
    else if (method === "tools/list") result = { tools: TOOLS };
    else if (method === "tools/call") {
      try {
        result = await callTool(params?.name, params?.arguments);
      } catch (e) {
        result = { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
      }
    } else {
      send({ jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } });
      return;
    }
    send({ jsonrpc: "2.0", id, result });
  } catch (e) {
    send({ jsonrpc: "2.0", id, error: { code: -32603, message: e.message } });
  }
}

const rl = createInterface({ input: process.stdin });
rl.on("line", (line) => {
  if (!line.trim()) return;
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    send({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
    return;
  }
  handle(msg);
});
