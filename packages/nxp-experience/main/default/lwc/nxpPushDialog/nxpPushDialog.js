import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import previewPush from '@salesforce/apex/NXP_PushController.previewPush';
import pushNotice from '@salesforce/apex/NXP_PushController.pushNotice';
import { reduceErrors } from 'c/nxpUtils';

/**
 * Push to TechnoMile dialog. Open with:
 *   const result = await NxpPushDialog.open({ noticeId, size: 'medium', label: 'Push to TechnoMile' });
 * Resolves to the push result, or undefined when cancelled.
 */
export default class NxpPushDialog extends LightningModal {
    @api noticeId;

    preview;
    error;
    loading = true;
    pushing = false;
    includeDocuments = true;

    connectedCallback() {
        previewPush({ noticeId: this.noticeId })
            .then((result) => {
                this.preview = result;
            })
            .catch((e) => {
                this.error = reduceErrors(e).join(', ');
            })
            .finally(() => {
                this.loading = false;
            });
    }

    get fields() {
        return this.preview ? this.preview.fields : [];
    }

    get hasExisting() {
        return this.preview && !!this.preview.existingRecordId;
    }

    get bannerClass() {
        return this.hasExisting ? 'banner banner_warn' : 'banner banner_ok';
    }

    get bannerText() {
        if (!this.preview) {
            return '';
        }
        if (this.preview.alreadyPushed) {
            return 'This notice was already pushed. Pushing again opens the existing record.';
        }
        if (this.preview.existingRecordId) {
            return `A matching ${this.preview.targetObject} record already exists (${this.preview.existingRecordName || this.preview.existingRecordId}). It will be linked instead of creating a duplicate.`;
        }
        return `No existing ${this.preview.targetObject} record found. A new one will be created.`;
    }

    get documentLabel() {
        const n = this.preview ? this.preview.documentCount : 0;
        return `Link the ${n} solicitation document${n === 1 ? '' : 's'} to the record`;
    }

    get pushLabel() {
        return this.hasExisting ? 'Link record' : 'Push opportunity';
    }

    get disablePush() {
        return this.loading || this.pushing || !!this.error;
    }

    handleDocuments(event) {
        this.includeDocuments = event.target.checked;
    }

    handleCancel() {
        this.close();
    }

    async handlePush() {
        this.pushing = true;
        try {
            const result = await pushNotice({
                noticeId: this.noticeId,
                ownerId: null,
                includeDocuments: this.includeDocuments
            });
            if (result.status === 'Failed') {
                this.error = result.message;
                this.pushing = false;
                return;
            }
            this.close(result);
        } catch (e) {
            this.error = reduceErrors(e).join(', ');
            this.pushing = false;
        }
    }
}
