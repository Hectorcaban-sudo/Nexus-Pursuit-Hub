import { LightningElement } from 'lwc';
import LightningAlert from 'lightning/alert';
import getConsole from '@salesforce/apex/NXP_FeedConsoleController.getConsole';
import runNow from '@salesforce/apex/NXP_FeedConsoleController.runNow';
import getRunErrors from '@salesforce/apex/NXP_FeedConsoleController.getRunErrors';
import { formatDate, toast, toastError, logUsage } from 'c/nxpUtils';

const HEALTH_CLASS = {
    Healthy: 'status status_ok',
    Running: 'status status_info',
    Warning: 'status status_warn',
    Failed: 'status status_bad',
    Paused: 'status status_neutral',
    'Never run': 'status status_neutral'
};

const COLUMNS = [
    { label: 'Started', fieldName: 'started', type: 'text' },
    { label: 'Feed', fieldName: 'feed', type: 'text' },
    { label: 'Channel', fieldName: 'channel', type: 'text' },
    { label: 'Read', fieldName: 'read', type: 'number' },
    { label: 'New', fieldName: 'created', type: 'number' },
    { label: 'Updated', fieldName: 'updated', type: 'number' },
    { label: 'Rejected', fieldName: 'rejected', type: 'number' },
    { label: 'Result', fieldName: 'status', type: 'text' },
    { type: 'action', typeAttributes: { rowActions: [{ label: 'Show errors', name: 'errors' }] } }
];

export default class NxpFeedConsole extends LightningElement {
    data;
    loading = true;
    columns = COLUMNS;

    connectedCallback() {
        logUsage('Feed Console');
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getConsole();
        } catch (e) {
            toastError(this, e, 'Could not load the Feed Console');
        } finally {
            this.loading = false;
        }
    }

    get tiles() {
        if (!this.data) {
            return [];
        }
        return this.data.feeds.map((f) => {
            const r = f.lastRun || {};
            const n = (v) => (v === null || v === undefined ? '–' : v);
            return {
                ...f,
                statusClass: HEALTH_CLASS[f.health] || 'status status_neutral',
                read: n(r.Records_Read__c),
                created: n(r.Records_Created__c),
                updated: n(r.Records_Updated__c),
                rejected: n(r.Records_Rejected__c),
                last: r.Started__c ? formatDate(r.Started__c, true) : 'never',
                every: f.intervalMinutes ? this.intervalText(f.intervalMinutes) : 'on push',
                lastRunId: r.Id,
                noRun: !r.Id,
                runDisabled: !this.data.canRun || !f.active || f.channel === 'Apex REST'
            };
        });
    }

    get rows() {
        if (!this.data) {
            return [];
        }
        return this.data.runs.map((r) => ({
            id: r.Id,
            started: formatDate(r.Started__c, true),
            feed: r.Feed_Name__c,
            channel: r.Channel__c,
            read: r.Records_Read__c,
            created: r.Records_Created__c,
            updated: r.Records_Updated__c,
            rejected: r.Records_Rejected__c,
            status: r.Status__c
        }));
    }

    get schedulerWarning() {
        return this.data && !this.data.schedulerActive;
    }

    intervalText(minutes) {
        if (minutes % 10080 === 0) {
            return 'weekly';
        }
        if (minutes % 1440 === 0) {
            return minutes === 1440 ? 'daily' : `every ${minutes / 1440} days`;
        }
        return minutes === 60 ? 'hourly' : `every ${minutes} min`;
    }

    async handleRun(event) {
        const feed = event.currentTarget.dataset.feed;
        try {
            await runNow({ feedName: feed });
            toast(this, 'Run started', `${feed} is running. Refresh in a minute to see results.`);
            this.load();
        } catch (e) {
            toastError(this, e, 'Could not start the run');
        }
    }

    async handleErrors(event) {
        this.showErrors(event.currentTarget.dataset.run);
    }

    handleRowAction(event) {
        this.showErrors(event.detail.row.id);
    }

    async showErrors(runId) {
        try {
            const text = await getRunErrors({ runId });
            await LightningAlert.open({
                message: text || 'No errors recorded for this run.',
                label: 'Run errors',
                theme: text ? 'warning' : 'success'
            });
        } catch (e) {
            toastError(this, e);
        }
    }

    handleRefresh() {
        this.load();
    }
}
