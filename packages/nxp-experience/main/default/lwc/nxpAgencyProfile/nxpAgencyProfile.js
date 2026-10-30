import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getAgencyProfile from '@salesforce/apex/NXP_MarketController.getAgencyProfile';
import watch from '@salesforce/apex/NXP_MarketController.watch';
import { daysUntil, formatMoney, toast, toastError, logUsage } from 'c/nxpUtils';

const KINDS = {
    notice: { label: 'Notice', className: 'kind kind_notice' },
    forecast: { label: 'Forecast', className: 'kind kind_forecast' },
    award: { label: 'Award ends', className: 'kind kind_award' }
};

function compactMoney(value) {
    if (value === null || value === undefined) {
        return '';
    }
    if (value >= 1000000) {
        return '$' + (value / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
    }
    if (value >= 1000) {
        return '$' + Math.round(value / 1000) + 'K';
    }
    return formatMoney(value);
}

function whenLabel(item) {
    const d = daysUntil(item.onDate);
    if (d === null) {
        return 'No date';
    }
    if (d < 0) {
        return item.kind === 'forecast' ? 'Expected now' : 'Past';
    }
    if (d === 0) {
        return 'Today';
    }
    if (d <= 60) {
        return d === 1 ? 'In 1 day' : `In ${d} days`;
    }
    const months = Math.round(d / 30.44);
    return `In ${months} months`;
}

export default class NxpAgencyProfile extends NavigationMixin(LightningElement) {
    @api recordId;
    data;
    loading = true;

    connectedCallback() {
        logUsage('Agency');
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getAgencyProfile({ agencyId: this.recordId });
        } catch (e) {
            toastError(this, e, 'Could not load the agency profile');
        } finally {
            this.loading = false;
        }
    }

    get agency() {
        return this.data ? this.data.agency : null;
    }

    get parent() {
        const a = this.agency;
        return a && a.Parent_Agency__c
            ? { id: a.Parent_Agency__c, name: a.Parent_Agency__r ? a.Parent_Agency__r.Name : 'Parent agency' }
            : null;
    }

    get chips() {
        const a = this.agency;
        if (!a) {
            return [];
        }
        const chips = [];
        if (a.Level__c) {
            chips.push({ key: 'level', label: a.Level__c, className: 'chip chip_strong' });
        }
        if (a.Agency_Code__c) {
            chips.push({ key: 'code', label: 'Code ' + a.Agency_Code__c, className: 'chip' });
        }
        if (this.data.targetAgency) {
            chips.push({ key: 'target', label: 'Target agency in your profile', className: 'chip chip_target' });
        }
        return chips;
    }

    get kpis() {
        const d = this.data;
        if (!d) {
            return [];
        }
        return [
            {
                key: 'notices',
                label: 'Open notices',
                value: String(d.openNotices),
                note: `${d.dueIn30} due in the next 30 days`
            },
            {
                key: 'forecasts',
                label: 'Forecasts',
                value: String(d.forecasts),
                note: d.forecastValue ? 'est. ' + compactMoney(d.forecastValue) : 'no values published'
            },
            {
                key: 'ending',
                label: 'Awards ending in 18 months',
                value: String(d.endingSoon),
                note: d.endingSoonValue ? compactMoney(d.endingSoonValue) + ' obligated' : 'none'
            },
            {
                key: 'incumbents',
                label: 'Incumbents',
                value: String(d.incumbents.length),
                note: d.incumbents.length ? d.incumbents[0].name : 'no award data yet'
            }
        ];
    }

    get coming() {
        if (!this.data) {
            return [];
        }
        return this.data.coming.map((c) => {
            const kind = KINDS[c.kind] || KINDS.notice;
            let right = '';
            if (c.kind === 'notice') {
                right = c.fitScore === null || c.fitScore === undefined ? '' : 'Fit ' + c.fitScore;
            } else {
                right = compactMoney(c.amount);
            }
            const d = daysUntil(c.onDate);
            return {
                ...c,
                when: whenLabel(c),
                whenClass: d !== null && d >= 0 && d <= 30 ? 'when when_soon' : 'when',
                kindLabel: kind.label,
                kindClass: kind.className,
                right
            };
        });
    }

    get hasComing() {
        return this.coming.length > 0;
    }

    get incumbents() {
        return this.data
            ? this.data.incumbents.map((i) => ({
                  ...i,
                  note: i.awards === 1 ? '1 award' : `${i.awards} awards`,
                  totalLabel: compactMoney(i.total)
              }))
            : [];
    }

    get hasIncumbents() {
        return this.incumbents.length > 0;
    }

    get naics() {
        return this.data
            ? this.data.naics.map((n) => ({
                  ...n,
                  totalLabel: compactMoney(n.total),
                  barStyle: `width: ${n.pct}%;`,
                  fitNote: n.inProfile ? 'In your company profile' : 'Not in your company profile'
              }))
            : [];
    }

    get hasNaics() {
        return this.naics.length > 0;
    }

    get contacts() {
        return this.data
            ? this.data.contacts.map((c) => ({
                  ...c,
                  meta: [c.role, c.email, c.phone, c.noticeKey].filter((p) => p).join(' · ')
              }))
            : [];
    }

    get hasContacts() {
        return this.contacts.length > 0;
    }

    get hasOffices() {
        return !!(this.data && this.data.offices.length);
    }

    get hasChildren() {
        return !!(this.data && this.data.children.length);
    }

    get covered() {
        return !!(this.data && this.data.coveringSearches.length);
    }

    get coverageText() {
        const d = this.data;
        if (!d) {
            return '';
        }
        if (d.coveringSearches.length) {
            return 'Covered by your saved searches: ' + d.coveringSearches.join(', ') + '.';
        }
        const broad =
            d.broadSearches === 1
                ? ' One of your searches has no agency filter and may still catch some of its notices.'
                : d.broadSearches > 1
                  ? ` ${d.broadSearches} of your searches have no agency filter and may still catch some of its notices.`
                  : '';
        return 'None of your saved searches targets this agency.' + broad;
    }

    get watchLabel() {
        return this.data && this.data.watching ? 'Watching' : 'Watch this agency';
    }

    get watchVariant() {
        return this.data && this.data.watching ? 'brand' : 'neutral';
    }

    handleOpen(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' }
        });
    }

    handleNewSearch() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'NXP_Search_Builder' }
        });
    }

    async handleWatch() {
        const watching = this.data.watching;
        try {
            await watch({ recordId: this.recordId, watch: !watching });
            toast(
                this,
                watching ? 'Stopped watching' : 'Watching this agency',
                watching ? '' : 'You will get an alert for every new notice from this agency and its sub-agencies.'
            );
            this.load();
        } catch (e) {
            toastError(this, e, 'Could not change the watch');
        }
    }
}
