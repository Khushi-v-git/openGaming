import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      // Small limits so the tests can reach them without waiting.
      miniflare: {
        bindings: {
          ALLOW_FIXED_CODES: "1",
          MAX_SOCKETS: "4",
          MAX_FRAME_CHARS: "2000",
          HOST_GRACE_SEC: "1",
          HANDSHAKE_SEC: "1",
          PEER_RATE_BURST: "10",
          PEER_RATE_PER_SEC: "1",
          MAX_VIOLATIONS: "3",
          BUFFER_PER_PEER: "3",
          BUFFER_ROOM_LIFETIME: "8",
          MAX_HOST_RESUMES: "3",
        },
      },
    }),
  ],
  test: { include: ["test/**/*.test.ts"], testTimeout: 15000 },
});
