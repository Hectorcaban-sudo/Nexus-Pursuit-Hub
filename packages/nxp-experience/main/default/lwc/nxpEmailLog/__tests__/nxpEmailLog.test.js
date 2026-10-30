import { createElement } from 'lwc';
import NxpEmailLog from 'c/nxpEmailLog';
import getEmails from '@salesforce/apex/NXP_EmailLogController.getEmails';
import getEmail from '@salesforce/apex/NXP_EmailLogController.getEmail';
import reprocess from '@salesforce/apex/NXP_EmailLogController.reprocess';
import ignore from '@salesforce/apex/NXP_EmailLogController.ignore';

jest.mock('@salesforce/apex/NXP_EmailLogController.getEmails', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_EmailLogController.getEmail', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_EmailLogController.reprocess', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_EmailLogController.ignore', () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const row = (over) => ({
    id: 'a0E000000000001',
    name: 'EM-000001',
    received: '2026-10-29T14:05:00.000Z',
    fromAddress: 'ebuy-sample@gsa.gov',
    fromName: 'GSA eBuy (SAMPLE)',
    subject: '[SAMPLE] eBuy RFQ9990001: Help Desk Modernization',
    rfqNumber: 'RFQ9990001',
    status: 'Ingested',
    statusDetail: 'Notice EBUY:RFQ9990001 created.',
    method: 'Rules',
    attachments: 1,
    vehicleName: 'GSA MAS IT (sample)',
    noticeId: 'a01000000000011',
    noticeKey: 'EBUY:RFQ9990001',
    noticeTitle: 'Help Desk Modernization',
    ...over
});

const LOG = {
    rows: [
        row(),
        row({
            id: 'a0E000000000002',
            name: 'EM-000002',
            subject: 'Quote request',
            rfqNumber: null,
            status: 'Needs Review',
            statusDetail:
                'Enter the RFQ number and click Reprocess.\nNo RFQ number (RFQ followed by digits) in the subject or body.',
            noticeId: null,
            noticeKey: null
        })
    ],
    counts: [
        { status: 'Received', count: 0 },
        { status: 'Ingested', count: 1 },
        { status: 'Needs Review', count: 1 },
        { status: 'Rejected', count: 1 },
        { status: 'Failed', count: 0 },
        { status: 'Ignored', count: 0 }
    ],
    last30: 3,
    allowedSenders: 'gsa.gov',
    aiEnabled: false
};

const detail = (r) => ({
    row: r,
    toAddresses: 'ebuy@yourcompany.example',
    body: 'RFQ ID: RFQ9990001\nTitle: Help Desk Modernization',
    extractedJson: JSON.stringify({
        rfqNumber: 'RFQ9990001',
        title: 'Help Desk Modernization',
        sins: ['54151S'],
        naics: '541513',
        evaluationFactors: [],
        notes: []
    }),
    processed: '2026-10-29T14:05:10.000Z',
    files: [{ documentId: '069000000000001', title: 'Statement of Work', extension: 'pdf', size: 245760 }]
});

function mount() {
    const el = createElement('c-nxp-email-log', { is: NxpEmailLog });
    document.body.appendChild(el);
    return el;
}

describe('c-nxp-email-log', () => {
    beforeEach(() => {
        getEmails.mockResolvedValue(LOG);
        getEmail.mockImplementation(({ emailId }) => Promise.resolve(detail(LOG.rows.find((r) => r.id === emailId))));
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('lists e-mails, totals, and opens the first one', async () => {
        const el = mount();
        await flush();
        await flush();

        const kpis = [...el.shadowRoot.querySelectorAll('.kpi')].map((k) => k.textContent);
        expect(kpis[0]).toContain('3');
        expect(kpis[3]).toContain('Rejected or failed');
        expect(el.shadowRoot.querySelectorAll('.row').length).toBe(2);
        expect(el.shadowRoot.querySelector('.row_selected').dataset.id).toBe('a0E000000000001');

        const panel = el.shadowRoot.querySelector('.detail');
        expect(panel.textContent).toContain('EBUY:RFQ9990001');
        expect(panel.textContent).toContain('Statement of Work.pdf');
        expect(panel.textContent).toContain('240 KB');
        const labels = [...panel.querySelectorAll('.pair dt')].map((n) => n.textContent);
        expect(labels).toEqual(['RFQ number', 'Title', 'SINs', 'NAICS']);
        expect(panel.querySelector('.body').textContent).toContain('RFQ ID: RFQ9990001');
        expect(panel.querySelector('.ignore')).toBeNull();
    });

    it('reprocesses a needs-review e-mail with a typed RFQ number', async () => {
        reprocess.mockResolvedValue('Reprocessing.');
        const el = mount();
        await flush();
        await flush();

        el.shadowRoot.querySelectorAll('.row')[1].click();
        await flush();
        await flush();
        expect(el.shadowRoot.querySelectorAll('.detail-line').length).toBe(2);
        const input = el.shadowRoot.querySelector('.rfq');
        input.dispatchEvent(new CustomEvent('change', { detail: { value: 'RFQ2468024' } }));
        el.shadowRoot.querySelector('.reprocess').click();
        await flush();
        expect(reprocess).toHaveBeenCalledWith({ emailId: 'a0E000000000002', rfqNumber: 'RFQ2468024' });
    });

    it('ignores an e-mail', async () => {
        ignore.mockResolvedValue(undefined);
        const el = mount();
        await flush();
        await flush();
        el.shadowRoot.querySelectorAll('.row')[1].click();
        await flush();
        await flush();
        el.shadowRoot.querySelector('.ignore').click();
        await flush();
        expect(ignore).toHaveBeenCalledWith({ emailId: 'a0E000000000002' });
        expect(getEmails).toHaveBeenCalledTimes(2);
    });

    it('explains an empty log', async () => {
        getEmails.mockResolvedValue({ ...LOG, rows: [], last30: 0 });
        const el = mount();
        await flush();
        expect(el.shadowRoot.querySelector('.empty').textContent).toContain('NXP_Ebuy_Inbox');
        expect(getEmail).not.toHaveBeenCalled();
    });
});
