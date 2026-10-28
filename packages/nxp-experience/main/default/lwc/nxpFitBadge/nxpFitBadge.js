import { LightningElement, api } from 'lwc';
import { fitTier } from 'c/nxpUtils';

export default class NxpFitBadge extends LightningElement {
    @api score;
    @api size = 'medium';

    get display() {
        return this.score === null || this.score === undefined ? '–' : Math.round(this.score);
    }

    get badgeClass() {
        return `badge tier_${fitTier(this.score)} size_${this.size}`;
    }

    get assistiveText() {
        return this.score === null || this.score === undefined ? 'Not scored' : `Fit score ${this.display} out of 100`;
    }
}
