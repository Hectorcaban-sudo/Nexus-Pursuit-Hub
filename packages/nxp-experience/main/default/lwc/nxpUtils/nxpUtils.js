/**
 * Shared helpers for Nexus Pursuit Hub Lightning Web Components.
 */
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

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

export function formatDate(value, withTime = false) {
    if (!value) {
        return '';
    }
    const options = withTime
        ? { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' }
        : { month: 'short', day: 'numeric', year: 'numeric' };
    return new Intl.DateTimeFormat('en-US', options).format(new Date(value));
}

/** Whole days from today until the date; negative when past. */
export function daysUntil(value) {
    if (!value) {
        return null;
    }
    const ms = new Date(value).setHours(0, 0, 0, 0) - new Date().setHours(0, 0, 0, 0);
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
