import { reduceErrors, formatMoney, daysUntil, dueLabel, fitTier, splitList, joinList, debounce } from 'c/nxpUtils';

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
