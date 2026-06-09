import { NIMClient } from "./nimClient";

export class CICNIM {
  constructor(
    private client: NIMClient,
    private models: {
      text: string;
      omni: string;
      embed: string;
      rerank: string;
      parse: string;
    }
  ) {}

  reason(messages: any[]) {
    return this.client.chat(this.models.text, messages);
  }

  multimodal(messages: any[]) {
    return this.client.chat(this.models.omni, messages);
  }

  embed(text: string | string[]) {
    return this.client.embed(this.models.embed, text);
  }

  rerank(query: string, docs: string[]) {
    return this.client.rerank(this.models.rerank, query, docs);
  }

  parse(fileBase64: string) {
    return this.client.parse(this.models.parse, fileBase64);
  }
}
