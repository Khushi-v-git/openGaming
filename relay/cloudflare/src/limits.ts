// Limits come from wrangler vars (strings); anything missing or unreadable falls back to a default.

export interface Limits {
  maxSockets: number;
  maxFrameChars: number;
  hostGraceSec: number;
  pingSec: number;
  watchdogSec: number;
  sweepSec: number;
  deadSec: number;
  handshakeSec: number;
  idleTtlSec: number;
  maxRoomAgeSec: number;
  peerRate: { burst: number; perSec: number };
  hostRate: { burst: number; perSec: number };
  maxViolations: number;
  bufferPerPeer: number;
  bufferMaxChars: number;
  bufferRoomLifetime: number;
  maxHostResumes: number;
  allowFixedCodes: boolean;
}

function num(value: unknown, fallback: number): number {
  const parsed = typeof value === "string" ? Number(value) : typeof value === "number" ? value : NaN;
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

export function readLimits(env: Record<string, unknown>): Limits {
  return {
    maxSockets: num(env.MAX_SOCKETS, 16),
    maxFrameChars: num(env.MAX_FRAME_CHARS, 65600),
    hostGraceSec: num(env.HOST_GRACE_SEC, 60),
    pingSec: num(env.PING_SEC, 15),
    watchdogSec: num(env.WATCHDOG_SEC, 45),
    sweepSec: num(env.SWEEP_SEC, 30),
    deadSec: num(env.DEAD_SEC, 50),
    handshakeSec: num(env.HANDSHAKE_SEC, 5),
    idleTtlSec: num(env.IDLE_TTL_SEC, 10800),
    maxRoomAgeSec: num(env.MAX_ROOM_AGE_SEC, 86400),
    peerRate: { burst: num(env.PEER_RATE_BURST, 30), perSec: num(env.PEER_RATE_PER_SEC, 20) },
    hostRate: { burst: num(env.HOST_RATE_BURST, 200), perSec: num(env.HOST_RATE_PER_SEC, 100) },
    maxViolations: num(env.MAX_VIOLATIONS, 20),
    bufferPerPeer: num(env.BUFFER_PER_PEER, 32),
    bufferMaxChars: num(env.BUFFER_MAX_CHARS, 131072),
    bufferRoomLifetime: num(env.BUFFER_ROOM_LIFETIME, 200),
    maxHostResumes: num(env.MAX_HOST_RESUMES, 20),
    allowFixedCodes: env.ALLOW_FIXED_CODES === "1",
  };
}

/** A token bucket. In memory only: after hibernation a bucket starts full, which is harmless. */
export class Bucket {
  private tokens: number;
  private last: number;
  constructor(private burst: number, private perSec: number, now: number) {
    this.tokens = burst;
    this.last = now;
  }
  allow(now: number): boolean {
    this.tokens = Math.min(this.burst, this.tokens + ((now - this.last) / 1000) * this.perSec);
    this.last = now;
    if (this.tokens >= 1) {
      this.tokens -= 1;
      return true;
    }
    return false;
  }
}
