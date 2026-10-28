import { createElement } from 'lwc';
import NxpNoticeSummary from 'c/nxpNoticeSummary';
import getDetail from '@salesforce/apex/NXP_NoticeController.getDetail';

jest.mock('@salesforce/apex/NXP_NoticeController.getDetail', () => ({ default: jest.fn() }), { virtual: true });
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
});
