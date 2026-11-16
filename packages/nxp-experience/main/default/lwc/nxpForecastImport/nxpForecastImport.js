import { LightningElement } from 'lwc';
import importForecasts from '@salesforce/apex/NXP_ForecastImportController.importForecasts';
import { toast, toastError } from 'c/nxpUtils';

const BATCH = 200;

/** Nexus fields, in order, with header words that usually name them in agency exports. */
export const FIELDS = [
    {
        key: 'forecastId',
        label: 'Forecast ID',
        hints: ['listing id', 'forecast id', 'apfs', 'record id', 'reference', 'id']
    },
    { key: 'title', label: 'Title', required: true, hints: ['title', 'requirement', 'project', 'name'] },
    { key: 'agency', label: 'Agency', required: true, hints: ['department', 'agency', 'organization'] },
    {
        key: 'subAgency',
        label: 'Sub-agency or office',
        hints: ['sub agency', 'subagency', 'component', 'bureau', 'office']
    },
    {
        key: 'solicitationDate',
        label: 'Expected solicitation date',
        hints: ['solicitation', 'release', 'anticipated award', 'award date', 'quarter']
    },
    { key: 'value', label: 'Estimated value', hints: ['value', 'dollar', 'range', 'amount'] },
    { key: 'fiscalYear', label: 'Fiscal year', hints: ['fiscal year', 'fy'] },
    { key: 'naics', label: 'NAICS', hints: ['naics'] },
    { key: 'setAside', label: 'Set-aside', hints: ['set aside', 'set-aside', 'small business', 'socioeconomic'] },
    { key: 'description', label: 'Description', hints: ['description', 'summary', 'scope'] }
];

/** Parses CSV text (quoted fields, commas and line breaks inside quotes, "" escapes). */
export function parseCsv(text) {
    const rows = [];
    let row = [];
    let field = '';
    let quoted = false;
    const src = (text || '').replace(new RegExp('^' + String.fromCharCode(0xfeff)), '');
    for (let i = 0; i < src.length; i++) {
        const c = src[i];
        if (quoted) {
            if (c === '"' && src[i + 1] === '"') {
                field += '"';
                i++;
            } else if (c === '"') {
                quoted = false;
            } else {
                field += c;
            }
        } else if (c === '"') {
            quoted = true;
        } else if (c === ',') {
            row.push(field);
            field = '';
        } else if (c === '\n' || c === '\r') {
            if (c === '\r' && src[i + 1] === '\n') {
                i++;
            }
            row.push(field);
            field = '';
            if (row.some((v) => v.trim() !== '')) {
                rows.push(row);
            }
            row = [];
        } else {
            field += c;
        }
    }
    row.push(field);
    if (row.some((v) => v.trim() !== '')) {
        rows.push(row);
    }
    return rows;
}

/** Picks a column for each field from the header names; each column is used once. */
export function guessMapping(headers) {
    const used = new Set();
    const mapping = {};
    const norm = headers.map((h) => (h || '').toLowerCase().replace(/[_.]/g, ' ').trim());
    for (const f of FIELDS) {
        for (const hint of f.hints) {
            const i = norm.findIndex(
                (h, n) => !used.has(n) && (hint === 'id' || hint === 'fy' ? h === hint : h.includes(hint))
            );
            if (i >= 0) {
                mapping[f.key] = String(i);
                used.add(i);
                break;
            }
        }
    }
    return mapping;
}

const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

function pad(n) {
    return String(n).padStart(2, '0');
}

function fullYear(y) {
    const n = Number(y);
    return n < 100 ? 2000 + n : n;
}

/**
 * Turns the date styles agencies use into yyyy-mm-dd: 2027-03-29, 3/29/2027, March 2027,
 * Q2 FY2027 / FY27 Q2 (start of that federal fiscal quarter). Returns null when it can't.
 */
export function parseDate(value) {
    const v = (value || '').trim();
    if (!v) {
        return null;
    }
    let m = v.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
    if (m) {
        return `${m[1]}-${pad(m[2])}-${pad(m[3])}`;
    }
    m = v.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2,4})$/);
    if (m) {
        return `${fullYear(m[3])}-${pad(m[1])}-${pad(m[2])}`;
    }
    m = v.match(/q([1-4])\D*fy\s*'?(\d{2,4})|fy\s*'?(\d{2,4})\D*q([1-4])/i);
    if (m) {
        const q = Number(m[1] || m[4]);
        const fy = fullYear(m[2] || m[3]);
        const starts = { 1: [fy - 1, 10], 2: [fy, 1], 3: [fy, 4], 4: [fy, 7] };
        return `${starts[q][0]}-${pad(starts[q][1])}-01`;
    }
    m = v.toLowerCase().match(/^([a-z]{3})[a-z]*\.?\s+(\d{4})$/);
    if (m && MONTHS.includes(m[1])) {
        return `${m[2]}-${pad(MONTHS.indexOf(m[1]) + 1)}-01`;
    }
    return null;
}

/** "$1,500,000", "1.5M", "$250K", "$1M - $5M": the number, or the upper end of a range. */
export function parseValue(value) {
    const v = (value || '').replace(/,/g, '');
    const re = /(\d+(?:\.\d+)?)\s*([kmb])?/gi;
    let best = null;
    let m;
    while ((m = re.exec(v)) !== null) {
        const mult = { k: 1e3, m: 1e6, b: 1e9 }[(m[2] || '').toLowerCase()] || 1;
        const n = Number(m[1]) * mult;
        if (best === null || n > best) {
            best = n;
        }
    }
    return best;
}

export default class NxpForecastImport extends LightningElement {
    fileName;
    headers = [];
    dataRows = [];
    mapping = {};
    sourceName = '';
    importing = false;
    progress = 0;
    result;
    error;

    get hasFile() {
        return this.headers.length > 0;
    }

    get rowCountText() {
        return `${this.dataRows.length} rows in ${this.fileName}`;
    }

    get columnOptions() {
        return [{ label: '(not in this file)', value: '' }].concat(
            this.headers.map((h, i) => ({ label: h || `Column ${i + 1}`, value: String(i) }))
        );
    }

    get fieldRows() {
        return FIELDS.map((f) => ({
            ...f,
            label: f.required ? `${f.label} (required)` : f.label,
            value: this.mapping[f.key] || '',
            sample: this.sampleFor(f.key)
        }));
    }

    sampleFor(key) {
        const col = this.mapping[key];
        if (col === undefined || col === '' || !this.dataRows.length) {
            return '';
        }
        const raw = (this.dataRows[0][Number(col)] || '').trim();
        if (key === 'solicitationDate') {
            const d = parseDate(raw);
            return raw ? `${raw} → ${d || 'not understood, left blank'}` : '';
        }
        if (key === 'value') {
            const n = parseValue(raw);
            return raw ? `${raw} → ${n === null ? 'not understood' : '$' + n.toLocaleString('en-US')}` : '';
        }
        return raw.length > 80 ? raw.slice(0, 80) + '…' : raw;
    }

    get importDisabled() {
        return this.importing || !this.mapping.title || !this.mapping.agency || !this.sourceName.trim();
    }

    get progressText() {
        return `Importing… ${this.progress} of ${this.dataRows.length}`;
    }

    handleFile(event) {
        const file = event.target.files && event.target.files[0];
        if (!file) {
            return;
        }
        this.result = undefined;
        this.error = undefined;
        if (!/\.csv$/i.test(file.name)) {
            this.error = 'Save the spreadsheet as CSV (File → Save As → CSV) and choose that file.';
            return;
        }
        this.fileName = file.name;
        const reader = new FileReader();
        reader.onload = () => this.loadText(String(reader.result || ''));
        reader.readAsText(file);
    }

    loadText(text) {
        const rows = parseCsv(text);
        if (rows.length < 2) {
            this.error = 'The file has no data rows.';
            this.headers = [];
            return;
        }
        this.headers = rows[0].map((h) => h.trim());
        this.dataRows = rows.slice(1);
        this.mapping = guessMapping(this.headers);
        if (!this.sourceName) {
            this.sourceName = /dhs|homeland/i.test(this.fileName)
                ? 'DHS forecast'
                : /hhs/i.test(this.fileName)
                  ? 'HHS forecast'
                  : 'Acquisition Gateway';
        }
    }

    handleSource(event) {
        this.sourceName = event.detail.value || '';
    }

    handleMap(event) {
        this.mapping = { ...this.mapping, [event.target.dataset.key]: event.detail.value };
    }

    mapped(row) {
        const get = (key) => {
            const col = this.mapping[key];
            return col === undefined || col === '' ? '' : (row[Number(col)] || '').trim();
        };
        return {
            forecastId: get('forecastId'),
            title: get('title'),
            agency: get('agency'),
            subAgency: get('subAgency'),
            solicitationDate: parseDate(get('solicitationDate')),
            value: parseValue(get('value')),
            fiscalYear: get('fiscalYear'),
            naics: get('naics'),
            setAside: get('setAside'),
            description: get('description')
        };
    }

    async handleImport() {
        this.importing = true;
        this.progress = 0;
        const total = { read: 0, created: 0, updated: 0, unchanged: 0, rejected: 0, problems: [] };
        try {
            for (let i = 0; i < this.dataRows.length; i += BATCH) {
                const batch = this.dataRows.slice(i, i + BATCH).map((r) => this.mapped(r));
                // eslint-disable-next-line no-await-in-loop
                const r = await importForecasts({ sourceName: this.sourceName, rowsJson: JSON.stringify(batch) });
                ['read', 'created', 'updated', 'unchanged', 'rejected'].forEach((k) => {
                    total[k] += r[k] || 0;
                });
                total.problems = total.problems.concat(
                    (r.problems || []).map((p) => p.replace(/^Row (\d+)/, (s, n) => `Row ${Number(n) + i}`))
                );
                this.progress = Math.min(this.dataRows.length, i + BATCH);
            }
            this.result = {
                ...total,
                summary: `${total.created} new, ${total.updated} updated, ${total.unchanged} unchanged, ${total.rejected} skipped`,
                problemRows: total.problems.slice(0, 20).map((p, n) => ({ key: 'p' + n, text: p }))
            };
            toast(this, 'Forecasts imported', this.result.summary);
        } catch (e) {
            toastError(this, e, 'Import stopped');
        } finally {
            this.importing = false;
        }
    }

    get hasProblems() {
        return !!(this.result && this.result.problemRows.length);
    }
}
