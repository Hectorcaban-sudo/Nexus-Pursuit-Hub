import { createElement } from 'lwc';
import NxpSearchBuilder from 'c/nxpSearchBuilder';
import previewSearch from '@salesforce/apex/NXP_SearchController.previewSearch';
import saveSearch from '@salesforce/apex/NXP_SearchController.saveSearch';
import getMySearches from '@salesforce/apex/NXP_SearchController.getMySearches';

jest.mock('@salesforce/apex/NXP_SearchController.getMySearches', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SearchController.getSearch', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SearchController.previewSearch', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SearchController.saveSearch', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SearchController.deleteSearch', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SearchController.draftCriteria', () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-nxp-search-builder', () => {
    beforeEach(() => {
        getMySearches.mockResolvedValue([
            { id: 's1', name: 'Mine', frequency: 'Daily', visibility: 'Private', mine: true }
        ]);
        previewSearch.mockResolvedValue({
            count: 3,
            capped: false,
            backtestTotal: 26,
            weekly: [1, 2, 3, 0, 1, 2, 3, 4, 2, 1, 3, 2, 2],
            top: [{ Id: 'n1', Title__c: 'Zero Trust', Fit_Score__c: 86, Agency_Path__c: 'DHS' }]
        });
        saveSearch.mockResolvedValue('s9');
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders the live preview and saves the criteria as JSON', async () => {
        const el = createElement('c-nxp-search-builder', { is: NxpSearchBuilder });
        document.body.appendChild(el);
        await flush();
        expect(el.shadowRoot.querySelector('.count-number').textContent).toBe('3');
        expect(el.shadowRoot.querySelectorAll('.bar').length).toBe(13);

        const naics = Array.from(el.shadowRoot.querySelectorAll('lightning-input')).find(
            (i) => i.dataset.field === 'naics'
        );
        naics.dispatchEvent(new CustomEvent('change', { detail: { value: '541512, 5415*' } }));
        const save = Array.from(el.shadowRoot.querySelectorAll('lightning-button')).find(
            (b) => b.label === 'Save search'
        );
        save.click();
        await flush();
        const input = saveSearch.mock.calls[0][0].input;
        expect(JSON.parse(input.criteriaJson).naics).toEqual(['541512', '5415*']);
        expect(input.frequency).toBe('Daily');
    });
});
