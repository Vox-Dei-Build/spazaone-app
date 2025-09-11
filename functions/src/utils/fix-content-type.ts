/**
 * @file fix-products-content-type.ts
 * @description Batch-fix Content-Type for ALL product images under `products/<merchantId>/...`.
 * - Sets image/jpeg for .jpg/.jpeg
 * - Sets image/png  for .png
 * - Skips .webp (WhatsApp interactive rejects webp anyway)
 * - Recurses all merchants automatically (prefix = "products/")
 *
 * Usage:
 *   GET /fixProductsContentType?bucket=<your-bucket>
 *   (optional) &dryRun=1    -> report only, no updates
 *   (optional) &concurrency=10  -> parallel updates (default 10)
 */

import * as functions from "firebase-functions";
import { initializeApp, getApps } from "firebase-admin/app";
import { getStorage } from "firebase-admin/storage";

if (!getApps().length) initializeApp();

const jpeg = "image/jpeg";
const png = "image/png";

const guessTarget = (name: string): "jpeg" | "png" | "skip" => {
  const n = name.toLowerCase();
  if (n.endsWith(".jpg") || n.endsWith(".jpeg")) return "jpeg";
  if (n.endsWith(".png")) return "png";
  if (n.endsWith(".webp")) return "skip"; // skip webp (not WA-friendly)
  // default to jpeg for unknown image extensions if you really want:
  return "jpeg";
};

async function mapWithLimit<T, R>(
  arr: T[],
  limit: number,
  fn: (item: T, idx: number) => Promise<R>,
): Promise<R[]> {
  const out: R[] = new Array(arr.length);
  let i = 0;
  const workers = Array(Math.min(limit, arr.length))
    .fill(0)
    .map(async () => {
      while (i < arr.length) {
        const idx = i++;
        out[idx] = await fn(arr[idx], idx);
      }
    });
  await Promise.all(workers);
  return out;
}

/**
 * @function fixProductsContentType
 * @route   GET /fixProductsContentType?bucket=<bucket>&dryRun=1&concurrency=10
 */
export const fixProductsContentType = functions
  .runWith({ timeoutSeconds: 540, memory: "1GB" })
  .https.onRequest(async (req, res): Promise<void> => {
    try {
      res.set("Access-Control-Allow-Origin", "*");
      if (req.method === "OPTIONS") {
        res.set("Access-Control-Allow-Methods", "GET,OPTIONS");
        res.set("Access-Control-Allow-Headers", "Content-Type");
        res.status(204).send("");
        return;
      }

      const bucketName = String(req.query.bucket || "").trim();
      const dryRun = !!req.query.dryRun;
      const concurrency = Math.max(
        1,
        Math.min(20, parseInt(String(req.query.concurrency || "10"), 10) || 10),
      );

      if (!bucketName) {
        res
          .status(400)
          .json({ ok: false, error: "Missing query param: bucket" });
        return;
      }

      const bucket = getStorage().bucket(bucketName);

      // Grab ALL product files across ALL merchants
      const [files] = await bucket.getFiles({ prefix: "whatsapp_media/" });

      const results = await mapWithLimit(files, concurrency, async (f) => {
        const name = f.name as string;

        // Decide target
        const target = guessTarget(name);
        if (target === "skip") {
          return { file: name, updated: false, reason: "Skipped WEBP" };
        }

        const targetType = target === "png" ? png : jpeg;

        // Read current metadata
        const [meta] = await f.getMetadata();
        const current = (
          meta.contentType || "application/octet-stream"
        ).toLowerCase();

        // Update only if needed
        const needs =
          current !== targetType || current === "application/octet-stream";
        if (!needs) {
          return {
            file: name,
            updated: false,
            from: current,
            to: targetType,
            reason: "Already correct",
          };
        }

        if (dryRun) {
          return {
            file: name,
            updated: false,
            from: current,
            to: targetType,
            reason: "Dry run",
          };
        }

        await f.setMetadata({
          contentType: targetType,
          cacheControl: "public, max-age=86400",
        });

        return { file: name, updated: true, from: current, to: targetType };
      });

      const summary = {
        ok: true,
        bucket: bucketName,
        prefix: "products/",
        total: results.length,
        updated: results.filter((r) => r.updated).length,
        skippedWebp: results.filter((r) => r.reason === "Skipped WEBP").length,
        results,
      };

      res.status(200).json(summary);
      return;
    } catch (e: any) {
      res.status(500).json({ ok: false, error: e?.message || String(e) });
      return;
    }
  });
