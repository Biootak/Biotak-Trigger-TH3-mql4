// The offline parity engine.
//
// Pine's only compiler is TradingView's, so "did the port give the same numbers"
// can only be answered by running the REAL Pine source. This module does that:
// a deterministic local market-data provider (no network, no API key) plus the
// PineTS runtime, so a parity run is reproducible byte for byte.
//
// Why the library and not the pinets-cli binary: the CLI leaves `syminfo` null on
// an offline dataset, and any script reading `syminfo.mintick` then dies at
// `Cannot read properties of undefined`. The library path fills syminfo from the
// provider's `getSymbolInfo()`, so the port reads the same pip size it will read
// on the chart.

import { PineTS, BaseProvider } from 'pinets';

export class LocalProvider extends BaseProvider {
  constructor(bars, symbolInfo) {
    super({ requiresApiKey: false, providerName: 'biotak-local' });
    this.bars = bars;
    this.symbolInfo = {
      ticker: 'PARITY',
      tickerid: 'PARITY',
      root: 'PARITY',
      prefix: '',
      description: 'Biotak parity series',
      type: 'forex',
      currency: 'USD',
      basecurrency: '',
      country: '',
      timezone: 'UTC',
      session: '24x7',
      volumetype: 'base',
      mintick: 0.00001,
      pricescale: 100000,
      minmove: 1,
      pointvalue: 1,
      mincontract: 1,
      ...symbolInfo,
    };
  }

  getSupportedTimeframes() {
    return new Set(['1', '5', '15', '30', '60', '240', 'D', 'W', 'M']);
  }

  async _getMarketDataNative(_tickerId, _timeframe, limit) {
    return typeof limit === 'number' && limit > 0 ? this.bars.slice(-limit) : this.bars.slice();
  }

  async getSymbolInfo() {
    return this.symbolInfo;
  }
}

// A deterministic bar series. `shape` decides the price path; the parity cases do
// not care about the path, they need a chart with enough bars to reach a decision.
export function syntheticBars(count, { start = 1700000000000, stepMs = 3600000, price = 1.1, shape = 'sine' } = {}) {
  const bars = [];
  let t = start;
  let p = price;
  for (let i = 0; i < count; i++) {
    const drift = shape === 'sine' ? Math.sin(i / 7) * 0.004 : shape === 'ramp' ? 0.0006 : 0;
    const o = p;
    const c = p + drift;
    const hi = Math.max(o, c) + 0.0009;
    const lo = Math.min(o, c) - 0.0009;
    const r = (v) => Math.round(v * 1e5) / 1e5;
    bars.push({ openTime: t, open: r(o), high: r(hi), low: r(lo), close: r(c), volume: 100 + i, closeTime: t + stepMs - 1 });
    t += stepMs;
    p = c;
  }
  return bars;
}

export async function runPine({ code, bars, symbolInfo, timeframe = '60' }) {
  const provider = new LocalProvider(bars, symbolInfo);
  const engine = new PineTS(provider, 'PARITY', timeframe, bars.length);
  await engine.ready();
  const ctx = await engine.run(code);
  return { ctx, engine };
}

// A plot's per-bar values, in bar order. na arrives as null/NaN/undefined.
export function plotValues(ctx, title) {
  const entry = ctx?.plots?.[title];
  if (!entry) throw new Error(`the run produced no plot named "${title}" - the probe and the reader disagree`);
  const data = Array.isArray(entry) ? entry : entry.data;
  if (!Array.isArray(data)) throw new Error(`plot "${title}" carries no data array`);
  return data.map((d) => (typeof d?.value === 'number' && Number.isFinite(d.value) ? d.value : null));
}

export function drawingObjects(ctx, kind) {
  const entry = ctx?.plots?.[`__${kind}__`];
  if (!entry) return [];
  const data = Array.isArray(entry) ? entry : entry.data;
  if (!Array.isArray(data)) return [];
  return data;
}

export const close = (a, b, tol) => {
  if (a === null || b === null || a === undefined || b === undefined) return false;
  if (!Number.isFinite(a) || !Number.isFinite(b)) return false;
  return Math.abs(a - b) <= tol;
};

export const fmt = (v, digits = 9) => (v === null || v === undefined ? 'na' : Number(v).toPrecision(digits));
