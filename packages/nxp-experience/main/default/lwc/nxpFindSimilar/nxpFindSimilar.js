import { api, track } from 'lwc';
import LightningModal from 'lightning/modal';
import draftSimilar from '@salesforce/apex/NXP_SearchController.draftSimilar';
import previewSearch from '@salesforce/apex/NXP_SearchController.previewSearch';
import saveSearch from '@salesforce/apex/NXP_SearchController.saveSearch';
import { debounce, dueLabel, reduceErrors } from 'c/nxpUtils';

const ANY = '__any';
const FREQUENCIES = ['Daily', 'Weekly', 'Real Time', 'None'].map((v) => ({ label: v, value: v }));

/**
 * Find similar: a saved search started from one notice. Open with
 *   const result = await NxpFindSimilar.open({ noticeId, size: 'large', label: 'Find notices like this' });
 * Resolves to { action: 'saved', searchId, name }, { action: 'edit', criteriaJson, name } or undefined.
 */
export default class NxpFindSimilar extends LightningModal {
    @api noticeId;

    draft;
    @track picks = {};
    keywords = '';
    name = '';
    frequency = 'Daily';
    preview;
    previewError;
    error;
    loading = true;
    previewing = false;
    saving = false;
    frequencyOptions = FREQUENCIES;

    schedulePreview = debounce(() => this.runPreview(), 500);

    async connectedCallback() {
        try {
            const d = await draftSimilar({ noticeId: this.noticeId });
            this.draft = d;
            this.name = d.name;
            this.keywords = d.keywords || '';
            const picks = {};
            d.groups.forEach((g) => {
                const chosen = g.choices.filter((c) => c.selected).map((c) => c.value);
                picks[g.key] = g.multiple ? chosen : chosen[0] || ANY;
            });
            this.picks = picks;
            await this.runPreview();
        } catch (e) {
            this.error = reduceErrors(e).join(', ');
        } finally {
            this.loading = false;
        }
    }

    get groups() {
        if (!this.draft) {
            return [];
        }
        return this.draft.groups.map((g) => {
            const options = g.choices.map((c) => ({ label: c.label, value: c.value }));
            return {
                ...g,
                options: g.multiple ? options : [...options, { label: 'Any', value: ANY }],
                value: this.picks[g.key],
                single: !g.multiple
            };
        });
    }

    get keywordsNote() {
        if (!this.draft) {
            return '';
        }
        if (this.draft.note) {
            return this.draft.note;
        }
        if (this.draft.keywordsSource === 'AI') {
            return 'AI picked these from the title and description. Check and edit them.';
        }
        if (this.draft.keywordsSource === 'Title') {
            return 'Taken from the title. Add synonyms with OR, for example ("zero trust" OR ZTA).';
        }
        return 'No keywords: the codes and buyer decide.';
    }

    /** Criteria JSON in the shape NXP_SearchCriteria expects. */
    get criteriaJson() {
        const c = {};
        const one = (key) => (this.picks[key] && this.picks[key] !== ANY ? [this.picks[key]] : undefined);
        c.agencies = one('buyer');
        c.naics = one('naics');
        c.psc = one('psc');
        c.setAsides = one('setAside');
        const types = this.picks.noticeTypes || [];
        c.noticeTypes = types.length ? types : undefined;
        c.keywords = this.keywords && this.keywords.trim() ? this.keywords.trim() : undefined;
        return JSON.stringify(c);
    }

    async runPreview() {
        this.previewing = true;
        this.previewError = null;
        try {
            this.preview = await previewSearch({ criteriaJson: this.criteriaJson });
        } catch (e) {
            this.preview = undefined;
            this.previewError = reduceErrors(e).join(', ');
        } finally {
            this.previewing = false;
        }
    }

    get countLabel() {
        if (!this.preview) {
            return '–';
        }
        return this.preview.capped ? `${this.preview.count}+` : `${this.preview.count}`;
    }

    get weeklyLabel() {
        return this.preview ? `about ${Math.round(this.preview.backtestTotal / 13)} a week over the last 13 weeks` : '';
    }

    get topRows() {
        if (!this.preview) {
            return [];
        }
        return this.preview.top
            .filter((n) => n.Id !== this.noticeId)
            .slice(0, 5)
            .map((n) => ({
                id: n.Id,
                title: n.Title__c || n.Name,
                fit: n.Fit_Score__c,
                meta: [n.Agency_Path__c, n.Notice_Type__c, dueLabel(n.Response_Due__c)].filter((x) => !!x).join(' · ')
            }));
    }

    get hasTop() {
        return this.topRows.length > 0;
    }

    get disableSave() {
        return this.loading || this.saving || !!this.previewError || !this.name;
    }

    handlePick(event) {
        const key = event.target.dataset.key;
        this.picks = { ...this.picks, [key]: event.detail.value };
        this.schedulePreview();
    }

    handleKeywords(event) {
        this.keywords = event.detail.value;
        this.schedulePreview();
    }

    handleName(event) {
        this.name = event.detail.value;
    }

    handleFrequency(event) {
        this.frequency = event.detail.value;
    }

    handleEdit() {
        this.close({ action: 'edit', criteriaJson: this.criteriaJson, name: this.name });
    }

    async handleSave() {
        this.saving = true;
        try {
            const searchId = await saveSearch({
                input: {
                    name: this.name,
                    criteriaJson: this.criteriaJson,
                    frequency: this.frequency,
                    channels: ['Email', 'Salesforce'],
                    visibility: 'Private',
                    alertOnChanges: true,
                    autoPush: 'Off',
                    active: true
                }
            });
            this.close({ action: 'saved', searchId, name: this.name });
        } catch (e) {
            this.error = reduceErrors(e).join(', ');
        } finally {
            this.saving = false;
        }
    }

    handleCancel() {
        this.close();
    }
}
