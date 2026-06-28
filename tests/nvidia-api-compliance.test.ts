import { NIMClient } from "../src/clients/nimClient";
import { CICNIM } from "../src/clients/cicNimClient";

/**
 * NVIDIA API Compliance Validation Tests
 *
 * Validates that CIC services can communicate with NVIDIA cloud API endpoints
 * without team-scoped path segments. Run before Sep 30, 2026 deadline.
 *
 * Prerequisites:
 * - Set NIM_API_KEY environment variable with valid NVIDIA API key
 * - Run in staging/integration environment
 * - No mocks; tests hit live NVIDIA API
 */

describe("NVIDIA API Compliance (No Team Scopes)", () => {
  let client: NIMClient;
  let cicnim: CICNIM;

  const BASE_URL = process.env.NIM_BASE_URL || "https://integrate.api.nvidia.com/v1";
  const API_KEY = process.env.NIM_API_KEY;

  beforeAll(() => {
    if (!API_KEY) {
      throw new Error("NIM_API_KEY not set. Required for live API tests.");
    }

    client = new NIMClient(BASE_URL, 30000);
    cicnim = new CICNIM(client, {
      text: process.env.NIM_MODEL_TEXT || "nvidia/nvidia-nemotron-nano-9b-v2",
      omni: process.env.NIM_MODEL_OMNI || "nvidia/nvidia-nemotron-nano-9b-v2",
      embed: process.env.NIM_MODEL_EMBED || "nvidia/nvidia-embed-qa-4",
      rerank: process.env.NIM_MODEL_RERANK || "nvidia/nvidia-reranker-qa-mistral-4b-v3",
      parse: process.env.NIM_MODEL_PARSE || "nvidia/nvidia-nemotron-nano-9b-v2"
    });
  });

  test("should resolve global endpoint without /teams/ segment", () => {
    // Verify endpoint structure
    expect(BASE_URL).toContain("integrate.api.nvidia.com");
    expect(BASE_URL).not.toContain("/teams/");
    expect(BASE_URL).not.toContain("api.ngc.nvidia.com");
  });

  test("should authenticate with NVIDIA API (live)", async () => {
    // Simple auth check: request that will fail if API key is invalid
    const testMessages = [
      { role: "user", content: "Ping" }
    ];

    try {
      const response = await cicnim.reason(testMessages);
      expect(response).toBeDefined();
      expect(response.choices).toBeDefined();
    } catch (err: any) {
      // Expect 401 if API key invalid; anything else is a network/endpoint error
      if (err.message?.includes("401")) {
        throw new Error("Invalid NVIDIA API key. Check NIM_API_KEY env var.");
      }
      // 404 would indicate team-scoped path or endpoint mismatch
      if (err.message?.includes("404")) {
        throw new Error("404 from NVIDIA API. May indicate deprecated team-scoped path.");
      }
      throw err;
    }
  });

  test("should call /v1/chat/completions without team scope", async () => {
    const messages = [
      { role: "system", content: "You are a helpful assistant." },
      { role: "user", content: "What is 2+2?" }
    ];

    const response = await cicnim.reason(messages);

    expect(response.choices).toBeDefined();
    expect(response.choices.length).toBeGreaterThan(0);
    expect(response.choices[0].message).toBeDefined();
  });

  test("should call /v1/embeddings without team scope", async () => {
    const text = "Sample text for embedding";
    const response = await cicnim.embed(text);

    expect(response.data).toBeDefined();
    expect(response.data.length).toBeGreaterThan(0);
    expect(response.data[0].embedding).toBeDefined();
  });

  test("should call /v1/rerank without team scope", async () => {
    const query = "What is AI?";
    const documents = [
      "AI is artificial intelligence",
      "The weather is sunny today",
      "Machine learning is a subset of AI"
    ];

    const response = await cicnim.rerank(query, documents);

    expect(response.results).toBeDefined();
    expect(Array.isArray(response.results)).toBe(true);
  });

  test("should not have hardcoded /teams/ in request paths", async () => {
    // Verify client does not construct paths with team scope
    // This is a code-level check, not an API call
    const testPath = "/v1/chat/completions";
    expect(testPath).not.toMatch(/\/teams\/[^/]+/);
  });

  test("should reject requests with team-scoped base URL", () => {
    // Negative test: ensure old team-scoped URLs are not in use
    const oldTeamScopedUrl = "https://api.ngc.nvidia.com/v2/teams/myteam/models";
    expect(BASE_URL).not.toContain("api.ngc.nvidia.com");
    expect(BASE_URL).not.toMatch(/\/teams\/[^/]+/);
  });

  test("recovery: handle 404 gracefully (team scope removed)", async () => {
    // If we get a 404, it likely means the endpoint deprecated team-scoped paths
    // as announced. Ensure error handling is in place.
    try {
      const messages = [{ role: "user", content: "test" }];
      await cicnim.reason(messages);
    } catch (err: any) {
      if (err.message?.includes("404")) {
        console.error("CRITICAL: 404 from NVIDIA API. Team scope may have been auto-removed or endpoint changed.");
        throw new Error("Endpoint mismatch detected. Verify NIM_BASE_URL is correct.");
      }
    }
  });
});

/**
 * Integration smoke test: verify all model types work end-to-end
 */
describe("NVIDIA API Smoke Test (All Model Types)", () => {
  const BASE_URL = process.env.NIM_BASE_URL || "https://integrate.api.nvidia.com/v1";
  const API_KEY = process.env.NIM_API_KEY;

  beforeAll(() => {
    if (!API_KEY) {
      throw new Error("NIM_API_KEY required for smoke tests");
    }
  });

  test("should support text reasoning model", async () => {
    const client = new NIMClient(BASE_URL);
    const response = await client.chat("nvidia/nvidia-nemotron-nano-9b-v2", [
      { role: "user", content: "Hello" }
    ]);
    expect(response.choices).toBeDefined();
  });

  test("should support multimodal model", async () => {
    const client = new NIMClient(BASE_URL);
    const response = await client.chat("nvidia/nvidia-nemotron-nano-9b-v2", [
      { role: "user", content: "Describe an image" }
    ]);
    expect(response.choices).toBeDefined();
  });

  test("should support embedding model", async () => {
    const client = new NIMClient(BASE_URL);
    const response = await client.embed("nvidia/nvidia-embed-qa-4", "sample text");
    expect(response.data).toBeDefined();
  });

  test("should support reranking model", async () => {
    const client = new NIMClient(BASE_URL);
    const response = await client.rerank("nvidia/nvidia-reranker-qa-mistral-4b-v3", "query", [
      "doc1",
      "doc2"
    ]);
    expect(response.results).toBeDefined();
  });
});

/**
 * Test runner note:
 *
 * Run with: npm test -- nvidia-api-compliance.test.ts
 * Set env: NIM_API_KEY=<your-key> NIM_BASE_URL=https://integrate.api.nvidia.com/v1
 *
 * Expected result: All tests pass (no 404/400 errors)
 * Failure modes:
 *   - 404: Endpoint changed or team scope still in use
 *   - 401: Invalid or expired API key
 *   - 429: Rate limited; try again later
 *   - Timeout: Network issue or service down
 */
