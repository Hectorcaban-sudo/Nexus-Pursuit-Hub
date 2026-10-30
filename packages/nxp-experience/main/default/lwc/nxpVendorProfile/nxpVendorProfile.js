import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getVendorProfile from '@salesforce/apex/NXP_MarketController.getVendorProfile';
import watch from '@salesforce/apex/NXP_MarketController.watch';
import refreshVendor from '@salesforce/apex/NXP_MarketController.refreshVendor';
import { daysUntil, dueLabel, formatDate, formatMoney, toast, toastError, logUsage } from 'c/nxpUtils';

export default class NxpVendorProfile extends NavigationMixin(LightningElement) {
    @api recordId;
    data;
    loading = true;
    refreshing = false;

    connectedCallback() {
        logUsage('Vendor');
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getVendorProfile({ vendorId: this.recordId });
        } catch (e) {
            toastError(this, e, 'Could not load the vendor profile');
        } finally {
            this.loading = false;
        }
    }

    get vendor() {
        return this.data ? this.data.vendor : null;
    }

    get chips() {
        const v = this.vendor;
        if (!v) {
            return [];
        }
        const chips = [{ key: 'size', label: v.Business_Size__c || 'Business size unknown', strong: true }];
        if (v.Socio_Economic__c) {
            v.Socio_Economic__c.split(';')
                .map((s) => s.trim())
                .filter((s) => s)
                .forEach((s, i) => chips.push({ key: 'se' + i, label: s }));
        }
        return chips.map((c) => ({ ...c, className: c.strong ? 'chip chip_strong' : 'chip' }));
    }

    get identity() {
        const v = this.vendor;
        if (!v) {
            return '';
        }
        const parts = [];
        if (v.UEI__c) {
            parts.push('UEI ' + v.UEI__c);
        }
        if (v.CAGE_Code__c) {
            parts.push('CAGE ' + v.CAGE_Code__c);
        }
        const place = [v.City__c, v.State__c].filter((p) => p).join(', ');
        if (place) {
            parts.push(place);
        }
        parts.push(
            v.Last_Synced__c ? 'SAM.gov details synced ' + formatDate(v.Last_Synced__c) : 'Not synced from SAM.gov'
        );
        return parts.join(' · ');
    }

    get kpis() {
        const d = this.data;
        if (!d) {
            return [];
        }
        return [
            { key: 'awards', label: 'Awards in Nexus', value: String(d.awardCount), note: 'from award data' },
            {
                key: 'obligated',
                label: 'Total obligated',
                value: formatMoney(d.totalObligated),
                note: 'on those awards'
            },
            { key: 'ending', label: 'Ending in 18 months', value: String(d.endingSoon), note: 'recompete exposure' },
            {
                key: 'agencies',
                label: 'Agencies',
                value: String(d.agencies.length),
                note: d.agencies.length ? d.agencies.slice(0, 3).join(', ') : 'none yet'
            }
        ];
    }

    get awards() {
        if (!this.data) {
            return [];
        }
        return this.data.awards.map((a) => {
            const days = daysUntil(a.periodEnd);
            let ends = 'No end date';
            if (days !== null) {
                ends =
                    days < 0
                        ? 'Ended ' + formatDate(a.periodEnd)
                        : 'In ' + Math.max(Math.round(days / 30.44), 0) + ' months';
            }
            return {
                ...a,
                obligatedLabel: formatMoney(a.obligated),
                ends,
                hasFollowOn: !!a.followOnId
            };
        });
    }

    get hasAwards() {
        return this.awards.length > 0;
    }

    get overlap() {
        return this.data ? this.data.overlap.map((o) => ({ ...o, key: o.label })) : [];
    }

    get openNotices() {
        if (!this.data) {
            return [];
        }
        return this.data.openNotices.map((n) => ({
            ...n,
            meta: [n.noticeType, n.agency, n.noticeKey].filter((p) => p).join(' · '),
            due: dueLabel(n.responseDue),
            fit: n.fitScore === null || n.fitScore === undefined ? '' : ' · fit ' + n.fitScore
        }));
    }

    get hasOpenNotices() {
        return this.openNotices.length > 0;
    }

    get watchLabel() {
        return this.data && this.data.watching ? 'Watching' : 'Watch this vendor';
    }

    get watchVariant() {
        return this.data && this.data.watching ? 'brand' : 'neutral';
    }

    get canRefresh() {
        return !!(this.data && this.data.canRefresh);
    }

    handleOpen(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' }
        });
    }

    async handleWatch() {
        const watching = this.data.watching;
        try {
            await watch({ recordId: this.recordId, watch: !watching });
            toast(
                this,
                watching ? 'Stopped watching' : 'Watching this vendor',
                watching ? '' : 'You will get an alert when they win a new award.'
            );
            this.load();
        } catch (e) {
            toastError(this, e, 'Could not change the watch');
        }
    }

    async handleRefresh() {
        this.refreshing = true;
        try {
            const message = await refreshVendor({ vendorId: this.recordId });
            toast(this, 'SAM.gov', message, message.startsWith('Updated') ? 'success' : 'warning');
            this.load();
        } catch (e) {
            toastError(this, e, 'Could not refresh from SAM.gov');
        } finally {
            this.refreshing = false;
        }
    }
}
