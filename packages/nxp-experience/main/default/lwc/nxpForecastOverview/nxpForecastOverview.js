import { LightningElement, api } from 'lwc';
import getOverview from '@salesforce/apex/NXP_ForecastController.getOverview';
import setPredecessor from '@salesforce/apex/NXP_ForecastController.setPredecessor';
import linkNotice from '@salesforce/apex/NXP_ForecastController.linkNotice';
import watch from '@salesforce/apex/NXP_MarketController.watch';
import { formatDate, formatMoney, toast, toastError, logUsage } from 'c/nxpUtils';

function money(v) {
    if (v === null || v === undefined) {
        return '';
    }
    const n = Number(v);
    if (Math.abs(n) >= 1000000) {
        return '$' + (n / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
    }
    return formatMoney(n);
}

export default class NxpForecastOverview extends LightningElement {
    @api recordId;
    data;
    loading = true;
    busy = false;
    linkNoticeId;

    connectedCallback() {
        logUsage('Forecast');
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getOverview({ forecastId: this.recordId });
        } catch (e) {
            toastError(this, e, 'Could not load the forecast');
        } finally {
            this.loading = false;
        }
    }

    get f() {
        return this.data ? this.data.forecast : {};
    }

    // ------------------------------------------------------------------ header

    get daysLabel() {
        const d = this.data.daysToSolicitation;
        if (d === null || d === undefined) {
            return '–';
        }
        return d < 0 ? 'Past' : String(d);
    }

    get daysCaption() {
        const d = this.data.daysToSolicitation;
        if (d === null || d === undefined) {
            return 'no solicitation date';
        }
        return d < 0 ? 'expected ' + formatDate(this.f.Estimated_Solicitation_Date__c) : 'days to solicitation';
    }

    get hasFit() {
        return this.data && this.data.fitScore !== null && this.data.fitScore !== undefined;
    }

    get agencyUrl() {
        return this.f.Agency__c ? '/' + this.f.Agency__c : null;
    }

    get agencyName() {
        return this.f.Agency__r ? this.f.Agency__r.Name : 'Not set';
    }

    get solicitationText() {
        return this.f.Estimated_Solicitation_Date__c ? formatDate(this.f.Estimated_Solicitation_Date__c) : 'Not known';
    }

    get valueText() {
        const parts = [];
        if (this.f.Estimated_Value__c) {
            parts.push(formatMoney(this.f.Estimated_Value__c));
        }
        if (this.f.Fiscal_Year__c) {
            parts.push(this.f.Fiscal_Year__c);
        }
        return parts.length ? parts.join(' · ') : 'Not published';
    }

    get naicsText() {
        return this.f.NAICS_Code__c || 'Not set';
    }

    get setAsideText() {
        return this.f.Set_Aside__c || 'None stated';
    }

    get hasSetAsideFlag() {
        return this.data && this.data.setAsideOk !== null && this.data.setAsideOk !== undefined;
    }

    get setAsideFlagClass() {
        return this.data.setAsideOk ? 'flag flag_ok' : 'flag flag_bad';
    }

    get watchLabel() {
        return this.data && this.data.watching ? 'Watching: stop' : 'Watch: tell me when it posts';
    }

    get watchVariant() {
        return this.data && this.data.watching ? 'neutral' : 'brand';
    }

    async handleWatch() {
        this.busy = true;
        try {
            const on = !this.data.watching;
            await watch({ recordId: this.recordId, watch: on });
            toast(
                this,
                on ? 'Watching this forecast' : 'Stopped watching',
                on ? 'You get an alert when its notice posts.' : ''
            );
            await this.load();
        } catch (e) {
            toastError(this, e, 'Could not change the watch');
        } finally {
            this.busy = false;
        }
    }

    // ------------------------------------------------------------------ fit

    get fitRows() {
        return (this.data ? this.data.fit : []).map((r, i) => ({
            key: 'r' + i,
            rule: r.rule,
            reason: r.reason,
            score: `${r.points} / ${r.weight}`,
            style: `width:${r.weight ? Math.round((r.points / r.weight) * 100) : 0}%`
        }));
    }

    // ------------------------------------------------------------------ where it stands

    get stages() {
        return (this.data ? this.data.stages : []).map((s, i) => ({
            ...s,
            key: 's' + i,
            cls: 'stage stage_' + s.state
        }));
    }

    get watchersText() {
        const n = this.data ? this.data.watchers : 0;
        return n === 1 ? '1 person watches this forecast' : `${n} people watch this forecast`;
    }

    get notices() {
        return (this.data ? this.data.notices : []).map((n) => ({
            id: n.Id,
            url: '/' + n.Id,
            title: n.Title__c || n.Name,
            meta: [n.Notice_Type__c, n.Posted_Date__c ? 'posted ' + formatDate(n.Posted_Date__c) : null, n.Status__c]
                .filter((x) => !!x)
                .join(' · ')
        }));
    }

    get hasNotices() {
        return this.notices.length > 0;
    }

    handleLinkPick(event) {
        this.linkNoticeId = event.detail.recordId;
    }

    get linkDisabled() {
        return !this.linkNoticeId || this.busy;
    }

    async handleLink() {
        this.busy = true;
        try {
            this.data = await linkNotice({ forecastId: this.recordId, noticeId: this.linkNoticeId });
            toast(this, 'Notice linked', 'Watchers see it here; a confirmed predecessor carries over.');
        } catch (e) {
            toastError(this, e, 'Could not link the notice');
        } finally {
            this.busy = false;
        }
    }

    // ------------------------------------------------------------------ predecessor candidates

    get candidates() {
        return (this.data ? this.data.candidates : []).map((c) => ({
            ...c,
            url: '/' + c.id,
            vendorUrl: c.vendorId ? '/' + c.vendorId : null,
            ends: formatDate(c.periodEnd),
            spent: money(c.obligated),
            matchClass: 'match match_' + (c.match || 'Low').toLowerCase(),
            actionLabel: c.confirmed ? 'Clear' : 'Confirm',
            actionTitle: c.confirmed ? 'Not the predecessor after all' : 'Set as the predecessor'
        }));
    }

    get hasCandidates() {
        return this.candidates.length > 0;
    }

    async handlePredecessor(event) {
        const id = event.currentTarget.dataset.id;
        const confirmed = event.currentTarget.dataset.confirmed === 'true';
        this.busy = true;
        try {
            this.data = await setPredecessor({ forecastId: this.recordId, awardId: confirmed ? null : id });
            toast(
                this,
                confirmed ? 'Predecessor cleared' : 'Predecessor confirmed',
                confirmed ? '' : 'The notice will get it when it posts.'
            );
        } catch (e) {
            toastError(this, e, 'Could not set the predecessor');
        } finally {
            this.busy = false;
        }
    }

    // ------------------------------------------------------------------ right column

    get leaders() {
        return (this.data ? this.data.leaders : []).map((l) => ({
            ...l,
            url: '/' + l.vendorId,
            meta: `${l.awards} ${l.awards === 1 ? 'award' : 'awards'}${l.obligated ? ' · ' + money(l.obligated) : ''}`
        }));
    }

    get hasLeaders() {
        return this.leaders.length > 0;
    }

    get leadersScope() {
        return `${this.agencyName}${this.f.NAICS_Code__c ? ', NAICS ' + this.f.NAICS_Code__c : ''}, last 5 years`;
    }

    get related() {
        return (this.data ? this.data.related : []).map((r) => ({
            id: r.Id,
            url: '/' + r.Id,
            text: [
                r.Name,
                r.Estimated_Solicitation_Date__c ? formatDate(r.Estimated_Solicitation_Date__c) : null,
                r.Estimated_Value__c ? money(r.Estimated_Value__c) : null
            ]
                .filter((x) => !!x)
                .join(' · ')
        }));
    }

    get hasRelated() {
        return this.related.length > 0;
    }

    get description() {
        return this.f.Description__c;
    }
}
