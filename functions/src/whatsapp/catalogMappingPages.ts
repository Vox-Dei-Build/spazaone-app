/**
 * Exhausts a document-ID ordered mapping query. Keeping this shared prevents
 * delivery and readiness/status from disagreeing when a merchant exceeds an
 * arbitrary first-query limit.
 */
export async function collectAllNativeCatalogMappingPages<
  T extends { id: string },
>(
  fetchPage: (cursor: string | undefined, limit: number) => Promise<T[]>,
  pageSize = 500,
): Promise<T[]> {
  const collected: T[] = [];
  let cursor: string | undefined;
  for (;;) {
    const page = await fetchPage(cursor, pageSize);
    collected.push(...page);
    if (page.length < pageSize) return collected;
    const nextCursor = page[page.length - 1]?.id;
    if (!nextCursor || nextCursor === cursor) {
      throw new Error("WHATSAPP_CATALOG_MAPPING_CURSOR_STALLED");
    }
    cursor = nextCursor;
  }
}

/** Bounded batch reads preserve the input ordering across every chunk. */
export async function collectNativeCatalogBatchReads<T, R>(
  items: readonly T[],
  readBatch: (batch: readonly T[]) => Promise<readonly R[]>,
  batchSize = 200,
): Promise<R[]> {
  const results: R[] = [];
  for (let start = 0; start < items.length; start += batchSize) {
    const batch = items.slice(start, start + batchSize);
    const read = await readBatch(batch);
    if (read.length !== batch.length) {
      throw new Error("WHATSAPP_CATALOG_BATCH_READ_INCOMPLETE");
    }
    results.push(...read);
  }
  return results;
}
