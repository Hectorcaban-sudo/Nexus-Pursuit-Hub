import { createElement } from 'lwc';
import NxpForecastOverview from 'c/nxpForecastOverview';
import getOverview from '@salesforce/apex/NXP_ForecastController.getOverview';
import setPredecessor from '@salesforce/apex/NXP_ForecastController.setPredecessor';
import linkNotice from '@salesforce/apex/NXP_ForecastController.linkNotice';
import watch from '@salesforce/apex/NXP_MarketController.watch';

jest.mock('@salesforce/apex/NXP_ForecastController.getOverview', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_ForecastController.setPredecessor', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_ForecastController.linkNotice', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_MarketController.watch', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_UsageController.logView', () => ({ default: jest.fn(() => Promise.resolve()) }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_PriceToWinController.getPriceCheck', () => ({ default: jest.fn() }), { virtual: true });
jest.mock(
    '@salesforce/apex/NXP_PriceToWinController.getForecastPriceCheck',
    () => ({ default: jest.fn(() => Promise.resolve({ enabled: false, note: 'off', scopes: [] })) }),
    { virtual: true }
);

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function overview(overrides) {
    return {
        forecast: {
            Id: 'a0F000000000001',
            Name: 'Tactical Cloud Operations Support',
            Agency__c: 'a0A000000000001',
            Agency__r: { Name: 'Dept of the Army' },
            Estimated_Solicitation_Date__c: '2027-03-29',
            Estimated_Value__c: 15000000,
            Fiscal_Year__c: 'FY2027',
            NAICS_Code__c: '541519',
            Set_Aside__c: '8(a) Set-Aside (FAR 19.8)',
            Source_Feed__c: 'SAMPLE',
            Description__c: 'Army cloud operations.'
        },
        daysToSolicitation: 134,
        fitScore: 67,
        fit: [
            { rule: 'NAICS', points: 30, weight: 30, reason: 'NAICS 541519 is in our profile' },
            { rule: 'Set-Aside', points: 0, weight: 15, reason: 'We do not qualify for 8(a)' }
        ],
        setAsideOk: false,
        setAsideNote: "We don't qualify: team with a firm that does",
        stages: [
            { label: 'Forecast', detail: 'Posted 10/29/2026', state: 'done' },
            { label: 'Sources Sought / RFI', detail: 'Not seen yet', state: 'now' },
            { label: 'Solicitation', detail: 'Expected 3/29/2027', state: 'next' },
            { label: 'Award', detail: 'Not known', state: 'next' }
        ],
        notices: [],
        watchers: 3,
        watching: false,
        canCurate: true,
        candidates: [
            {
                id: 'a0S000000000001',
                piid: 'W912DY22F0118',
                name: 'Tactical cloud operations',
                vendorId: 'a0V000000000001',
                vendorName: 'Vendor R',
                periodEnd: '2027-04-18',
                obligated: 9000000,
                match: 'High',
                confirmed: false
            }
        ],
        leaders: [{ vendorId: 'a0V000000000001', vendorName: 'Vendor R', awards: 14, obligated: 41200000 }],
        related: [{ Id: 'a0F000000000002', Name: 'Enterprise Cloud Migration', Estimated_Value__c: 22000000 }],
        ...overrides
    };
}

function mount() {
    const el = createElement('c-nxp-forecast-overview', { is: NxpForecastOverview });
    el.recordId = 'a0F000000000001';
    document.body.appendChild(el);
    return el;
}

const text = (el) => el.shadowRoot.textContent;

describe('c-nxp-forecast-overview', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows the countdown, fit, set-aside flag, stages, candidates and market', async () => {
        getOverview.mockResolvedValue(overview());
        const el = mount();
        await flush();
        const t = text(el);
        expect(t).toContain('134');
        expect(t).toContain('days to solicitation');
        expect(t).toContain('Early fit 67');
        expect(t).toContain("We don't qualify: team with a firm that does");
        expect(t).toContain('3 people watch this forecast');
        expect(el.shadowRoot.querySelectorAll('li.stage_done').length).toBe(1);
        expect(el.shadowRoot.querySelectorAll('li.stage_now').length).toBe(1);
        expect(t).toContain('W912DY22F0118');
        expect(t).toContain('14 awards · $41.2M');
        expect(t).toContain('Enterprise Cloud Migration');
        expect(el.shadowRoot.querySelector('.right c-nxp-price-to-win')).not.toBeNull();
    });

    it('watches, confirms a predecessor and links a notice', async () => {
        getOverview.mockResolvedValue(overview());
        watch.mockResolvedValue(true);
        setPredecessor.mockResolvedValue(overview({ candidates: [{ ...overview().candidates[0], confirmed: true }] }));
        linkNotice.mockResolvedValue(
            overview({
                notices: [
                    {
                        Id: 'a01000000000001',
                        Title__c: 'Tactical Cloud Ops (Sources Sought)',
                        Notice_Type__c: 'Sources Sought'
                    }
                ]
            })
        );
        const el = mount();
        await flush();

        el.shadowRoot.querySelector('lightning-button.watch').click();
        await flush();
        expect(watch).toHaveBeenCalledWith({ recordId: 'a0F000000000001', watch: true });

        el.shadowRoot.querySelector('lightning-button.predecessor').click();
        await flush();
        expect(setPredecessor).toHaveBeenCalledWith({ forecastId: 'a0F000000000001', awardId: 'a0S000000000001' });
        expect(text(el)).toContain('Predecessor');
        expect(el.shadowRoot.querySelector('lightning-button.predecessor').label).toBe('Clear');

        const link = el.shadowRoot.querySelector('lightning-button.link');
        expect(link.disabled).toBe(true);
        el.shadowRoot
            .querySelector('lightning-record-picker.link-notice')
            .dispatchEvent(new CustomEvent('change', { detail: { recordId: 'a01000000000001' } }));
        await flush();
        el.shadowRoot.querySelector('lightning-button.link').click();
        await flush();
        expect(linkNotice).toHaveBeenCalledWith({ forecastId: 'a0F000000000001', noticeId: 'a01000000000001' });
        expect(text(el)).toContain('Tactical Cloud Ops (Sources Sought)');
    });
});
