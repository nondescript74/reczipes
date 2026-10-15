// Minimal CloudKit Web Services client for the PUBLIC database, read-only.
//
// Auth: an API token created in CloudKit Console for container
// iCloud.com.headydiscy.reczipes (Tokens & Keys -> API Tokens). Public-database
// reads need no user sign-in. The token lives only on the server (env var),
// never in the browser.
//
// Endpoint: POST https://api.apple-cloudkit.com/database/1/{container}/{env}/public/records/query?ckAPIToken=...
// The Swift app deliberately does not sort in its queries (fields are not
// marked sortable in the schema), so neither do we; sorting happens in memory.

const API_BASE = 'https://api.apple-cloudkit.com/database/1';

export class CloudKitError extends Error {
  constructor(message, { status, code, reason } = {}) {
    super(message);
    this.name = 'CloudKitError';
    this.status = status;
    this.code = code;
    this.reason = reason;
  }
}

export function createCloudKitClient({ container, environment, apiToken, fetchImpl = fetch, pageSize = 200, maxPages = 50 }) {
  if (!container || !environment || !apiToken) {
    throw new Error('CloudKit client needs container, environment and apiToken');
  }
  const queryURL = `${API_BASE}/${encodeURIComponent(container)}/${encodeURIComponent(environment)}/public/records/query?ckAPIToken=${encodeURIComponent(apiToken)}`;

  async function queryAll(recordType) {
    const records = [];
    let continuationMarker = null;
    for (let page = 0; page < maxPages; page++) {
      const body = { query: { recordType }, resultsLimit: pageSize };
      if (continuationMarker) body.continuationMarker = continuationMarker;
      const res = await fetchImpl(queryURL, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(body),
      });
      let json;
      try {
        json = await res.json();
      } catch {
        throw new CloudKitError(`CloudKit ${recordType} query: non-JSON response (HTTP ${res.status})`, { status: res.status });
      }
      if (!res.ok || json.serverErrorCode) {
        throw new CloudKitError(
          `CloudKit ${recordType} query failed: ${json.serverErrorCode ?? 'HTTP ' + res.status}${json.reason ? ' — ' + json.reason : ''}`,
          { status: res.status, code: json.serverErrorCode, reason: json.reason },
        );
      }
      records.push(...(json.records ?? []));
      continuationMarker = json.continuationMarker ?? null;
      if (!continuationMarker) return records;
    }
    // Hitting the page cap is a truncation, and it must say so (MTA M-19).
    throw new CloudKitError(`CloudKit ${recordType} query exceeded ${maxPages} pages; results would be truncated`);
  }

  return { queryAll };
}
