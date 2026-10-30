import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getEmails from '@salesforce/apex/NXP_EmailLogController.getEmails';
import getEmail from '@salesforce/apex/NXP_EmailLogController.getEmail';
import reprocess from '@salesforce/apex/NXP_EmailLogController.reprocess';
import ignore from '@salesforce/apex/NXP_EmailLogController.ignore';
import { debounce, formatDate, toast, toastError, logUsage } from 'c/nxpUtils';

const STATUS_OPTIONS = [
    { label: 'All statuses', value: '' },
    { label: 'Received (waiting)', value: 'Received' },
    { label: 'Ingested', value: 'Ingested' },
    { label: 'Needs review', value: 'Needs Review' },
    { label: 'Rejected', value: 'Rejected' },
    { label: 'Failed', value: 'Failed' },
    { label: 'Ignored', value: 'Ignored' }
];

const STATUS_CLASS = {
    Ingested: 'status status_ok',
    'Needs Review': 'status status_warn',
    Rejected: 'status status_bad',
    Failed: 'status status_bad',
    Received: 'status',
    Ignored: 'status status_muted'
};

/** Order and wording of the extracted fields shown in the detail panel. */
const FIELD_LABELS = [
    ['rfqNumber', 'RFQ number'],
    ['title', 'Title'],
    ['agency', 'Agency'],
    ['office', 'Office'],
    ['sins', 'SINs'],
    ['naics', 'NAICS'],
    ['setAside', 'Set-aside'],
    ['issueDate', 'Issued'],
    ['responseDue', 'Closes'],
    ['placeOfPerformance', 'Place of performance'],
    ['buyerName', 'Buyer'],
    ['buyerEmail', 'Buyer e-mail'],
    ['url', 'eBuy link'],
    ['summary', 'AI summary'],
    ['evaluationFactors', 'Evaluation factors (AI)']
];

function sizeLabel(bytes) {
    if (!bytes) {
        return '';
    }
    if (bytes < 1024 * 1024) {
        return Math.max(1, Math.round(bytes / 1024)) + ' KB';
    }
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

function fieldValue(key, value) {
    if (Array.isArray(value)) {
        return value.join(', ');
    }
    if (key === 'responseDue') {
        return formatDate(value, true);
    }
    if (key === 'issueDate') {
        return formatDate(value);
    }
    return String(value);
}

export default class NxpEmailLog extends NavigationMixin(LightningElement) {
    log;
    detail;
    selectedId;
    status = '';
    search = '';
    rfqInput = '';
    loading = true;
    detailLoading = false;
    busy = false;
    statusOptions = STATUS_OPTIONS;

    connectedCallback() {
        logUsage('Inbound Emails');
        this.debouncedLoad = debounce(() => this.load(), 400);
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.log = await getEmails({ status: this.status, search: this.search, rowLimit: 100 });
            const rows = this.log.rows;
            if (!this.selectedId && rows.length) {
                this.select(rows[0].id);
            } else if (this.selectedId) {
                this.select(this.selectedId);
            }
        } catch (e) {
            toastError(this, e, 'Could not load inbound e-mail');
        } finally {
            this.loading = false;
        }
    }

    async select(emailId) {
        this.selectedId = emailId;
        this.detailLoading = true;
        try {
            this.detail = await getEmail({ emailId });
            this.rfqInput = this.detail.row.rfqNumber || '';
        } catch (e) {
            this.detail = undefined;
            toastError(this, e, 'Could not open the e-mail');
        } finally {
            this.detailLoading = false;
        }
    }

    // ------------------------------------------------------------------------- view model

    count(status) {
        const c = this.log ? this.log.counts.find((x) => x.status === status) : null;
        return c ? c.count : 0;
    }

    get kpis() {
        if (!this.log) {
            return [];
        }
        const bad = this.count('Rejected') + this.count('Failed');
        return [
            { key: 'all', label: 'Received (30 days)', value: this.log.last30, valueClass: 'kpi-value' },
            { key: 'ok', label: 'Became notices', value: this.count('Ingested'), valueClass: 'kpi-value' },
            {
                key: 'review',
                label: 'Need review',
                value: this.count('Needs Review'),
                valueClass: this.count('Needs Review') ? 'kpi-value kpi-value_warn' : 'kpi-value'
            },
            {
                key: 'bad',
                label: 'Rejected or failed',
                value: bad,
                valueClass: bad ? 'kpi-value kpi-value_bad' : 'kpi-value'
            }
        ];
    }

    get rows() {
        if (!this.log) {
            return [];
        }
        return this.log.rows.map((r) => ({
            ...r,
            when: formatDate(r.received, true),
            from: r.fromName ? `${r.fromName} <${r.fromAddress || ''}>` : r.fromAddress,
            subjectLabel: r.subject || '(no subject)',
            rfqLabel: r.rfqNumber || '—',
            statusClass: STATUS_CLASS[r.status] || 'status',
            rowClass: r.id === this.selectedId ? 'row row_selected' : 'row',
            selected: r.id === this.selectedId ? 'true' : 'false'
        }));
    }

    get nothingFound() {
        return !this.loading && this.log && this.log.rows.length === 0;
    }

    get allowedSenders() {
        return this.log ? this.log.allowedSenders : '';
    }

    get aiNote() {
        return this.log && this.log.aiEnabled
            ? 'AI fills in fields the rules miss (checked by code before use).'
            : 'AI is off (AI_Enabled), so fields are read with fixed rules only.';
    }

    get current() {
        if (!this.detail) {
            return null;
        }
        const r = this.detail.row;
        return {
            ...r,
            when: formatDate(r.received, true),
            processed: this.detail.processed ? formatDate(this.detail.processed, true) : 'Not yet',
            to: this.detail.toAddresses,
            statusClass: STATUS_CLASS[r.status] || 'status',
            methodLabel: r.method === 'AI' ? 'Read by rules and AI' : r.method === 'Rules' ? 'Read by rules' : '',
            detailLines: (r.statusDetail || '')
                .split('\n')
                .filter((l) => l.trim().length > 0)
                .map((text, i) => ({ key: 'line' + i, text })),
            hasNotice: !!r.noticeId,
            noticeLabel: r.noticeKey ? `${r.noticeKey} · ${r.noticeTitle || ''}` : '',
            canReprocess: r.status !== 'Rejected',
            canIgnore: r.status !== 'Ignored' && r.status !== 'Ingested',
            needsRfq: r.status === 'Needs Review' && !r.noticeId
        };
    }

    get extracted() {
        if (!this.detail || !this.detail.extractedJson) {
            return [];
        }
        let data;
        try {
            data = JSON.parse(this.detail.extractedJson);
        } catch (e) {
            return [];
        }
        return FIELD_LABELS.filter(([key]) => {
            const v = data[key];
            return v !== null && v !== undefined && v !== '' && !(Array.isArray(v) && v.length === 0);
        }).map(([key, label]) => ({ key, label, value: fieldValue(key, data[key]) }));
    }

    get hasExtracted() {
        return this.extracted.length > 0;
    }

    get files() {
        return this.detail
            ? this.detail.files.map((f) => ({
                  ...f,
                  label: f.extension ? `${f.title}.${f.extension}` : f.title,
                  size: sizeLabel(f.size)
              }))
            : [];
    }

    get hasFiles() {
        return this.files.length > 0;
    }

    get body() {
        return this.detail && this.detail.body ? this.detail.body : '(empty)';
    }

    // ------------------------------------------------------------------------- handlers

    handleFilter(event) {
        const name = event.target.dataset.filter;
        this[name] = event.detail.value;
        this.debouncedLoad();
    }

    handleRefresh() {
        this.load();
    }

    handleSelect(event) {
        this.select(event.currentTarget.dataset.id);
    }

    handleRfq(event) {
        this.rfqInput = event.detail.value;
    }

    async handleReprocess() {
        this.busy = true;
        try {
            const message = await reprocess({ emailId: this.selectedId, rfqNumber: this.rfqInput });
            toast(this, 'Reprocessing', message);
            // The job runs in the background; look again shortly.
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this.load(), 4000);
        } catch (e) {
            toastError(this, e, 'Could not reprocess');
        } finally {
            this.busy = false;
        }
    }

    async handleIgnore() {
        this.busy = true;
        try {
            await ignore({ emailId: this.selectedId });
            toast(this, 'E-mail ignored', 'It stays in the log with status Ignored.');
            await this.load();
        } catch (e) {
            toastError(this, e, 'Could not ignore the e-mail');
        } finally {
            this.busy = false;
        }
    }

    handleOpenNotice(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.detail.row.noticeId, actionName: 'view' }
        });
    }

    handleOpenFile(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: event.currentTarget.dataset.id }
        });
    }
}
