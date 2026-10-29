import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getForecastBoard from '@salesforce/apex/NXP_MarketController.getForecastBoard';
import watch from '@salesforce/apex/NXP_MarketController.watch';
import { debounce, formatDate, formatMoney, toast, toastError } from 'c/nxpUtils';

const SET_ASIDES = [
    { label: 'Any set-aside', value: '' },
    { label: 'Small business', value: 'Small Business' },
    { label: '8(a)', value: '8(a)' },
    { label: 'HUBZone', value: 'HUBZone' },
    { label: 'Service-disabled veteran-owned', value: 'Service-Disabled' },
    { label: 'Women-owned', value: 'Women-Owned' }
];

/** Expected solicitation date in words: "In 12 days", "Expected now", "Mar 2027". */
function whenLabel(card) {
    if (card.solicitationDate === null || card.solicitationDate === undefined) {
        return 'No date in the forecast';
    }
    const d = card.daysUntil;
    if (d < 0) {
        return 'Expected now (was ' + formatDate(card.solicitationDate) + ')';
    }
    if (d === 0) {
        return 'Expected today';
    }
    if (d <= 90) {
        return d === 1 ? 'In 1 day' : `In ${d} days`;
    }
    return 'Est. ' + formatDate(card.solicitationDate);
}

export default class NxpForecastBoard extends NavigationMixin(LightningElement) {
    board;
    loading = true;
    agency = '';
    naics = '';
    setAside = '';
    fiscalYear = '';
    profileOnly = true;
    setAsideOptions = SET_ASIDES;

    connectedCallback() {
        this.debouncedLoad = debounce(() => this.load(), 400);
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.board = await getForecastBoard({
                agency: this.agency,
                naics: this.naics,
                setAside: this.setAside,
                fiscalYear: this.fiscalYear,
                profileOnly: this.profileOnly
            });
        } catch (e) {
            toastError(this, e, 'Could not load forecasts');
        } finally {
            this.loading = false;
        }
    }

    get fiscalYearOptions() {
        const years = this.board ? this.board.fiscalYears : [];
        return [{ label: 'All fiscal years', value: '' }, ...years.map((y) => ({ label: y, value: y }))];
    }

    get kpis() {
        const b = this.board;
        if (!b) {
            return [];
        }
        return [
            { key: 'tracked', label: 'Forecasts tracked', value: b.tracked, note: 'matching the filters' },
            {
                key: 'next90',
                label: 'Expected in 90 days',
                value: b.next90,
                note: b.next90Value ? 'est. ' + formatMoney(b.next90Value) + ' total' : 'no values published'
            },
            { key: 'released', label: 'Released as notices', value: b.released, note: 'linked to their notice' },
            {
                key: 'watched',
                label: 'Watched by you',
                value: b.watched,
                note: b.watched ? 'alerts when released' : 'watch one to get alerts'
            }
        ];
    }

    get columns() {
        if (!this.board) {
            return [];
        }
        return this.board.columns
            .filter((c) => c.key !== 'later' || c.cards.length > 0)
            .map((c) => ({
                ...c,
                count: c.cards.length,
                empty: c.cards.length === 0,
                cards: c.cards.map((card) => ({
                    ...card,
                    agencyLabel: card.agency || 'Agency not given',
                    naicsLabel: card.naics ? 'NAICS ' + card.naics : 'No NAICS',
                    setAsideLabel: card.setAside || 'Set-aside not stated',
                    valueLabel: card.value ? formatMoney(card.value) : 'Value not published',
                    when: card.released ? 'Posted ' + formatDate(card.noticePosted) : whenLabel(card),
                    whenClass:
                        !card.released && card.daysUntil !== null && card.daysUntil <= 90 ? 'when when_soon' : 'when',
                    fitClass: card.profileMatch ? 'fit fit_yes' : 'fit',
                    watchLabel: card.watching ? 'Watching' : 'Watch',
                    watchVariant: card.watching ? 'brand' : 'neutral',
                    watchState: card.watching ? 'true' : 'false'
                }))
            }));
    }

    get nothingFound() {
        return !this.loading && this.board && this.board.tracked === 0;
    }

    handleFilter(event) {
        const name = event.target.dataset.filter;
        this[name] = event.target.type === 'checkbox' ? event.target.checked : event.detail.value;
        this.debouncedLoad();
    }

    handleOpen(event) {
        event.preventDefault();
        this.navigateTo(event.currentTarget.dataset.id);
    }

    navigateTo(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }

    handleNewSearch() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'NXP_Search_Builder' }
        });
    }

    async handleWatch(event) {
        const recordId = event.currentTarget.dataset.id;
        const watching = event.currentTarget.dataset.watching === 'true';
        try {
            await watch({ recordId, watch: !watching });
            toast(
                this,
                watching ? 'Stopped watching' : 'Watching this forecast',
                watching ? '' : 'You will get an alert when it is released as a notice.'
            );
            this.load();
        } catch (e) {
            toastError(this, e, 'Could not change the watch');
        }
    }
}
