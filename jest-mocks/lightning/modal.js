/* Jest stub for lightning/modal (LightningModal base class). */
import { LightningElement, api } from 'lwc';

export default class LightningModal extends LightningElement {
    @api size;
    @api label;
    @api description;

    static open = jest.fn(() => Promise.resolve());

    close(result) {
        this.closeResult = result;
    }
}
