import { LightningElement } from 'lwc';
import getLibrary from '@salesforce/apex/NXP_AnalysisPlaybookController.getLibrary';
import getVersions from '@salesforce/apex/NXP_AnalysisPlaybookController.getVersions';
import savePlaybook from '@salesforce/apex/NXP_AnalysisPlaybookController.savePlaybook';
import setStatus from '@salesforce/apex/NXP_AnalysisPlaybookController.setStatus';
import copyPlaybook from '@salesforce/apex/NXP_AnalysisPlaybookController.copyPlaybook';
import testPlaybook from '@salesforce/apex/NXP_AnalysisPlaybookController.testPlaybook';
import { formatDate, toast, toastError } from 'c/nxpUtils';

const CATEGORIES = ['BD', 'Capture', 'Proposal'];

const SOURCE_HELP = {
    Notice: 'Title, buyer, dates, set-aside, NAICS, description, AI summary',
    Documents: 'What the Document Reader extracted from the notice files',
    'Fit reasons': 'The fit score and why',
    Incumbent: 'The incumbent and the predecessor award',
    'Award history': 'Vendors with the most awards at this agency and NAICS; awards ending soon',
    'Price-to-Win': 'Per-year award range, predecessor rate, incumbent hold, similar-awards estimate',
    'Vendor profiles': 'For the incumbent and the top 5 vendors here: where else they win',
    'Company Profile': 'Our NAICS, capabilities, set-asides and target agencies',
    'Contract vehicles': 'Vehicles we hold',
    'Version history': 'Amendments and what changed'
};

function blank() {
    return {
        id: null,
        key: null,
        name: '',
        category: 'Capture',
        description: '',
        status: 'Draft',
        version: 0,
        steps: [{ title: '', text: '' }],
        sections: [],
        sources: ['Notice', 'Documents', 'Incumbent', 'Award history', 'Company Profile'],
        askVerdict: false,
        askStrategies: false
    };
}

function clone(d) {
    return JSON.parse(JSON.stringify(d));
}

export default class NxpAnalysisLibrary extends LightningElement {
    lib;
    loading = true;
    error;
    view = 'library';
    search = '';
    filter = 'all';
    category = null;

    draft;
    sectionsText = '';
    changeNote = '';
    saving = false;
    versions = [];
    testNoticeId;
    testing = false;
    testResult;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.lib = await getLibrary();
            this.error = undefined;
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'Could not load the playbooks.';
        } finally {
            this.loading = false;
        }
    }

    // ------------------------------------------------------------------ library

    get isLibrary() {
        return this.view === 'library';
    }
    get isEditor() {
        return this.view === 'editor';
    }
    get canEdit() {
        return !!(this.lib && this.lib.canEdit);
    }

    handleSearch(event) {
        this.search = (event.target.value || '').toLowerCase();
    }

    get filters() {
        const lib = this.lib || { playbooks: [], defaults: [] };
        const drafts = lib.playbooks.filter((p) => p.status === 'Draft').length;
        const list = [
            { key: 'all', label: `All ${lib.playbooks.length + lib.defaults.length}` },
            { key: 'org', label: `Our organization ${lib.playbooks.filter((p) => p.status !== 'Draft').length}` },
            { key: 'defaults', label: `Nexus defaults ${lib.defaults.length}` }
        ];
        if (this.canEdit) {
            list.push({ key: 'drafts', label: `Drafts ${drafts}` });
        }
        return list.map((f) => ({ ...f, variant: f.key === this.filter ? 'brand' : 'neutral' }));
    }

    get categoryFilters() {
        return CATEGORIES.map((c) => ({ key: c, label: c, variant: c === this.category ? 'brand' : 'neutral' }));
    }

    handleFilter(event) {
        this.filter = event.currentTarget.dataset.key;
    }

    handleCategory(event) {
        const c = event.currentTarget.dataset.key;
        this.category = this.category === c ? null : c;
    }

    matches(item) {
        if (this.category && item.category !== this.category) {
            return false;
        }
        if (!this.search) {
            return true;
        }
        return `${item.name || item.label} ${item.description || ''}`.toLowerCase().includes(this.search);
    }

    sourceChips(sources) {
        return (sources || []).map((s) => ({ key: s, label: s }));
    }

    inFilter(p) {
        if (this.filter === 'drafts') {
            return p.status === 'Draft';
        }
        if (this.filter === 'org') {
            return p.status !== 'Draft';
        }
        return true;
    }

    get orgCards() {
        if (!this.lib || this.filter === 'defaults') {
            return [];
        }
        return this.lib.playbooks
            .filter((p) => this.inFilter(p))
            .filter((p) => this.matches(p))
            .map((p) => ({
                ...p,
                headClass: 'card-head head_' + (p.category || 'Capture').toLowerCase(),
                statusClass: 'badge badge_' + (p.status || 'Draft').toLowerCase(),
                sourceList: this.sourceChips(p.sources),
                meta: [
                    p.version ? 'v' + p.version : 'not published',
                    p.ownerName,
                    p.timesUsed ? `used ${p.timesUsed} ${p.timesUsed === 1 ? 'time' : 'times'}` : null
                ]
                    .filter((x) => !!x)
                    .join(' · ')
            }));
    }

    get hasOrgCards() {
        return this.orgCards.length > 0;
    }

    get showOrg() {
        return this.filter !== 'defaults';
    }

    get defaultCards() {
        if (!this.lib || this.filter === 'org' || this.filter === 'drafts') {
            return [];
        }
        return this.lib.defaults
            .filter((k) => this.matches(k))
            .map((k) => ({
                ...k,
                headClass: 'card-head head_' + (k.category || 'Capture').toLowerCase(),
                sourceList: this.sourceChips(k.sources)
            }));
    }

    get hasDefaultCards() {
        return this.defaultCards.length > 0;
    }

    get orgEmptyText() {
        return this.canEdit
            ? 'None yet. Click New playbook, or Copy a Nexus analysis to make your own version.'
            : 'None published yet. Power Users and admins create them here.';
    }

    handleNew() {
        this.openEditor(blank());
    }

    handleOpen(event) {
        const id = event.currentTarget.dataset.id;
        const p = this.lib.playbooks.find((x) => x.id === id);
        if (p) {
            this.openEditor(clone(p));
        }
    }

    async handleCopy(event) {
        const source = event.currentTarget.dataset.source;
        try {
            const d = await copyPlaybook({ source });
            toast(this, 'Copied', `"${d.name}" is a draft. Edit it, test it, then publish.`);
            await this.load();
            this.openEditor(d);
        } catch (e) {
            toastError(this, e, 'Could not copy');
        }
    }

    // ------------------------------------------------------------------ editor

    async openEditor(d) {
        this.draft = clone(d);
        if (!this.draft.steps || !this.draft.steps.length) {
            this.draft.steps = [{ title: '', text: '' }];
        }
        this.sectionsText = (this.draft.sections || []).join('\n');
        this.changeNote = '';
        this.testResult = undefined;
        this.versions = [];
        this.view = 'editor';
        if (this.draft.id) {
            try {
                this.versions = (await getVersions({ playbookId: this.draft.id })) || [];
            } catch (e) {
                this.versions = [];
            }
        }
    }

    handleBack() {
        this.view = 'library';
        this.draft = undefined;
        this.load();
    }

    get readOnly() {
        return !this.canEdit;
    }
    get isPublished() {
        return this.draft && this.draft.status === 'Published';
    }
    get isSaved() {
        return !!(this.draft && this.draft.id);
    }
    get canSaveDraft() {
        return this.canEdit && !this.isPublished;
    }
    get canUnpublish() {
        return this.canEdit && this.isPublished;
    }
    get canRetire() {
        return this.canEdit && this.isSaved && this.draft.status !== 'Retired';
    }
    get publishLabel() {
        return `Publish v${(this.draft.version || 0) + 1}`;
    }
    get editorTitle() {
        return this.draft.id ? this.draft.name : 'New analysis playbook';
    }
    get statusText() {
        const d = this.draft;
        if (d.status === 'Published') {
            return `Published · v${d.version}`;
        }
        if (d.status === 'Retired') {
            return 'Retired';
        }
        return d.version ? `Draft (last published v${d.version})` : 'Draft';
    }
    get statusClass() {
        return 'badge badge_' + (this.draft.status || 'Draft').toLowerCase();
    }
    get categoryOptions() {
        return CATEGORIES.map((c) => ({ label: c, value: c }));
    }
    get maxSteps() {
        return (this.lib && this.lib.maxSteps) || 12;
    }
    get canAddStep() {
        return this.canEdit && this.draft.steps.length < this.maxSteps;
    }

    get stepRows() {
        const n = this.draft.steps.length;
        return this.draft.steps.map((s, i) => ({
            ...s,
            index: i,
            key: 'step' + i,
            number: i + 1,
            first: i === 0,
            last: i === n - 1,
            only: n === 1
        }));
    }

    get sourceOptions() {
        return ((this.lib && this.lib.sources) || []).map((s) => ({
            label: SOURCE_HELP[s] ? `${s}: ${SOURCE_HELP[s]}` : s,
            value: s
        }));
    }

    handleField(event) {
        const field = event.target.dataset.field;
        const value =
            event.target.type === 'toggle' || event.target.type === 'checkbox'
                ? event.target.checked
                : event.detail.value;
        this.draft = { ...this.draft, [field]: value };
    }

    handleSources(event) {
        this.draft = { ...this.draft, sources: event.detail.value };
    }

    handleSections(event) {
        this.sectionsText = event.detail.value || '';
    }

    handleChangeNote(event) {
        this.changeNote = event.detail.value || '';
    }

    handleStepField(event) {
        const i = Number(event.target.dataset.index);
        const field = event.target.dataset.field;
        const steps = this.draft.steps.map((s, n) => (n === i ? { ...s, [field]: event.detail.value } : s));
        this.draft = { ...this.draft, steps };
    }

    handleAddStep() {
        this.draft = { ...this.draft, steps: [...this.draft.steps, { title: '', text: '' }] };
    }

    handleMoveStep(event) {
        const i = Number(event.currentTarget.dataset.index);
        const to = event.currentTarget.dataset.dir === 'up' ? i - 1 : i + 1;
        const steps = [...this.draft.steps];
        [steps[i], steps[to]] = [steps[to], steps[i]];
        this.draft = { ...this.draft, steps };
    }

    handleRemoveStep(event) {
        const i = Number(event.currentTarget.dataset.index);
        this.draft = { ...this.draft, steps: this.draft.steps.filter((s, n) => n !== i) };
    }

    definitionJson() {
        const sections = this.sectionsText
            .split('\n')
            .map((s) => s.trim())
            .filter((s) => !!s);
        return JSON.stringify({ ...this.draft, sections });
    }

    async save(publish) {
        this.saving = true;
        try {
            const saved = await savePlaybook({
                definitionJson: this.definitionJson(),
                publish,
                changeNote: publish ? this.changeNote : null
            });
            toast(
                this,
                publish ? 'Published' : 'Saved',
                publish
                    ? `"${saved.name}" v${saved.version} now shows under Analyze this notice for everyone.`
                    : `"${saved.name}" is saved as a draft.`
            );
            await this.openEditor(saved);
            this.lib = await getLibrary();
        } catch (e) {
            toastError(this, e, publish ? 'Could not publish' : 'Could not save');
        } finally {
            this.saving = false;
        }
    }

    handleSaveDraft() {
        this.save(false);
    }

    handlePublish() {
        this.save(true);
    }

    async changeStatus(status, done) {
        this.saving = true;
        try {
            const d = await setStatus({ playbookId: this.draft.id, status });
            toast(this, done, `"${d.name}"`);
            await this.openEditor(d);
            this.lib = await getLibrary();
        } catch (e) {
            toastError(this, e, 'Could not change the status');
        } finally {
            this.saving = false;
        }
    }

    handleUnpublish() {
        this.changeStatus('Draft', 'Unpublished: it is a draft again');
    }

    handleRetire() {
        this.changeStatus('Retired', 'Retired: hidden from notices');
    }

    // ------------------------------------------------------------------ test on a notice

    handleTestNotice(event) {
        this.testNoticeId = event.detail.recordId;
    }

    get testDisabled() {
        return !this.testNoticeId || this.testing;
    }

    async handleTest() {
        this.testing = true;
        this.testResult = undefined;
        try {
            this.testResult = await testPlaybook({
                noticeId: this.testNoticeId,
                definitionJson: this.definitionJson()
            });
        } catch (e) {
            toastError(this, e, 'Could not test the playbook');
        } finally {
            this.testing = false;
        }
    }

    get testSections() {
        return ((this.testResult && this.testResult.sections) || []).map((s, i) => ({
            key: 's' + i,
            title: s.title,
            items: s.items.map((it, j) => ({
                key: `s${i}i${j}`,
                text: it.text,
                tag: it.assumption ? 'Assumption to check' : it.sources.join(', '),
                tagClass: it.assumption ? 'tag tag_warn' : 'tag'
            }))
        }));
    }

    get testFacts() {
        return ((this.testResult && this.testResult.facts) || []).map((f, i) => ({
            key: 'f' + i,
            source: f.source,
            text: f.text
        }));
    }

    get testFactsLabel() {
        const n = this.testFacts.length;
        return `Facts it was given (${n})`;
    }

    get versionRows() {
        return this.versions.map((v, i) => ({
            key: 'v' + i,
            text: `v${v.version} · ${formatDate(v.changedOn)} · ${v.byName || ''}${v.note ? ' · ' + v.note : ''}`
        }));
    }

    get hasVersions() {
        return this.versionRows.length > 0;
    }
}
