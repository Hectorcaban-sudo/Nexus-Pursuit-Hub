import { createElement } from 'lwc';
import NxpAdminSettings from 'c/nxpAdminSettings';
import getSettings from '@salesforce/apex/NXP_SettingsController.getSettings';
import getHealth from '@salesforce/apex/NXP_SettingsController.getHealth';
import saveSettings from '@salesforce/apex/NXP_SettingsController.saveSettings';
import rescheduleJobs from '@salesforce/apex/NXP_SettingsController.rescheduleJobs';
import reapplySettings from '@salesforce/apex/NXP_SettingsController.reapplySettings';

jest.mock('@salesforce/apex/NXP_SettingsController.getSettings', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SettingsController.getHealth', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SettingsController.saveSettings', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SettingsController.getSaveStatus', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SettingsController.testSamKey', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SettingsController.rescheduleJobs', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SettingsController.reapplySettings', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_SettingsController.rescoreNotices', () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const MODEL = {
    aiCallsToday: 12,
    canDeploy: true,
    history: [
        {
            label: 'Problems e-mail',
            oldValue: 'Problems',
            newValue: 'Daily',
            status: 'Saved',
            changedBy: 'Ana Admin',
            changed: '2026-10-29T14:05:00.000Z'
        }
    ],
    sections: [
        {
            key: 'alerts',
            label: 'Alerts and e-mail',
            help: 'How people are told.',
            items: [
                {
                    id: 'NXP_Setting.Admin_Digest_Mode',
                    label: 'Problems e-mail',
                    type: 'Picklist',
                    value: 'Problems',
                    defaultValue: 'Problems',
                    options: [
                        { label: 'Problems', value: 'Problems' },
                        { label: 'Daily', value: 'Daily' },
                        { label: 'Off', value: 'Off' }
                    ]
                }
            ]
        },
        {
            key: 'ai',
            label: 'AI',
            help: 'Prompt templates and limits.',
            items: [
                { id: 'NXP_Setting.AI_Enabled', label: 'AI on', type: 'Boolean', value: 'true', releaseManaged: true },
                { id: 'NXP_Setting.AI_Max_Calls_Per_Day', label: 'Daily AI limit', type: 'Integer', value: '500' }
            ]
        }
    ]
};

const HEALTH = [
    { key: 'mail', title: 'E-mail delivery', status: 'ok', detail: 'All email' },
    {
        key: 'jobs',
        title: 'Scheduled jobs',
        status: 'warn',
        detail: '6 of 7',
        action: 'reschedule',
        actionLabel: 'Reschedule'
    }
];

async function mount() {
    getSettings.mockResolvedValue(JSON.parse(JSON.stringify(MODEL)));
    getHealth.mockResolvedValue(HEALTH);
    const el = createElement('c-nxp-admin-settings', { is: NxpAdminSettings });
    document.body.appendChild(el);
    await flush();
    await flush();
    return el;
}

const rows = (el) => el.shadowRoot.querySelectorAll('.row');
const saveBar = (el) => el.shadowRoot.querySelector('.save-bar');

describe('c-nxp-admin-settings', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows the sections, the open section, health checks and history', async () => {
        const el = await mount();
        expect(el.shadowRoot.querySelectorAll('.nav-item')).toHaveLength(2);
        expect(rows(el)).toHaveLength(1);
        expect(el.shadowRoot.querySelectorAll('.check')).toHaveLength(2);
        expect(el.shadowRoot.querySelector('.history-text').textContent).toContain('Problems → Daily');
        expect(saveBar(el)).toBeNull();
    });

    it('opens a section, shows AI usage and the release badge', async () => {
        const el = await mount();
        el.shadowRoot.querySelectorAll('.nav-item')[1].click();
        await flush();
        expect(rows(el)).toHaveLength(2);
        expect(el.shadowRoot.querySelector('.usage').textContent).toBe('12 of 500 AI calls used today');
        expect(el.shadowRoot.querySelector('.tag_release')).not.toBeNull();
    });

    it('finds settings across sections', async () => {
        const el = await mount();
        const filter = el.shadowRoot.querySelector('.filter');
        filter.dispatchEvent(new CustomEvent('change', { detail: { value: 'limit' } }));
        await flush();
        expect(rows(el)).toHaveLength(1);
        expect(el.shadowRoot.querySelector('.row-label').textContent).toContain('Daily AI limit');
    });

    it('tracks a change, discards it, and saves changes', async () => {
        const el = await mount();
        const combo = el.shadowRoot.querySelector('lightning-combobox');
        combo.dispatchEvent(new CustomEvent('change', { detail: { value: 'Daily' } }));
        await flush();
        expect(saveBar(el).textContent).toContain('1 unsaved change');
        expect(el.shadowRoot.querySelector('.tag_changed')).not.toBeNull();

        el.shadowRoot.querySelector('.discard').click();
        await flush();
        expect(saveBar(el)).toBeNull();

        el.shadowRoot
            .querySelector('lightning-combobox')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'Off' } }));
        await flush();
        saveSettings.mockResolvedValue('test');
        el.shadowRoot.querySelector('.save').click();
        await flush();
        await flush();
        await flush();
        expect(saveSettings).toHaveBeenCalledWith({
            changes: [{ id: 'NXP_Setting.Admin_Digest_Mode', value: 'Off' }]
        });
        expect(getSettings).toHaveBeenCalledTimes(2);
    });

    it('runs a health check action', async () => {
        const el = await mount();
        rescheduleJobs.mockResolvedValue(7);
        el.shadowRoot.querySelector('.check-action').click();
        await flush();
        await flush();
        expect(rescheduleJobs).toHaveBeenCalled();
        expect(getHealth).toHaveBeenCalledTimes(2);
    });

    it('reapplies settings a release put back', async () => {
        getHealth.mockResolvedValue([
            {
                key: 'saved',
                title: 'Settings saved here',
                status: 'warn',
                detail: '1 setting(s) were put back',
                action: 'reapply',
                actionLabel: 'Reapply my settings'
            }
        ]);
        getSettings.mockResolvedValue(JSON.parse(JSON.stringify(MODEL)));
        const el = createElement('c-nxp-admin-settings', { is: NxpAdminSettings });
        document.body.appendChild(el);
        await flush();
        await flush();
        reapplySettings.mockResolvedValue('test');
        el.shadowRoot.querySelector('.check-action').click();
        await flush();
        await flush();
        await flush();
        expect(reapplySettings).toHaveBeenCalled();
        expect(getSettings).toHaveBeenCalledTimes(2);
    });

    it('shows an error when loading fails', async () => {
        getSettings.mockRejectedValue({ body: { message: 'Only Nexus admins can change settings.' } });
        getHealth.mockResolvedValue([]);
        const el = createElement('c-nxp-admin-settings', { is: NxpAdminSettings });
        document.body.appendChild(el);
        await flush();
        await flush();
        expect(el.shadowRoot.querySelector('.error').textContent).toContain('Only Nexus admins');
    });
});
