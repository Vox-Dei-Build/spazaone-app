import { createHash } from "crypto";
import { readFileSync } from "fs";
import { join } from "path";
import { firebaseProjectId } from "../config/environment";

type ImmutableTargetConfiguration = Record<string, string | number> & {
  schemaVersion: number;
  SPAZAONE_ENVIRONMENT: string;
  SPAZAONE_FIREBASE_PROJECT_ID: string;
  WHATSAPP_CATALOG_ID: string;
  WHATSAPP_SENDER_NUMBER_ID: string;
  META_GRAPH_API_VERSION: string;
};

type ProductionTargetDocument = {
  schemaVersion: number;
  firebaseProjectId: string;
  functionRegions: string[];
  catalogId: string;
  senderPhoneNumberId: string;
  graphApiVersion: string;
  immutableTargetConfiguration: ImmutableTargetConfiguration;
  targetConfigurationDigestSha256: string;
};

function loadCheckedTargetDocument(): ProductionTargetDocument {
  try {
    const parsed: unknown = JSON.parse(
      readFileSync(
        join(__dirname, "../../config/whatsapp-catalog-production-target.json"),
        "utf8",
      ),
    );
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("invalid target document");
    }
    return parsed as ProductionTargetDocument;
  } catch (_) {
    throw new Error("WHATSAPP_CATALOG_PRODUCTION_TARGET_UNREADABLE");
  }
}

const targetDocument = loadCheckedTargetDocument();

function value(name: string): string {
  return String(process.env[name] ?? "").trim();
}

function checkedTargetTemplate(): Record<string, string | number> {
  const template = targetDocument.immutableTargetConfiguration;
  const digest = createHash("sha256")
    .update(JSON.stringify(template))
    .digest("hex");
  if (
    targetDocument.schemaVersion !== 1 ||
    targetDocument.firebaseProjectId !== "pasella-ledger" ||
    targetDocument.functionRegions.length !== 1 ||
    targetDocument.functionRegions[0] !== "us-central1" ||
    template.schemaVersion !== 1 ||
    template.SPAZAONE_ENVIRONMENT !== "production" ||
    template.SPAZAONE_FIREBASE_PROJECT_ID !==
      targetDocument.firebaseProjectId ||
    template.WHATSAPP_CATALOG_ID !== targetDocument.catalogId ||
    template.WHATSAPP_SENDER_NUMBER_ID !== targetDocument.senderPhoneNumberId ||
    template.META_GRAPH_API_VERSION !== targetDocument.graphApiVersion ||
    digest !== targetDocument.targetConfigurationDigestSha256
  ) {
    throw new Error("WHATSAPP_CATALOG_PRODUCTION_TARGET_INVALID");
  }
  return template;
}

/** Property insertion order comes only from the checked target JSON. */
export function immutableWhatsAppCatalogTargetConfiguration(): Record<
  string,
  string | number
> {
  return Object.fromEntries(
    Object.keys(checkedTargetTemplate()).map((name) => [
      name,
      name === "schemaVersion"
        ? 1
        : name === "SPAZAONE_FIREBASE_PROJECT_ID"
          ? firebaseProjectId()
          : value(name),
    ]),
  );
}

export function whatsappCatalogTargetConfigurationDigestSha256(): string {
  return createHash("sha256")
    .update(JSON.stringify(immutableWhatsAppCatalogTargetConfiguration()))
    .digest("hex");
}

export type WhatsAppCatalogDeploymentBinding = {
  deployedAppCommit: string;
  targetConfigurationDigestSha256: string;
  firebaseProjectId: string;
  catalogId: string;
  senderPhoneNumberId: string;
};

export function currentWhatsAppCatalogDeploymentBinding(): WhatsAppCatalogDeploymentBinding {
  const target = immutableWhatsAppCatalogTargetConfiguration();
  return {
    deployedAppCommit: value("BUILD_COMMIT"),
    targetConfigurationDigestSha256:
      whatsappCatalogTargetConfigurationDigestSha256(),
    firebaseProjectId: String(target.SPAZAONE_FIREBASE_PROJECT_ID),
    catalogId: String(target.WHATSAPP_CATALOG_ID),
    senderPhoneNumberId: String(target.WHATSAPP_SENDER_NUMBER_ID),
  };
}

export function assertWhatsAppCatalogDeploymentBinding(input: {
  expectedAppCommit: unknown;
  expectedTargetConfigurationDigestSha256: unknown;
}): WhatsAppCatalogDeploymentBinding {
  const expectedAppCommit = String(input.expectedAppCommit ?? "").trim();
  const expectedTargetDigest = String(
    input.expectedTargetConfigurationDigestSha256 ?? "",
  ).trim();
  const current = currentWhatsAppCatalogDeploymentBinding();
  if (
    !/^[a-f0-9]{40}$/.test(expectedAppCommit) ||
    !/^[a-f0-9]{64}$/.test(expectedTargetDigest) ||
    current.deployedAppCommit !== expectedAppCommit ||
    current.targetConfigurationDigestSha256 !== expectedTargetDigest
  ) {
    throw new Error("WHATSAPP_CATALOG_DEPLOYMENT_BINDING_MISMATCH");
  }
  return current;
}
