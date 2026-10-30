import { createElement } from 'lwc';
import NxpMatchInbox from 'c/nxpMatchInbox';
import getMySearches from '@salesforce/apex/NXP_SearchController.getMySearches';
import getInbox from '@salesforce/apex/NXP_SearchController.getInbox';
import setMatchAction from '@salesforce/apex/NXP_SearchController.setMatchAction';
import setMatchActions from '@salesforce/apex/NXP_SearchController.setMatchActions';
import LightningPrompt from 'lightning/prompt';

jest.mock('@salesforce/apex/NXP_SearchController.getMySearches', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SearchController.getInbox', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SearchController.setMatchAction', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SearchController.setMatchActions', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_PushController.bulkPush', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('c/nxpPushDialog', () => ({ __esModule: true, default: { open: jest.fn() } }));

const SEARCHES = [
    { id: 's1', name: 'DHS cyber', frequency: 'Daily', mine: true, newCount: 2 },
    { id: 's2', name: 'Shared', frequency: 'Weekly', mine: false, newCount: 0 }
];
const due = (days) => {
    const d = new Date();
    d.setDate(d.getDate() + days);
    return d.toISOString();
};
const ITEMS = [
    {
        matchId: 'm1',
        searchName: 'DHS cyber',
        matchedTerms: 'zero trust, 541512',
        changeType: 'New',
        userAction: 'None',
        matchedAt: new Date().toISOString(),
        notice: { Id: 'n1', Title__c: 'Lower fit', Fit_Score__c: 60, Notice_Type__c: 'RFI', Response_Due__c: due(3) }
    },
    {
        matchId: 'm2',
        searchName: 'DHS cyber',
        changeType: 'Due date',
        userAction: 'None',
        matchedAt: new Date().toISOString(),
        notice: {
            Id: 'n2',
            Title__c: 'Higher fit',
            Fit_Score__c: 86,
            Notice_Type__c: 'Solicitation',
            Set_Aside__c: '8(a)',
            Estimated_Value__c: 5000000,
            Response_Due__c: due(20)
        }
    }
];

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-nxp-match-inbox', () => {
    beforeEach(() => {
        getMySearches.mockResolvedValue(SEARCHES);
        getInbox.mockResolvedValue(ITEMS);
        setMatchAction.mockResolvedValue(undefined);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('lists only my searches and sorts cards by fit', async () => {
        const el = createElement('c-nxp-match-inbox', { is: NxpMatchInbox });
        document.body.appendChild(el);
        await flush();
        const rows = el.shadowRoot.querySelectorAll('.search-name');
        // "All searches" plus the one search the user owns.
        expect(rows.length).toBe(2);
        const titles = Array.from(el.shadowRoot.querySelectorAll('.title')).map((a) => a.textContent);
        expect(titles).toEqual(['Higher fit', 'Lower fit']);
        expect(el.shadowRoot.querySelector('.chip_warn').textContent).toContain('Due date');
    });

    it('watches a match and reloads', async () => {
        const el = createElement('c-nxp-match-inbox', { is: NxpMatchInbox });
        document.body.appendChild(el);
        await flush();
        const watch = Array.from(el.shadowRoot.querySelectorAll('.card-actions lightning-button')).find(
            (b) => b.label === 'Watch'
        );
        watch.click();
        await flush();
        expect(setMatchAction).toHaveBeenCalledWith({ matchId: 'm2', action: 'Watching', reason: null });
        expect(getInbox).toHaveBeenCalledTimes(2);
    });

    it('watches and dismisses selected matches in bulk', async () => {
        setMatchActions.mockResolvedValue(2);
        LightningPrompt.open = jest.fn().mockResolvedValue('Not a fit');
        const el = createElement('c-nxp-match-inbox', { is: NxpMatchInbox });
        document.body.appendChild(el);
        await flush();
        expect(el.shadowRoot.querySelector('.bulk-watch').disabled).toBe(true);

        const all = el.shadowRoot.querySelector('.select-all');
        all.checked = true;
        all.dispatchEvent(new CustomEvent('change'));
        await flush();
        expect(el.shadowRoot.querySelector('.bulk-push').label).toBe('Push 2');

        el.shadowRoot.querySelector('.bulk-watch').click();
        await flush();
        expect(setMatchActions).toHaveBeenCalledWith({
            matchIds: expect.arrayContaining(['m1', 'm2']),
            action: 'Watching',
            reason: null
        });

        all.checked = true;
        all.dispatchEvent(new CustomEvent('change'));
        await flush();
        el.shadowRoot.querySelector('.bulk-dismiss').click();
        await flush();
        expect(setMatchActions).toHaveBeenLastCalledWith({
            matchIds: expect.arrayContaining(['m1', 'm2']),
            action: 'Dismissed',
            reason: 'Not a fit'
        });
    });

    it('shows the empty state', async () => {
        getInbox.mockResolvedValue([]);
        const el = createElement('c-nxp-match-inbox', { is: NxpMatchInbox });
        document.body.appendChild(el);
        await flush();
        expect(el.shadowRoot.querySelector('.empty')).not.toBeNull();
    });
});
