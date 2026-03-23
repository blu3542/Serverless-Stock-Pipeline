#!/usr/bin/env node
import { Command } from "commander";
import chalk from "chalk";
import { fetchMovers, filterMovers } from "./api.js";
import { formatMovers } from "./formatter.js";

const program = new Command();

program
  .name("stocks")
  .description("Stock Movers CLI")
  .version("1.0.0")
  .argument("<ticker>", "stock ticker to filter (e.g. TSLA, AAPL) or all")
  .option("-d, --days <number>", "number of days to fetch (1-90)", "7")
  .action(async (ticker: string, options: { days: string }) => {
    try {
      const days = Math.max(1, Math.min(parseInt(options.days, 10) || 7, 90));
      const data = await fetchMovers(days);
      const filtered = filterMovers(data.movers, ticker);

      if (filtered.length === 0) {
        console.log(chalk.yellow("No movers found for ticker: " + ticker.toUpperCase()));
        const available = [...new Set(data.movers.map((m) => m.ticker))];
        console.log(chalk.dim("Available tickers in data: " + available.join(", ")));
        console.log(chalk.dim("Try increasing --days or use 'all' to see everything."));
        return;
      }

      console.log(formatMovers(filtered, data.generated_at));
    } catch (err) {
      console.error(
        chalk.red("Error: " + (err instanceof Error ? err.message : "Unknown error"))
      );
      process.exit(1);
    }
  });

program.parse();
