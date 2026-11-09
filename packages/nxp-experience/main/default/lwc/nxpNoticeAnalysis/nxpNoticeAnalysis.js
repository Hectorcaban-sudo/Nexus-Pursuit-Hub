import { LightningElement, api, wire } from 'lwc';
import getAnalysisKinds from '@salesforce/apex/NXP_NoticeController.getAnalysisKinds';
import analyzeNotice from '@salesforce/apex/NXP_NoticeController.analyzeNotice';
import saveAnalysis from '@salesforce/apex/NXP_NoticeController.saveAnalysis';
import analysisText from '@salesforce/apex/NXP_NoticeController.analysisText';
import { toast, toastError, logUsage } from 'c/nxpUtils';

const SECTION_TONES = {
    strengths: 'tone_good',
    'reasons to bid': 'tone_good',
    'requirements we meet': 'tone_good',
    weaknesses: 'tone_bad',
    'reasons not to bid': 'tone_bad',
    'requirements we may not meet': 'tone_bad',
    opportunities: 'tone_info',
    threats: 'tone_warn'
};

/**
 * Analyze this notice: bid / no-bid brief, opportunity SWOT, incumbent and competitors, gaps,
 * win themes and teaming. Every point shows where it came from; amber tags are assumptions.
 */
export default class NxpNoticeAnalysis extends LightningElement {
    @api noticeId;
    kinds = [];
    selected;
    results = {};
    loading = false;
    saving = false;
    error;

    @wire(getAnalysisKinds)
    wiredKinds({ data, error }) {
        if (data) {
            this.kinds = data;
        } else if (error) {
            this.error = 'Could not load the analysis types.';
        }
    }

    get chips() {
        return this.kinds.map((k) => ({
            ...k,
            className: k.key === this.selected ? 'chip chip_on' : 'chip',
            pressed: k.key === this.selected ? 'true' : 'false'
        }));
    }

    get result() {
        return this.selected ? this.results[this.selected] : null;
    }

    get hasResult() {
        return !!this.result && !this.loading;
    }

    get verdictClass() {
        const v = (this.result.verdict || '').toLowerCase();
        if (v.startsWith('no')) {
            return 'verdict verdict_no';
        }
        if (v.startsWith('lean no')) {
            return 'verdict verdict_lean-no';
        }
        return 'verdict';
    }

    get hasVerdict() {
        return !!this.result.verdict;
    }

    get hasStrategies() {
        return this.result.strategies && this.result.strategies.length > 0;
    }

    get sections() {
        return (this.result.sections || []).map((s, i) => ({
            key: `${i}-${s.title}`,
            title: s.title,
            className: `quad ${SECTION_TONES[(s.title || '').toLowerCase()] || ''}`,
            items: s.items.map((it, j) => ({
                key: `${i}-${j}`,
                text: it.text,
                assumption: it.assumption,
                sources: (it.sources || []).map((src) => ({ key: `${i}-${j}-${src}`, label: src }))
            }))
        }));
    }

    get strategies() {
        return this.result.strategies.map((s) => ({ ...s, key: `s${s.rank}` }));
    }

    get facts() {
        return (this.result.facts || []).map((f, i) => ({ ...f, key: `f${i}` }));
    }

    get loadingText() {
        const k = this.kinds.find((x) => x.key === this.selected);
        return `Writing the ${k ? k.label.toLowerCase() : 'analysis'}…`;
    }

    async handleKind(event) {
        this.selected = event.currentTarget.dataset.key;
        if (!this.results[this.selected]) {
            await this.run();
        }
    }

    async handleRegenerate() {
        await this.run();
    }

    async run() {
        const kind = this.selected;
        this.loading = true;
        this.error = undefined;
        logUsage('Analyze notice');
        try {
            const result = await analyzeNotice({ noticeId: this.noticeId, kind });
            this.results = { ...this.results, [kind]: result };
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'The analysis could not be written.';
        } finally {
            this.loading = false;
        }
    }

    async handleSave() {
        this.saving = true;
        try {
            await saveAnalysis({ noticeId: this.noticeId, analysisJson: JSON.stringify(this.result) });
            toast(
                this,
                'Saved to the notice',
                'Refresh the page to see it under Documents. It goes with the notice when it is pushed.'
            );
        } catch (e) {
            toastError(this, e, 'Not saved');
        } finally {
            this.saving = false;
        }
    }

    async handleCopy() {
        try {
            const text = await analysisText({ noticeId: this.noticeId, analysisJson: JSON.stringify(this.result) });
            await navigator.clipboard.writeText(text);
            toast(this, 'Copied', 'Paste it into an e-mail or a document.');
        } catch (e) {
            toastError(this, e, 'Could not copy');
        }
    }
}
