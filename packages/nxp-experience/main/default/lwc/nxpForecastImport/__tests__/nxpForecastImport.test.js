import { createElement } from 'lwc';
import NxpForecastImport, { parseCsv, guessMapping, parseDate, parseValue } from 'c/nxpForecastImport';
import importForecasts from '@salesforce/apex/NXP_ForecastImportController.importForecasts';

jest.mock('@salesforce/apex/NXP_ForecastImportController.importForecasts', () => ({ default: jest.fn() }), {
    virtual: true
});

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const CSV =
    'Listing ID,Title,Department,Sub Agency,Estimated Solicitation Release Date,Estimated Contract Value,NAICS,Set Aside Type,Description\r\n' +
    'AG-1,"Tactical Cloud Operations, Support",Dept. of the Army,Army Contracting Command,Q2 FY2027,"$10M - $25M",541519,8(a),"Line one\nline two"\r\n' +
    'AG-2,Help Desk,Dept. of the Army,,3/29/2027,"$1,500,000",541513,,\r\n';

describe('c-nxp-forecast-import helpers', () => {
    it('parses quoted CSV', () => {
        const rows = parseCsv(CSV);
        expect(rows.length).toBe(3);
        expect(rows[1][1]).toBe('Tactical Cloud Operations, Support');
        expect(rows[1][8]).toBe('Line one\nline two');
    });

    it('guesses the columns from agency headers', () => {
        const m = guessMapping(parseCsv(CSV)[0]);
        expect(m).toEqual({
            forecastId: '0',
            title: '1',
            agency: '2',
            subAgency: '3',
            solicitationDate: '4',
            value: '5',
            naics: '6',
            setAside: '7',
            description: '8'
        });
    });

    it('reads agency date and value styles', () => {
        expect(parseDate('2027-03-29')).toBe('2027-03-29');
        expect(parseDate('3/29/2027')).toBe('2027-03-29');
        expect(parseDate('Q1 FY2027')).toBe('2026-10-01');
        expect(parseDate('FY27 Q3')).toBe('2027-04-01');
        expect(parseDate('March 2027')).toBe('2027-03-01');
        expect(parseDate('TBD')).toBeNull();
        expect(parseValue('$1,500,000')).toBe(1500000);
        expect(parseValue('$10M - $25M')).toBe(25000000);
        expect(parseValue('$250K')).toBe(250000);
        expect(parseValue('TBD')).toBeNull();
    });
});

describe('c-nxp-forecast-import', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('maps a file and imports it in batches', async () => {
        importForecasts.mockResolvedValue({ read: 2, created: 2, updated: 0, unchanged: 0, rejected: 0, problems: [] });
        const el = createElement('c-nxp-forecast-import', { is: NxpForecastImport });
        document.body.appendChild(el);
        const original = global.FileReader;
        global.FileReader = class {
            readAsText() {
                this.result = CSV;
                this.onload();
            }
        };
        const input = el.shadowRoot.querySelector('lightning-input.file');
        Object.defineProperty(input, 'files', { value: [{ name: 'forecast_export.csv' }] });
        input.dispatchEvent(new CustomEvent('change'));
        await flush();
        global.FileReader = original;

        expect(el.shadowRoot.textContent).toContain('2 rows in forecast_export.csv');
        expect(el.shadowRoot.textContent).toContain('Q2 FY2027 → 2027-01-01');
        el.shadowRoot.querySelector('lightning-button.import').click();
        await flush();
        await flush();
        const args = importForecasts.mock.calls[0][0];
        expect(args.sourceName).toBe('Acquisition Gateway');
        const sent = JSON.parse(args.rowsJson);
        expect(sent[0]).toMatchObject({
            forecastId: 'AG-1',
            agency: 'Dept. of the Army',
            subAgency: 'Army Contracting Command',
            solicitationDate: '2027-01-01',
            value: 25000000,
            naics: '541519'
        });
        expect(el.shadowRoot.textContent).toContain('2 new, 0 updated, 0 unchanged, 0 skipped');
    });

    it('asks for CSV when given an Excel file', async () => {
        const el = createElement('c-nxp-forecast-import', { is: NxpForecastImport });
        document.body.appendChild(el);
        const input = el.shadowRoot.querySelector('lightning-input.file');
        Object.defineProperty(input, 'files', { value: [{ name: 'forecast.xlsx' }] });
        input.dispatchEvent(new CustomEvent('change'));
        await flush();
        expect(el.shadowRoot.textContent).toContain('save as CSV');
    });
});
