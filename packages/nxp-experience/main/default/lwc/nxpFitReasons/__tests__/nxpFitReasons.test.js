import { createElement } from 'lwc';
import NxpFitReasons from 'c/nxpFitReasons';
import { fitReasons } from 'c/nxpUtils';

const BREAKDOWN = JSON.stringify([
    { rule: 'NAICS', weight: 30, points: 30, reason: 'NAICS 541512 is in our profile' },
    { rule: 'Agency', weight: 20, points: 20, reason: 'Target agency' },
    { rule: 'Set-Aside', weight: 15, points: 15, reason: 'We qualify for Small Business' },
    { rule: 'Keyword', weight: 20, points: 6.67, reason: 'Found: cyber' },
    { rule: 'Value Range', weight: 15, points: 0, reason: 'Value outside our range' },
    { rule: 'PSC', weight: 0, points: 0, reason: 'Off' }
]);

describe('fitReasons', () => {
    it('picks the two biggest gains and the biggest loss', () => {
        const r = fitReasons(BREAKDOWN);
        expect(r.map((x) => x.label)).toEqual(['+30', '+20', '0 of 15']);
        expect(r.map((x) => x.kind)).toEqual(['good', 'good', 'bad']);
        expect(r[2].text).toBe('Value outside our range');
    });

    it('labels partial points and ignores bad input', () => {
        const r = fitReasons([
            { rule: 'Keyword', weight: 20, points: 6.67, reason: 'Found: cyber' },
            { rule: 'NAICS', weight: 30, points: 0, reason: 'NAICS not in our profile' }
        ]);
        expect(r[0].label).toBe('+7 of 20');
        expect(r[0].kind).toBe('part');
        expect(r[1].label).toBe('0 of 30');
        expect(fitReasons('not json')).toEqual([]);
        expect(fitReasons(null)).toEqual([]);
    });
});

describe('c-nxp-fit-reasons', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders chips and raises showall', async () => {
        const el = createElement('c-nxp-fit-reasons', { is: NxpFitReasons });
        el.breakdown = BREAKDOWN;
        el.score = 71;
        el.showAll = true;
        const handler = jest.fn();
        el.addEventListener('showall', handler);
        document.body.appendChild(el);
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.lead').textContent).toBe('Why 71');
        expect(el.shadowRoot.querySelectorAll('.reason').length).toBe(3);
        el.shadowRoot.querySelector('.all').click();
        expect(handler).toHaveBeenCalled();
    });

    it('renders nothing without a breakdown', async () => {
        const el = createElement('c-nxp-fit-reasons', { is: NxpFitReasons });
        document.body.appendChild(el);
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.reasons')).toBeNull();
    });
});
