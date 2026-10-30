import { createElement } from 'lwc';
import NxpSearchBuilder from 'c/nxpSearchBuilder';
import previewSearch from '@salesforce/apex/NXP_SearchController.previewSearch';
import saveSearch from '@salesforce/apex/NXP_SearchController.saveSearch';
import getMySearches from '@salesforce/apex/NXP_SearchController.getMySearches';
import getTemplates from '@salesforce/apex/NXP_SearchController.getTemplates';
import getSearch from '@salesforce/apex/NXP_SearchController.getSearch';

jest.mock('@salesforce/apex/NXP_SearchController.getMySearches', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SearchController.getTemplates', () => ({ default: jest.fn() }), { virtual: true });
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
        getTemplates.mockResolvedValue([]);
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
    it('copies a template into a private search', async () => {
        getMySearches.mockResolvedValue([
            { id: 's1', name: 'Mine', frequency: 'Daily', visibility: 'Private', mine: true },
            { id: 't1', name: 'High fit', frequency: 'None', visibility: 'Org Template', mine: false }
        ]);
        getTemplates.mockResolvedValue([
            { id: 't1', name: 'High fit', description: 'Fit 70+', matchCount: 14, capped: false, usedBy: 9 }
        ]);
        getSearch.mockResolvedValue({
            Id: 't1',
            Name: 'High fit',
            Criteria_JSON__c: '{"minFit":70,"dueWithinDays":30}',
            Visibility__c: 'Org Template',
            Alert_Frequency__c: 'None',
            Active__c: false
        });
        const el = createElement('c-nxp-search-builder', { is: NxpSearchBuilder });
        document.body.appendChild(el);
        await flush();
        expect(el.shadowRoot.querySelectorAll('.my-name').length).toBe(1);
        expect(el.shadowRoot.querySelector('.template-count').textContent).toBe('14 now');
        expect(el.shadowRoot.querySelector('.template-meta').textContent).toBe('Used by 9 people');

        el.shadowRoot.querySelector('.use-template').click();
        await flush();
        const save = Array.from(el.shadowRoot.querySelectorAll('lightning-button')).find(
            (b) => b.label === 'Save search'
        );
        save.click();
        await flush();
        const input = saveSearch.mock.calls[0][0].input;
        expect(input.id).toBeNull();
        expect(input.name).toBe('High fit (my copy)');
        expect(input.visibility).toBe('Private');
        expect(input.active).toBe(true);
        expect(input.templateId).toBe('t1');
        expect(JSON.parse(input.criteriaJson).minFit).toBe(70);
    });
});
