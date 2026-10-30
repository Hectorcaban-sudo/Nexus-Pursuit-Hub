import { LightningElement, api } from 'lwc';
import { fitReasons } from 'c/nxpUtils';

/** Up to three chips explaining a fit score: the two biggest gains and the biggest loss. */
export default class NxpFitReasons extends LightningElement {
    /** Fit_Breakdown__c JSON text, or the parsed list of rule results. */
    @api breakdown;
    @api score;
    /** Shows "All rules" when the parent can open the full breakdown. */
    @api showAll = false;

    get reasons() {
        return fitReasons(this.breakdown);
    }

    get hasReasons() {
        return this.reasons.length > 0;
    }

    get lead() {
        return this.score === null || this.score === undefined ? 'Why' : `Why ${Math.round(this.score)}`;
    }

    handleAll(event) {
        event.preventDefault();
        this.dispatchEvent(new CustomEvent('showall'));
    }
}
