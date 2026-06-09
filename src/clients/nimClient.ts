export class NIMClient {
  constructor(
    private baseUrl: string,
    private timeoutMs = 20000
  ) {}

  private async request(path: string, body: any) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const res = await fetch(`${this.baseUrl}${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: controller.signal
      });

      if (!res.ok) {
        const text = await res.text();
        throw new Error(`NIM error ${res.status}: ${text}`);
      }

      return await res.json();
    } finally {
      clearTimeout(timeout);
    }
  }

  chat(model: string, messages: any[]) {
    return this.request("/v1/chat/completions", { model, messages });
  }

  embed(model: string, input: string | string[]) {
    return this.request("/v1/embeddings", { model, input });
  }

  rerank(model: string, query: string, documents: string[]) {
    return this.request("/v1/rerank", { model, query, documents });
  }

  parse(model: string, fileBase64: string) {
    return this.request("/v1/parse", { model, file: fileBase64 });
  }
}
