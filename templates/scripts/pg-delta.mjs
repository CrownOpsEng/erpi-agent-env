import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { createPlan, renderPlanFiles } from "@supabase/pg-delta";
import { supabase } from "@supabase/pg-delta/integrations/supabase";

const PG_DELTA_VERSION = "1.0.0-alpha.33";
const SUPABASE_CLI_BASELINE = "2.114.0";

function usage() {
  process.stderr.write(
    "Usage: agent-env pg-delta plan --source postgresql://... --target postgresql://... --out DIR\n",
  );
}

function fail(message, code = 2) {
  process.stderr.write(`${message}\n`);
  process.exit(code);
}

function parseArgs(argv) {
  const result = { source: null, target: null, out: null };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--source" || arg === "--target" || arg === "--out") {
      const value = argv[i + 1];
      if (!value || value.startsWith("--")) fail(`${arg} requires a value.`);
      result[arg.slice(2)] = value;
      i += 1;
    } else if (arg === "-h" || arg === "--help") {
      usage();
      process.exit(0);
    } else {
      fail(`Unknown pg-delta plan argument: ${arg}`);
    }
  }
  if (!result.source || !result.target || !result.out) {
    usage();
    fail("pg-delta plan requires --source, --target, and --out.");
  }
  return result;
}

function validateLoopbackDatabaseUrl(raw, label) {
  let url;
  try {
    url = new URL(raw);
  } catch {
    fail(`${label} must be a valid PostgreSQL URL.`);
  }
  if (url.protocol !== "postgres:" && url.protocol !== "postgresql:") {
    fail(`${label} must use postgres:// or postgresql://.`);
  }
  if (!new Set(["127.0.0.1", "[::1]", "::1"]).has(url.hostname)) {
    fail(`${label} must target numeric loopback only (127.0.0.1 or ::1); remote database URLs are refused.`);
  }
  if (url.search || url.hash) {
    fail(`${label} must not contain query parameters or fragments; connection routing must remain explicit.`);
  }
  if (!url.pathname || url.pathname === "/") {
    fail(`${label} must name a database.`);
  }
  return url.toString();
}

function prepareOutput(raw) {
  const out = path.resolve(raw);
  if (fs.existsSync(out)) {
    const stat = fs.lstatSync(out);
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
      fail(`Output path must be a real directory, not a symlink or file: ${raw}`);
    }
    if (fs.readdirSync(out).length !== 0) {
      fail(`Output directory must be empty: ${raw}`);
    }
  } else {
    fs.mkdirSync(out, { recursive: true, mode: 0o755 });
  }
  return out;
}

function safeRenderedPath(renderedPath) {
  if (
    !renderedPath ||
    path.isAbsolute(renderedPath) ||
    renderedPath.includes("/") ||
    renderedPath.includes("\\") ||
    renderedPath === "." ||
    renderedPath === ".." ||
    renderedPath.includes("..")
  ) {
    throw new Error("pg-delta returned an unsafe output filename.");
  }
  return renderedPath;
}

function redact(text, values) {
  let result = String(text ?? "");
  for (const value of values) {
    if (!value) continue;
    result = result.split(value).join("<redacted-database-url>");
    try {
      const parsed = new URL(value);
      if (parsed.password) {
        result = result.split(parsed.password).join("<redacted-password>");
        result = result.split(decodeURIComponent(parsed.password)).join("<redacted-password>");
      }
    } catch {
      // Inputs were validated before this function is used.
    }
  }
  return result;
}

const args = parseArgs(process.argv.slice(2));
const source = validateLoopbackDatabaseUrl(args.source, "--source");
const target = validateLoopbackDatabaseUrl(args.target, "--target");
// Explicit URLs are the sole database authority for this command. Prevent host
// PostgreSQL environment from influencing pg-delta or any transitive client.
for (const key of [
  "DATABASE_URL", "PGHOST", "PGHOSTADDR", "PGPORT", "PGDATABASE", "PGUSER",
  "PGPASSWORD", "PGPASSFILE", "PGSERVICE", "PGSERVICEFILE", "PGOPTIONS",
  "PGAPPNAME", "PGCONNECT_TIMEOUT", "PGCHANNELBINDING", "PGSSLMODE", "PGSSLROOTCERT",
  "PGSSLCERT", "PGSSLKEY", "PGREQUIRESSL", "PGTARGETSESSIONATTRS",
]) {
  delete process.env[key];
}

try {
  const result = await createPlan(source, target, {
    ...supabase,
    skipDefaultPrivilegeSubtraction: true,
  });
  const files = result
    ? renderPlanFiles(result.plan, {
        includeTransactions: false,
        sqlFormatOptions: { maxWidth: 180, keywordCase: "upper" },
      })
    : [];
  const out = prepareOutput(args.out);
  const envelope = {
    version: 1,
    pgDeltaVersion: PG_DELTA_VERSION,
    supabaseCliBaseline: SUPABASE_CLI_BASELINE,
    files: files.map((file, index) => {
      const renderedPath = safeRenderedPath(file.path);
      return {
        order: index + 1,
        name: renderedPath.replace(/^\d+_/, "").replace(/\.sql$/, ""),
        path: renderedPath,
        transactionMode: file.unit.transactionMode,
        statements: file.unit.statements.length,
      };
    }),
  };
  for (const [index, file] of files.entries()) {
    fs.writeFileSync(path.join(out, envelope.files[index].path), file.sql, { encoding: "utf8", mode: 0o644 });
  }
  fs.writeFileSync(path.join(out, "envelope.json"), `${JSON.stringify(envelope, null, 2)}\n`, { encoding: "utf8", mode: 0o644 });
  process.stdout.write(`${JSON.stringify(envelope)}\n`);
} catch (error) {
  const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
  process.stderr.write(`pg-delta plan failed: ${redact(message, [source, target, args.source, args.target])}\n`);
  process.exit(1);
}
