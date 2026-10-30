import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import previewPush from '@salesforce/apex/NXP_PushController.previewPush';
import pushNoticeFrom from '@salesforce/apex/NXP_PushController.pushNoticeFrom';
import { reduceErrors } from 'c/nxpUtils';

/**
 * Push to Opportunity dialog. Open with:
 *   const result = await NxpPushDialog.open({ noticeId, size: 'medium', label: 'Push to Opportunity' });
 * Resolves to the push result, or undefined when cancelled.
 */
export default class NxpPushDialog extends LightningModal {
    @api noticeId;
    /** Where the dialog was opened from, recorded on the push log: Match Inbox or Notice Page. */
    @api source = 'Notice Page';

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

    /** Read documents disagree with the notice and nobody has marked it checked. */
    get checksText() {
        const n = this.preview ? this.preview.openChecks : 0;
        if (!n) {
            return '';
        }
        return `The solicitation documents disagree with this notice on ${n} point${n === 1 ? '' : 's'} (for example the due date). Check them on the notice page; the values below come from the notice.`;
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
            const result = await pushNoticeFrom({
                noticeId: this.noticeId,
                includeDocuments: this.includeDocuments,
                source: this.source
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
