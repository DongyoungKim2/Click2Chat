#!/usr/bin/env node
import { spawn } from "node:child_process";
import { mkdir, readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const action = process.argv[2] || "status";
const supportedActions = new Set(["status", "open-project", "start-fresh-voice", "stop-voice", "toggle-voice"]);

const defaultConfig = {
  chromePath: "/Applications/Google Chrome.app",
  chatGPTURL: "https://chatgpt.com",
  projectURL: "",
  openingPrompt: "안녕! 무엇이 궁금해?",
  chromeProfileDir: join(homedir(), "Library/Application Support/Click2Chat/ChromeProfile"),
  remoteDebuggingPort: 9222,
  webLoadTimeout: 20,
  webPollInterval: 0.5,
};

const configPath = process.env.CLICK2CHAT_CONFIG || join(homedir(), "Library/Application Support/Click2Chat/config.json");
const config = await loadConfig();
const chromeBin = join(config.chromePath, "Contents/MacOS/Google Chrome");
const origin = `http://127.0.0.1:${config.remoteDebuggingPort}`;

const pageStatusExpression = String.raw`
(() => {
  const body = (document.body?.innerText || '').toLowerCase();
  const url = location.href;
  const title = document.title || '';
  const hasLogin = /\b(log in|sign up)\b|로그인|가입/.test(body);
  const unavailable = /not found|doesn't exist|couldn.t find|unavailable|찾을 수 없|사용할 수 없|권한/.test(body);
  const hasComposer = !!document.querySelector('textarea, [contenteditable="true"], [data-testid*="composer"], form');
  return { url, title, readyState: document.readyState, hasLogin, unavailable, hasComposer, bodyLength: body.length, body: body.slice(0, 500) };
})()
`;

const stopVoiceStateExpression = String.raw`
(() => {
  const visible = (el) => {
    const rect = el.getBoundingClientRect();
    const style = window.getComputedStyle(el);
    return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none' && !el.disabled;
  };
  const textFor = (el) => [
    el.getAttribute('aria-label'),
    el.getAttribute('title'),
    el.getAttribute('data-testid'),
    el.getAttribute('data-state'),
    el.innerText,
    el.value
  ].filter(Boolean).join(' ').trim().toLowerCase();
  const controls = Array.from(document.querySelectorAll('button, [role="button"], a, input[type="button"]')).filter(visible);
  const target = controls.find((el) => {
    const text = textFor(el);
    const hasStopIntent = /\b(end|stop|leave|disconnect)\b|hang up|종료|중지|나가기|끊기/i.test(text);
    const hasVoiceContext = /\b(voice|conversation|call|chat|microphone|mic)\b|음성|대화|통화|채팅|마이크/i.test(text);
    const isExplicitHangup = /\bhang up\b|끊기/i.test(text);
    return ((hasStopIntent && hasVoiceContext) || isExplicitHangup)
      && !/(stop generating|generating|dictate|attach|upload|send|submit|search|sidebar|menu|settings|history-item|options|생성|첨부|업로드|보내기|검색|설정|옵션)/i.test(text);
  });
  if (!target) return { status: 'not-active' };
  const rect = target.getBoundingClientRect();
  return { status: 'button', text: textFor(target), x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
})()
`;

const voiceStateExpression = String.raw`
(() => {
  const visible = (el) => {
    const rect = el.getBoundingClientRect();
    const style = window.getComputedStyle(el);
    return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none' && !el.disabled;
  };
  const textFor = (el) => [
    el.getAttribute('aria-label'),
    el.getAttribute('title'),
    el.getAttribute('data-testid'),
    el.getAttribute('data-state'),
    el.innerText,
    el.value
  ].filter(Boolean).join(' ').trim().toLowerCase();
  const controls = Array.from(document.querySelectorAll('button, [role="button"], a, input[type="button"]')).filter(visible);
  const active = controls.some((el) => {
    const text = textFor(el);
    return /\b(end|stop|leave)\b|hang up|종료|중지/i.test(text)
      || (/\b(close|cancel)\b|닫기|취소/i.test(text) && /(voice|call|conversation|chat|음성|통화|대화|채팅)/i.test(text));
  });
  if (active) return { status: 'active' };
  const target = controls.find((el) => {
    const text = textFor(el);
    return /^(start voice|turn on microphone|음성 시작|마이크 켜기)$/i.test(text)
      && !/(dictate|attach|upload|send|submit|search|options|history-item|conversation options|첨부|업로드|보내기|검색|옵션)/i.test(text);
  });
  if (!target) return { status: 'voice-button-missing' };
  const rect = target.getBoundingClientRect();
  return { status: 'button', x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
})()
`;

const composerStateExpression = String.raw`
(() => {
  const visible = (el) => {
    const rect = el.getBoundingClientRect();
    const style = window.getComputedStyle(el);
    return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none' && !el.disabled;
  };
  const textFor = (el) => [
    el.getAttribute('aria-label'),
    el.getAttribute('placeholder'),
    el.getAttribute('data-testid'),
    el.innerText,
    el.value
  ].filter(Boolean).join(' ').trim().toLowerCase();
  const candidates = Array.from(document.querySelectorAll('textarea, [contenteditable="true"], [role="textbox"]')).filter(visible);
  const target = candidates.find((el) => {
    const text = textFor(el);
    return /(new chat|chat with chatgpt|ask anything|type|message|메시지|입력)/i.test(text);
  }) || candidates.sort((a, b) => b.getBoundingClientRect().top - a.getBoundingClientRect().top)[0];
  if (!target) return { status: 'composer-missing' };
  const rect = target.getBoundingClientRect();
  return { status: 'composer', x: rect.left + Math.min(40, Math.max(10, rect.width / 2)), y: rect.top + rect.height / 2 };
})()
`;

async function main() {
  if (!supportedActions.has(action)) {
    throw new Error(`unknown action: ${action}`);
  }

  if (!config.projectURL && (action === "open-project" || action === "start-fresh-voice" || action === "toggle-voice")) {
    console.log("missing-project-url");
    return;
  }

  try {
    await ensureChrome();
  } catch {
    console.log("chrome-unreachable");
    return;
  }

  const target = await getOrCreateChatGPTTarget();

  if (action === "status") {
    const status = await safePageStatus(target);
    console.log(JSON.stringify(status));
    return;
  }

  if (action === "open-project") {
    await navigateAndWait(target, config.projectURL);
    await minimizeTarget(target);
    const status = await safePageStatus(target);
    console.log(mapPageStatus(status, "opened", config.projectURL));
    return;
  }

  if (action === "stop-voice") {
    const result = await stopVoiceAndWait(target);
    await minimizeTarget(target);
    console.log(result);
    return;
  }

  if (action === "toggle-voice") {
    const stopState = await currentStopVoiceState(target);
    if (stopState?.status === "button") {
      const result = await stopVoiceAndWait(target);
      await minimizeTarget(target);
      console.log(result);
      return;
    }
  }

  await navigateAndWait(target, config.projectURL);
  let status = await safePageStatus(target);
  const mapped = mapPageStatus(status, "ready", config.projectURL);
  if (mapped !== "ready") {
    await minimizeTarget(target);
    console.log(mapped);
    return;
  }

  await stopVoiceAndWait(target).catch(() => "not-active");
  await sleep(600);
  await navigateAndWait(target, config.projectURL);
  await sleep(800);

  status = await safePageStatus(target);
  if (mapPageStatus(status, "ready", config.projectURL) !== "ready") {
    await minimizeTarget(target);
    console.log(mapPageStatus(status, "ready", config.projectURL));
    return;
  }

  const startResult = await clickVoiceAndWait(target);
  if (startResult === "started") {
    await sendOpeningPrompt(target);
  }
  await minimizeTarget(target);
  console.log(startResult);
}

async function loadConfig() {
  try {
    const raw = await readFile(configPath, "utf8");
    return { ...defaultConfig, ...JSON.parse(raw) };
  } catch {
    return defaultConfig;
  }
}

async function ensureChrome() {
  await mkdir(config.chromeProfileDir, { recursive: true });
  if (await canReachDevTools()) {
    return;
  }

  spawn(chromeBin, [
    `--user-data-dir=${config.chromeProfileDir}`,
    `--remote-debugging-port=${config.remoteDebuggingPort}`,
    `--remote-allow-origins=${origin}`,
    "--no-first-run",
    "--new-window",
    config.projectURL || config.chatGPTURL,
  ], {
    detached: true,
    stdio: "ignore",
  }).unref();

  const deadline = Date.now() + config.webLoadTimeout * 1000;
  while (Date.now() < deadline) {
    if (await canReachDevTools()) {
      return;
    }
    await sleep(300);
  }
  throw new Error("Chrome DevTools endpoint did not start");
}

async function canReachDevTools() {
  try {
    const response = await fetch(`${origin}/json/version`);
    return response.ok;
  } catch {
    return false;
  }
}

async function getOrCreateChatGPTTarget() {
  let targets = await targetsJson();
  let target = targets.find((item) => item.type === "page" && item.url.includes("chatgpt.com"));
  if (target) {
    return target;
  }

  const response = await fetch(`${origin}/json/new?${encodeURIComponent(config.projectURL || config.chatGPTURL)}`, { method: "PUT" });
  if (!response.ok) {
    throw new Error(`DevTools target create failed: ${response.status}`);
  }

  const deadline = Date.now() + config.webLoadTimeout * 1000;
  while (Date.now() < deadline) {
    targets = await targetsJson();
    target = targets.find((item) => item.type === "page" && item.url.includes("chatgpt.com"));
    if (target) {
      return target;
    }
    await sleep(300);
  }
  throw new Error("ChatGPT tab not found");
}

async function targetsJson() {
  const response = await fetch(`${origin}/json/list`);
  if (!response.ok) {
    throw new Error(`DevTools target list failed: ${response.status}`);
  }
  return await response.json();
}

async function navigateAndWait(target, url) {
  const before = await safePageStatus(target);
  await evaluate(target, `location.href = ${JSON.stringify(url)}; 'navigating';`);
  const deadline = Date.now() + config.webLoadTimeout * 1000;
  while (Date.now() < deadline) {
    const status = await safePageStatus(target);
    const arrived = urlLooksNavigated(status.url, url, before.url);
    if (arrived && (status.hasLogin || status.unavailable || status.hasComposer || (status.readyState === "complete" && status.bodyLength > 0))) {
      return status;
    }
    await sleep(config.webPollInterval * 1000);
  }
  return await safePageStatus(target);
}

function urlLooksNavigated(actual, expected, previous) {
  if (!actual?.includes("chatgpt.com")) return false;
  const actualClean = cleanURL(actual);
  const expectedClean = cleanURL(expected);
  if (actualClean === expectedClean || actualClean.startsWith(`${expectedClean}/`)) {
    return true;
  }
  const projectID = expected.match(/\/g\/(g-p-[^/?#]+)/)?.[1];
  if (projectID && actual.includes(projectID)) {
    return true;
  }
  if (!projectID && actual !== previous && actual.includes("chatgpt.com")) {
    return true;
  }
  return false;
}

function cleanURL(value) {
  try {
    const url = new URL(value);
    return `${url.origin}${url.pathname}`.replace(/\/+$/, "");
  } catch {
    return String(value).split(/[?#]/)[0].replace(/\/+$/, "");
  }
}

async function safePageStatus(target) {
  try {
    return await evaluate(target, pageStatusExpression);
  } catch (error) {
    return { error: error.message || String(error), hasLogin: false, unavailable: true, hasComposer: false, url: "" };
  }
}

function mapPageStatus(status, okStatus, expectedURL = "") {
  if (status.hasLogin) return "login-required";
  if (status.unavailable) return "project-unavailable";
  if (!status.url?.includes("chatgpt.com")) return "project-unavailable";
  if (expectedURL && !urlLooksNavigated(status.url, expectedURL, "")) return "project-unavailable";
  return okStatus;
}

async function minimizeTarget(target) {
  try {
    const result = await cdp(target, "Browser.getWindowForTarget", { targetId: target.id });
    if (result?.result?.windowId) {
      await cdp(target, "Browser.setWindowBounds", {
        windowId: result.result.windowId,
        bounds: { windowState: "minimized" },
      });
    }
  } catch {
    // Minimizing is best-effort; voice startup should not fail because of it.
  }
}

async function normalizeTarget(target) {
  try {
    const result = await cdp(target, "Browser.getWindowForTarget", { targetId: target.id });
    if (result?.result?.windowId) {
      await cdp(target, "Browser.setWindowBounds", {
        windowId: result.result.windowId,
        bounds: { windowState: "normal" },
      });
    }
    await cdp(target, "Page.bringToFront");
  } catch {
    // Focusing is best-effort. The mouse event path still works for normal pages.
  }
}

async function clickVoiceAndWait(target) {
  await normalizeTarget(target);
  await grantMicrophonePermission(target);
  let state = await evaluate(target, voiceStateExpression).catch(() => ({ status: "voice-button-missing" }));
  if (state?.status === "active") return "started";
  if (state?.status !== "button") return "voice-button-missing";

  await clickAt(target, state.x, state.y);
  const deadline = Date.now() + 8000;
  while (Date.now() < deadline) {
    await sleep(500);
    state = await evaluate(target, voiceStateExpression).catch(() => ({ status: "voice-button-missing" }));
    if (state?.status === "active") return "started";
    if (state?.status === "button") {
      await clickAt(target, state.x, state.y);
    }
  }
  return "voice-button-missing";
}

async function stopVoiceAndWait(target) {
  await normalizeTarget(target);
  let state = await currentStopVoiceState(target);
  if (state?.status !== "button") return "not-active";

  await clickAt(target, state.x, state.y);
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    await sleep(300);
    state = await currentStopVoiceState(target);
    if (state?.status !== "button") return "stopped";
  }
  return "stopped";
}

async function currentStopVoiceState(target) {
  return await evaluate(target, stopVoiceStateExpression).catch(() => ({ status: "not-active" }));
}

async function sendOpeningPrompt(target) {
  const prompt = String(config.openingPrompt || "").trim();
  if (!prompt) return "skipped";

  await normalizeTarget(target);
  const composer = await evaluate(target, composerStateExpression).catch(() => ({ status: "composer-missing" }));
  if (composer?.status !== "composer") return "composer-missing";

  await clickAt(target, composer.x, composer.y);
  await sleep(200);
  await cdp(target, "Input.insertText", { text: prompt });
  await sleep(200);
  await pressEnter(target);
  return "sent";
}

async function grantMicrophonePermission(target) {
  try {
    await cdp(target, "Browser.grantPermissions", {
      origin: "https://chatgpt.com",
      permissions: ["audioCapture"],
    });
  } catch {
    // Chrome may reject this on some versions; the visible permission prompt remains the fallback.
  }
}

async function clickAt(target, x, y) {
  await cdp(target, "Input.dispatchMouseEvent", { type: "mouseMoved", x, y, button: "none" });
  await cdp(target, "Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "left", clickCount: 1 });
  await cdp(target, "Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "left", clickCount: 1 });
}

async function pressEnter(target) {
  await cdp(target, "Input.dispatchKeyEvent", {
    type: "keyDown",
    key: "Enter",
    code: "Enter",
    windowsVirtualKeyCode: 13,
    nativeVirtualKeyCode: 13,
  });
  await cdp(target, "Input.dispatchKeyEvent", {
    type: "keyUp",
    key: "Enter",
    code: "Enter",
    windowsVirtualKeyCode: 13,
    nativeVirtualKeyCode: 13,
  });
}

async function evaluate(target, expression) {
  const response = await cdp(target, "Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });

  if (response.error) {
    throw new Error(response.error.message || JSON.stringify(response.error));
  }
  if (response.result?.exceptionDetails) {
    throw new Error(response.result.exceptionDetails.text || "JavaScript exception");
  }
  return response.result?.result?.value;
}

async function cdp(target, method, params = {}) {
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    ws.addEventListener("open", resolve, { once: true });
    ws.addEventListener("error", reject, { once: true });
  });

  const payload = { id: 1, method, params };
  const response = await new Promise((resolve, reject) => {
    const onMessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.id === payload.id) {
        ws.removeEventListener("message", onMessage);
        resolve(data);
      }
    };
    ws.addEventListener("message", onMessage);
    ws.addEventListener("error", reject, { once: true });
    ws.send(JSON.stringify(payload));
  });
  ws.close();
  return response;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((error) => {
  console.error(error.message || String(error));
  process.exit(1);
});
