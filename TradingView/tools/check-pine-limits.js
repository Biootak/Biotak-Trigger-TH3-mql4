// Platform-limits gate.
//
//   node tools/check-pine-limits.js
//
// TradingView refuses a script at attach on numbers, not on intent, and a refusal
// costs a paste round trip that no offline tool afterwards can recover. This gate
// counts the numbers on the generated artifact, so the count is citable.
//
// The caps (TradingView Pine v6, as the IDE Tools validator models them too):
//   64   plot-family outputs            (plot / plotshape / plotchar / plotarrow /
//                                        plotcandle / plotbar / hline / bgcolor /
//                                        barcolor / fill are each their own family;
//                                        the hard refusal is on the plot family)
//   40   request.*() calls
//   500  max_lines_count / max_labels_count / max_boxes_count / max_polylines_count
//   5000 max_bars_back
//   one  indicator()/strategy()/library() declaration, on the first code line

import fs from 'node:fs';
import path from 'node:path';
import { ROOT, DIST } from './lib/pine-build.js';

export const LIMITS = {
  plotFamily: 64,
  requestCalls: 40,
  drawings: 500,
  barsBack: 5000,
  alertConditions: 64,
};

const count = (src, re) => (src.match(re) ?? []).length;

export function inspect(file) {
  const src = fs.readFileSync(file, 'utf8').replace(/\r\n?/g, '\n');
  const lines = src.split('\n');
  const code = lines.map((l) => l.replace(/\/\/.*$/, ''));

  const plotFamily = [
    /\bplot\s*\(/g,
    /\bplotshape\s*\(/g,
    /\bplotchar\s*\(/g,
    /\bplotarrow\s*\(/g,
    /\bplotcandle\s*\(/g,
    /\bplotbar\s*\(/g,
    /\bhline\s*\(/g,
  ].reduce((n, re) => n + count(src, re), 0);

  const requests = count(src, /\b(?:request\.\w+|security|request\.security_lower_tf)\s*\(/g);
  const alertConditions = count(src, /\balertcondition\s*\(/g);
  const declarations = count(src, /^\s*(indicator|strategy|library)\s*\(/gm);
  const linesNew = count(src, /\bline\.new\s*\(/g);
  const labelsNew = count(src, /\blabel\.new\s*\(/g);
  const boxesNew = count(src, /\bbox\.new\s*\(/g);
  const version = lines[0]?.trim() ?? '';

  const declared = (key) => {
    const m = new RegExp(`${key}\\s*=\\s*(\\d+)`).exec(src);
    return m ? Number(m[1]) : null;
  };

  const out = { file, lines: lines.length, plotFamily, requests, alertConditions, declarations, linesNew, labelsNew, boxesNew, version };
  for (const key of ['max_lines_count', 'max_labels_count', 'max_boxes_count', 'max_bars_back']) out[key] = declared(key);
  out.bareSecurity = !!code.some((l) => /(^|[^.\w])security\s*\(/.test(l));
  out.strategyInIndicator = /^\s*indicator\s*\(/m.test(src) && /\bstrategy\.\w+\s*\(/.test(src);
  out.strategyInIndicator = out.strategyInIndicator && /\bstrategy\.\w+\s*\(/.test(code.join('\n'));
  return out;
}

export function verify(info) {
  const bad = [];
  const rel = path.relative(ROOT, info.file) || info.file;
  const cap = (name, value, limit) =>
    value > limit && bad.push(`${rel} ${name}=${value} exceeds the platform cap ${limit}`);

  if (info.version !== '//@version=6') bad.push(`${rel} line 1 is "${info.version}" - Pine reads the version from line 1`);
  if (info.declarations !== 1) bad.push(`${rel} has ${info.declarations} declaration(s) - exactly one indicator()/strategy()/library() is allowed`);
  cap('plot-family', info.plotFamily, LIMITS.plotFamily);
  cap('request calls', info.requests, LIMITS.requestCalls);
  cap('alertcondition', info.alertConditions, LIMITS.alertConditions);
  if (info.bareSecurity) bad.push(`${rel} uses the bare security() alias - v6 moved it to request.security()`);
  if (info.strategyInIndicator) bad.push(`${rel} declares indicator() and calls strategy.* - a script is one or the other`);
  for (const key of ['max_lines_count', 'max_labels_count', 'max_boxes_count']) {
    if (info[key] !== null && info[key] > LIMITS.drawings) bad.push(`${rel} ${key}=${info[key]} exceeds the drawing cap ${LIMITS.drawings}`);
    if (info[key] !== null && info[key] <= 0) bad.push(`${rel} ${key}=${info[key]} is not a usable drawing budget`);
  }
  if (info.max_bars_back !== null && info.max_bars_back > LIMITS.barsBack) bad.push(`${rel} max_bars_back=${info.max_bars_back} exceeds ${LIMITS.barsBack}`);
  if (info.max_lines_count !== null && info.linesNew > info.max_lines_count) {
    bad.push(`${rel} creates up to ${info.linesNew} line(s) per bar against max_lines_count=${info.max_lines_count} - the oldest are silently deleted`);
  }
  if (info.max_labels_count !== null && info.labelsNew > info.max_labels_count) {
    bad.push(`${rel} creates up to ${info.labelsNew} label(s) per bar against max_labels_count=${info.max_labels_count} - the oldest are silently deleted`);
  }
  return bad;
}

const files = process.argv.slice(2).length
  ? process.argv.slice(2)
  : fs.existsSync(DIST)
    ? fs.readdirSync(DIST).filter((f) => f.endsWith('.pine')).sort().map((f) => path.join(DIST, f))
    : [];

if (files.length === 0) {
  console.error('[FAIL] limits gate - no .pine file to check. Run: npm run build');
  process.exit(1);
}

let bad = [];
for (const file of files) {
  const info = inspect(file);
  const rel = path.relative(ROOT, file) || file;
  console.log(
    `[note] ${rel}  lines=${info.lines}  plot-family=${info.plotFamily}/${LIMITS.plotFamily}  request=${info.requests}/${LIMITS.requestCalls}  ` +
    `line.new=${info.linesNew}  label.new=${info.labelsNew}  box.new=${info.boxesNew}  ` +
    `lines=${info.max_lines_count} labels=${info.max_labels_count} boxes=${info.max_boxes_count} maxBarsBack=${info.max_bars_back}`,
  );
  bad = bad.concat(verify(info));
}

if (bad.length) {
  for (const b of bad) console.error(`[FAIL] ${b}`);
  console.error(`\nLIMITS FAILED - ${bad.length} finding(s)`);
  process.exit(1);
}
console.log(`\n[PASS] limits gate - ${files.length} file(s) inside every TradingView cap`);
