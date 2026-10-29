import { createElement } from 'lwc';
import NxpAgencyProfile from 'c/nxpAgencyProfile';
import getAgencyProfile from '@salesforce/apex/NXP_MarketController.getAgencyProfile';
import watch from '@salesforce/apex/NXP_MarketController.watch';

jest.mock('@salesforce/apex/NXP_MarketController.getAgencyProfile', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_MarketController.watch', () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
// A local calendar date "YYYY-MM-DD", like Apex Date values.
const inDays = (days) => {
    const d = new Date();
    d.setDate(d.getDate() + days);
    const pad = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};

const PROFILE = {
    agency: {
        Id: 'a0G000000000004',
        Name: 'Veterans Health Administration',
        Agency_Code__c: '036.3600',
        Level__c: 'Agency',
        Parent_Agency__c: 'a0G000000000003',
        Parent_Agency__r: { Name: 'Veterans Affairs, Department of' }
    },
    targetAgency: true,
    watching: false,
    openNotices: 2,
    dueIn30: 1,
    forecasts: 1,
    forecastValue: 30000000,
    endingSoon: 2,
    endingSoonValue: 39200000,
    coming: [
        {
            kind: 'notice',
            recordId: 'a01000000000004',
            title: 'Security Operations Center Support',
            onDate: inDays(9),
            detail: 'RFI · SAMPLE-0004',
            fitScore: 73
        },
        {
            kind: 'forecast',
            recordId: 'a0F000000000002',
            title: 'Enterprise Data Platform Modernization',
            onDate: inDays(90),
            detail: 'Expected solicitation',
            amount: 30000000
        },
        {
            kind: 'award',
            recordId: 'a0A000000000003',
            title: 'VHA Security Operations Support',
            onDate: inDays(304),
            detail: 'Meridian Health IT',
            amount: 12300000
        }
    ],
    incumbents: [{ vendorId: 'a0V000000000004', name: 'Meridian Health IT', awards: 2, total: 39200000 }],
    naics: [
        { code: '541511', total: 26900000, pct: 69, inProfile: true },
        { code: '541512', total: 12300000, pct: 31, inProfile: true }
    ],
    contacts: [
        {
            id: 'a0C000000000001',
            name: 'Pat Jones',
            role: 'Contracting Officer',
            email: 'pat.jones@example.gov',
            noticeKey: 'SAMPLE-0004'
        }
    ],
    offices: ['VHA Program Contracting Activity'],
    children: [],
    coveringSearches: [],
    broadSearches: 1,
    pushed: 0,
    followed: 0
};

describe('c-nxp-agency-profile', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    async function render(profile = PROFILE) {
        getAgencyProfile.mockResolvedValue(profile);
        const el = createElement('c-nxp-agency-profile', { is: NxpAgencyProfile });
        el.recordId = 'a0G000000000004';
        document.body.appendChild(el);
        await flush();
        return el;
    }

    it('shows the hierarchy, totals and a dated list of what is coming', async () => {
        const el = await render();
        expect(getAgencyProfile).toHaveBeenCalledWith({ agencyId: 'a0G000000000004' });
        expect(el.shadowRoot.querySelector('.crumbs').textContent).toContain('Veterans Affairs, Department of');
        expect(el.shadowRoot.querySelector('.chip_target')).not.toBeNull();
        const values = [...el.shadowRoot.querySelectorAll('.kpi-value')].map((n) => n.textContent);
        expect(values).toEqual(['2', '1', '2', '1']);
        const kinds = [...el.shadowRoot.querySelectorAll('.coming-item .kind')].map((n) => n.textContent);
        expect(kinds).toEqual(['Notice', 'Forecast', 'Award ends']);
        const when = [...el.shadowRoot.querySelectorAll('.coming-item .when')].map((n) => n.textContent);
        expect(when).toEqual(['In 9 days', 'In 3 months', 'In 10 months']);
        expect(el.shadowRoot.querySelector('.coming-item .right').textContent).toBe('Fit 73');
        expect(el.shadowRoot.querySelectorAll('.incumbent').length).toBe(1);
        expect(el.shadowRoot.querySelectorAll('.naics').length).toBe(2);
        expect(el.shadowRoot.querySelector('.contact').textContent).toContain('Pat Jones');
    });

    it('warns when no saved search targets the agency, and watches it', async () => {
        watch.mockResolvedValue(true);
        const el = await render();
        const coverage = el.shadowRoot.querySelector('.coverage');
        expect(coverage.className).not.toContain('coverage_ok');
        expect(coverage.textContent).toContain('None of your saved searches targets this agency');
        el.shadowRoot.querySelector('lightning-button.watch').click();
        await flush();
        expect(watch).toHaveBeenCalledWith({ recordId: 'a0G000000000004', watch: true });
    });

    it('confirms coverage and handles an agency with no data', async () => {
        const el = await render({
            ...PROFILE,
            coveringSearches: ['VA cyber'],
            coming: [],
            incumbents: [],
            naics: [],
            contacts: [],
            offices: [],
            agency: { ...PROFILE.agency, Parent_Agency__c: null, Parent_Agency__r: null }
        });
        expect(el.shadowRoot.querySelector('.coverage_ok').textContent).toContain('VA cyber');
        expect(el.shadowRoot.querySelector('.crumbs')).toBeNull();
        expect(el.shadowRoot.querySelector('.coming')).toBeNull();
        expect(el.shadowRoot.textContent).toContain('No contacts yet');
    });
});
