import { LightningElement, api } from 'lwc';

/**
 * Likely to Pursue: the chance BD pursues a notice, learned from past pushes and dismissals,
 * with the factors that moved it most. Not a win probability.
 */
export default class NxpPursuitChip extends LightningElement {
    @api likelihood;
    /** JSON from Pursuit_Factors__c. */
    @api factors;
    /** Show the factor list under the chip (notice page) instead of only a tooltip (inbox). */
    @api detailed = false;

    get hasValue() {
        return this.likelihood !== null && this.likelihood !== undefined && this.likelihood !== '';
    }

    get chipClass() {
        const v = Number(this.likelihood);
        if (v >= 60) {
            return 'chip chip_high';
        }
        if (v >= 30) {
            return 'chip chip_mid';
        }
        return 'chip chip_low';
    }

    get label() {
        return `Likely to pursue ${Math.round(Number(this.likelihood))}%`;
    }

    get factorList() {
        let list = [];
        try {
            list = this.factors ? JSON.parse(this.factors) : [];
        } catch (e) {
            list = [];
        }
        return list.map((f, i) => ({
            key: `f${i}`,
            arrow: f.direction === 'down' ? '↓' : '↑',
            arrowClass: f.direction === 'down' ? 'arrow arrow_down' : 'arrow arrow_up',
            text: `${f.label}: ${f.value}`,
            history: `pushed ${f.pursued} of ${f.decided} before`
        }));
    }

    get hasFactors() {
        return this.factorList.length > 0;
    }

    get tooltip() {
        const lines = this.factorList.map((f) => `${f.arrow} ${f.text} (${f.history})`);
        return ['Learned from what BD pushed and dismissed before. Not a win probability.', ...lines].join('\n');
    }
}
