/**
 * Shared helpers for Nexus Pursuit Hub Lightning Web Components.
 */
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import logView from '@salesforce/apex/NXP_UsageController.logView';

/** Flattens the many shapes of LDS / Apex errors into readable strings. */
export function reduceErrors(errors) {
    const list = Array.isArray(errors) ? errors : [errors];
    return list
        .filter((e) => !!e)
        .map((e) => {
            if (Array.isArray(e.body)) {
                return e.body.map((b) => b.message);
            }
            if (e.body && typeof e.body.message === 'string') {
                return e.body.message;
            }
            if (e.body && e.body.pageErrors && e.body.pageErrors.length) {
                return e.body.pageErrors.map((p) => p.message);
            }
            if (typeof e.message === 'string') {
                return e.message;
            }
            return e.statusText || 'Unknown error';
        })
        .flat()
        .filter((m) => !!m);
}

export function toast(component, title, message, variant = 'success') {
    component.dispatchEvent(new ShowToastEvent({ title, message, variant }));
}

export function toastError(component, error, title = 'Something went wrong') {
    toast(component, title, reduceErrors(error).join(', '), 'error');
}

const currency = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });

export function formatMoney(value) {
    return value === null || value === undefined ? '' : currency.format(value);
}

const DATE_ONLY = /^(\d{4})-(\d{2})-(\d{2})$/;

/**
 * Apex Date values arrive as "YYYY-MM-DD". new Date() reads that as midnight UTC, which is the
 * previous evening in US time zones, so read it as a local calendar date instead.
 */
export function toDate(value) {
    if (value instanceof Date) {
        return value;
    }
    const m = typeof value === 'string' ? DATE_ONLY.exec(value) : null;
    return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : new Date(value);
}

export function formatDate(value, withTime = false) {
    if (!value) {
        return '';
    }
    const options = withTime
        ? { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' }
        : { month: 'short', day: 'numeric', year: 'numeric' };
    return new Intl.DateTimeFormat('en-US', options).format(toDate(value));
}

/** Whole days from today until the date; negative when past. */
export function daysUntil(value) {
    if (!value) {
        return null;
    }
    const ms = toDate(value).setHours(0, 0, 0, 0) - new Date().setHours(0, 0, 0, 0);
    return Math.round(ms / 86400000);
}

export function dueLabel(value) {
    const d = daysUntil(value);
    if (d === null) {
        return 'No due date';
    }
    if (d < 0) {
        return 'Closed';
    }
    if (d === 0) {
        return 'Due today';
    }
    return d === 1 ? 'Due tomorrow' : `Due in ${d} days`;
}

/** high (75+), medium (60-74), low; used for colour and wording. */
export function fitTier(score) {
    if (score === null || score === undefined) {
        return 'none';
    }
    if (score >= 75) {
        return 'high';
    }
    return score >= 60 ? 'medium' : 'low';
}

/**
 * The two rules that added the most points and the one that cost the most, from a notice's
 * Fit_Breakdown__c (JSON text or a parsed list). Kind: good (full points), part, bad (none).
 */
export function fitReasons(breakdown) {
    let rules = breakdown;
    if (typeof rules === 'string') {
        try {
            rules = JSON.parse(rules);
        } catch (e) {
            return [];
        }
    }
    if (!Array.isArray(rules)) {
        return [];
    }
    rules = rules.filter((r) => r && Number(r.weight) > 0);
    const gains = rules
        .filter((r) => Number(r.points) > 0)
        .sort((a, b) => Number(b.points) - Number(a.points))
        .slice(0, 2);
    const losses = rules
        .filter((r) => !gains.includes(r) && Number(r.points) < Number(r.weight))
        .sort((a, b) => b.weight - b.points - (a.weight - a.points))
        .slice(0, 1);
    return [...gains, ...losses].map((r, i) => {
        const points = Math.round(Number(r.points) || 0);
        const weight = Math.round(Number(r.weight));
        let kind = 'part';
        let label = `+${points} of ${weight}`;
        if (points >= weight) {
            kind = 'good';
            label = `+${points}`;
        } else if (points === 0) {
            kind = 'bad';
            label = `0 of ${weight}`;
        }
        return {
            key: `reason${i}`,
            kind,
            className: `reason reason_${kind}`,
            label,
            text: r.reason || r.rule,
            title: `${r.rule}: ${points} of ${weight} points`
        };
    });
}

/** "a, b , c" -> ['a','b','c'] */
export function splitList(text) {
    return (text || '')
        .split(/[,;\n]/)
        .map((s) => s.trim())
        .filter((s) => s.length > 0);
}

export function joinList(values) {
    return (values || []).join(', ');
}

export function debounce(fn, wait) {
    let timer;
    return (...args) => {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        clearTimeout(timer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        timer = setTimeout(() => fn(...args), wait);
    };
}

/** Records that the user opened a Nexus screen, for the Adoption dashboard. Never fails the screen. */
export function logUsage(screen) {
    try {
        const pending = logView({ screen });
        if (pending && typeof pending.catch === 'function') {
            pending.catch(() => {});
        }
    } catch (e) {
        // ignore: usage is best effort
    }
}
