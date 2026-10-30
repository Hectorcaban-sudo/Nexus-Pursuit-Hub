/* Jest stub for lightning/modal (LightningModal base class). */
import { LightningElement, api } from 'lwc';

export default class LightningModal extends LightningElement {
    @api size;
    @api label;
    @api description;

    static open = jest.fn(() => Promise.resolve());

    /** Tests can listen for "modalclose" to see what the modal resolved to. */
    close(result) {
        this.closeResult = result;
        this.dispatchEvent(new CustomEvent('modalclose', { detail: result }));
    }
}
