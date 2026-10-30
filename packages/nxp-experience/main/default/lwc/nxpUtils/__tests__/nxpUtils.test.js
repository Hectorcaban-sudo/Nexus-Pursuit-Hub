import logView from '@salesforce/apex/NXP_UsageController.logView';
import {
    logUsage,
    reduceErrors,
    formatMoney,
    daysUntil,
    dueLabel,
    fitTier,
    splitList,
    joinList,
    debounce,
    formatDate,
    toDate
} from 'c/nxpUtils';

jest.mock('@salesforce/apex/NXP_UsageController.logView', () => ({ default: jest.fn() }), { virtual: true });

describe('c-nxp-utils', () => {
    it('flattens Apex and JS errors', () => {
        expect(
            reduceErrors([
                { body: { message: 'Apex says no' } },
                new Error('JS says no'),
                { body: [{ message: 'a' }, { message: 'b' }] }
            ])
        ).toEqual(['Apex says no', 'JS says no', 'a', 'b']);
        expect(reduceErrors({ body: { pageErrors: [{ message: 'page' }] } })).toEqual(['page']);
    });

    it('formats money and due dates', () => {
        expect(formatMoney(20000000)).toBe('$20,000,000');
        expect(formatMoney(null)).toBe('');
        const inFive = new Date();
        inFive.setDate(inFive.getDate() + 5);
        expect(daysUntil(inFive)).toBe(5);
        expect(dueLabel(inFive)).toBe('Due in 5 days');
        expect(dueLabel(null)).toBe('No due date');
        const past = new Date();
        past.setDate(past.getDate() - 2);
        expect(dueLabel(past)).toBe('Closed');
    });

    it('maps fit scores to tiers', () => {
        expect(fitTier(86)).toBe('high');
        expect(fitTier(60)).toBe('medium');
        expect(fitTier(10)).toBe('low');
        expect(fitTier(null)).toBe('none');
    });

    it('splits and joins lists', () => {
        expect(splitList('541512, 5415*;\n DA01')).toEqual(['541512', '5415*', 'DA01']);
        expect(joinList(['a', 'b'])).toBe('a, b');
        expect(joinList(undefined)).toBe('');
    });

    it('debounces calls', () => {
        jest.useFakeTimers();
        const fn = jest.fn();
        const d = debounce(fn, 100);
        d(1);
        d(2);
        jest.advanceTimersByTime(100);
        expect(fn).toHaveBeenCalledTimes(1);
        expect(fn).toHaveBeenCalledWith(2);
        jest.useRealTimers();
    });
});

describe('c/nxpUtils dates', () => {
    it('reads Apex Date strings as local calendar dates', () => {
        const d = toDate('2026-11-07');
        expect([d.getFullYear(), d.getMonth(), d.getDate()]).toEqual([2026, 10, 7]);
        expect(formatDate('2026-11-07')).toBe('Nov 7, 2026');
    });

    it('counts whole days to a date-only value in any time zone', () => {
        const today = new Date();
        const pad = (n) => String(n).padStart(2, '0');
        const iso = `${today.getFullYear()}-${pad(today.getMonth() + 1)}-${pad(today.getDate())}`;
        expect(daysUntil(iso)).toBe(0);
        expect(daysUntil(null)).toBeNull();
    });

    it('still accepts full timestamps', () => {
        expect(toDate('2026-11-07T18:00:00.000Z').toISOString()).toBe('2026-11-07T18:00:00.000Z');
    });
});

describe('logUsage', () => {
    it('records the screen and never throws', async () => {
        logView.mockResolvedValue(undefined);
        logUsage('Forecasts');
        expect(logView).toHaveBeenCalledWith({ screen: 'Forecasts' });
        logView.mockRejectedValue(new Error('offline'));
        expect(() => logUsage('Forecasts')).not.toThrow();
        logView.mockImplementation(() => {
            throw new Error('boom');
        });
        expect(() => logUsage('Forecasts')).not.toThrow();
    });
});
