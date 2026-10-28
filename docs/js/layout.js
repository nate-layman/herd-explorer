// Shared header and footer. Every page calls renderLayout(activePage).
import { fillMeta } from './meta.js';

export const REPO = 'https://github.com/nate-layman/herd-explorer';
export const REPORT_ERROR = `${REPO}/issues/new?template=data-error.yml`;

const PAGES = [
  ['index.html', 'Trends'],
  ['compare.html', 'Compare'],
  ['explore.html', 'Explore'],
  ['ask.html', 'Ask'],
  ['model.html', 'About the model'],
  ['data.html', 'Data & sources'],
];

export const DISCLAIMER =
  'HERD Explorer is an independent project. It is not an official product of NCSES or the U.S. National Science ' +
  'Foundation, and neither NCSES, NSF nor the University of Idaho endorses it. The data, charts and projections are ' +
  'provided as is, without warranty of any kind, and are not financial, budget, legal or investment advice. ' +
  'Check figures against the official NCSES tables before relying on them.';

export function renderLayout(active) {
  const nav = PAGES.map(([href, label]) =>
    `<a href="${href}"${href === active ? ' aria-current="page"' : ''}>${label}</a>`).join('');
  document.body.insertAdjacentHTML('afterbegin', `
    <header class="site-header">
      <a class="brand" href="index.html">HERD Explorer</a>
      <nav>${nav}</nav>
    </header>`);
  document.body.insertAdjacentHTML('beforeend', `
    <footer class="site-footer">
      <p>Data: <a href="https://ncses.nsf.gov/explore-data/microdata/higher-education-research-development">NCSES
        Higher Education Research and Development Survey</a>, FY <span data-meta="first_year">2012</span> to FY <span data-meta="last_year">2024</span>. See <a href="data.html">Data &amp; sources</a>.</p>
      <p><a href="${REPORT_ERROR}">Report a data error</a> &middot; <a href="${REPO}">Source code on GitHub</a>
        &middot; Apache 2.0</p>
      <p>A project of <a href="https://ai4ra.uidaho.edu">AI4RA</a> at the University of Idaho, funded by the U.S. National Science Foundation
        GRANTED program, award <a href="https://www.nsf.gov/awardsearch/show-award?AWD_ID=2427549">#2427549</a>.</p>
      <p class="disclaimer">${DISCLAIMER}</p>
    </footer>`);
  fillMeta();
}
