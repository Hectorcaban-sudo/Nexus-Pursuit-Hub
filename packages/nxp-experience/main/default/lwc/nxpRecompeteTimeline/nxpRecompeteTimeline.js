import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRecompetes from '@salesforce/apex/NXP_MarketController.getRecompetes';
import watch from '@salesforce/apex/NXP_MarketController.watch';
import { daysUntil, debounce, formatDate, formatMoney, toast, toastError, logUsage } from 'c/nxpUtils';

/** The timeline axis runs from 24 months ago to 24 months ahead; today is the middle. */
const AXIS_MONTHS = 24;
const DAYS_PER_MONTH = 30.44;
const WINDOWS = [6, 12, 18, 24];

function monthsFromToday(value) {
    const d = daysUntil(value);
    return d === null ? null : d / DAYS_PER_MONTH;
}

function percent(months) {
    const clamped = Math.max(-AXIS_MONTHS, Math.min(AXIS_MONTHS, months));
    return ((clamped + AXIS_MONTHS) / (2 * AXIS_MONTHS)) * 100;
}

function compactMoney(value) {
    if (value === null || value === undefined) {
        return '–';
    }
    if (value >= 1000000) {
        return '$' + (value / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
    }
    if (value >= 1000) {
        return '$' + Math.round(value / 1000) + 'K';
    }
    return formatMoney(value);
}

export default class NxpRecompeteTimeline extends NavigationMixin(LightningElement) {
    rows = [];
    loading = true;
    agency = '';
    naics = '';
    monthsAhead = 18;
    minValue = null;
    selectedId;

    connectedCallback() {
        logUsage('Recompetes');
        this.debouncedLoad = debounce(() => this.load(), 400);
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.rows = await getRecompetes({
                agency: this.agency,
                naics: this.naics,
                monthsAhead: this.monthsAhead,
                minValue: this.minValue
            });
            if (!this.rows.some((r) => r.id === this.selectedId)) {
                const upcoming = this.rows.find((r) => r.monthsLeft !== null && r.monthsLeft >= 0);
                this.selectedId = upcoming ? upcoming.id : this.rows.length ? this.rows[0].id : undefined;
            }
        } catch (e) {
            toastError(this, e, 'Could not load recompetes');
        } finally {
            this.loading = false;
        }
    }

    get windows() {
        return WINDOWS.map((m) => ({
            months: m,
            label: `${m} months`,
            variant: m === this.monthsAhead ? 'brand' : 'neutral'
        }));
    }

    get view() {
        return this.rows.map((r) => {
            const end = monthsFromToday(r.periodEnd);
            const start = r.periodStart ? monthsFromToday(r.periodStart) : end - 12;
            const left = percent(start);
            const width = Math.max(percent(end) - left, 1);
            const ended = end !== null && end < 0;
            const soon = !ended && end !== null && end <= 6;
            let ends = 'No end date';
            if (end !== null) {
                ends = ended ? 'Ended' : end < 1 ? '< 1 mo' : `${Math.round(end)} mo`;
            }
            return {
                ...r,
                ends,
                endsClass: ended ? 'ends ends_past' : soon ? 'ends ends_soon' : 'ends',
                barClass: ended ? 'bar bar_ended' : soon ? 'bar bar_soon' : 'bar',
                barStyle: `left: ${left.toFixed(1)}%; width: ${width.toFixed(1)}%;`,
                obligatedLabel: compactMoney(r.obligated),
                ceilingLabel: r.ceiling ? compactMoney(r.ceiling) : '–',
                vendorLabel: r.vendorName || 'Unknown vendor',
                hasVendor: !!r.vendorId,
                hasFollowOn: !!r.followOnId,
                rowClass: r.id === this.selectedId ? 'grid row row_selected' : 'grid row'
            };
        });
    }

    get selected() {
        const r = this.view.find((v) => v.id === this.selectedId);
        if (!r) {
            return null;
        }
        return {
            ...r,
            details: [
                { k: 'PIID', v: r.piid || '–' },
                { k: 'Incumbent', v: r.vendorLabel },
                { k: 'Agency', v: r.agency || '–' },
                { k: 'NAICS / PSC', v: (r.naics || '–') + ' / ' + (r.psc || '–') },
                {
                    k: 'Obligated / ceiling',
                    v: formatMoney(r.obligated) + ' / ' + (r.ceiling ? formatMoney(r.ceiling) : '–')
                },
                { k: 'Period', v: formatDate(r.periodStart) + ' to ' + formatDate(r.periodEnd) }
            ],
            followOnText: r.followOnConfirmed
                ? 'This notice names the award as its predecessor.'
                : r.followOnKind === 'notice'
                  ? 'A recent notice from the same agency with the same NAICS: likely the follow-on.'
                  : r.followOnKind === 'forecast'
                    ? 'An open forecast from the same agency with the same NAICS.'
                    : 'No notice or forecast from this agency with this NAICS yet. Watch it to get an alert.',
            watchLabel: r.watching ? 'Watching' : 'Watch this recompete',
            watchVariant: r.watching ? 'brand' : 'neutral',
            watchState: r.watching ? 'true' : 'false'
        };
    }

    get empty() {
        return !this.loading && this.rows.length === 0;
    }

    handleFilter(event) {
        const name = event.target.dataset.filter;
        const value = event.detail.value;
        this[name] = name === 'minValue' ? (value === '' || value === null ? null : Number(value)) : value;
        this.debouncedLoad();
    }

    handleWindow(event) {
        this.monthsAhead = Number(event.currentTarget.dataset.months);
        this.load();
    }

    handleSelect(event) {
        this.selectedId = event.currentTarget.dataset.id;
    }

    handleOpen(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' }
        });
    }

    async handleWatch(event) {
        const recordId = event.currentTarget.dataset.id;
        const watching = event.currentTarget.dataset.watching === 'true';
        try {
            await watch({ recordId, watch: !watching });
            toast(
                this,
                watching ? 'Stopped watching' : 'Watching this recompete',
                watching ? '' : 'You will get an alert when a likely follow-on notice is posted.'
            );
            this.load();
        } catch (e) {
            toastError(this, e, 'Could not change the watch');
        }
    }
}
