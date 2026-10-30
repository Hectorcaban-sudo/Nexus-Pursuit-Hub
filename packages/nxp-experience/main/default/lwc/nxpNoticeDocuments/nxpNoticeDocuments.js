import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getDocuments from '@salesforce/apex/NXP_DocumentController.getDocuments';
import analyze from '@salesforce/apex/NXP_DocumentController.analyze';
import { formatDate, toast, toastError } from 'c/nxpUtils';

const STATUS = {
    Complete: { label: 'Read', cls: 'status status_ok' },
    Pending: { label: 'Waiting to be read', cls: 'status' },
    Failed: { label: 'Could not read', cls: 'status status_bad' },
    Unsupported: { label: 'Not a PDF', cls: 'status status_muted' },
    'Too Large': { label: 'Too large', cls: 'status status_muted' },
    'Not read': { label: 'Not read yet', cls: 'status' }
};

function sizeLabel(bytes) {
    if (!bytes) {
        return '';
    }
    return bytes < 1024 * 1024
        ? Math.max(1, Math.round(bytes / 1024)) + ' KB'
        : (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

function list(value) {
    return Array.isArray(value) ? value.map((text, i) => ({ key: 'i' + i, text })) : [];
}

function dateLabel(value) {
    if (!value) {
        return '';
    }
    return value.length > 10 ? formatDate(value, true) : formatDate(value);
}

/** Turns the stored result into the sections the card shows. */
function sections(result) {
    const out = [];
    const add = (key, label, items) => {
        if (items.length) {
            out.push({ key, label, items });
        }
    };
    add('requirements', 'Requirements', list(result.requirements));
    add('deliverables', 'Deliverables', list(result.deliverables));
    add('evaluation', 'Evaluation factors', list(result.evaluationFactors));
    const s = result.submission || {};
    add(
        'submission',
        'Submission',
        [
            s.dueDate ? 'Due ' + dateLabel(s.dueDate) : null,
            s.questionsDue ? 'Questions due ' + dateLabel(s.questionsDue) : null,
            s.pageLimit ? 'Page limit: ' + s.pageLimit : null,
            s.format ? 'Format: ' + s.format : null,
            s.method ? 'How: ' + s.method : null
        ]
            .filter((x) => !!x)
            .map((text, i) => ({ key: 's' + i, text }))
    );
    add(
        'dates',
        'Key dates',
        (Array.isArray(result.keyDates) ? result.keyDates : []).map((d, i) => ({
            key: 'd' + i,
            text: `${d.label}: ${dateLabel(d.date)}`
        }))
    );
    add(
        'terms',
        'Terms',
        [
            result.contractType ? 'Contract type: ' + result.contractType : null,
            result.periodOfPerformance ? 'Period of performance: ' + result.periodOfPerformance : null,
            result.placeOfPerformance ? 'Place of performance: ' + result.placeOfPerformance : null,
            result.clearance ? 'Clearance: ' + result.clearance : null,
            result.setAside ? 'Set-aside: ' + result.setAside : null,
            result.naics ? 'NAICS: ' + result.naics : null
        ]
            .filter((x) => !!x)
            .map((text, i) => ({ key: 't' + i, text }))
    );
    add('risks', 'Risks and watch-outs', list(result.risks));
    return out;
}

export default class NxpNoticeDocuments extends NavigationMixin(LightningElement) {
    @api recordId;
    docs;
    loading = true;
    busyId;
    openId;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.docs = await getDocuments({ noticeId: this.recordId });
            if (!this.openId) {
                const firstRead = this.docs.rows.find((r) => r.status === 'Complete');
                this.openId = firstRead ? firstRead.documentId : undefined;
            }
        } catch (e) {
            toastError(this, e, 'Could not load the documents');
        } finally {
            this.loading = false;
        }
    }

    get enabled() {
        return !!(this.docs && this.docs.enabled);
    }

    get rows() {
        if (!this.docs) {
            return [];
        }
        return this.docs.rows.map((r) => {
            const status = STATUS[r.status] || { label: r.status, cls: 'status' };
            let result = null;
            try {
                result = r.resultJson ? JSON.parse(r.resultJson) : null;
            } catch (e) {
                result = null;
            }
            const readable = r.status !== 'Unsupported' && r.status !== 'Too Large';
            const open = r.documentId === this.openId && !!result;
            return {
                ...r,
                sizeLabel: sizeLabel(r.size),
                statusLabel: status.label,
                statusClass: status.cls,
                hasDetail: !!r.statusDetail,
                analyzedLabel: r.analyzed ? 'Read ' + formatDate(r.analyzed, true) : '',
                canAnalyze: this.enabled && readable,
                analyzeLabel: r.status === 'Complete' || r.status === 'Failed' ? 'Read again' : 'Analyze',
                analyzeDisabled: this.busyId === r.documentId,
                hasResult: !!result,
                open,
                toggleLabel: open ? 'Hide' : 'Show what it says',
                summary: result ? result.summary : null,
                docType: result ? result.documentType : null,
                checks: result ? list(result.checks) : [],
                hasChecks: !!(result && Array.isArray(result.checks) && result.checks.length),
                sections: open ? sections(result) : []
            };
        });
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get emptyMessage() {
        return 'No documents yet. Add the solicitation files (PDF) here, or they arrive with eBuy RFQs.';
    }

    get offNote() {
        return this.docs && !this.docs.enabled
            ? 'Document reading is off, so files are listed but not read. An admin turns it on (AI_Enabled and Document_Analysis_Enabled).'
            : '';
    }

    handleUploaded() {
        toast(this, 'Documents added', this.enabled ? 'PDF files are read in the background.' : '');
        this.load();
    }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.openId = this.openId === id ? undefined : id;
    }

    async handleAnalyze(event) {
        const documentId = event.currentTarget.dataset.id;
        this.busyId = documentId;
        try {
            const message = await analyze({ noticeId: this.recordId, documentId });
            toast(this, 'Reading the document', message);
            await this.load();
        } catch (e) {
            toastError(this, e, 'Could not read the document');
        } finally {
            this.busyId = undefined;
        }
    }

    handleRefresh() {
        this.load();
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
