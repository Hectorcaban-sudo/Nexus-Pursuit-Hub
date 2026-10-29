import { createElement } from 'lwc';
import NxpForecastBoard from 'c/nxpForecastBoard';
import getForecastBoard from '@salesforce/apex/NXP_MarketController.getForecastBoard';
import watch from '@salesforce/apex/NXP_MarketController.watch';

jest.mock('@salesforce/apex/NXP_MarketController.getForecastBoard', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_MarketController.watch', () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const card = (over) => ({
    id: 'a0F000000000001',
    title: 'Enterprise Data Platform Modernization',
    agency: 'Veterans Affairs › Veterans Health Administration',
    naics: '541511',
    setAside: null,
    value: 30000000,
    solicitationDate: '2027-01-26',
    daysUntil: 45,
    fiscalYear: 'FY2027',
    profileMatch: true,
    profileNote: 'Matches NAICS, target agency',
    released: false,
    watching: false,
    ...over
});

const BOARD = {
    tracked: 3,
    next90: 1,
    next90Value: 30000000,
    released: 1,
    watched: 0,
    fiscalYears: ['FY2027'],
    columns: [
        { key: 'next90', label: 'Next 90 days', cards: [card()] },
        {
            key: 'next180',
            label: '3 to 6 months',
            cards: [card({ id: 'a0F000000000002', title: 'Tactical Cloud', daysUntil: 150, watching: true })]
        },
        { key: 'next365', label: '6 to 12 months', cards: [] },
        { key: 'later', label: 'Later or no date', cards: [] },
        {
            key: 'released',
            label: 'Released as notices',
            cards: [
                card({
                    id: 'a0F000000000003',
                    title: 'ICAM Modernization',
                    released: true,
                    noticeId: 'a01000000000001',
                    noticeKey: 'SAMPLE-0002',
                    noticePosted: '2026-10-26'
                })
            ]
        }
    ]
};

describe('c-nxp-forecast-board', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows KPIs and one column per date bucket, hiding an empty "later" column', async () => {
        getForecastBoard.mockResolvedValue(BOARD);
        const el = createElement('c-nxp-forecast-board', { is: NxpForecastBoard });
        document.body.appendChild(el);
        await flush();

        expect(getForecastBoard).toHaveBeenCalledWith(expect.objectContaining({ profileOnly: true }));
        const columns = el.shadowRoot.querySelectorAll('.column');
        expect(columns.length).toBe(4);
        const kpiValues = [...el.shadowRoot.querySelectorAll('.kpi-value')].map((n) => n.textContent);
        expect(kpiValues).toEqual(['3', '1', '1', '0']);
        expect(el.shadowRoot.querySelector('.when_soon').textContent).toBe('In 45 days');
        expect(el.shadowRoot.querySelector('.released').textContent).toContain('SAMPLE-0002');
        expect(el.shadowRoot.querySelector('.empty')).toBeNull();
    });

    it('toggles a watch and reloads', async () => {
        getForecastBoard.mockResolvedValue(BOARD);
        watch.mockResolvedValue(true);
        const el = createElement('c-nxp-forecast-board', { is: NxpForecastBoard });
        document.body.appendChild(el);
        await flush();

        const buttons = el.shadowRoot.querySelectorAll('lightning-button.watch');
        expect(buttons.length).toBe(2);
        expect(buttons[1].label).toBe('Watching');
        buttons[0].click();
        await flush();
        expect(watch).toHaveBeenCalledWith({ recordId: 'a0F000000000001', watch: true });
        expect(getForecastBoard).toHaveBeenCalledTimes(2);
    });

    it('explains when nothing matches', async () => {
        getForecastBoard.mockResolvedValue({ ...BOARD, tracked: 0, columns: [] });
        const el = createElement('c-nxp-forecast-board', { is: NxpForecastBoard });
        document.body.appendChild(el);
        await flush();
        expect(el.shadowRoot.querySelector('.empty')).not.toBeNull();
    });
});
