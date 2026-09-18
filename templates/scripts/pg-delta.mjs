import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { Pool } from "pg";
import {
  hasBlockingDiagnostics,
  renderPlanFiles,
  STRICT_COVERAGE_CODES,
} from "@supabase/pg-delta/frontends";
import { resolveProfile, supabaseProfile } from "@supabase/pg-delta/integrations";
import { plan } from "@supabase/pg-delta/plan";

const PG_DELTA_VERSION = "1.0.0-alpha.49";
const SUPABASE_CLI_BASELINE = "2.117.0";

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

function renderedPath(index, suffix) {
  const sequence = String(index + 1).padStart(3, "0");
  const tail = suffix ?? "";
  return `${sequence}_plan${tail}.sql`;
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

function diagnosticText(diagnostic) {
  const code = typeof diagnostic?.code === "string" ? diagnostic.code : "unknown";
  const severity = typeof diagnostic?.severity === "string" ? diagnostic.severity : "unknown";
  const message = typeof diagnostic?.message === "string" ? diagnostic.message : "diagnostic without message";
  return `${severity} ${code}: ${message}`;
}

function isStrictCoverageBlocker(diagnostic) {
  return diagnostic?.severity === "error" || STRICT_COVERAGE_CODES.has(diagnostic?.code);
}

const args = parseArgs(process.argv.slice(2));
const source = validateLoopbackDatabaseUrl(args.source, "--source");
const target = validateLoopbackDatabaseUrl(args.target, "--target");

// Explicit URLs are the sole database authority for this command. Prevent host
// PostgreSQL environment from influencing pg-delta or its pg client.
for (const key of [
  "DATABASE_URL", "PGHOST", "PGHOSTADDR", "PGPORT", "PGDATABASE", "PGUSER",
  "PGPASSWORD", "PGPASSFILE", "PGSERVICE", "PGSERVICEFILE", "PGOPTIONS",
  "PGAPPNAME", "PGCONNECT_TIMEOUT", "PGCHANNELBINDING", "PGSSLMODE", "PGSSLROOTCERT",
  "PGSSLCERT", "PGSSLKEY", "PGREQUIRESSL", "PGTARGETSESSIONATTRS",
]) {
  delete process.env[key];
}

const sourcePool = new Pool({ connectionString: source, max: 4 });
const targetPool = new Pool({ connectionString: target, max: 4 });

try {
  // Match the bundled Supabase CLI 2.117 profile-based pipeline rather than
  // reconstructing its managed-view policy locally. Resolve once against the
  // source and use the same profile/options to extract both sides.
  const profile = await resolveProfile(sourcePool, supabaseProfile, { redactSecrets: true });
  const [sourceState, targetState] = await Promise.all([
    profile.extract(sourcePool, { redactSecrets: true }),
    profile.extract(targetPool, { redactSecrets: true }),
  ]);
  const generatedPlan = plan(sourceState.factBase, targetState.factBase, {
    ...profile.planOptions,
    redactSecrets: true,
  });
  const diagnostics = [
    ...sourceState.diagnostics,
    ...targetState.diagnostics,
    ...(generatedPlan.diagnostics ?? []),
  ];
  if (hasBlockingDiagnostics(diagnostics, { strictCoverage: true })) {
    const blocking = diagnostics.filter(isStrictCoverageBlocker).map(diagnosticText);
    throw new Error(`strict coverage gate refused an incomplete pg-delta plan: ${blocking.join(" | ")}`);
  }
  for (const diagnostic of diagnostics) {
    process.stderr.write(`pg-delta diagnostic: ${diagnosticText(diagnostic)}\n`);
  }
  const rendered = renderPlanFiles(generatedPlan, { allowDrops: true });
  const out = prepareOutput(args.out);
  const envelope = {
    version: 1,
    pgDeltaVersion: PG_DELTA_VERSION,
    supabaseCliBaseline: SUPABASE_CLI_BASELINE,
    profile: profile.id,
    files: rendered.files.map((file, index) => ({
      order: index + 1,
      name: file.suffix === null ? "plan" : `plan${file.suffix}`,
      path: renderedPath(index, file.suffix),
      transactionMode: file.transactional ? "transactional" : "none",
      statements: file.actionCount,
    })),
  };
  for (const [index, file] of rendered.files.entries()) {
    fs.writeFileSync(path.join(out, envelope.files[index].path), file.contents, {
      encoding: "utf8",
      mode: 0o644,
    });
  }
  fs.writeFileSync(path.join(out, "envelope.json"), `${JSON.stringify(envelope, null, 2)}\n`, {
    encoding: "utf8",
    mode: 0o644,
  });
  process.stdout.write(`${JSON.stringify(envelope)}\n`);
} catch (error) {
  const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
  process.stderr.write(`pg-delta plan failed: ${redact(message, [source, target, args.source, args.target])}\n`);
  process.exitCode = 1;
} finally {
  await Promise.allSettled([sourcePool.end(), targetPool.end()]);
}
