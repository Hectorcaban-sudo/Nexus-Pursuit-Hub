import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import LightningPrompt from 'lightning/prompt';
import getMySearches from '@salesforce/apex/NXP_SearchController.getMySearches';
import getInbox from '@salesforce/apex/NXP_SearchController.getInbox';
import setMatchAction from '@salesforce/apex/NXP_SearchController.setMatchAction';
import setMatchActions from '@salesforce/apex/NXP_SearchController.setMatchActions';
import bulkPush from '@salesforce/apex/NXP_PushController.bulkPush';
import NxpPushDialog from 'c/nxpPushDialog';
import { formatMoney, dueLabel, daysUntil, toast, toastError, logUsage } from 'c/nxpUtils';

const SORTS = [
    { label: 'Fit score, then due date', value: 'fit' },
    { label: 'Due date', value: 'due' },
    { label: 'Newest match', value: 'newest' }
];

export default class NxpMatchInbox extends NavigationMixin(LightningElement) {
    @track searches = [];
    @track items = [];
    selectedSearchId = null;
    includeWatching = false;
    sortBy = 'fit';
    loading = true;
    selected = new Set();

    sortOptions = SORTS;

    connectedCallback() {
        logUsage('Match Inbox');
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            const [searches, items] = await Promise.all([
                getMySearches(),
                getInbox({ searchId: this.selectedSearchId, includeWatching: this.includeWatching })
            ]);
            this.searches = searches.filter((s) => s.mine);
            this.items = items;
            this.selected = new Set();
        } catch (e) {
            toastError(this, e, 'Could not load the Match Inbox');
        } finally {
            this.loading = false;
        }
    }

    get searchRows() {
        return this.searches.map((s) => ({
            ...s,
            rowClass: s.id === this.selectedSearchId ? 'search-row search-row_active' : 'search-row',
            showCount: s.newCount > 0
        }));
    }

    get allRowClass() {
        return this.selectedSearchId ? 'search-row' : 'search-row search-row_active';
    }

    get totalNew() {
        return this.searches.reduce((sum, s) => sum + (s.newCount || 0), 0);
    }

    get cards() {
        const list = this.items.map((i) => {
            const n = i.notice;
            const summary =
                n.AI_Summary__c || (n.Description__c && !n.Description__c.startsWith('http') ? n.Description__c : '');
            return {
                key: i.matchId,
                matchId: i.matchId,
                noticeId: n.Id,
                title: n.Title__c || n.Name,
                fit: n.Fit_Score__c,
                breakdown: n.Fit_Breakdown__c,
                type: n.Notice_Type__c,
                setAside: n.Set_Aside__c,
                hasSetAside: !!n.Set_Aside__c,
                agency: n.Agency_Path__c,
                value: n.Estimated_Value__c ? formatMoney(n.Estimated_Value__c) : 'Value not published',
                due: dueLabel(n.Response_Due__c),
                dueSoon: daysUntil(n.Response_Due__c) !== null && daysUntil(n.Response_Due__c) <= 7,
                summary: summary ? summary.substring(0, 280) + (summary.length > 280 ? '…' : '') : '',
                hasSummary: !!summary,
                isChange: !!i.changeType && i.changeType !== 'New' && i.changeType !== 'Already open',
                changeType: i.changeType,
                watching: i.userAction === 'Watching',
                hasChecks: i.openChecks > 0,
                checksLabel: i.openChecks === 1 ? '1 document check' : `${i.openChecks} document checks`,
                searchName: i.searchName,
                matchedTerms: i.matchedTerms,
                checked: this.selected.has(n.Id),
                dueRaw: n.Response_Due__c ? new Date(n.Response_Due__c).getTime() : Number.MAX_SAFE_INTEGER,
                matchedRaw: new Date(i.matchedAt).getTime()
            };
        });
        if (this.sortBy === 'due') {
            list.sort((a, b) => a.dueRaw - b.dueRaw);
        } else if (this.sortBy === 'newest') {
            list.sort((a, b) => b.matchedRaw - a.matchedRaw);
        } else {
            list.sort((a, b) => (b.fit || 0) - (a.fit || 0) || a.dueRaw - b.dueRaw);
        }
        return list;
    }

    get hasCards() {
        return this.items.length > 0;
    }

    get selectedCount() {
        return this.selected.size;
    }

    get disableBulk() {
        return this.selected.size === 0;
    }

    get bulkLabel() {
        return this.selected.size ? `Push ${this.selected.size}` : 'Push';
    }

    get allSelected() {
        return this.items.length > 0 && this.selected.size === this.items.length;
    }

    get selectAllLabel() {
        return this.selected.size ? `${this.selected.size} selected` : 'Select all';
    }

    /** Match records behind the selected notice cards. */
    get selectedMatchIds() {
        return this.items.filter((i) => this.selected.has(i.notice.Id)).map((i) => i.matchId);
    }

    handleSelectSearch(event) {
        this.selectedSearchId = event.currentTarget.dataset.id || null;
        this.load();
    }

    handleSort(event) {
        this.sortBy = event.detail.value;
    }

    handleWatchingToggle(event) {
        this.includeWatching = event.target.checked;
        this.load();
    }

    handleCheck(event) {
        const id = event.target.dataset.id;
        const next = new Set(this.selected);
        if (event.target.checked) {
            next.add(id);
        } else {
            next.delete(id);
        }
        this.selected = next;
    }

    handleSelectAll(event) {
        this.selected = event.target.checked ? new Set(this.items.map((i) => i.notice.Id)) : new Set();
    }

    async handleBulkWatch() {
        try {
            const count = await setMatchActions({ matchIds: this.selectedMatchIds, action: 'Watching', reason: null });
            toast(this, 'Watching', `${count} notices. You will be alerted when they change.`);
            this.load();
        } catch (e) {
            toastError(this, e, 'Could not watch the selected notices');
        }
    }

    async handleBulkDismiss() {
        const reason = await LightningPrompt.open({
            message: `Why are you dismissing these ${this.selected.size} notices? This helps tune your searches.`,
            label: 'Dismiss notices',
            defaultValue: 'Not a fit'
        });
        if (reason === null) {
            return;
        }
        try {
            const count = await setMatchActions({ matchIds: this.selectedMatchIds, action: 'Dismissed', reason });
            toast(this, 'Dismissed', `${count} notices removed from the inbox.`);
            this.load();
        } catch (e) {
            toastError(this, e, 'Could not dismiss the selected notices');
        }
    }

    handleOpen(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.currentTarget.dataset.id,
                objectApiName: 'NXP_Gov_Notice__c',
                actionName: 'view'
            }
        });
    }

    handleNewSearch() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'NXP_Search_Builder' }
        });
    }

    async handlePush(event) {
        const noticeId = event.currentTarget.dataset.id;
        const result = await NxpPushDialog.open({
            noticeId,
            source: 'Match Inbox',
            size: 'medium',
            label: 'Push to Opportunity'
        });
        if (result) {
            toast(this, 'Pushed to Opportunity', result.message);
            this.load();
        }
    }

    async handleWatch(event) {
        try {
            await setMatchAction({ matchId: event.currentTarget.dataset.match, action: 'Watching', reason: null });
            toast(this, 'Watching', 'You will be alerted when this notice changes.');
            this.load();
        } catch (e) {
            toastError(this, e);
        }
    }

    async handleDismiss(event) {
        const matchId = event.currentTarget.dataset.match;
        const reason = await LightningPrompt.open({
            message: 'Why are you dismissing this notice? This helps tune your searches.',
            label: 'Dismiss notice',
            defaultValue: 'Not a fit'
        });
        if (reason === null) {
            return;
        }
        try {
            await setMatchAction({ matchId, action: 'Dismissed', reason });
            this.load();
        } catch (e) {
            toastError(this, e);
        }
    }

    async handleBulkPush() {
        try {
            const results = await bulkPush({ noticeIds: Array.from(this.selected) });
            const ok = results.filter((r) => r.status !== 'Failed').length;
            toast(
                this,
                'Bulk push finished',
                `${ok} of ${results.length} pushed or linked.`,
                ok === results.length ? 'success' : 'warning'
            );
            this.load();
        } catch (e) {
            toastError(this, e, 'Bulk push failed');
        }
    }
}
