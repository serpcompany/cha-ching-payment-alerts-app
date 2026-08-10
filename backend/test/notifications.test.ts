import { describe, expect, it } from "vitest";

import {
  currencyExponent,
  formatMinorAmount,
  shouldRetryUnclaimedDelivery,
} from "../src/notifications";

describe("notification amount formatting", () => {
  it("formats two-decimal, zero-decimal, and three-decimal currencies", () => {
    expect(currencyExponent("USD")).toBe(2);
    expect(formatMinorAmount(1999, "USD")).toBe("$19.99");
    expect(currencyExponent("JPY")).toBe(0);
    expect(formatMinorAmount(1999, "JPY")).toContain("1,999");
    expect(currencyExponent("KWD")).toBe(3);
    expect(formatMinorAmount(1999, "KWD")).toContain("1.999");
  });
});

describe("delivery recovery", () => {
  it("keeps an unclaimed in-progress delivery on the queue until it can be reclaimed", () => {
    expect(shouldRetryUnclaimedDelivery("sending")).toBe(true);
    expect(shouldRetryUnclaimedDelivery("sent")).toBe(false);
    expect(shouldRetryUnclaimedDelivery("failed")).toBe(false);
  });
});
