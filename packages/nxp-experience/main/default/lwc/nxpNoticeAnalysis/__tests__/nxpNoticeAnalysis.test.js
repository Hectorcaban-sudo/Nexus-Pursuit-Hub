import { createElement } from 'lwc';
import NxpNoticeAnalysis from 'c/nxpNoticeAnalysis';
import getAnalysisKinds from '@salesforce/apex/NXP_NoticeController.getAnalysisKinds';
import analyzeNotice from '@salesforce/apex/NXP_NoticeController.analyzeNotice';
import saveAnalysis from '@salesforce/apex/NXP_NoticeController.saveAnalysis';

jest.mock(
    '@salesforce/apex/NXP_NoticeController.getAnalysisKinds',
    () => {
        const { createApexTestWireAdapter: create } = require('@salesforce/sfdx-lwc-jest');
        return { default: create(jest.fn()) };
    },
    { virtual: true }
);
jest.mock('@salesforce/apex/NXP_NoticeController.analyzeNotice', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_NoticeController.saveAnalysis', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_NoticeController.analysisText', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_UsageController.logUsage', () => ({ default: jest.fn(() => Promise.resolve()) }), {
    virtual: true
});

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const KINDS = [
    { key: 'brief', label: 'Bid / no-bid brief' },
    { key: 'swot', label: 'Opportunity SWOT' },
    { key: 'competitors', label: 'Incumbent and competitors' }
];
const BRIEF = {
    kind: 'brief',
    label: 'Bid / no-bid brief',
    verdict: 'Lean bid',
    confidence: 'medium',
    summary: 'Pursue if two cleared leads are confirmed.',
    aiUsed: true,
    sections: [
        {
            title: 'Reasons to bid',
            items: [{ text: 'NAICS is in our profile', sources: ['Fit reasons'], assumption: false }]
        },
        { title: 'Reasons not to bid', items: [{ text: 'Staffing is tight', sources: [], assumption: true }] }
    ],
    strategies: [
        {
            rank: 1,
            text: 'Team with a CBP partner',
            pairs: 'Weakness + Threat',
            impact: 'High',
            effort: 'Medium',
            firstStep: 'Shortlist 3'
        }
    ],
    facts: [{ source: 'Notice', text: 'Title: Zero Trust' }]
};

describe('c-nxp-notice-analysis', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    async function mount() {
        const el = createElement('c-nxp-notice-analysis', { is: NxpNoticeAnalysis });
        el.noticeId = 'n1';
        document.body.appendChild(el);
        getAnalysisKinds.emit(KINDS);
        await flush();
        return el;
    }

    it('lists the analysis types', async () => {
        const el = await mount();
        expect(el.shadowRoot.querySelectorAll('.chip')).toHaveLength(3);
        expect(el.shadowRoot.querySelector('.quads')).toBeNull();
    });

    it('writes a brief with sources, assumptions and strategies, and saves it', async () => {
        analyzeNotice.mockResolvedValue(BRIEF);
        saveAnalysis.mockResolvedValue('069000000000001');
        const el = await mount();
        el.shadowRoot.querySelector('.chip').click();
        await flush();
        await flush();
        expect(analyzeNotice).toHaveBeenCalledWith({ noticeId: 'n1', kind: 'brief' });
        expect(el.shadowRoot.querySelector('.chip_on').textContent).toContain('Bid / no-bid brief');
        expect(el.shadowRoot.querySelector('.verdict').textContent).toBe('Lean bid');
        expect(el.shadowRoot.querySelectorAll('.quad')).toHaveLength(2);
        expect(el.shadowRoot.querySelector('.quad.tone_good .tag').textContent).toBe('Fit reasons');
        expect(el.shadowRoot.querySelector('.tag_assumption')).not.toBeNull();
        expect(el.shadowRoot.querySelectorAll('.strategies tbody tr')).toHaveLength(1);

        // Switching back to a written analysis doesn't call the AI again.
        el.shadowRoot.querySelectorAll('.chip')[0].click();
        await flush();
        expect(analyzeNotice).toHaveBeenCalledTimes(1);

        el.shadowRoot.querySelector('.save').click();
        await flush();
        expect(saveAnalysis).toHaveBeenCalledWith({ noticeId: 'n1', analysisJson: JSON.stringify(BRIEF) });
    });

    it('shows the facts and the reason when AI is off', async () => {
        analyzeNotice.mockResolvedValue({
            kind: 'competitors',
            label: 'Incumbent and competitors',
            aiUsed: false,
            note: 'AI is off: these are the facts Nexus has for this notice.',
            sections: [],
            strategies: [],
            facts: [
                { source: 'Incumbent', text: 'Predecessor award 70B held by Vendor A' },
                { source: 'Award history', text: 'Vendor A: 4 awards' }
            ]
        });
        const el = await mount();
        el.shadowRoot.querySelectorAll('.chip')[2].click();
        await flush();
        await flush();
        expect(el.shadowRoot.querySelector('.note').textContent).toContain('AI is off');
        expect(el.shadowRoot.querySelectorAll('.facts li')).toHaveLength(2);
        expect(el.shadowRoot.querySelector('.strategies')).toBeNull();
    });

    it('shows an error when the analysis fails', async () => {
        analyzeNotice.mockRejectedValue({ body: { message: 'The daily AI limit is used up.' } });
        const el = await mount();
        el.shadowRoot.querySelector('.chip').click();
        await flush();
        await flush();
        expect(el.shadowRoot.querySelector('.error').textContent).toContain('daily AI limit');
    });
});
