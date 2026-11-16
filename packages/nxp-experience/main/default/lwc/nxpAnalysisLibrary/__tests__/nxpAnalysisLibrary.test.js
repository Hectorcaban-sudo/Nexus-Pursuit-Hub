import { createElement } from 'lwc';
import NxpAnalysisLibrary from 'c/nxpAnalysisLibrary';
import getLibrary from '@salesforce/apex/NXP_AnalysisPlaybookController.getLibrary';
import getVersions from '@salesforce/apex/NXP_AnalysisPlaybookController.getVersions';
import savePlaybook from '@salesforce/apex/NXP_AnalysisPlaybookController.savePlaybook';
import setStatus from '@salesforce/apex/NXP_AnalysisPlaybookController.setStatus';
import copyPlaybook from '@salesforce/apex/NXP_AnalysisPlaybookController.copyPlaybook';
import testPlaybook from '@salesforce/apex/NXP_AnalysisPlaybookController.testPlaybook';

jest.mock('@salesforce/apex/NXP_AnalysisPlaybookController.getLibrary', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_AnalysisPlaybookController.getVersions', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_AnalysisPlaybookController.savePlaybook', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_AnalysisPlaybookController.setStatus', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_AnalysisPlaybookController.copyPlaybook', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_AnalysisPlaybookController.testPlaybook', () => ({ default: jest.fn() }), {
    virtual: true
});

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const PUBLISHED = {
    id: 'a0P000000000001',
    key: 'blackhat-1a2b3c',
    name: 'BAE Blackhat executive competitive brief',
    category: 'Capture',
    description: 'Competitors and how we beat them.',
    status: 'Published',
    version: 3,
    steps: [
        { title: 'Pick the competitors', text: 'List the incumbent and the top vendors.' },
        { title: 'How we beat them', text: 'One way we win and one risk each.' }
    ],
    sections: ['Competitors', 'How we win'],
    sources: ['Incumbent', 'Award history', 'Price-to-Win'],
    askVerdict: false,
    askStrategies: true,
    timesUsed: 41,
    ownerName: 'Ellen Runno'
};
const DRAFT = {
    ...PUBLISHED,
    id: 'a0P000000000002',
    key: 'bw-1',
    name: 'Black-Hat assessment',
    status: 'Draft',
    version: 0,
    timesUsed: 0
};

function library(canEdit) {
    return {
        canEdit,
        maxSteps: 12,
        sources: ['Notice', 'Documents', 'Incumbent', 'Award history', 'Price-to-Win', 'Company Profile'],
        playbooks: canEdit ? [PUBLISHED, DRAFT] : [PUBLISHED],
        defaults: [
            {
                key: 'brief',
                label: 'Bid / no-bid brief',
                category: 'Capture',
                description: 'Bid or not.',
                sources: ['Notice']
            },
            {
                key: 'competitors',
                label: 'Incumbent and competitors',
                category: 'BD',
                description: 'Who wins.',
                sources: ['Incumbent']
            }
        ]
    };
}

function mount() {
    const el = createElement('c-nxp-analysis-library', { is: NxpAnalysisLibrary });
    document.body.appendChild(el);
    return el;
}

const text = (el) => el.shadowRoot.textContent;
const buttons = (el, cls) => Array.from(el.shadowRoot.querySelectorAll(`lightning-button.${cls}`));

describe('c-nxp-analysis-library', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('lists our playbooks and the Nexus defaults, with filters', async () => {
        getLibrary.mockResolvedValue(library(true));
        const el = mount();
        await flush();
        const t = text(el);
        expect(t).toContain('BAE Blackhat executive competitive brief');
        expect(t).toContain('v3 · Ellen Runno · used 41 times');
        expect(t).toContain('Black-Hat assessment');
        expect(t).toContain('Bid / no-bid brief');
        expect(buttons(el, 'copy-default').length).toBe(2);
        expect(el.shadowRoot.querySelector('lightning-button.new')).not.toBeNull();

        // Drafts only.
        buttons(el, 'filter')
            .find((b) => b.dataset.key === 'drafts')
            .click();
        await flush();
        expect(text(el)).toContain('Black-Hat assessment');
        expect(text(el)).not.toContain('BAE Blackhat');
        expect(text(el)).not.toContain('Bid / no-bid brief');

        // Category and search.
        buttons(el, 'filter')
            .find((b) => b.dataset.key === 'all')
            .click();
        buttons(el, 'category')
            .find((b) => b.dataset.key === 'BD')
            .click();
        await flush();
        expect(text(el)).toContain('Incumbent and competitors');
        expect(text(el)).not.toContain('Bid / no-bid brief');
    });

    it('BD users see published playbooks read-only', async () => {
        getLibrary.mockResolvedValue(library(false));
        getVersions.mockResolvedValue([]);
        const el = mount();
        await flush();
        expect(el.shadowRoot.querySelector('lightning-button.new')).toBeNull();
        expect(buttons(el, 'copy-default').length).toBe(0);
        buttons(el, 'open')[0].click();
        await flush();
        expect(text(el)).toContain('Only Power Users and Nexus admins change playbooks.');
        expect(el.shadowRoot.querySelector('lightning-input.f-name').disabled).toBe(true);
        expect(el.shadowRoot.querySelector('lightning-button.publish')).toBeNull();
    });

    it('creates, edits steps and publishes a new playbook', async () => {
        getLibrary.mockResolvedValue(library(true));
        savePlaybook.mockImplementation(({ definitionJson, publish }) =>
            Promise.resolve({
                ...JSON.parse(definitionJson),
                id: 'a0P000000000009',
                status: publish ? 'Published' : 'Draft',
                version: publish ? 1 : 0
            })
        );
        getVersions.mockResolvedValue([
            { version: 1, note: 'First version', byName: 'Hector', changedOn: '2026-11-14T20:00:00Z' }
        ]);
        const el = mount();
        await flush();
        el.shadowRoot.querySelector('lightning-button.new').click();
        await flush();
        expect(text(el)).toContain('New analysis playbook');

        const name = el.shadowRoot.querySelector('lightning-input.f-name');
        name.dispatchEvent(new CustomEvent('change', { detail: { value: 'Teaming shortlist' } }));
        const stepText = el.shadowRoot.querySelector('lightning-textarea.step-text');
        stepText.dispatchEvent(new CustomEvent('change', { detail: { value: 'List partners with CBP awards.' } }));
        el.shadowRoot.querySelector('lightning-button.add-step').click();
        await flush();
        expect(el.shadowRoot.querySelectorAll('li.step').length).toBe(2);
        el.shadowRoot
            .querySelectorAll('lightning-textarea.step-text')[1]
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'Rank them.' } }));
        // Move step 2 up.
        el.shadowRoot.querySelectorAll('lightning-button-icon[data-dir="up"]')[1].click();
        await flush();
        el.shadowRoot
            .querySelector('lightning-textarea.f-sections')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'Shortlist\n\nWhy each' } }));
        el.shadowRoot
            .querySelector('lightning-input.f-note')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'First version' } }));

        el.shadowRoot.querySelector('lightning-button.publish').click();
        await flush();
        await flush();
        const args = savePlaybook.mock.calls[0][0];
        expect(args.publish).toBe(true);
        expect(args.changeNote).toBe('First version');
        const sent = JSON.parse(args.definitionJson);
        expect(sent.name).toBe('Teaming shortlist');
        expect(sent.steps.map((s) => s.text)).toEqual(['Rank them.', 'List partners with CBP awards.']);
        expect(sent.sections).toEqual(['Shortlist', 'Why each']);
        expect(text(el)).toContain('Published · v1');
        expect(text(el)).toContain('v1 ·');
        expect(el.shadowRoot.querySelector('lightning-button.save-draft')).toBeNull();
        expect(el.shadowRoot.querySelector('lightning-button.unpublish')).not.toBeNull();
    });

    it('copies a Nexus analysis and tests a playbook on a notice', async () => {
        getLibrary.mockResolvedValue(library(true));
        getVersions.mockResolvedValue([]);
        copyPlaybook.mockResolvedValue({ ...DRAFT, id: 'a0P000000000010', name: 'Bid / no-bid brief (our version)' });
        testPlaybook.mockResolvedValue({
            verdict: 'Lean bid',
            confidence: 'medium',
            summary: 'Two competitors.',
            note: 'Test run: not saved.',
            sections: [
                {
                    title: 'Competitors',
                    items: [
                        { text: 'Vendor A holds it', sources: ['Incumbent'], assumption: false },
                        { text: 'Vendor B will bid', sources: [], assumption: true }
                    ]
                }
            ],
            facts: [{ source: 'Incumbent', text: 'Predecessor award PB-PIID-1' }]
        });
        const el = mount();
        await flush();
        buttons(el, 'copy-default')[0].click();
        await flush();
        await flush();
        expect(copyPlaybook).toHaveBeenCalledWith({ source: 'brief' });
        expect(text(el)).toContain('Bid / no-bid brief (our version)');
        expect(el.shadowRoot.querySelector('lightning-button.save-draft')).not.toBeNull();

        const run = el.shadowRoot.querySelector('lightning-button.run-test');
        expect(run.disabled).toBe(true);
        el.shadowRoot
            .querySelector('lightning-record-picker.test-notice')
            .dispatchEvent(new CustomEvent('change', { detail: { recordId: 'a01000000000001' } }));
        await flush();
        el.shadowRoot.querySelector('lightning-button.run-test').click();
        await flush();
        await flush();
        expect(testPlaybook.mock.calls[0][0].noticeId).toBe('a01000000000001');
        const t = text(el);
        expect(t).toContain('Lean bid');
        expect(t).toContain('Vendor A holds it');
        expect(t).toContain('Assumption to check');
        expect(t).toContain('Facts it was given (1)');
    });

    it('unpublishes and retires', async () => {
        getLibrary.mockResolvedValue(library(true));
        getVersions.mockResolvedValue([]);
        setStatus.mockResolvedValue({ ...PUBLISHED, status: 'Draft' });
        const el = mount();
        await flush();
        buttons(el, 'open')[0].click();
        await flush();
        el.shadowRoot.querySelector('lightning-button.unpublish').click();
        await flush();
        await flush();
        expect(setStatus).toHaveBeenCalledWith({ playbookId: PUBLISHED.id, status: 'Draft' });
        expect(text(el)).toContain('Draft (last published v3)');
    });
});
