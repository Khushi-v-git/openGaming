import type { Room } from "./room";

export interface Env {
  ROOM: DurableObjectNamespace<Room>;
  /** Optional Rate Limiting binding; only used if configured (see docs/relay.md). */
  JOIN_LIMITER?: { limit(options: { key: string }): Promise<{ success: boolean }> };
  [name: string]: unknown;
}
