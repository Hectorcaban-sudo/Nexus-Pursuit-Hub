import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSettings from '@salesforce/apex/NXP_SettingsController.getSettings';
import getHealth from '@salesforce/apex/NXP_SettingsController.getHealth';
import saveSettings from '@salesforce/apex/NXP_SettingsController.saveSettings';
import getSaveStatus from '@salesforce/apex/NXP_SettingsController.getSaveStatus';
import testSamKey from '@salesforce/apex/NXP_SettingsController.testSamKey';
import rescheduleJobs from '@salesforce/apex/NXP_SettingsController.rescheduleJobs';
import rescoreNotices from '@salesforce/apex/NXP_SettingsController.rescoreNotices';
import { formatDate, toast, toastError, logUsage } from 'c/nxpUtils';

const POLL_MS = 3000;
const POLL_TRIES = 40;
const MARK = { ok: '✓', warn: '!', fail: '✕' };

/** Settings tab: every Nexus setting in one place, saved as a custom metadata deployment. */
export default class NxpAdminSettings extends NavigationMixin(LightningElement) {
    model;
    @track health = [];
    @track edits = {};
    sectionKey = 'alerts';
    filter = '';
    loading = true;
    saving = false;
    savingNote = '';
    error;

    connectedCallback() {
        logUsage('Settings');
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            const [model, health] = await Promise.all([getSettings(), getHealth()]);
            this.model = model;
            this.health = health;
            this.error = undefined;
        } catch (e) {
            this.error = e && e.body && e.body.message ? e.body.message : 'Could not load the settings.';
        } finally {
            this.loading = false;
        }
    }

    // ------------------------------------------------------------------ view model

    valueOf(item) {
        return Object.prototype.hasOwnProperty.call(this.edits, item.id) ? this.edits[item.id] : item.value;
    }

    isChanged(item) {
        return Object.prototype.hasOwnProperty.call(this.edits, item.id) && this.edits[item.id] !== (item.value || '');
    }

    get sections() {
        if (!this.model) {
            return [];
        }
        return this.model.sections
            .filter((s) => s.items.length > 0)
            .map((s) => {
                const changed = s.items.filter((i) => this.isChanged(i)).length;
                return {
                    ...s,
                    badge: changed ? `${changed} changed` : '',
                    navClass: s.key === this.sectionKey && !this.filter ? 'nav-item nav-item_active' : 'nav-item'
                };
            });
    }

    get current() {
        return this.sections.find((s) => s.key === this.sectionKey);
    }

    /** Items of the open section, or every match of the filter, grouped by sub-heading. */
    get groups() {
        if (!this.model) {
            return [];
        }
        const needle = this.filter.toLowerCase();
        let items = [];
        if (needle) {
            this.model.sections.forEach((s) =>
                s.items
                    .filter((i) =>
                        `${i.subgroup || ''} ${i.label} ${i.help || ''} ${i.id}`.toLowerCase().includes(needle)
                    )
                    .forEach((i) => items.push({ ...i, subgroup: i.subgroup || s.label }))
            );
        } else if (this.current) {
            items = this.current.items;
        }
        const groups = [];
        items.forEach((i) => {
            const name = i.subgroup || '';
            let g = groups.find((x) => x.name === name);
            if (!g) {
                g = { name, key: `g-${groups.length}`, hasName: !!name, items: [] };
                groups.push(g);
            }
            const value = this.valueOf(i);
            const changed = this.isChanged(i);
            g.items.push({
                ...i,
                key: i.id,
                current: value,
                checked: value === 'true',
                isBoolean: i.type === 'Boolean',
                isInteger: i.type === 'Integer',
                isText: i.type === 'Text',
                isPicklist: i.type === 'Picklist',
                changed,
                rowClass: changed ? 'row row_changed' : 'row',
                isDefault: i.defaultValue !== undefined && i.defaultValue !== null && value === i.defaultValue
            });
        });
        return groups;
    }

    get sectionTitle() {
        if (this.filter) {
            return `Settings matching "${this.filter}"`;
        }
        return this.current ? this.current.label : '';
    }

    get sectionHelp() {
        return this.filter ? '' : this.current ? this.current.help : '';
    }

    get isAi() {
        return this.sectionKey === 'ai' && !this.filter;
    }

    get aiUsage() {
        if (!this.model) {
            return '';
        }
        const limitItem = this.model.sections
            .flatMap((s) => s.items)
            .find((i) => i.id === 'NXP_Setting.AI_Max_Calls_Per_Day');
        const limit = limitItem ? Number(limitItem.value) : 0;
        return limit > 0
            ? `${this.model.aiCallsToday} of ${limit} AI calls used today`
            : `${this.model.aiCallsToday} AI calls today (no limit)`;
    }

    get changeCount() {
        if (!this.model) {
            return 0;
        }
        return this.model.sections.flatMap((s) => s.items).filter((i) => this.isChanged(i)).length;
    }

    get hasChanges() {
        return this.changeCount > 0;
    }

    get changeSummary() {
        return this.changeCount === 1 ? '1 unsaved change' : `${this.changeCount} unsaved changes`;
    }

    get checks() {
        return this.health.map((c) => ({
            ...c,
            mark: MARK[c.status] || '?',
            markClass: `mark mark_${c.status}`,
            hasAction: !!c.action
        }));
    }

    get history() {
        return this.model
            ? this.model.history.map((h, i) => ({
                  ...h,
                  key: `h${i}`,
                  text: `${h.label}: ${h.oldValue || '(blank)'} → ${h.newValue || '(blank)'}`,
                  meta: `${h.changedBy} · ${formatDate(h.changed, true)} · ${h.status}`,
                  failed: h.status === 'Failed'
              }))
            : [];
    }

    get hasHistory() {
        return this.history.length > 0;
    }

    // ------------------------------------------------------------------ handlers

    handleSection(event) {
        this.sectionKey = event.currentTarget.dataset.key;
        this.filter = '';
    }

    handleFilter(event) {
        this.filter = (event.detail.value || '').trim();
    }

    handleValue(event) {
        const id = event.target.dataset.id;
        const value =
            event.target.type === 'toggle' || event.target.type === 'checkbox'
                ? String(event.target.checked)
                : event.detail.value === undefined || event.detail.value === null
                  ? ''
                  : String(event.detail.value);
        this.edits = { ...this.edits, [id]: value };
    }

    handleDiscard() {
        this.edits = {};
    }

    async handleSave() {
        const changes = this.model.sections
            .flatMap((s) => s.items)
            .filter((i) => this.isChanged(i))
            .map((i) => ({ id: i.id, value: this.edits[i.id] }));
        this.saving = true;
        this.savingNote = 'Saving… this takes about 30 seconds.';
        try {
            const jobId = await saveSettings({ changes });
            const result = await this.waitFor(jobId);
            if (result.status === 'Saved') {
                toast(this, 'Settings saved', `${changes.length} change(s) are in effect.`);
                this.edits = {};
                await this.load();
            } else if (result.status === 'Failed') {
                toast(this, 'Settings not saved', result.detail || 'The deployment failed.', 'error');
            } else {
                toast(
                    this,
                    'Still saving',
                    'The save is taking longer than usual. Check History in a minute.',
                    'warning'
                );
            }
        } catch (e) {
            toastError(this, e, 'Settings not saved');
        } finally {
            this.saving = false;
            this.savingNote = '';
        }
    }

    async waitFor(jobId) {
        if (jobId === 'test') {
            return { status: 'Saved' };
        }
        for (let i = 0; i < POLL_TRIES; i++) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation, no-await-in-loop
            await new Promise((resolve) => setTimeout(resolve, POLL_MS));
            // eslint-disable-next-line no-await-in-loop
            const r = await getSaveStatus({ deployId: jobId });
            if (r.status !== 'Pending') {
                return r;
            }
        }
        return { status: 'Pending' };
    }

    async handleCheckAction(event) {
        const action = event.currentTarget.dataset.action;
        try {
            if (action === 'testKey') {
                toast(this, 'SAM.gov key', await testSamKey());
            } else if (action === 'reschedule') {
                const n = await rescheduleJobs();
                toast(this, 'Jobs rescheduled', `${n} Nexus jobs are scheduled, as you.`);
            } else if (action === 'rescore') {
                await rescoreNotices();
                toast(this, 'Rescoring', 'Open notices are being re-scored in the background.');
            } else if (action && action.startsWith('/')) {
                this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url: action } });
                return;
            }
            this.health = await getHealth();
        } catch (e) {
            toastError(this, e);
        }
    }
}
