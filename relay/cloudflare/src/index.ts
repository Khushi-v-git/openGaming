import type { Env } from "./env";
import { CLOSE_CODES, errorFrame, type RelayError } from "./frames";
import { readLimits } from "./limits";
import { generateCode, normalizeCode } from "./room_code";

export { Room } from "./room";

const HOST_CODE_ATTEMPTS = 5;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/health") return Response.json({ ok: true, service: "onlygaming-relay" });
    if (request.headers.get("Upgrade") !== "websocket") return new Response("This relay speaks WebSocket.", { status: 426 });

    if (url.pathname === "/host") return host(request, env, url);
    const match = /^\/(join|resume)\/([^/]+)$/.exec(url.pathname);
    if (match) {
      const code = normalizeCode(decodeURIComponent(match[2]));
      if (!code) return errorSocket("ROOM_NOT_FOUND");
      if (match[1] === "join" && !(await underJoinLimit(request, env))) return errorSocket("RATE_LIMITED");
      return enter(request, env, match[1], code);
    }
    return new Response("Not found.", { status: 404 });
  },
} satisfies ExportedHandler<Env>;

/** Opens a new room under a fresh random code; a taken code is simply retried. */
async function host(request: Request, env: Env, url: URL): Promise<Response> {
  if (!(await underJoinLimit(request, env))) return errorSocket("RATE_LIMITED");
  const limits = readLimits(env);
  const fixed = limits.allowFixedCodes ? normalizeCode(url.searchParams.get("code") ?? "") : null;
  for (let attempt = 0; attempt < HOST_CODE_ATTEMPTS; attempt++) {
    const code = fixed ?? generateCode();
    const response = await forward(request, env, "host", code);
    if (response.status === 101) return response;
    if (response.status !== 409 || fixed) return failure(response);
  }
  return errorSocket("RELAY_BUSY");
}

async function enter(request: Request, env: Env, intent: string, code: string): Promise<Response> {
  const response = await forward(request, env, intent, code);
  return response.status === 101 ? response : failure(response);
}

function forward(request: Request, env: Env, intent: string, code: string): Promise<Response> {
  const headers = new Headers(request.headers);
  headers.set("x-relay-intent", intent);
  headers.set("x-relay-code", code);
  return env.ROOM.getByName(code).fetch(new Request(request, { headers }));
}

/** A refusal from the room, delivered as a WebSocket that says why and closes. */
async function failure(response: Response): Promise<Response> {
  let code: RelayError = "RELAY_BUSY";
  try {
    const body = (await response.json()) as { error?: string };
    if (body.error && body.error in CLOSE_CODES) code = body.error as RelayError;
  } catch {
    /* an unexpected answer is reported as RELAY_BUSY */
  }
  return errorSocket(code);
}

/**
 * Godot cannot read the HTTP status of a refused upgrade, so refusals complete the upgrade,
 * send one error frame and close.
 */
function errorSocket(code: RelayError): Response {
  const pair = new WebSocketPair();
  const server = pair[1];
  server.accept();
  server.send(errorFrame(code));
  server.close(CLOSE_CODES[code] ?? 1000, code);
  return new Response(null, { status: 101, webSocket: pair[0] });
}

async function underJoinLimit(request: Request, env: Env): Promise<boolean> {
  if (!env.JOIN_LIMITER) return true;
  const key = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const verdict = await env.JOIN_LIMITER.limit({ key });
  return verdict.success;
}
