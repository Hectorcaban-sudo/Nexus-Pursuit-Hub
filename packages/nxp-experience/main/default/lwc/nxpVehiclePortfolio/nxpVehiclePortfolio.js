import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getVehiclePortfolio from '@salesforce/apex/NXP_VehicleController.getVehiclePortfolio';
import setHeld from '@salesforce/apex/NXP_VehicleController.setHeld';
import watch from '@salesforce/apex/NXP_MarketController.watch';
import { dueLabel, daysUntil, formatDate, formatMoney, toast, toastError } from 'c/nxpUtils';

const VEHICLE_OBJECT = 'NXP_Contract_Vehicle__c';

/** "Expires in 11 months", "Expires in 20 days", "Expired Mar 3, 2026", "No expiry date on file". */
function expiryLabel(v) {
    if (v.daysLeft === null || v.daysLeft === undefined) {
        return 'No expiry date on file';
    }
    if (v.daysLeft < 0) {
        return 'Expired ' + formatDate(v.expiryDate);
    }
    if (v.daysLeft <= 60) {
        return v.daysLeft === 1 ? 'Expires tomorrow' : `Expires in ${v.daysLeft} days`;
    }
    if (v.daysLeft <= 365) {
        const months = Math.round(v.daysLeft / 30.4);
        return `Expires in ${months} months`;
    }
    return 'Expires ' + formatDate(v.expiryDate);
}

function expiryClass(v) {
    if (v.daysLeft === null || v.daysLeft === undefined) {
        return 'chip';
    }
    if (v.daysLeft < 0) {
        return 'chip chip_bad';
    }
    return v.daysLeft <= 365 ? 'chip chip_warn' : 'chip';
}

function plural(n, one, many) {
    return n === 1 ? `1 ${one}` : `${n} ${many}`;
}

function noticeRow(n) {
    const due = daysUntil(n.responseDue);
    return {
        ...n,
        meta: [n.noticeType, n.agency, n.noticeKey].filter((p) => !!p).join(' · '),
        due: dueLabel(n.responseDue),
        dueClass: due !== null && due <= 30 ? 'due due_soon' : 'due',
        followLabel: n.following ? 'Following' : 'Follow',
        followVariant: n.following ? 'brand' : 'neutral',
        followState: n.following ? 'true' : 'false'
    };
}

export default class NxpVehiclePortfolio extends NavigationMixin(LightningElement) {
    portfolio;
    loading = true;
    busy = false;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.portfolio = await getVehiclePortfolio();
        } catch (e) {
            toastError(this, e, 'Could not load contract vehicles');
        } finally {
            this.loading = false;
        }
    }

    get canManage() {
        return !!(this.portfolio && this.portfolio.canManage);
    }

    get kpis() {
        const p = this.portfolio;
        if (!p) {
            return [];
        }
        return [
            {
                key: 'held',
                label: 'Vehicles you hold',
                value: p.held.length,
                note: p.expiringSoon
                    ? plural(p.expiringSoon, 'expires', 'expire') + ' within 12 months'
                    : 'none expiring within 12 months',
                valueClass: 'kpi-value'
            },
            {
                key: 'open',
                label: 'Open notices on them',
                value: p.openOnHeld,
                note: p.dueIn30 ? p.dueIn30 + ' due in the next 30 days' : 'none due in the next 30 days',
                valueClass: 'kpi-value'
            },
            {
                key: 'blocked',
                label: "Notices you can't bid alone",
                value: p.blockedNotices,
                note: p.notHeld.length
                    ? 'on ' + plural(p.notHeld.length, "vehicle you don't hold", "vehicles you don't hold")
                    : 'every open vehicle notice is on one you hold',
                valueClass: p.blockedNotices ? 'kpi-value kpi-value_warn' : 'kpi-value'
            },
            {
                key: 'inbox',
                label: 'Task-order inboxes',
                value: p.inboxesSet + ' of ' + p.held.length,
                note: 'set up on vehicles you hold',
                valueClass: 'kpi-value'
            }
        ];
    }

    get held() {
        if (!this.portfolio) {
            return [];
        }
        return this.portfolio.held.map((v) => ({
            ...v,
            codeLine: ['Code ' + v.code, v.ceiling ? 'Ceiling ' + formatMoney(v.ceiling) : 'Ceiling not on file']
                .filter((p) => !!p)
                .join(' · '),
            expiry: expiryLabel(v),
            expiryClass: expiryClass(v),
            inbox: v.inboxAddress ? 'Task-order inbox set up' : 'No task-order inbox',
            inboxClass: v.inboxAddress ? 'chip chip_ok' : 'chip chip_warn',
            heldNote: v.heldByProfile ? 'Listed in the Company Profile' : '',
            canRelease: this.canManage && !v.heldByProfile,
            hasNotices: v.notices.length > 0,
            more: v.open > v.notices.length ? `Showing ${v.notices.length} of ${v.open} open notices` : '',
            notices: v.notices.map(noticeRow)
        }));
    }

    get noneHeld() {
        return !this.loading && this.portfolio && this.portfolio.held.length === 0;
    }

    get gaps() {
        if (!this.portfolio) {
            return [];
        }
        return this.portfolio.notHeld.map((v) => ({
            ...v,
            count: plural(v.open, 'notice', 'notices'),
            notices: v.notices.map(noticeRow)
        }));
    }

    get noGaps() {
        return !this.loading && this.portfolio && this.portfolio.notHeld.length === 0;
    }

    get taskOrders30() {
        return this.portfolio ? this.portfolio.taskOrders30 : 0;
    }

    get lastTaskOrder() {
        return this.portfolio && this.portfolio.lastTaskOrder
            ? formatDate(this.portfolio.lastTaskOrder, true)
            : 'None in the last 30 days';
    }

    get showRuleNote() {
        return !!(this.portfolio && !this.portfolio.vehicleRuleActive);
    }

    handleOpen(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' }
        });
    }

    handleAllVehicles() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: VEHICLE_OBJECT, actionName: 'list' },
            state: { filterName: 'Recent' }
        });
    }

    handleNewVehicle() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: VEHICLE_OBJECT, actionName: 'new' }
        });
    }

    async handleHeld(event) {
        const vehicleId = event.currentTarget.dataset.id;
        const held = event.currentTarget.dataset.held === 'true';
        this.busy = true;
        try {
            const message = await setHeld({ vehicleId, held });
            toast(this, held ? 'Vehicle marked as held' : 'Vehicle marked as not held', message);
            await this.load();
        } catch (e) {
            toastError(this, e, 'Could not change the vehicle');
        } finally {
            this.busy = false;
        }
    }

    async handleFollow(event) {
        const recordId = event.currentTarget.dataset.id;
        const following = event.currentTarget.dataset.following === 'true';
        try {
            await watch({ recordId, watch: !following });
            toast(
                this,
                following ? 'Stopped following' : 'Following this notice',
                following ? '' : 'You will get an alert when it changes.'
            );
            await this.load();
        } catch (e) {
            toastError(this, e, 'Could not change the follow');
        }
    }
}
