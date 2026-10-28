import { createElement } from 'lwc';
import NxpPushDialog from 'c/nxpPushDialog';
import previewPush from '@salesforce/apex/NXP_PushController.previewPush';

jest.mock('@salesforce/apex/NXP_PushController.previewPush', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_PushController.pushNotice', () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-nxp-push-dialog', () => {
    it('renders the mapped values and the duplicate warning', async () => {
        previewPush.mockResolvedValue({
            noticeTitle: 'Zero Trust',
            targetObject: 'Opportunity',
            existingRecordId: '006000000000001',
            existingRecordName: 'Already tracked',
            documentCount: 2,
            fields: [{ field: 'Name', label: 'Opportunity Name', value: 'Zero Trust', required: true, sync: 'No' }]
        });
        const el = createElement('c-nxp-push-dialog', { is: NxpPushDialog });
        el.noticeId = 'n1';
        document.body.appendChild(el);
        await flush();
        expect(el.shadowRoot.querySelector('.banner_warn').textContent).toContain('Already tracked');
        expect(el.shadowRoot.querySelectorAll('tbody tr').length).toBe(1);
    });
});
