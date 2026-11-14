import { LightningElement, api } from 'lwc';
import getPriceCheck from '@salesforce/apex/NXP_PriceToWinController.getPriceCheck';
import { formatDate, toast, toastError } from 'c/nxpUtils';

/** $4.73M, $950K, $12.5M: short money for tiles and the chart. */
function shortMoney(value) {
    if (value === null || value === undefined || isNaN(value)) {
        return '';
    }
    const v = Number(value);
    if (Math.abs(v) >= 1000000) {
        return '$' + (v / 1000000).toFixed(v >= 10000000 ? 1 : 2).replace(/\.?0+$/, '') + 'M';
    }
    if (Math.abs(v) >= 1000) {
        return '$' + Math.round(v / 1000) + 'K';
    }
    return '$' + Math.round(v);
}

/** How many of the sorted values are below the given value. */
function countBelow(sorted, value) {
    let n = 0;
    for (const v of sorted || []) {
        if (v < value) {
            n++;
        }
    }
    return n;
}

function relative(a, b) {
    if (!b) {
        return '';
    }
    const d = Math.round(((a - b) / b) * 100);
    return d === 0 ? 'about the same as' : `${Math.abs(d)}% ${d < 0 ? 'below' : 'above'}`;
}

const YEAR_OPTIONS = Array.from({ length: 10 }, (_, i) => ({
    label: i === 0 ? '1 year' : `${i + 1} years`,
    value: String(i + 1)
}));

export default class NxpPriceToWin extends LightningElement {
    @api recordId;
    data;
    loading = true;
    scopeKey;
    years;
    price;
    showBasis = false;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getPriceCheck({ noticeId: this.recordId, scopeKey: this.scopeKey || null });
            this.scopeKey = this.data.scopeKey;
            if (!this.years) {
                this.years = this.data.noticeYears || 5;
            }
        } catch (e) {
            toastError(this, e, 'Could not load Price-to-Win');
        } finally {
            this.loading = false;
        }
    }

    // ------------------------------------------------------------------ state

    get enabled() {
        return !!(this.data && this.data.enabled);
    }

    get offNote() {
        return this.data && !this.data.enabled ? this.data.note : '';
    }

    get note() {
        return this.data && this.data.enabled ? this.data.note : '';
    }

    get enough() {
        return !!(this.data && this.data.enough);
    }

    get scopes() {
        return (this.data ? this.data.scopes : []).map((s) => ({
            ...s,
            buttonLabel: s.available ? `${s.label} (${s.count})` : s.label,
            variant: s.key === this.scopeKey ? 'brand' : 'neutral',
            disabled: !s.available
        }));
    }

    get scopeSummary() {
        if (!this.data) {
            return '';
        }
        const n = this.data.count;
        return `${n} ${n === 1 ? 'award' : 'awards'} · ${this.data.scopeLabel} · started in the last ${this.data.lookbackYears} years · value per year of performance`;
    }

    handleScope(event) {
        const key = event.currentTarget.dataset.key;
        if (key && key !== this.scopeKey) {
            this.scopeKey = key;
            this.load();
        }
    }

    // ------------------------------------------------------------------ range

    get lowLabel() {
        return shortMoney(this.data.low);
    }
    get medianLabel() {
        return shortMoney(this.data.median);
    }
    get highLabel() {
        return shortMoney(this.data.high);
    }

    get axisMax() {
        const d = this.data;
        const top = Math.max(
            d.high || 0,
            d.predecessor ? d.predecessor.perYear || 0 : 0,
            this.pricePerYear || 0,
            d.estimate && d.estimate.perYear ? d.estimate.perYear : 0
        );
        return top > 0 ? top * 1.1 : 1;
    }

    pos(value) {
        return Math.max(0, Math.min(100, (Number(value) / this.axisMax) * 100));
    }

    get axisMaxLabel() {
        return shortMoney(this.axisMax);
    }

    get spanStyle() {
        const l = this.pos(this.data.low);
        return `left:${l}%;width:${this.pos(this.data.high) - l}%`;
    }
    get bandStyle() {
        const l = this.pos(this.data.q1);
        return `left:${l}%;width:${this.pos(this.data.q3) - l}%`;
    }
    get lowStyle() {
        return `left:${this.pos(this.data.low)}%`;
    }
    get highStyle() {
        return `left:${this.pos(this.data.high)}%`;
    }
    get medianStyle() {
        return `left:${this.pos(this.data.median)}%`;
    }

    get hasPredecessor() {
        return !!(this.data && this.data.predecessor);
    }
    get predecessor() {
        return this.data.predecessor;
    }
    get predecessorUrl() {
        return '/' + this.data.predecessor.id;
    }
    get predecessorPerYearLabel() {
        return shortMoney(this.data.predecessor.perYear);
    }
    get predecessorDetail() {
        const p = this.data.predecessor;
        const parts = [p.vendorName, p.piid];
        if (p.obligated) {
            parts.push(`${shortMoney(p.obligated)} spent over ${p.years} ${p.years === 1 ? 'year' : 'years'}`);
        }
        if (p.periodEnd) {
            parts.push('ends ' + formatDate(p.periodEnd));
        }
        return parts.filter((x) => !!x).join(' · ');
    }
    get predecessorStyle() {
        return `left:${this.pos(this.data.predecessor.perYear)}%`;
    }

    get yearOptions() {
        return YEAR_OPTIONS;
    }
    get yearsValue() {
        return String(this.years || 5);
    }
    get yearsNote() {
        return this.data && this.data.noticeYearsSource === 'predecessor'
            ? 'Starts at the predecessor contract’s length; change it to the notice’s period of performance.'
            : 'Set this to the notice’s period of performance.';
    }
    handleYears(event) {
        this.years = Number(event.detail.value);
    }

    get rangeTotalLabel() {
        return `${shortMoney(this.data.q1 * this.years)} – ${shortMoney(this.data.q3 * this.years)}`;
    }
    get predecessorTotalLabel() {
        return this.hasPredecessor ? shortMoney(this.data.predecessor.perYear * this.years) : '';
    }

    // ------------------------------------------------------------------ compare a price

    get priceInputLabel() {
        return `Total price, all ${this.years || 5} years`;
    }

    handlePrice(event) {
        const v = Number(event.detail.value);
        this.price = v > 0 ? v : undefined;
    }

    get hasPrice() {
        return !!this.price && !!this.data && this.data.count > 0;
    }
    get pricePerYear() {
        return this.price ? this.price / (this.years || 1) : undefined;
    }
    get pricePerYearLabel() {
        return shortMoney(this.pricePerYear);
    }
    get priceStyle() {
        return `left:${this.pos(this.pricePerYear)}%`;
    }
    get priceTag() {
        const d = this.data;
        const p = this.pricePerYear;
        if (!d.enough) {
            return { label: 'Few awards to compare', cls: 'tag tag_muted' };
        }
        if (p < d.low) {
            return { label: 'Below every past award', cls: 'tag tag_warn' };
        }
        if (p < d.q1) {
            return { label: 'Below the typical range', cls: 'tag tag_warn' };
        }
        if (p <= d.q3) {
            return { label: 'In the typical range', cls: 'tag tag_ok' };
        }
        if (p <= d.high) {
            return { label: 'Above the typical range', cls: 'tag tag_bad' };
        }
        return { label: 'Above every past award', cls: 'tag tag_bad' };
    }
    get priceFacts() {
        const d = this.data;
        const p = this.pricePerYear;
        const facts = [];
        const below = countBelow(d.values, p);
        facts.push({ key: 'rank', text: `Higher than ${below} of ${d.values.length} comparable awards` });
        if (this.hasPredecessor && d.predecessor.perYear) {
            facts.push({
                key: 'pred',
                text: `${relative(p, d.predecessor.perYear)} the predecessor’s ${shortMoney(d.predecessor.perYear)} a year`
            });
        }
        if (d.enough) {
            facts.push({
                key: 'median',
                text: `${relative(p, d.median)} the median of ${shortMoney(d.median)} a year`
            });
        }
        return facts;
    }

    // ------------------------------------------------------------------ incumbent hold

    get hold() {
        return this.data ? this.data.hold : null;
    }
    get hasHold() {
        return !!(this.hold && this.hold.matched > 0);
    }
    get holdPercent() {
        return Math.round((this.hold.kept / this.hold.matched) * 100) + '%';
    }
    get holdLabel() {
        return `${this.hold.kept} of ${this.hold.matched} ended contracts went to the same vendor again`;
    }
    get pips() {
        const n = Math.min(this.hold.matched, 12);
        const won = Math.round((this.hold.kept / this.hold.matched) * n);
        return Array.from({ length: n }, (_, i) => ({ key: 'p' + i, cls: i < won ? 'pip pip_kept' : 'pip' }));
    }
    get incumbentLine() {
        const h = this.hold;
        if (!h.incumbentName) {
            return '';
        }
        if (!h.incumbentMatched) {
            return `${h.incumbentName}: no ended contract here to compare.`;
        }
        return `${h.incumbentName} kept ${h.incumbentKept} of ${h.incumbentMatched} here.`;
    }
    get holdExamples() {
        return (this.hold ? this.hold.examples : []).map((e, i) => ({
            key: 'h' + i,
            cls: e.kept ? 'dot dot_kept' : 'dot dot_lost',
            text: e.kept
                ? `${e.vendorName} kept it: ${e.fromPiid} → ${e.toPiid}`
                : `${e.vendorName} lost it to ${e.toVendorName}: ${e.fromPiid} → ${e.toPiid}`,
            ended: 'Ended ' + formatDate(e.endedOn)
        }));
    }

    // ------------------------------------------------------------------ similar awards

    get estimate() {
        return this.data ? this.data.estimate : null;
    }
    get hasEstimate() {
        return !!(this.estimate && this.estimate.count > 0);
    }
    get estimateLabel() {
        return shortMoney(this.estimate.perYear);
    }
    get estimateRange() {
        return `${shortMoney(this.estimate.low)} – ${shortMoney(this.estimate.high)}`;
    }
    get estimateTotal() {
        return shortMoney(this.estimate.perYear * this.years);
    }
    get estimateStyle() {
        return `left:${this.pos(this.estimate.perYear)}%`;
    }
    get basisToggleLabel() {
        return this.showBasis ? 'Hide the closest matches' : 'Show the closest matches';
    }
    handleToggleBasis() {
        this.showBasis = !this.showBasis;
    }
    get basis() {
        return (this.estimate ? this.estimate.basis : []).map((a) => ({
            ...a,
            url: '/' + a.id,
            perYearLabel: shortMoney(a.perYear),
            meta: [a.vendorName, a.agencyName, a.naics, a.periodStart ? formatDate(a.periodStart) : null]
                .filter((x) => !!x)
                .join(' · ')
        }));
    }

    // ------------------------------------------------------------------ awards table

    get hasAwards() {
        return !!(this.data && this.data.awards && this.data.awards.length);
    }
    get awards() {
        return this.data.awards.map((a) => ({
            ...a,
            url: '/' + a.id,
            vendorUrl: a.vendorId ? '/' + a.vendorId : null,
            started: formatDate(a.periodStart),
            spentLabel: shortMoney(a.obligated || a.ceiling),
            perYearLabel: shortMoney(a.perYear),
            rowClass: a.inRange ? 'row row_in' : 'row'
        }));
    }

    get footer() {
        return this.data && this.data.dataThrough ? `Newest award started ${formatDate(this.data.dataThrough)}.` : '';
    }

    // ------------------------------------------------------------------ copy

    get summaryText() {
        const d = this.data;
        const lines = [`Price-to-Win, ${d.scopeLabel} (${d.count} awards, last ${d.lookbackYears} years)`];
        if (d.enough) {
            lines.push(
                `Per year: low ${shortMoney(d.low)}, median ${shortMoney(d.median)}, high ${shortMoney(d.high)}; typical range ${shortMoney(d.q1)} – ${shortMoney(d.q3)}.`
            );
            lines.push(`Typical total over ${this.years} years: ${this.rangeTotalLabel}.`);
        }
        if (this.hasPredecessor) {
            lines.push(`Predecessor: ${this.predecessorDetail}; ${this.predecessorPerYearLabel} a year.`);
        }
        if (this.hasEstimate) {
            lines.push(
                `Similar-awards estimate: ${this.estimateLabel} a year (${this.estimateRange}) from the ${this.estimate.count} closest awards.`
            );
        }
        if (this.hasHold) {
            lines.push(`Incumbent hold (estimated): ${this.holdLabel}. ${this.incumbentLine}`);
        }
        lines.push('Source: Nexus award history (USAspending). Winners only; not a chance of winning.');
        return lines.join('\n');
    }

    async handleCopy() {
        try {
            await navigator.clipboard.writeText(this.summaryText);
            toast(this, 'Copied', 'Paste it into the capture plan or the Opportunity.');
        } catch (e) {
            toastError(this, e, 'Could not copy');
        }
    }

    handleRefresh() {
        this.load();
    }
}
