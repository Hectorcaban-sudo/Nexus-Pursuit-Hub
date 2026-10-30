import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import LightningConfirm from 'lightning/confirm';
import getMySearches from '@salesforce/apex/NXP_SearchController.getMySearches';
import getSearch from '@salesforce/apex/NXP_SearchController.getSearch';
import previewSearch from '@salesforce/apex/NXP_SearchController.previewSearch';
import saveSearch from '@salesforce/apex/NXP_SearchController.saveSearch';
import deleteSearch from '@salesforce/apex/NXP_SearchController.deleteSearch';
import draftCriteria from '@salesforce/apex/NXP_SearchController.draftCriteria';
import {
    splitList,
    joinList,
    dueLabel,
    formatMoney,
    debounce,
    toast,
    toastError,
    reduceErrors,
    logUsage
} from 'c/nxpUtils';

const SET_ASIDES = ['Small Business', '8(a)', 'HUBZone', 'Service-Disabled', 'Women-Owned'];
const TYPES = [
    'Pre-solicitation',
    'Sources Sought',
    'Solicitation',
    'Combined Synopsis/Solicitation',
    'RFI',
    'Special Notice',
    'Award Notice',
    'Task Order',
    'Grant'
];
const opts = (values) => values.map((v) => ({ label: v, value: v }));

function emptyForm() {
    return {
        id: null,
        name: '',
        keywords: '',
        searchIn: ['title', 'description'],
        agencies: '',
        excludeAgencies: '',
        naics: '',
        psc: '',
        setAsides: [],
        noticeTypes: [],
        places: '',
        minValue: null,
        maxValue: null,
        dueWithinDays: null,
        postedWithinDays: null,
        minFit: null,
        visibility: 'Private',
        teamGroup: '',
        frequency: 'Daily',
        channels: ['Email', 'Salesforce'],
        alertOnChanges: true,
        autoPush: 'Off',
        autoPushMinFit: 70,
        active: true
    };
}

export default class NxpSearchBuilder extends NavigationMixin(LightningElement) {
    @track form = emptyForm();
    @track searches = [];
    preview;
    previewError;
    previewing = false;
    saving = false;
    drafting = false;
    nlText = '';

    setAsideOptions = opts(SET_ASIDES);
    typeOptions = opts(TYPES);
    searchInOptions = [
        { label: 'Title', value: 'title' },
        { label: 'Description', value: 'description' }
    ];
    visibilityOptions = opts(['Private', 'Team', 'Org Template']);
    frequencyOptions = opts(['Real Time', 'Daily', 'Weekly', 'None']);
    channelOptions = opts(['Email', 'Salesforce', 'Slack', 'Teams', 'Mobile']);
    autoPushOptions = opts(['Off', 'Fit Threshold', 'All Matches']);

    schedulePreview = debounce(() => this.runPreview(), 600);

    @wire(CurrentPageReference)
    pageRef(ref) {
        const id = ref && ref.state ? ref.state.c__searchId : null;
        if (id && id !== this.form.id) {
            this.loadSearch(id);
        }
    }

    connectedCallback() {
        logUsage('My Searches');
        this.loadSearches();
        this.runPreview();
    }

    async loadSearches() {
        try {
            this.searches = await getMySearches();
        } catch (e) {
            toastError(this, e, 'Could not load your searches');
        }
    }

    async loadSearch(searchId) {
        try {
            const s = await getSearch({ searchId });
            const c = s.Criteria_JSON__c ? JSON.parse(s.Criteria_JSON__c) : {};
            this.form = {
                ...emptyForm(),
                id: s.Id,
                name: s.Name,
                keywords: c.keywords || '',
                searchIn: c.searchIn && c.searchIn.length ? c.searchIn : ['title', 'description'],
                agencies: joinList(c.agencies),
                excludeAgencies: joinList(c.excludeAgencies),
                naics: joinList(c.naics),
                psc: joinList(c.psc),
                setAsides: c.setAsides || [],
                noticeTypes: c.noticeTypes || [],
                places: joinList(c.places),
                minValue: c.minValue,
                maxValue: c.maxValue,
                dueWithinDays: c.dueWithinDays,
                postedWithinDays: c.postedWithinDays,
                minFit: c.minFit,
                visibility: s.Visibility__c || 'Private',
                teamGroup: s.Team_Group__c || '',
                frequency: s.Alert_Frequency__c || 'Daily',
                channels: s.Channels__c ? s.Channels__c.split(';') : [],
                alertOnChanges: s.Alert_On_Changes__c,
                autoPush: s.Auto_Push__c || 'Off',
                autoPushMinFit: s.Auto_Push_Min_Fit__c || 70,
                active: s.Active__c
            };
            this.runPreview();
        } catch (e) {
            toastError(this, e, 'Could not open the search');
        }
    }

    /** Criteria JSON in the shape NXP_SearchCriteria expects; blank filters are left out. */
    get criteriaJson() {
        const f = this.form;
        const c = {};
        const list = (v) => {
            const a = splitList(v);
            return a.length ? a : undefined;
        };
        const num = (v) => (v === null || v === undefined || v === '' ? undefined : Number(v));
        c.keywords = f.keywords ? f.keywords.trim() : undefined;
        c.searchIn = f.searchIn.length === 2 ? undefined : f.searchIn;
        c.agencies = list(f.agencies);
        c.excludeAgencies = list(f.excludeAgencies);
        c.naics = list(f.naics);
        c.psc = list(f.psc);
        c.places = list(f.places);
        c.setAsides = f.setAsides.length ? f.setAsides : undefined;
        c.noticeTypes = f.noticeTypes.length ? f.noticeTypes : undefined;
        c.minValue = num(f.minValue);
        c.maxValue = num(f.maxValue);
        c.dueWithinDays = num(f.dueWithinDays);
        c.postedWithinDays = num(f.postedWithinDays);
        c.minFit = num(f.minFit);
        return JSON.stringify(c);
    }

    async runPreview() {
        this.previewing = true;
        this.previewError = null;
        try {
            this.preview = await previewSearch({ criteriaJson: this.criteriaJson });
        } catch (e) {
            this.previewError = reduceErrors(e).join(', ');
        } finally {
            this.previewing = false;
        }
    }

    // ---------------------------------------------------------------- view

    get title() {
        return this.form.id ? 'Edit search' : 'New search';
    }

    get countLabel() {
        if (!this.preview) {
            return '–';
        }
        return this.preview.capped ? `${this.preview.count}+` : `${this.preview.count}`;
    }

    get weeklyAverage() {
        return this.preview ? Math.round(this.preview.backtestTotal / 13) : 0;
    }

    get bars() {
        if (!this.preview) {
            return [];
        }
        const max = Math.max(1, ...this.preview.weekly);
        return this.preview.weekly.map((v, i) => ({
            key: `w${i}`,
            style: `height:${Math.max(2, Math.round((v / max) * 100))}%`,
            title: `${13 - i} week(s) ago: ${v}`
        }));
    }

    get topRows() {
        if (!this.preview) {
            return [];
        }
        return this.preview.top.map((n) => ({
            id: n.Id,
            title: n.Title__c || n.Name,
            fit: n.Fit_Score__c,
            meta: [
                n.Agency_Path__c,
                n.Notice_Type__c,
                n.Estimated_Value__c ? formatMoney(n.Estimated_Value__c) : null,
                dueLabel(n.Response_Due__c)
            ]
                .filter((x) => !!x)
                .join(' · ')
        }));
    }

    get hasTop() {
        return this.topRows.length > 0;
    }

    get showTeamGroup() {
        return this.form.visibility === 'Team';
    }

    get showMinFit() {
        return this.form.autoPush === 'Fit Threshold';
    }

    get searchRows() {
        return this.searches.map((s) => ({
            ...s,
            rowClass: s.id === this.form.id ? 'my-row my-row_active' : 'my-row',
            canDelete: s.mine
        }));
    }

    // ------------------------------------------------------------- handlers

    handleField(event) {
        const field = event.target.dataset.field;
        const value =
            event.target.type === 'checkbox' || event.target.type === 'toggle'
                ? event.target.checked
                : event.detail.value;
        this.form = { ...this.form, [field]: value };
        if (event.target.dataset.preview !== 'false') {
            this.schedulePreview();
        }
    }

    handleNl(event) {
        this.nlText = event.detail.value;
    }

    async handleDraft() {
        if (!this.nlText) {
            return;
        }
        this.drafting = true;
        try {
            const d = await draftCriteria({ text: this.nlText });
            const c = d.criteria || {};
            this.form = {
                ...this.form,
                keywords: c.keywords || '',
                agencies: joinList(c.agencies),
                naics: joinList(c.naics),
                setAsides: c.setAsides || [],
                noticeTypes: c.noticeTypes || [],
                minValue: c.minValue,
                maxValue: c.maxValue,
                dueWithinDays: c.dueWithinDays,
                frequency: d.frequency || this.form.frequency,
                name: this.form.name || this.nlText.substring(0, 60)
            };
            toast(this, 'Criteria drafted', d.summary, 'info');
            this.runPreview();
        } catch (e) {
            toastError(this, e, 'Could not draft criteria');
        } finally {
            this.drafting = false;
        }
    }

    handleNew() {
        this.form = emptyForm();
        this.runPreview();
    }

    handleEdit(event) {
        this.loadSearch(event.currentTarget.dataset.id);
    }

    async handleDelete(event) {
        const id = event.currentTarget.dataset.id;
        const ok = await LightningConfirm.open({
            message: 'Delete this saved search and its matches?',
            label: 'Delete search',
            theme: 'warning'
        });
        if (!ok) {
            return;
        }
        try {
            await deleteSearch({ searchId: id });
            if (this.form.id === id) {
                this.handleNew();
            }
            this.loadSearches();
        } catch (e) {
            toastError(this, e);
        }
    }

    async handleSave() {
        this.saving = true;
        const f = this.form;
        try {
            const id = await saveSearch({
                input: {
                    id: f.id,
                    name: f.name,
                    criteriaJson: this.criteriaJson,
                    visibility: f.visibility,
                    teamGroup: f.teamGroup,
                    frequency: f.frequency,
                    channels: f.channels,
                    alertOnChanges: f.alertOnChanges,
                    autoPush: f.autoPush,
                    autoPushMinFit: f.autoPushMinFit,
                    active: f.active
                }
            });
            this.form = { ...this.form, id };
            toast(
                this,
                'Search saved',
                `"${f.name}" will alert you ${f.frequency === 'None' ? 'in the inbox only' : f.frequency.toLowerCase()}.`
            );
            this.loadSearches();
        } catch (e) {
            toastError(this, e, 'Could not save');
        } finally {
            this.saving = false;
        }
    }

    handleOpenNotice(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.currentTarget.dataset.id,
                objectApiName: 'NXP_Gov_Notice__c',
                actionName: 'view'
            }
        });
    }
}
