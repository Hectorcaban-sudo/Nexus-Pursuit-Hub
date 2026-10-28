import { createElement } from 'lwc';
import NxpFitBadge from 'c/nxpFitBadge';

describe('c-nxp-fit-badge', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('shows the score with the matching tier', () => {
        const el = createElement('c-nxp-fit-badge', { is: NxpFitBadge });
        el.score = 86;
        document.body.appendChild(el);
        const badge = el.shadowRoot.querySelector('.badge');
        expect(badge.className).toContain('tier_high');
        expect(badge.className).toContain('size_medium');
        expect(el.shadowRoot.querySelector('.value').textContent).toBe('86');
    });

    it('shows a dash when not scored', () => {
        const el = createElement('c-nxp-fit-badge', { is: NxpFitBadge });
        el.size = 'small';
        document.body.appendChild(el);
        expect(el.shadowRoot.querySelector('.value').textContent).toBe('–');
        expect(el.shadowRoot.querySelector('.badge').className).toContain('tier_none');
    });
});
