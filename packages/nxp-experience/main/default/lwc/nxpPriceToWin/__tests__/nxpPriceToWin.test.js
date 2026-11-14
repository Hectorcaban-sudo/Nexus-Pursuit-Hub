import { createElement } from 'lwc';
import NxpPriceToWin from 'c/nxpPriceToWin';
import getPriceCheck from '@salesforce/apex/NXP_PriceToWinController.getPriceCheck';

jest.mock('@salesforce/apex/NXP_PriceToWinController.getPriceCheck', () => ({ default: jest.fn() }), {
    virtual: true
});

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const PRED = {
    id: 'a05000000000001',
    name: 'Zero trust engineering',
    piid: '70B04C24F00000312',
    vendorId: 'a04000000000001',
    vendorName: 'Vendor A',
    agencyName: 'U.S. Customs and Border Protection',
    periodStart: '2024-04-01',
    periodEnd: '2027-03-31',
    obligated: 11600000,
    years: 2.6,
    perYear: 4461538,
    isPredecessor: true,
    inRange: false
};

function result(overrides) {
    return {
        enabled: true,
        noticeId: 'a01000000000011',
        scopeKey: 'agency',
        scopeLabel: 'NAICS + CBP',
        lookbackYears: 5,
        minAwards: 5,
        count: 6,
        enough: true,
        low: 1000000,
        q1: 2550000,
        median: 3500000,
        q3: 4375000,
        high: 5555556,
        values: [1000000, 2400000, 3000000, 4000000, 4461538, 5555556],
        noticeYears: 3,
        noticeYearsSource: 'predecessor',
        predecessor: PRED,
        dataThrough: '2026-04-27',
        scopes: [
            { key: 'agency', label: 'NAICS + CBP', count: 6, available: true, selected: true },
            { key: 'department', label: 'NAICS + DHS', count: 7, available: true, selected: false },
            { key: 'naics', label: 'NAICS, all agencies', count: 8, available: true, selected: false },
            { key: 'agencyAll', label: 'CBP, all our NAICS', count: 0, available: false, selected: false }
        ],
        hold: {
            matched: 2,
            kept: 1,
            incumbentName: 'Vendor A',
            incumbentMatched: 1,
            incumbentKept: 1,
            examples: [
                {
                    vendorName: 'Vendor B',
                    fromPiid: 'PTW-Z',
                    toPiid: 'PTW-W',
                    toVendorName: 'Vendor C',
                    endedOn: '2025-10-08',
                    kept: false
                },
                {
                    vendorName: 'Vendor A',
                    fromPiid: 'PTW-X',
                    toPiid: 'PTW-Y',
                    toVendorName: 'Vendor A',
                    endedOn: '2024-11-13',
                    kept: true
                }
            ]
        },
        estimate: {
            count: 9,
            perYear: 3800000,
            low: 2400000,
            high: 4500000,
            basis: [
                {
                    id: 'a05000000000002',
                    name: 'Zero trust architecture',
                    vendorName: 'Vendor A',
                    agencyName: 'U.S. Customs and Border Protection',
                    naics: '541512',
                    periodStart: '2022-11-14',
                    perYear: 4000000,
                    similarity: 6.6
                }
            ]
        },
        awards: [
            {
                id: 'a05000000000003',
                piid: 'PTW-V',
                vendorId: 'a04000000000002',
                vendorName: 'Vendor B',
                agencyName: 'U.S. Customs and Border Protection',
                periodStart: '2026-04-27',
                years: 1,
                obligated: 1000000,
                perYear: 1000000,
                inRange: false
            },
            { ...PRED, inRange: false },
            {
                id: 'a05000000000004',
                piid: 'PTW-W',
                vendorId: 'a04000000000003',
                vendorName: 'Vendor C',
                agencyName: 'U.S. Customs and Border Protection',
                periodStart: '2025-11-08',
                years: 1,
                obligated: 3000000,
                perYear: 3000000,
                inRange: true
            }
        ],
        ...overrides
    };
}

function mount() {
    const el = createElement('c-nxp-price-to-win', { is: NxpPriceToWin });
    el.recordId = 'a01000000000011';
    document.body.appendChild(el);
    return el;
}

const text = (el) => el.shadowRoot.textContent;

describe('c-nxp-price-to-win', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows the range, the predecessor, the estimate and the incumbent hold', async () => {
        getPriceCheck.mockResolvedValue(result());
        const el = mount();
        await flush();
        expect(getPriceCheck).toHaveBeenCalledWith({ noticeId: 'a01000000000011', scopeKey: null });
        const t = text(el);
        expect(t).toContain('$1M');
        expect(t).toContain('$3.5M');
        expect(t).toContain('$5.56M');
        // Typical range over the predecessor's 3 years: 2.55M x 3 to 4.375M x 3.
        expect(t).toContain('$7.65M – $13.1M');
        expect(t).toContain('Vendor A');
        expect(t).toContain('$4.46M');
        expect(t).toContain('$3.8M');
        expect(t).toContain('9 most similar awards');
        expect(t).toContain('50%');
        expect(t).toContain('1 of 2 ended contracts went to the same vendor again');
        expect(t).toContain('Vendor A kept 1 of 1 here.');
        expect(t).toContain('Vendor B lost it to Vendor C');
        expect(el.shadowRoot.querySelectorAll('tr.row_in').length).toBe(1);
        expect(t).toContain('Predecessor');

        const scopes = el.shadowRoot.querySelectorAll('lightning-button.scope');
        expect(scopes.length).toBe(4);
        expect(scopes[0].variant).toBe('brand');
        expect(scopes[3].disabled).toBe(true);
    });

    it('switches scope and reloads', async () => {
        getPriceCheck.mockResolvedValue(result());
        const el = mount();
        await flush();
        getPriceCheck.mockResolvedValue(result({ scopeKey: 'department', scopeLabel: 'NAICS + DHS', count: 7 }));
        el.shadowRoot.querySelectorAll('lightning-button.scope')[1].click();
        await flush();
        expect(getPriceCheck).toHaveBeenLastCalledWith({ noticeId: 'a01000000000011', scopeKey: 'department' });
        expect(text(el)).toContain('7 awards · NAICS + DHS');
    });

    it('places a price against past awards without odds', async () => {
        getPriceCheck.mockResolvedValue(result());
        const el = mount();
        await flush();
        const input = el.shadowRoot.querySelector('lightning-input.price');
        input.dispatchEvent(new CustomEvent('change', { detail: { value: '10500000' } }));
        await flush();
        const t = text(el);
        // 10.5M over 3 years = 3.5M a year.
        expect(t).toContain('$3.5M a year');
        expect(t).toContain('In the typical range');
        expect(t).toContain('Higher than 3 of 6 comparable awards');
        expect(t).toContain('22% below the predecessor’s $4.46M a year');
        expect(t).toContain('about the same as the median');
        expect(t).not.toMatch(/likelihood|probability of winning/i);
    });

    it('changing the years changes the totals', async () => {
        getPriceCheck.mockResolvedValue(result());
        const el = mount();
        await flush();
        const years = el.shadowRoot.querySelector('lightning-combobox.years');
        years.dispatchEvent(new CustomEvent('change', { detail: { value: '5' } }));
        await flush();
        expect(text(el)).toContain('$12.8M – $21.9M');
    });

    it('says when there are too few awards, and when it is off', async () => {
        getPriceCheck.mockResolvedValue(
            result({
                enough: false,
                count: 3,
                low: null,
                q1: null,
                median: null,
                q3: null,
                high: null,
                note: 'Only 3 comparable awards here; a range needs 5.'
            })
        );
        let el = mount();
        await flush();
        expect(text(el)).toContain('Only 3 comparable awards here');
        expect(el.shadowRoot.querySelector('.tiles')).toBeNull();
        expect(text(el)).toContain('$3.8M');

        document.body.removeChild(el);
        getPriceCheck.mockResolvedValue({ enabled: false, note: 'Price-to-Win is off.', scopes: [] });
        el = mount();
        await flush();
        expect(text(el)).toContain('Price-to-Win is off.');
        expect(el.shadowRoot.querySelector('.scopes')).toBeNull();
    });

    it('copies a plain-text summary', async () => {
        getPriceCheck.mockResolvedValue(result());
        const writeText = jest.fn().mockResolvedValue();
        Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
        const el = mount();
        await flush();
        const buttons = el.shadowRoot.querySelectorAll('lightning-button');
        buttons[buttons.length - 1].click();
        await flush();
        expect(writeText).toHaveBeenCalled();
        const copied = writeText.mock.calls[0][0];
        expect(copied).toContain('Price-to-Win, NAICS + CBP (6 awards, last 5 years)');
        expect(copied).toContain('not a chance of winning');
    });
});
