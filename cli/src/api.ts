export interface Mover {
  date: string;
  ticker: string;
  pct_change: number;
  open_price: number;
  close_price: number;
  percentile_rank: number | null;
  is_significant: boolean;
}

export interface MoversResponse {
  movers: Mover[];
  count: number;
  generated_at: string;
}

const API_BASE_URL =
  "https://y8kadghxxb.execute-api.us-west-1.amazonaws.com/prod/movers";

export async function fetchMovers(days: number): Promise<MoversResponse> {
  const url = new URL(API_BASE_URL);
  url.searchParams.set("days", days.toString());

  const response = await fetch(url.toString());

  if (!response.ok) {
    throw new Error(
      `API request failed with status ${response.status}: ${response.statusText}`
    );
  }

  const data = (await response.json()) as MoversResponse;
  return data;
}

export function filterMovers(movers: Mover[], ticker: string): Mover[] {
  if (!ticker || ticker.toLowerCase() === "all") {
    return movers;
  }
  return movers.filter(
    (m) => m.ticker.toLowerCase() === ticker.toLowerCase()
  );
}
