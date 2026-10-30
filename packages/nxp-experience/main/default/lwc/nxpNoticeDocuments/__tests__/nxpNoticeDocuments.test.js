import { createElement } from 'lwc';
import NxpNoticeDocuments from 'c/nxpNoticeDocuments';
import getDocuments from '@salesforce/apex/NXP_DocumentController.getDocuments';
import analyze from '@salesforce/apex/NXP_DocumentController.analyze';
import requestSamFiles from '@salesforce/apex/NXP_DocumentController.requestSamFiles';

jest.mock('@salesforce/apex/NXP_DocumentController.getDocuments', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_DocumentController.analyze', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_DocumentController.requestSamFiles', () => ({ default: jest.fn() }), {
    virtual: true
});

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const RESULT = {
    summary: 'Tier 1 and tier 2 help desk support for VA.',
    documentType: 'SOW',
    requirements: ['24x7 tier 1 coverage', 'Knowledge base migration'],
    evaluationFactors: ['Technical approach', 'Price'],
    submission: { dueDate: '2026-11-12T14:00:00-05:00', pageLimit: '10 pages' },
    keyDates: [{ label: 'Questions due', date: '2026-11-05' }],
    clearance: 'Public Trust',
    risks: ['Short response window'],
    checks: ['The document says responses are due 2026-11-12; the notice says 2026-11-19.']
};

const DOCS = {
    enabled: true,
    rows: [
        {
            documentId: '069000000000001',
            fileName: 'Statement of Work.pdf',
            size: 245760,
            status: 'Complete',
            analyzed: '2026-10-29T14:05:10.000Z',
            resultJson: JSON.stringify(RESULT)
        },
        {
            documentId: '069000000000002',
            fileName: 'Pricing.xlsx',
            size: 10240,
            status: 'Unsupported',
            statusDetail: 'Only PDF files can be read.'
        },
        { documentId: '069000000000003', fileName: 'Amendment 1.pdf', size: 20480, status: 'Not read' }
    ]
};

function mount() {
    const el = createElement('c-nxp-notice-documents', { is: NxpNoticeDocuments });
    el.recordId = 'a01000000000011';
    document.body.appendChild(el);
    return el;
}

describe('c-nxp-notice-documents', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('lists files, opens the first read one and shows checks against the notice', async () => {
        getDocuments.mockResolvedValue(DOCS);
        const el = mount();
        await flush();

        expect(getDocuments).toHaveBeenCalledWith({ noticeId: 'a01000000000011' });
        const docs = el.shadowRoot.querySelectorAll('.doc');
        expect(docs.length).toBe(3);
        expect(docs[0].querySelector('.status').textContent).toBe('Read');
        expect(docs[0].querySelector('.check').textContent).toContain('responses are due');
        const titles = [...docs[0].querySelectorAll('.section-title')].map((n) => n.textContent);
        expect(titles).toEqual([
            'Requirements',
            'Evaluation factors',
            'Submission',
            'Key dates',
            'Terms',
            'Risks and watch-outs'
        ]);
        expect(docs[0].textContent).toContain('Clearance: Public Trust');
        expect(docs[1].querySelector('.analyze')).toBeNull();
        expect(docs[2].querySelector('.analyze').label).toBe('Analyze');
        expect(el.shadowRoot.querySelector('.off')).toBeNull();
    });

    it('analyzes a file and reloads', async () => {
        getDocuments.mockResolvedValue(DOCS);
        analyze.mockResolvedValue('Reading the document.');
        const el = mount();
        await flush();

        el.shadowRoot.querySelectorAll('.doc')[2].querySelector('.analyze').click();
        await flush();
        expect(analyze).toHaveBeenCalledWith({ noticeId: 'a01000000000011', documentId: '069000000000003' });
        expect(getDocuments).toHaveBeenCalledTimes(2);
    });

    it('hides a result and explains when reading is off', async () => {
        getDocuments.mockResolvedValue({ ...DOCS, enabled: false });
        const el = mount();
        await flush();

        expect(el.shadowRoot.querySelector('.off').textContent).toContain('Document reading is off');
        expect(el.shadowRoot.querySelector('.analyze')).toBeNull();
        el.shadowRoot.querySelector('.toggle').click();
        await flush();
        expect(el.shadowRoot.querySelectorAll('.section').length).toBe(0);
    });

    it('shows an empty state', async () => {
        getDocuments.mockResolvedValue({ enabled: true, rows: [] });
        const el = mount();
        await flush();
        expect(el.shadowRoot.querySelector('.empty').textContent).toContain('No documents yet');
    });
    it('offers to get the SAM.gov files', async () => {
        getDocuments.mockResolvedValue({ ...DOCS, samFiles: 3, samFilesPending: true, samFilesStatus: null });
        requestSamFiles.mockResolvedValue('Getting the files from SAM.gov.');
        const el = mount();
        await flush();
        expect(el.shadowRoot.querySelector('.sam-text').textContent).toContain('SAM.gov lists 3 files.');
        el.shadowRoot.querySelector('.get-sam-files').click();
        await flush();
        expect(requestSamFiles).toHaveBeenCalledWith({ noticeId: 'a01000000000011' });
        expect(getDocuments).toHaveBeenCalledTimes(2);
    });
});
