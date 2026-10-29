import { createElement } from 'lwc';
import NxpVehiclePortfolio from 'c/nxpVehiclePortfolio';
import getVehiclePortfolio from '@salesforce/apex/NXP_VehicleController.getVehiclePortfolio';
import setHeld from '@salesforce/apex/NXP_VehicleController.setHeld';
import watch from '@salesforce/apex/NXP_MarketController.watch';

jest.mock('@salesforce/apex/NXP_VehicleController.getVehiclePortfolio', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/NXP_VehicleController.setHeld', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/NXP_MarketController.watch', () => ({ default: jest.fn() }), { virtual: true });

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

/** Local calendar date n days from today as "YYYY-MM-DD" (the shape Apex sends). */
function isoDate(n) {
    const d = new Date();
    d.setDate(d.getDate() + n);
    const pad = (x) => String(x).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function inDays(n) {
    return new Date(Date.now() + n * 86400000).toISOString();
}

const notice = (over) => ({
    id: 'a01000000000006',
    title: 'Continuous Diagnostics Dashboard Integration',
    noticeKey: 'SAMPLE-0006',
    noticeType: 'Solicitation',
    agency: 'Homeland Security › USCIS',
    responseDue: inDays(40),
    fitScore: 73,
    pushed: false,
    following: false,
    ...over
});

const vehicle = (over) => ({
    id: 'a05000000000001',
    name: 'OASIS+ (sample)',
    code: 'OASIS+',
    held: true,
    heldByProfile: false,
    ceiling: null,
    expiryDate: isoDate(1500),
    daysLeft: 1500,
    inboxAddress: 'oasis@example.com',
    open: 1,
    dueIn30: 0,
    pushed: 0,
    taskOrders30: 0,
    notices: [notice()],
    ...over
});

const PORTFOLIO = {
    held: [
        vehicle(),
        vehicle({
            id: 'a05000000000002',
            name: 'GSA MAS IT (sample)',
            code: 'GSA-MAS-IT',
            expiryDate: isoDate(330),
            daysLeft: 330,
            inboxAddress: null,
            dueIn30: 1,
            notices: [
                notice({ id: 'a01000000000007', title: 'Enterprise Help Desk Services', responseDue: inDays(15) })
            ]
        })
    ],
    notHeld: [
        vehicle({
            id: 'a05000000000003',
            name: 'CIO-SP4 (sample)',
            code: 'CIO-SP4',
            held: false,
            notices: [notice({ id: 'a01000000000005', title: 'Network Segmentation Pilot', following: true })]
        })
    ],
    openOnHeld: 2,
    dueIn30: 1,
    expiringSoon: 1,
    blockedNotices: 1,
    inboxesSet: 1,
    taskOrders30: 0,
    lastTaskOrder: null,
    otherVehicles: 0,
    vehicleRuleActive: false,
    canManage: true
};

function mount() {
    const el = createElement('c-nxp-vehicle-portfolio', { is: NxpVehiclePortfolio });
    document.body.appendChild(el);
    return el;
}

describe('c-nxp-vehicle-portfolio', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows totals, a card per held vehicle and the vehicles you lack', async () => {
        getVehiclePortfolio.mockResolvedValue(PORTFOLIO);
        const el = mount();
        await flush();

        const kpis = [...el.shadowRoot.querySelectorAll('.kpi')].map((k) => k.textContent);
        expect(kpis[0]).toContain('Vehicles you hold');
        expect(kpis[0]).toContain('1 expires within 12 months');
        expect(kpis[2]).toContain("on 1 vehicle you don't hold");
        expect(kpis[3]).toContain('1 of 2');

        const cards = el.shadowRoot.querySelectorAll('.vehicle');
        expect(cards.length).toBe(2);
        expect(cards[1].textContent).toContain('Expires in 11 months');
        expect(cards[1].textContent).toContain('No task-order inbox');
        expect(cards[1].querySelector('.due').textContent).toBe('Due in 15 days');
        expect(cards[1].querySelector('.due').className).toContain('due_soon');
        expect(cards[0].textContent).toContain('Ceiling not on file');

        const gaps = el.shadowRoot.querySelectorAll('.gap');
        expect(gaps.length).toBe(1);
        expect(gaps[0].textContent).toContain('CIO-SP4 (sample)');
        expect(gaps[0].querySelector('.follow').label).toBe('Following');
        expect(el.shadowRoot.querySelector('.note')).not.toBeNull();
    });

    it('marks a vehicle as held and reloads', async () => {
        getVehiclePortfolio.mockResolvedValue(PORTFOLIO);
        setHeld.mockResolvedValue('CIO-SP4 (sample) marked as held.');
        const el = mount();
        await flush();

        el.shadowRoot.querySelector('.mark-held').click();
        await flush();
        expect(setHeld).toHaveBeenCalledWith({ vehicleId: 'a05000000000003', held: true });
        expect(getVehiclePortfolio).toHaveBeenCalledTimes(2);
    });

    it('unfollows a notice', async () => {
        getVehiclePortfolio.mockResolvedValue(PORTFOLIO);
        watch.mockResolvedValue(false);
        const el = mount();
        await flush();

        el.shadowRoot.querySelector('.follow').click();
        await flush();
        expect(watch).toHaveBeenCalledWith({ recordId: 'a01000000000005', watch: false });
    });

    it('hides admin actions and explains an empty portfolio', async () => {
        getVehiclePortfolio.mockResolvedValue({
            ...PORTFOLIO,
            held: [],
            notHeld: [],
            openOnHeld: 0,
            blockedNotices: 0,
            inboxesSet: 0,
            canManage: false,
            vehicleRuleActive: true
        });
        const el = mount();
        await flush();

        expect(el.shadowRoot.querySelector('.empty').textContent).toContain('No vehicles are recorded as held');
        expect(el.shadowRoot.querySelector('.ok')).not.toBeNull();
        expect(el.shadowRoot.querySelector('.mark-held')).toBeNull();
        expect(el.shadowRoot.querySelector('.note')).toBeNull();
        const buttons = [...el.shadowRoot.querySelectorAll('lightning-button')].map((b) => b.label);
        expect(buttons).not.toContain('Add a vehicle');
    });
});
