// The relay's wire format. The only thing the relay ever reads is the first character of a frame
// and, where a frame names a peer, the number before the first ":". Payloads are opaque text.
//
// joiner -> relay   M<payload>                  to the host
// relay  -> joiner  M<payload>                  from the host
//                   H  host is away (relay is holding the room)      B  host is back
//                   X<code>  final: the relay is about to disconnect you (code = reason)
// host   -> relay   S<peer>:<payload>           to one joiner
//                   K<peer>:<code>              disconnect a joiner (after anything sent before)
//                   Q                            the host is leaving for good: close the room
// relay  -> host    M<peer>:<payload>           from a joiner
//                   J<peer>   a joiner arrived        L<peer>  a joiner left
// relay  -> any     C<json>                     control: hosted / joined / resumed / error
// any    -> relay   "ping"                      answered "pong" by the runtime, never woken for
// resume (first frame on /resume/<code>):  R<token>

export const KEEPALIVE_REQUEST = "ping";
export const KEEPALIVE_RESPONSE = "pong";

export type RelayError =
  | "ROOM_NOT_FOUND"
  | "ROOM_FULL"
  | "BAD_TOKEN"
  | "RATE_LIMITED"
  | "RELAY_BUSY"
  | "HOST_AWAY"
  | "ROOM_CLOSED"
  | "KICKED"
  | "TOO_LARGE"
  | "BAD_FRAME"
  | "TIMEOUT"
  | "REPLACED";

// Application close codes (4000-4999 are free for applications).
export const CLOSE_CODES: Record<string, number> = {
  ROOM_NOT_FOUND: 4404,
  ROOM_FULL: 4409,
  BAD_TOKEN: 4401,
  RATE_LIMITED: 4429,
  RELAY_BUSY: 4503,
  HOST_AWAY: 4423,
  ROOM_CLOSED: 4410,
  KICKED: 4403,
  TOO_LARGE: 1009,
  BAD_FRAME: 1003,
  TIMEOUT: 4408,
  REPLACED: 4412,
};

export function control(value: Record<string, unknown>): string {
  return "C" + JSON.stringify(value);
}

export function errorFrame(code: RelayError): string {
  return control({ t: "error", code });
}

/** Splits "<peer>:<rest>" (after the type character). Returns null if malformed. */
export function splitPeer(body: string): { peer: number; rest: string } | null {
  const colon = body.indexOf(":");
  if (colon < 1 || colon > 10) return null;
  const digits = body.slice(0, colon);
  if (!/^[0-9]+$/.test(digits)) return null;
  const peer = Number(digits);
  if (!Number.isSafeInteger(peer) || peer < 2) return null;
  return { peer, rest: body.slice(colon + 1) };
}

/** Peer ids on their own ("J2", "L2"). */
export function parsePeer(body: string): number | null {
  if (!/^[0-9]{1,10}$/.test(body)) return null;
  const peer = Number(body);
  return peer >= 2 ? peer : null;
}
