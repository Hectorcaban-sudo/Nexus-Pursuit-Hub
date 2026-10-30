import NxpFindSimilar from 'c/nxpFindSimilar';
import { createElement } from 'lwc';
import draftSimilar from '@salesforce/apex/NXP_SearchController.draftSimilar';
import previewSearch from '@salesforce/apex/NXP_SearchController.previewSearch';
import saveSearch from '@salesforce/apex/NXP_SearchController.saveSearch';

jest.mock('@salesforce/apex/NXP_SearchController.draftSimilar', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SearchController.previewSearch', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SearchController.saveSearch', () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const DRAFT = {
    noticeId: 'n1',
    noticeTitle: 'Zero Trust Architecture Engineering Support',
    name: 'Like: Zero Trust Architecture Engineering Support',
    keywords: '"zero trust" OR ICAM',
    keywordsSource: 'AI',
    groups: [
        {
            key: 'buyer',
            label: 'Buyer',
            multiple: false,
            choices: [
                { label: 'Customs and Border Protection', value: 'Customs and Border Protection', selected: true },
                { label: 'All of Homeland Security', value: 'Homeland Security', selected: false }
            ]
        },
        {
            key: 'naics',
            label: 'NAICS',
            multiple: false,
            choices: [
                { label: '541512 only', value: '541512', selected: false },
                { label: '5415* (family)', value: '5415*', selected: true }
            ]
        },
        {
            key: 'noticeTypes',
            label: 'Notice type',
            multiple: true,
            choices: [
                { label: 'Solicitation', value: 'Solicitation', selected: true },
                { label: 'RFI', value: 'RFI', selected: false }
            ]
        }
    ]
};

function mount() {
    const el = createElement('c-nxp-find-similar', { is: NxpFindSimilar });
    el.noticeId = 'n1';
    el.closed = jest.fn();
    el.addEventListener('modalclose', (e) => el.closed(e.detail));
    document.body.appendChild(el);
    return el;
}

describe('c-nxp-find-similar', () => {
    beforeEach(() => {
        draftSimilar.mockResolvedValue(DRAFT);
        previewSearch.mockResolvedValue({
            count: 14,
            capped: false,
            backtestTotal: 39,
            weekly: [],
            top: [
                { Id: 'n1', Title__c: 'Self', Fit_Score__c: 86 },
                { Id: 'n2', Title__c: 'ICAM Modernization', Fit_Score__c: 82, Notice_Type__c: 'Pre-solicitation' }
            ]
        });
        saveSearch.mockResolvedValue('s1');
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('previews the criteria built from the notice and leaves the notice itself out', async () => {
        const el = mount();
        await flush();
        await flush();
        const criteria = JSON.parse(previewSearch.mock.calls[0][0].criteriaJson);
        expect(criteria).toEqual({
            agencies: ['Customs and Border Protection'],
            naics: ['5415*'],
            noticeTypes: ['Solicitation'],
            keywords: '"zero trust" OR ICAM'
        });
        expect(el.shadowRoot.querySelector('.count').textContent).toBe('14');
        const titles = Array.from(el.shadowRoot.querySelectorAll('.top-title')).map((t) => t.textContent);
        expect(titles).toEqual(['ICAM Modernization']);
        expect(el.shadowRoot.querySelector('.keywords-note').textContent).toContain('AI picked');
    });

    it('widens the buyer and saves a private search', async () => {
        const el = mount();
        await flush();
        await flush();
        const buyer = el.shadowRoot.querySelector('lightning-radio-group[data-key="buyer"]');
        buyer.dispatchEvent(new CustomEvent('change', { detail: { value: 'Homeland Security' } }));
        el.shadowRoot.querySelector('.save').click();
        await flush();
        const input = saveSearch.mock.calls[0][0].input;
        expect(JSON.parse(input.criteriaJson).agencies).toEqual(['Homeland Security']);
        expect(input.name).toBe('Like: Zero Trust Architecture Engineering Support');
        expect(input.frequency).toBe('Daily');
        expect(input.visibility).toBe('Private');
        expect(el.closed).toHaveBeenCalledWith({
            action: 'saved',
            searchId: 's1',
            name: 'Like: Zero Trust Architecture Engineering Support'
        });
    });

    it('hands the criteria to My Searches', async () => {
        const el = mount();
        await flush();
        await flush();
        const naics = el.shadowRoot.querySelector('lightning-radio-group[data-key="naics"]');
        naics.dispatchEvent(new CustomEvent('change', { detail: { value: '__any' } }));
        el.shadowRoot.querySelector('.edit').click();
        const result = el.closed.mock.calls[0][0];
        expect(result.action).toBe('edit');
        expect(JSON.parse(result.criteriaJson).naics).toBeUndefined();
    });
});
