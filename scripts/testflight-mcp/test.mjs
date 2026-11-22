// Runs server.mjs against a fake App Store Connect API: `node scripts/testflight-mcp/test.mjs`.
// Checks the JWT signature, the requests the server makes, and what the tools return.
import { spawn } from "node:child_process";
import { createVerify, generateKeyPairSync } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";

const tmp = mkdtempSync(join(tmpdir(), "asc-mcp-"));
const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
writeFileSync(join(tmp, "AuthKey_TESTKEY.p8"), privateKey.export({ type: "pkcs8", format: "pem" }));

const PNG = Buffer.from("89504e470d0a1a0a0000000d4948445200000001000000010806000000" + "1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082", "hex");
const requests = [];
let base;

const fake = createServer((req, res) => {
  const url = new URL(req.url, base);
  requests.push({ method: req.method, path: url.pathname, query: Object.fromEntries(url.searchParams) });
  if (url.pathname === "/cdn/shot.png") {
    res.writeHead(200, { "content-type": "image/png" });
    return res.end(PNG);
  }
  const [h, p, s] = (req.headers.authorization || "").replace("Bearer ", "").split(".");
  const ok = h && createVerify("SHA256").update(`${h}.${p}`).verify({ key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(s, "base64url"));
  const claims = ok && JSON.parse(Buffer.from(p, "base64url"));
  if (!ok || claims.iss !== "ISSUER" || claims.aud !== "appstoreconnect-v1" || JSON.parse(Buffer.from(h, "base64url")).kid !== "TESTKEY") {
    res.writeHead(401);
    return res.end(JSON.stringify({ errors: [{ title: "NOT_AUTHORIZED", detail: "bad token" }] }));
  }
  const json = (body, code = 200) => (res.writeHead(code, { "content-type": "application/json" }), res.end(JSON.stringify(body)));
  const included = [
    { type: "builds", id: "b1", attributes: { version: "202611210900" } },
    { type: "betaTesters", id: "t1", attributes: { firstName: "Ada", lastName: "L" } },
  ];
  const rel = { build: { data: { type: "builds", id: "b1" } }, tester: { data: { type: "betaTesters", id: "t1" } } };
  const shot = { type: "betaFeedbackScreenshotSubmissions", id: "s1", attributes: { createdDate: "2026-11-21T10:00:00Z", comment: "Highlight menu covers the text", deviceModel: "iPhone16,1", osVersion: "26.1", email: "ada@example.com", screenshots: [{ url: `${base}/cdn/shot.png`, width: 1, height: 1, expirationDate: "2026-11-23T00:00:00Z" }] }, relationships: rel };
  const crash = { type: "betaFeedbackCrashSubmissions", id: "c1", attributes: { createdDate: "2026-11-21T12:00:00Z", comment: "Crashed opening a book", deviceModel: "iPhone15,2", osVersion: "26.0" }, relationships: rel };
  switch (url.pathname) {
    case "/v1/apps":
      return json({ data: [{ type: "apps", id: "app1", attributes: { bundleId: url.searchParams.get("filter[bundleId]") } }] });
    case "/v1/apps/app1/betaFeedbackScreenshotSubmissions":
      return json({ data: [shot], included });
    case "/v1/apps/app1/betaFeedbackCrashSubmissions":
      return json({ data: [crash], included });
    case "/v1/betaFeedbackScreenshotSubmissions/s1":
      return json({ data: shot, included });
    case "/v1/betaFeedbackScreenshotSubmissions/c1":
      return json({ errors: [{ title: "NOT_FOUND", detail: "nope" }] }, 404);
    case "/v1/betaFeedbackCrashSubmissions/c1":
      return json({ data: crash, included });
    case "/v1/betaFeedbackCrashSubmissions/c1/crashLog":
      return json({ data: { type: "betaCrashLogs", id: "l1", attributes: { logText: "Exception Type: EXC_BAD_ACCESS\nThread 0 Crashed: ReaderView" } } });
  }
  json({ errors: [{ title: "NOT_FOUND", detail: url.pathname }] }, 404);
});
await new Promise((r) => fake.listen(0, "127.0.0.1", r));
base = `http://127.0.0.1:${fake.address().port}`;

const server = spawn(process.execPath, [join(dirname(fileURLToPath(import.meta.url)), "server.mjs")], {
  env: { ...process.env, ASC_API_BASE: base, ASC_KEY_ID: "TESTKEY", ASC_ISSUER_ID: "ISSUER", ASC_KEY_PATH: join(tmp, "AuthKey_TESTKEY.p8"), ASC_FEEDBACK_DIR: join(tmp, "out") },
  stdio: ["pipe", "pipe", "inherit"],
});
const pending = new Map();
let buf = "";
server.stdout.on("data", (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const msg = JSON.parse(buf.slice(0, i));
    buf = buf.slice(i + 1);
    pending.get(msg.id)?.(msg);
  }
});
let nextId = 1;
const rpc = (method, params) => new Promise((r) => { const id = nextId++; pending.set(id, r); server.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n"); });
const call = async (name, args) => (await rpc("tools/call", { name, arguments: args })).result;

const init = await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "0" } });
assert.equal(init.result.serverInfo.name, "testflight-feedback");
server.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
assert.deepEqual((await rpc("tools/list")).result.tools.map((t) => t.name), ["list_testflight_feedback", "get_testflight_feedback"]);

const list = await call("list_testflight_feedback", {});
assert.ok(!list.isError, list.content[0].text);
const items = JSON.parse(list.content[0].text).items;
assert.deepEqual(items.map((i) => i.id), ["c1", "s1"], "newest first across both kinds");
assert.equal(items[1].tester, "Ada L");
assert.equal(items[1].build.version, "202611210900");
assert.equal(requests.find((r) => r.path === "/v1/apps").query["filter[bundleId]"], "computer.srcery.dogear");

const shot = await call("get_testflight_feedback", { id: "s1" });
assert.ok(!shot.isError, shot.content[0].text);
assert.equal(shot.content[1].type, "image");
assert.equal(shot.content[1].mimeType, "image/png");
const shotDetail = JSON.parse(shot.content[0].text);
assert.ok(existsSync(shotDetail.screenshots[0].path));
assert.equal(shotDetail.attributes.email, undefined, "tester email is not echoed");

const crash = await call("get_testflight_feedback", { id: "c1" });
assert.ok(!crash.isError, crash.content[0].text);
const crashDetail = JSON.parse(crash.content[0].text);
assert.equal(crashDetail.kind, "crash");
assert.match(readFileSync(crashDetail.crashLog.path, "utf8"), /EXC_BAD_ACCESS/);

assert.ok(requests.every((r) => r.method === "GET"), "read-only");
console.log(`ok: ${requests.length} GET requests, all tools behave`);
server.kill();
fake.close();
