import { createElement } from 'lwc';
import NxpPursuitChip from 'c/nxpPursuitChip';

const FACTORS = JSON.stringify([
    { label: 'Department', value: 'Homeland Security', pursued: 12, decided: 15, direction: 'up' },
    { label: 'Set-aside', value: '8(a)', pursued: 0, decided: 9, direction: 'down' }
]);

function mount(props) {
    const el = createElement('c-nxp-pursuit-chip', { is: NxpPursuitChip });
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

describe('c-nxp-pursuit-chip', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('shows nothing before the model has scored the notice', () => {
        const el = mount({ likelihood: null });
        expect(el.shadowRoot.querySelector('.chip')).toBeNull();
    });

    it('shows the likelihood with the factors in the tooltip', () => {
        const el = mount({ likelihood: 72, factors: FACTORS });
        const chip = el.shadowRoot.querySelector('.chip');
        expect(chip.textContent).toBe('Likely to pursue 72%');
        expect(chip.className).toContain('chip_high');
        expect(chip.title).toContain('Department: Homeland Security (pushed 12 of 15 before)');
        expect(el.shadowRoot.querySelector('.factors')).toBeNull();
    });

    it('lists the factors on the notice page', () => {
        const el = mount({ likelihood: 18, factors: FACTORS, detailed: true });
        expect(el.shadowRoot.querySelector('.chip').className).toContain('chip_low');
        const items = el.shadowRoot.querySelectorAll('.factors li');
        expect(items).toHaveLength(2);
        expect(items[1].querySelector('.arrow_down')).not.toBeNull();
        expect(el.shadowRoot.querySelector('.note').textContent).toContain('Not a win probability');
    });
});
