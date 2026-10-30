import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getDetail from '@salesforce/apex/NXP_NoticeController.getDetail';
import followNotice from '@salesforce/apex/NXP_SearchController.followNotice';
import NxpPushDialog from 'c/nxpPushDialog';
import { daysUntil, formatDate, formatMoney, toast, toastError, logUsage } from 'c/nxpUtils';

export default class NxpNoticeSummary extends NavigationMixin(LightningElement) {
    @api recordId;
    detail;
    loading = true;

    connectedCallback() {
        logUsage('Notice');
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.detail = await getDetail({ noticeId: this.recordId });
        } catch (e) {
            toastError(this, e, 'Could not load the notice');
        } finally {
            this.loading = false;
        }
    }

    get notice() {
        return this.detail ? this.detail.notice : {};
    }

    get days() {
        return daysUntil(this.notice.Response_Due__c);
    }

    get daysLabel() {
        const d = this.days;
        if (d === null) {
            return '–';
        }
        return d < 0 ? 'Closed' : `${d}`;
    }

    get daysCaption() {
        const d = this.days;
        if (d === null) {
            return 'no due date';
        }
        return d < 0 ? formatDate(this.notice.Response_Due__c) : 'days to respond';
    }

    get dueClass() {
        const d = this.days;
        return d !== null && d >= 0 && d <= 7 ? 'tile tile_warn' : 'tile tile_neutral';
    }

    get dueText() {
        return formatDate(this.notice.Response_Due__c, true);
    }

    get valueText() {
        return this.notice.Estimated_Value__c ? formatMoney(this.notice.Estimated_Value__c) : 'Not published';
    }

    get summaryText() {
        return this.notice.AI_Summary__c;
    }

    get summaryNote() {
        switch (this.notice.AI_Summary_Status__c) {
            case 'Pending':
                return 'An AI summary is being prepared for this notice.';
            case 'Failed':
                return 'The AI summary could not be generated. The full description is below.';
            default:
                return 'An AI summary is generated once the notice matches a saved search.';
        }
    }

    get descriptionText() {
        const d = this.notice.Description__c;
        return d && !d.startsWith('http') ? d : null;
    }

    get breakdown() {
        return (this.detail ? this.detail.breakdown : []).map((r, i) => ({
            key: `r${i}`,
            rule: r.rule,
            reason: r.reason,
            score: `${r.points} / ${r.weight}`,
            style: `width:${r.weight ? Math.round((r.points / r.weight) * 100) : 0}%`
        }));
    }

    get hasBreakdown() {
        return this.breakdown.length > 0;
    }

    get versions() {
        return (this.detail ? this.detail.versions : []).map((v) => ({
            id: v.Id,
            name: v.Version_Number__c === 1 ? 'Original' : `Amendment ${v.Version_Number__c - 1}`,
            when: formatDate(v.CreatedDate),
            what: v.AI_Change_Summary__c || v.Diff_Summary__c,
            type: v.Change_Type__c
        }));
    }

    get contacts() {
        return this.detail ? this.detail.contacts : [];
    }

    get hasContacts() {
        return this.contacts.length > 0;
    }

    get pushLogs() {
        return (this.detail ? this.detail.pushLogs : []).map((l) => ({ ...l, when: formatDate(l.CreatedDate, true) }));
    }

    get hasPushLogs() {
        return this.pushLogs.length > 0;
    }

    get pushed() {
        return !!this.notice.Pushed_Record_Id__c;
    }

    get pushLabel() {
        return this.pushed ? 'Open Opportunity record' : 'Push to Opportunity';
    }

    get followLabel() {
        return this.detail && this.detail.following ? 'Unfollow' : 'Follow';
    }

    get sourcesText() {
        return this.detail && this.detail.sources.length ? this.detail.sources.join(', ') : this.notice.Source_Feed__c;
    }

    async handlePush() {
        if (this.pushed) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: this.notice.Pushed_Record_Id__c, actionName: 'view' }
            });
            return;
        }
        const result = await NxpPushDialog.open({
            noticeId: this.recordId,
            size: 'medium',
            label: 'Push to Opportunity'
        });
        if (result) {
            toast(this, 'Pushed to Opportunity', result.message);
            this.load();
        }
    }

    async handleFollow() {
        try {
            await followNotice({ noticeId: this.recordId, follow: !this.detail.following });
            this.load();
        } catch (e) {
            toastError(this, e);
        }
    }

    handleOpenSam() {
        if (this.notice.Notice_URL__c) {
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: { url: this.notice.Notice_URL__c }
            });
        }
    }
}
