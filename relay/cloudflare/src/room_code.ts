// Room codes: 6 characters, no 0/O/1/I/L. 31 symbols, so about 8.9e8 codes.

export const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const CODE_LENGTH = 6;

/** A random code from the CSPRNG, without modulo bias (rejection sampling). */
export function generateCode(random: (n: Uint8Array) => Uint8Array = (n) => crypto.getRandomValues(n)): string {
  const limit = 256 - (256 % ALPHABET.length); // bytes at or above this would bias the result
  let code = "";
  while (code.length < CODE_LENGTH) {
    const bytes = random(new Uint8Array(CODE_LENGTH * 2));
    for (const b of bytes) {
      if (b < limit) {
        code += ALPHABET[b % ALPHABET.length];
        if (code.length === CODE_LENGTH) break;
      }
    }
  }
  return code;
}

/** What a player typed, cleaned up: upper case, no spaces or hyphens. Null if it cannot be a code. */
export function normalizeCode(input: string): string | null {
  const cleaned = input.toUpperCase().replace(/[\s-]/g, "");
  if (cleaned.length !== CODE_LENGTH) return null;
  for (const ch of cleaned) if (!ALPHABET.includes(ch)) return null;
  return cleaned;
}

export function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
