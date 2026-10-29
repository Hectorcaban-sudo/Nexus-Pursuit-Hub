import { createElement } from 'lwc';
import NxpVendorProfile from 'c/nxpVendorProfile';
import getVendorProfile from '@salesforce/apex/NXP_MarketController.getVendorProfile';
import watch from '@salesforce/apex/NXP_MarketController.watch';
import refreshVendor from '@salesforce/apex/NXP_MarketController.refreshVendor';

jest.mock('@salesforce/apex/NXP_MarketController.getVendorProfile', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_MarketController.watch', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_MarketController.refreshVendor', () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const inDays = (days) => new Date(Date.now() + days * 86400000).toISOString();

const PROFILE = {
    vendor: {
        Id: 'a0V000000000004',
        Name: 'Meridian Health IT',
        UEI__c: 'SMPLUEI00004',
        CAGE_Code__c: '0SMP4',
        Business_Size__c: 'Other than small',
        City__c: 'Falls Church',
        State__c: 'VA'
    },
    awardCount: 2,
    totalObligated: 39200000,
    endingSoon: 2,
    agencies: ['Veterans Health Administration'],
    awards: [
        {
            id: 'a0A000000000003',
            title: 'VHA Security Operations Support',
            piid: 'SAMPLE-PIID-0003',
            agency: 'Veterans Affairs › Veterans Health Administration',
            naics: '541512',
            obligated: 12300000,
            periodEnd: inDays(304).slice(0, 10),
            followOnId: 'a01000000000004',
            followOnLabel: 'Likely RFI: SAMPLE-0004'
        },
        {
            id: 'a0A000000000004',
            title: 'VHA Clinical Data Warehouse',
            piid: 'SAMPLE-PIID-0004',
            agency: 'Veterans Affairs › Veterans Health Administration',
            naics: '541511',
            obligated: 26900000,
            periodEnd: inDays(457).slice(0, 10),
            followOnId: null,
            followOnLabel: 'Nothing yet'
        }
    ],
    overlap: [
        { label: 'NAICS overlap', value: '541511, 541512', note: 'In your company profile' },
        { label: 'Agency overlap', value: 'Veterans Health Administration', note: 'Target agencies in your profile' },
        { label: 'Set-aside eligibility', value: "Can't bid small-business set-asides", note: 'Other than small' }
    ],
    openNotices: [
        {
            id: 'a01000000000004',
            title: 'Security Operations Center Support',
            noticeKey: 'SAMPLE-0004',
            noticeType: 'RFI',
            agency: 'Veterans Affairs › Veterans Health Administration',
            responseDue: inDays(9),
            fitScore: 54,
            reason: 'Same agency and NAICS as one of their awards ending soon'
        }
    ],
    watching: false,
    canRefresh: true
};

describe('c-nxp-vendor-profile', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    async function render(profile = PROFILE) {
        getVendorProfile.mockResolvedValue(profile);
        const el = createElement('c-nxp-vendor-profile', { is: NxpVendorProfile });
        el.recordId = 'a0V000000000004';
        document.body.appendChild(el);
        await flush();
        return el;
    }

    it('shows identity, totals, awards, overlap and open notices', async () => {
        const el = await render();
        expect(getVendorProfile).toHaveBeenCalledWith({ vendorId: 'a0V000000000004' });
        expect(el.shadowRoot.querySelector('h1').textContent).toBe('Meridian Health IT');
        expect(el.shadowRoot.querySelector('.identity').textContent).toContain('UEI SMPLUEI00004 · CAGE 0SMP4');
        const values = [...el.shadowRoot.querySelectorAll('.kpi-value')].map((n) => n.textContent);
        expect(values).toEqual(['2', '$39,200,000', '2', '1']);
        expect(el.shadowRoot.querySelectorAll('.award-row').length).toBe(2);
        expect(el.shadowRoot.querySelectorAll('.overlap-item').length).toBe(3);
        const notice = el.shadowRoot.querySelector('.notice');
        expect(notice.textContent).toContain('Security Operations Center Support');
        expect(notice.textContent).toContain('fit 54');
    });

    it('refreshes from SAM.gov and toggles the watch', async () => {
        refreshVendor.mockResolvedValue('Updated from SAM.gov.');
        watch.mockResolvedValue(true);
        const el = await render();
        el.shadowRoot.querySelector('lightning-button.refresh').click();
        await flush();
        expect(refreshVendor).toHaveBeenCalledWith({ vendorId: 'a0V000000000004' });
        el.shadowRoot.querySelector('lightning-button.watch').click();
        await flush();
        expect(watch).toHaveBeenCalledWith({ recordId: 'a0V000000000004', watch: true });
        expect(getVendorProfile).toHaveBeenCalledTimes(3);
    });

    it('hides Refresh for non-admins and handles a vendor with no awards', async () => {
        const el = await render({ ...PROFILE, canRefresh: false, awards: [], openNotices: [], awardCount: 0 });
        expect(el.shadowRoot.querySelector('lightning-button.refresh')).toBeNull();
        expect(el.shadowRoot.querySelector('table')).toBeNull();
        expect(el.shadowRoot.textContent).toContain('No open notices');
    });
});
