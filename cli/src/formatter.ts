import chalk from "chalk";
import type { Mover } from "./api.js";

function fmtDate(d: string): string {
  const [y, m, day] = d.split("-").map(Number);
  return new Date(y, m - 1, day).toLocaleDateString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
  });
}

function fmtPct(v: number, width = 12): string {
  const str = ((v >= 0 ? "+" : "") + v.toFixed(2) + "%").padEnd(width);
  return v >= 0 ? chalk.green(str) : chalk.red(str);
}

function fmtPrice(v: number): string {
  return "$" + v.toFixed(2);
}

function fmtPercentile(v: number | null): string {
  return v != null ? v.toFixed(1) + "%" : "\u2014";
}

function fmtSignificance(sig: boolean): string {
  return sig
    ? chalk.yellow.bold("\u26A0 Unusual Move")
    : chalk.dim("Normal");
}

export function formatMovers(movers: Mover[], generatedAt: string): string {
  if (movers.length === 0) {
    return chalk.yellow("No data to display.");
  }

  const header = [
    "Date".padEnd(16),
    "Ticker".padEnd(8),
    "% Change".padEnd(12),
    "Open".padEnd(12),
    "Close".padEnd(12),
    "Percentile".padEnd(12),
    "Significance",
  ];

  const lines: string[] = [];
  lines.push("");
  lines.push(chalk.bold(header.join("")));
  lines.push(chalk.dim("\u2500".repeat(84)));

  for (const m of movers) {
    const row = [
      fmtDate(m.date).padEnd(16),
      chalk.bold(m.ticker.padEnd(8)),
      fmtPct(m.pct_change),
      fmtPrice(m.open_price).padEnd(12),
      fmtPrice(m.close_price).padEnd(12),
      fmtPercentile(m.percentile_rank).padEnd(12),
      fmtSignificance(m.is_significant),
    ];
    lines.push(row.join(""));
  }

  lines.push("");
  lines.push(
    chalk.dim(
      `${movers.length} record${movers.length !== 1 ? "s" : ""} \u00B7 last updated ${generatedAt}`
    )
  );

  return lines.join("\n");
}
