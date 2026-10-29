import { createElement } from 'lwc';
import NxpRecompeteTimeline from 'c/nxpRecompeteTimeline';
import getRecompetes from '@salesforce/apex/NXP_MarketController.getRecompetes';
import watch from '@salesforce/apex/NXP_MarketController.watch';

jest.mock('@salesforce/apex/NXP_MarketController.getRecompetes', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_MarketController.watch', () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const isoInMonths = (months) => {
    const d = new Date();
    d.setDate(d.getDate() + Math.round(months * 30.44));
    return d.toISOString().slice(0, 10);
};

const ROWS = [
    {
        id: 'a0A000000000006',
        title: 'Army Cyber Range Support',
        piid: 'SAMPLE-PIID-0006',
        agency: 'Dept of Defense › Dept of the Army',
        naics: '541512',
        vendorId: 'a0V000000000002',
        vendorName: 'Bluefin Cyber Solutions',
        obligated: 4100000,
        ceiling: 5000000,
        periodStart: isoInMonths(-60),
        periodEnd: isoInMonths(-2),
        monthsLeft: -2,
        followOnKind: 'notice',
        followOnLabel: 'Likely Solicitation: SAMPLE-0010',
        followOnId: 'a01000000000010',
        followOnConfirmed: false,
        watching: false
    },
    {
        id: 'a0A000000000001',
        title: 'CBP Zero Trust Engineering',
        piid: 'SAMPLE-PIID-0001',
        agency: 'Homeland Security › US Customs and Border Protection',
        naics: '541512',
        vendorId: 'a0V000000000001',
        vendorName: 'Northwind Federal Systems',
        obligated: 18400000,
        ceiling: 25000000,
        periodStart: isoInMonths(-54),
        periodEnd: isoInMonths(4),
        monthsLeft: 4,
        followOnKind: 'notice',
        followOnLabel: 'Solicitation: SAMPLE-0001',
        followOnId: 'a01000000000001',
        followOnConfirmed: true,
        watching: false
    },
    {
        id: 'a0A000000000005',
        title: 'USCIS Identity Services',
        piid: 'SAMPLE-PIID-0005',
        agency: 'Homeland Security › USCIS',
        naics: '541512',
        vendorId: null,
        vendorName: null,
        obligated: 6200000,
        ceiling: null,
        periodStart: null,
        periodEnd: isoInMonths(14),
        monthsLeft: 14,
        followOnKind: 'none',
        followOnLabel: 'Nothing yet',
        followOnId: null,
        followOnConfirmed: false,
        watching: true
    }
];

describe('c-nxp-recompete-timeline', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('draws a bar per award, colours by time left and selects the first upcoming award', async () => {
        getRecompetes.mockResolvedValue(ROWS);
        const el = createElement('c-nxp-recompete-timeline', { is: NxpRecompeteTimeline });
        document.body.appendChild(el);
        await flush();

        expect(getRecompetes).toHaveBeenCalledWith({ agency: '', naics: '', monthsAhead: 18, minValue: null });
        const bars = el.shadowRoot.querySelectorAll('.track .bar');
        expect(bars.length).toBe(3);
        expect(bars[0].className).toContain('bar_ended');
        expect(bars[1].className).toContain('bar_soon');
        expect(bars[2].className).toBe('bar');
        // Started before the 2-year axis: clipped to the left edge.
        expect(bars[0].getAttribute('style')).toContain('left: 0.0%');
        const ends = [...el.shadowRoot.querySelectorAll('.row .ends')].map((n) => n.textContent);
        expect(ends).toEqual(['Ended', '4 mo', '14 mo']);
        expect(el.shadowRoot.querySelector('.detail h2').textContent).toBe('CBP Zero Trust Engineering');
        expect(el.shadowRoot.querySelector('.signal').textContent).toContain('names the award as its predecessor');
    });

    it('changes the window and watches the selected award', async () => {
        getRecompetes.mockResolvedValue(ROWS);
        watch.mockResolvedValue(true);
        const el = createElement('c-nxp-recompete-timeline', { is: NxpRecompeteTimeline });
        document.body.appendChild(el);
        await flush();

        el.shadowRoot.querySelectorAll('lightning-button.window')[3].click();
        await flush();
        expect(getRecompetes).toHaveBeenLastCalledWith(expect.objectContaining({ monthsAhead: 24 }));

        el.shadowRoot.querySelectorAll('.select')[2].click();
        await flush();
        const watchButton = el.shadowRoot.querySelector('.detail lightning-button.watch');
        expect(watchButton.label).toBe('Watching');
        watchButton.click();
        await flush();
        expect(watch).toHaveBeenCalledWith({ recordId: 'a0A000000000005', watch: false });
    });

    it('explains an empty window', async () => {
        getRecompetes.mockResolvedValue([]);
        const el = createElement('c-nxp-recompete-timeline', { is: NxpRecompeteTimeline });
        document.body.appendChild(el);
        await flush();
        expect(el.shadowRoot.querySelector('.empty')).not.toBeNull();
        expect(el.shadowRoot.querySelector('.detail')).toBeNull();
    });
});
