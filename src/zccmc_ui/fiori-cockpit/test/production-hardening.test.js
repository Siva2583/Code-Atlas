import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";

const read = (file) => readFileSync(new URL(file, import.meta.url), "utf8");

describe("production configuration", () => {
  it("maps every route to an existing Fiori Elements target", () => {
    const manifest = JSON.parse(read("../webapp/manifest.json"));
    const routing = manifest["sap.ui5"].routing;

    for (const route of routing.routes) {
      expect(routing.targets[route.target], route.target).toBeDefined();
    }
  });

  it("resolves every annotation i18n reference", () => {
    const metadata = read("../webapp/localService/mainService/metadata.xml");
    const bundle = read("../webapp/i18n/i18n.properties");
    const keys = [...metadata.matchAll(/\{@i18n>([^}]+)\}/g)].map((match) => match[1]);
    const bundleKeys = new Set(
      bundle
        .split(/\r?\n/)
        .filter((line) => line && !line.startsWith("#"))
        .map((line) => line.split("=", 1)[0])
    );

    expect(keys.length).toBeGreaterThan(0);
    for (const key of keys) {
      expect(bundleKeys.has(key), key).toBe(true);
    }
  });

  it("externalizes visible annotation labels", () => {
    const metadata = read("../webapp/localService/mainService/metadata.xml");
    const labels = [
      ...metadata.matchAll(
        /<PropertyValue Property="(?:Label|TypeName|TypeNamePlural|Title|Text)" String="([^"]+)"/g
      )
    ].map((match) => match[1]);

    expect(labels.length).toBeGreaterThan(0);
    expect(labels.every((label) => label.startsWith("{@i18n>"))).toBe(true);
  });

  it("keeps live and mock middleware configurations separate", () => {
    const liveConfig = read("../ui5.yaml");
    const mockConfig = read("../ui5-mock.yaml");

    expect(liveConfig).not.toContain("sap-fe-mockserver");
    expect(liveConfig).toContain("<SAP_BACKEND_HOST>");
    expect(mockConfig).toContain("sap-fe-mockserver");
    expect(mockConfig).toContain("metadata.xml");
    expect(mockConfig).toContain("mockdata");
  });
});
