import { createElement } from 'lwc';
import NxpFeedConsole from 'c/nxpFeedConsole';
import getConsole from '@salesforce/apex/NXP_FeedConsoleController.getConsole';

jest.mock('@salesforce/apex/NXP_FeedConsoleController.getConsole', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_FeedConsoleController.runNow', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_FeedConsoleController.getRunErrors', () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('c-nxp-feed-console', () => {
    it('renders a tile per feed with health and a scheduler warning', async () => {
        getConsole.mockResolvedValue({
            canRun: true,
            schedulerActive: false,
            feeds: [
                {
                    name: 'SAM_Opportunities',
                    label: 'SAM.gov Opportunities',
                    channel: 'Standard Pipeline',
                    active: true,
                    intervalMinutes: 60,
                    health: 'Healthy',
                    lastRun: {
                        Id: 'r1',
                        Records_Read__c: 10,
                        Records_Created__c: 4,
                        Records_Updated__c: 1,
                        Records_Rejected__c: 0,
                        Started__c: new Date().toISOString()
                    }
                },
                {
                    name: 'USAspending_Awards',
                    label: 'USAspending Awards',
                    channel: 'Scheduled Batch',
                    active: false,
                    intervalMinutes: 10080,
                    health: 'Paused'
                }
            ],
            runs: [
                {
                    Id: 'r1',
                    Feed_Name__c: 'SAM_Opportunities',
                    Channel__c: 'Standard Pipeline',
                    Status__c: 'Succeeded',
                    Started__c: new Date().toISOString()
                }
            ]
        });
        const el = createElement('c-nxp-feed-console', { is: NxpFeedConsole });
        document.body.appendChild(el);
        await flush();
        const tiles = el.shadowRoot.querySelectorAll('.tile');
        expect(tiles.length).toBe(2);
        expect(tiles[0].querySelector('.status').className).toContain('status_ok');
        expect(tiles[1].querySelector('.channel').textContent).toContain('weekly');
        expect(el.shadowRoot.querySelector('.banner')).not.toBeNull();
    });
});
