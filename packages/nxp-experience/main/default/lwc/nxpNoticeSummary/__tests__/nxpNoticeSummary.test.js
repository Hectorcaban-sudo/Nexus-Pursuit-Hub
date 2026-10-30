import { createElement } from 'lwc';
import NxpNoticeSummary from 'c/nxpNoticeSummary';
import getDetail from '@salesforce/apex/NXP_NoticeController.getDetail';
import loadDescription from '@salesforce/apex/NXP_NoticeController.loadDescription';
import markChecked from '@salesforce/apex/NXP_DocumentController.markChecked';

jest.mock('@salesforce/apex/NXP_NoticeController.getDetail', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_NoticeController.loadDescription', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_DocumentController.markChecked', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_SearchController.followNotice', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('c/nxpPushDialog', () => ({ __esModule: true, default: { open: jest.fn() } }));

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-nxp-notice-summary', () => {
    it('shows countdown, fit breakdown and versions', async () => {
        const due = new Date();
        due.setDate(due.getDate() + 5);
        getDetail.mockResolvedValue({
            notice: {
                Id: 'n1',
                Response_Due__c: due.toISOString(),
                Fit_Score__c: 86,
                AI_Summary__c: 'Summary text',
                Description__c: 'https://api.sam.gov/x'
            },
            breakdown: [{ rule: 'NAICS', weight: 30, points: 30, reason: 'In profile' }],
            versions: [
                {
                    Id: 'v2',
                    Version_Number__c: 2,
                    CreatedDate: new Date().toISOString(),
                    Diff_Summary__c: 'Response Due: a → b'
                }
            ],
            contacts: [],
            pushLogs: [],
            following: false,
            sources: ['SAM_Opportunities']
        });
        const el = createElement('c-nxp-notice-summary', { is: NxpNoticeSummary });
        el.recordId = 'n1';
        document.body.appendChild(el);
        await flush();
        expect(el.shadowRoot.querySelector('.tile-value').textContent).toBe('5');
        expect(el.shadowRoot.querySelector('.tile').className).toContain('tile_warn');
        expect(el.shadowRoot.querySelector('.rule-score').textContent).toBe('30 / 30');
        expect(el.shadowRoot.querySelector('.v-name').textContent).toContain('Amendment 1');
    });
    it('loads a SAM.gov description on request', async () => {
        const base = {
            breakdown: [],
            versions: [],
            contacts: [],
            pushLogs: [],
            following: false,
            sources: ['SAM_Opportunities']
        };
        getDetail.mockResolvedValueOnce({
            ...base,
            notice: { Id: 'n2', Needs_Description__c: true, Description__c: 'https://api.sam.gov/x' }
        });
        getDetail.mockResolvedValueOnce({
            ...base,
            notice: { Id: 'n2', Needs_Description__c: false, Description__c: 'Help desk support' }
        });
        loadDescription.mockResolvedValue('Help desk support');
        const el = createElement('c-nxp-notice-summary', { is: NxpNoticeSummary });
        el.recordId = 'n2';
        document.body.appendChild(el);
        await flush();
        expect(el.shadowRoot.querySelector('details')).toBeNull();
        el.shadowRoot.querySelector('.load-description-button').click();
        await flush();
        await flush();
        expect(loadDescription).toHaveBeenCalledWith({ noticeId: 'n2' });
        expect(el.shadowRoot.querySelector('.load-description-button')).toBeNull();
        expect(el.shadowRoot.querySelector('details')).not.toBeNull();
    });
    it('warns where documents disagree and marks them checked', async () => {
        const base = {
            notice: { Id: 'n3', Response_Due__c: new Date(Date.now() + 9 * 86400000).toISOString() },
            breakdown: [],
            versions: [],
            contacts: [],
            pushLogs: [],
            following: false,
            sources: []
        };
        getDetail.mockResolvedValueOnce({
            ...base,
            checks: [
                {
                    key: 'a1-0',
                    analysisId: 'a1',
                    documentId: '069x',
                    fileName: 'SOW.pdf',
                    field: 'Response due',
                    noticeValue: '2026-11-19',
                    documentValue: '2026-11-12'
                }
            ]
        });
        getDetail.mockResolvedValueOnce({ ...base, checks: [] });
        markChecked.mockResolvedValue(undefined);
        const el = createElement('c-nxp-notice-summary', { is: NxpNoticeSummary });
        el.recordId = 'n3';
        document.body.appendChild(el);
        await flush();
        expect(el.shadowRoot.querySelector('.checks-title').textContent).toContain('1 point');
        expect(el.shadowRoot.querySelector('.check-doc').textContent).toBe('2026-11-12');
        expect(el.shadowRoot.querySelector('.tile-flag')).not.toBeNull();
        el.shadowRoot.querySelector('.mark-checked').click();
        await flush();
        await flush();
        expect(markChecked).toHaveBeenCalledWith({ analysisId: 'a1' });
        expect(el.shadowRoot.querySelector('.checks')).toBeNull();
    });
});
