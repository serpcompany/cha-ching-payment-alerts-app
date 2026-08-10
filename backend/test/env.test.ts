import { describe, expect, it } from "vitest";

import { providerCapabilities } from "../src/env";
import type { Env } from "../src/env";

describe("provider capabilities", () => {
  it("reports availability only when each provider has all required credentials", () => {
    const env = {
      STRIPE_CONNECT_CLIENT_ID: "ca_test",
      STRIPE_SECRET_KEY: "sk_test",
      PAYPAL_CLIENT_ID: "",
      PAYPAL_CLIENT_SECRET: "",
    } as Env;

    expect(providerCapabilities(env)).toEqual({ stripe: true, paypal: false });
  });
});
