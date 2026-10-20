// SPDX-License-Identifier: GPL-3.0-or-later
//
// Lays out a graph file with the original JavaScript dagre and prints it in the
// same format as dagre-dump.vala. It made the tests/dagre/*.expected files and
// isn't run by meson test. To add a case:
//
//   npm install --prefix DIR dagre-d3-es@7.0.14
//   DAGRE_DIR=DIR node tests/dagre-dump.mjs tests/dagre/NAME.graph > tests/dagre/NAME.expected
import { readFileSync } from 'node:fs';
const base = process.env.DAGRE_DIR;
const { layout } = await import(base + '/node_modules/dagre-d3-es/src/dagre/index.js');
const { Graph } = await import(base + '/node_modules/dagre-d3-es/src/graphlib/index.js');

const g = new Graph({ multigraph: true, compound: true });
g.setGraph({});
const parents = [];
for (const line of readFileSync(process.argv[2], 'utf8').split('\n')) {
  const f = line.trim().split(' ');
  if (f[0] === 'graph') {
    g.setGraph({ rankdir: f[1], nodesep: +f[2], edgesep: +f[3], ranksep: +f[4], marginx: +f[5], marginy: +f[6] });
  } else if (f[0] === 'node') {
    g.setNode(f[1], { width: +f[2], height: +f[3] });
    if (f.length > 4) parents.push([f[1], f[4]]);
  } else if (f[0] === 'edge') {
    g.setEdge(f[1], f[2], { minlen: +f[4], weight: +f[5], width: +f[6], height: +f[7], labelpos: f[8] }, f[3] === '-' ? undefined : f[3]);
  }
}
for (const [v, p] of parents) {
  if (!g.hasNode(p)) g.setNode(p, {});
  g.setParent(v, p);
}
layout(g);
const fmt = (d) => { const s = d.toFixed(3); return s === '-0.000' ? '0.000' : s; };
const out = [];
out.push(`graph ${fmt(g.graph().width)} ${fmt(g.graph().height)}`);
for (const v of g.nodes()) {
  const n = g.node(v);
  out.push(`node ${v} ${fmt(n.x)} ${fmt(n.y)} ${fmt(n.width)} ${fmt(n.height)}`);
}
for (const e of g.edges()) {
  const l = g.edge(e);
  let s = `edge ${e.v} ${e.w} ${e.name ?? '-'}`;
  if (Object.prototype.hasOwnProperty.call(l, 'x')) s += ` label ${fmt(l.x)} ${fmt(l.y)}`;
  s += ' points' + l.points.map((p) => ` ${fmt(p.x)},${fmt(p.y)}`).join('');
  out.push(s);
}
console.log(out.join('\n'));
