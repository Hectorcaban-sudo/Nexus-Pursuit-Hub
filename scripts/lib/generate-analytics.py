"""Generates packages/nxp-analytics: report types, reports, dashboards (Salesforce metadata, API 68.0)."""
import os, sys
from xml.sax.saxutils import escape as esc
ROOT = sys.argv[1] + '/packages/nxp-analytics/main/default'
H = '<?xml version="1.0" encoding="UTF-8" ?>\n'
NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'

def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w').write(text)

# ------------------------------------------------------------------------------------ report types
RT = {
    'NXP_Notices': ('NXP_Gov_Notice__c', 'NXP Notices', 'Gov Notices with source, fit, due date and push status.', [
        ('Notices', 'NXP_Gov_Notice__c', ['Name', 'Notice_Id__c', 'Title__c', 'Notice_Type__c', 'Status__c', 'Source_Feed__c',
            'Agency_Path__c', 'Office__c', 'NAICS_Code__c', 'Set_Aside__c', 'Fit_Score__c', 'Fit_Band__c', 'Response_Due__c',
            'Days_To_Respond__c', 'Posted_Date__c', 'Pushed__c', 'Contract_Vehicle_Code__c', 'Solicitation_Number__c', 'CreatedDate'])], None),
    'NXP_Searches_And_Matches': ('NXP_Saved_Search__c', 'NXP Saved Searches with Matches', 'Saved searches and the notices they matched, with what the user did.', [
        ('Saved Searches', 'NXP_Saved_Search__c', ['Name', 'Owner_Name__c', 'Alert_Frequency__c', 'Auto_Push__c', 'Visibility__c', 'Active__c']),
        ('Matches', 'NXP_Saved_Search__c.Matches__r', ['Name', 'User_Action__c', 'Change_Type__c', 'Alert_Status__c', 'Gov_Notice__c', 'CreatedDate'])], 'Matches__r'),
    'NXP_Saved_Searches': ('NXP_Saved_Search__c', 'NXP Saved Searches', 'Saved searches by owner.', [
        ('Saved Searches', 'NXP_Saved_Search__c', ['Name', 'Owner_Name__c', 'Alert_Frequency__c', 'Auto_Push__c', 'Visibility__c', 'Active__c', 'CreatedDate'])], None),
    'NXP_Push_Logs': ('NXP_Push_Log__c', 'NXP Push Logs', 'Each push to TechnoMile and each sync.', [
        ('Push Logs', 'NXP_Push_Log__c', ['Name', 'Gov_Notice__c', 'Status__c', 'Mode__c', 'Source__c', 'Target_Object__c', 'Target_Record_Id__c', 'Pushed_By__c', 'Attempts__c', 'Error__c', 'CreatedDate'])], None),
    'NXP_Feed_Runs': ('NXP_Feed_Run__c', 'NXP Feed Runs', 'Feed runs and import calls with their counts.', [
        ('Feed Runs', 'NXP_Feed_Run__c', ['Name', 'Feed_Name__c', 'Channel__c', 'Status__c', 'Started__c', 'Finished__c', 'Records_Read__c', 'Records_Created__c', 'Records_Updated__c', 'Records_Rejected__c', 'Caller__c'])], None),
    'NXP_Inbound_Emails': ('NXP_Inbound_Email__c', 'NXP Inbound Emails', 'E-mail received by the eBuy inbox (admins only).', [
        ('Inbound Emails', 'NXP_Inbound_Email__c', ['Name', 'Received__c', 'From_Address__c', 'Subject__c', 'Status__c', 'RFQ_Number__c', 'Contract_Vehicle__c', 'Gov_Notice__c', 'Extraction_Method__c', 'Attachment_Count__c'])], None),
    'NXP_Document_Analyses': ('NXP_Document_Analysis__c', 'NXP Document Analyses', 'What the Document Reader read from notice files.', [
        ('Document Analyses', 'NXP_Document_Analysis__c', ['Name', 'Gov_Notice__c', 'File_Name__c', 'Status__c', 'Status_Detail__c', 'Analyzed__c', 'CreatedDate'])], None),
    'NXP_Logs': ('NXP_Log__c', 'NXP Logs', 'Application log entries.', [
        ('Logs', 'NXP_Log__c', ['Name', 'Level__c', 'Source__c', 'Message__c', 'Record_Id__c', 'CreatedDate'])], None),
    'NXP_Usage': ('NXP_Usage__c', 'NXP Usage', 'Which users opened Nexus screens each week (admins only).', [
        ('Usage', 'NXP_Usage__c', ['Name', 'User__c', 'Week__c', 'Views__c', 'Screens__c', 'Last_Screen__c'])], None),
    'NXP_GovWin_Alerts': ('NXP_GovWin_Alert__c', 'NXP GovWin Alerts', 'GovWin alerts from the parallel run and whether Nexus caught them.', [
        ('GovWin Alerts', 'NXP_GovWin_Alert__c', ['Name', 'GovWin_Id__c', 'Title__c', 'Solicitation_Number__c', 'Agency__c', 'Alert_Date__c', 'Result__c', 'Search_Matches__c', 'Gov_Notice__c', 'Compared__c'])], None),
}
for name, (base, label, desc, sections, join) in RT.items():
    x = H + f'<ReportType {NS}>\n    <baseObject>{base}</baseObject>\n    <category>other</category>\n    <deployed>true</deployed>\n    <description>{esc(desc)}</description>\n'
    if join:
        x += f'    <join>\n        <outerJoin>false</outerJoin>\n        <relationship>{join}</relationship>\n    </join>\n'
    x += f'    <label>{esc(label)}</label>\n'
    for slabel, table, cols in sections:
        x += '    <sections>\n'
        for c in cols:
            x += f'        <columns>\n            <checkedByDefault>false</checkedByDefault>\n            <field>{c}</field>\n            <table>{table}</table>\n        </columns>\n'
        x += f'        <masterLabel>{esc(slabel)}</masterLabel>\n    </sections>\n'
    x += '</ReportType>\n'
    w(f'{ROOT}/reportTypes/{name}.reportType-meta.xml', x)

# ---------------------------------------------------------------------------------------- reports
FOLDERS = {'NXP_Reports': 'Nexus Pursuit Hub', 'NXP_Admin_Reports': 'Nexus Admin'}
for f, n in FOLDERS.items():
    w(f'{ROOT}/reports/{f}.reportFolder-meta.xml', H + f'<ReportFolder {NS}>\n    <name>{n}</name>\n</ReportFolder>\n')

def B(rt):
    return RT[rt][0]

REPORTS = []
def report(folder, name, label, rt, desc, fmt='Summary', down=(), across=(), columns=(), filters=(), time=None, details=False, aggregates=()):
    """down/across: (field, granularity|None); filters: (field, operator, value); time: (field, interval)."""
    REPORTS.append((folder, name))
    x = H + f'<Report {NS}>\n'
    cols = list(columns)
    for c in cols:
        x += f'    <columns>\n        <field>{c}</field>\n    </columns>\n'
    for c, agg in aggregates:
        x += f'    <columns>\n        <aggregateTypes>{agg}</aggregateTypes>\n        <field>{c}</field>\n    </columns>\n'
    x += f'    <description>{esc(desc)}</description>\n'
    if filters:
        x += '    <filter>\n'
        for col, op, val in filters:
            x += f'        <criteriaItems>\n            <column>{col}</column>\n            <isUnlocked>true</isUnlocked>\n            <operator>{op}</operator>\n            <value>{esc(val)}</value>\n        </criteriaItems>\n'
        x += '    </filter>\n'
    x += f'    <format>{fmt}</format>\n'
    for field, gran in across:
        x += '    <groupingsAcross>\n' + (f'        <dateGranularity>{gran}</dateGranularity>\n' if gran else '') + f'        <field>{field}</field>\n        <sortOrder>Asc</sortOrder>\n    </groupingsAcross>\n'
    for field, gran in down:
        x += '    <groupingsDown>\n' + (f'        <dateGranularity>{gran}</dateGranularity>\n' if gran else '') + f'        <field>{field}</field>\n        <sortOrder>Asc</sortOrder>\n    </groupingsDown>\n'
    x += f'    <name>{esc(label)}</name>\n'
    x += '    <params>\n        <name>co</name>\n        <value>1</value>\n    </params>\n'
    x += f'    <reportType>{rt}__c</reportType>\n    <scope>organization</scope>\n    <showDetails>{"true" if details else "false"}</showDetails>\n'
    x += '    <showGrandTotal>true</showGrandTotal>\n    <showSubTotals>true</showSubTotals>\n'
    if time:
        x += f'    <timeFrameFilter>\n        <dateColumn>{time[0]}</dateColumn>\n        <interval>{time[1]}</interval>\n    </timeFrameFilter>\n'
    x += '</Report>\n'
    w(f'{ROOT}/reports/{folder}/{name}.report-meta.xml', x)

N = 'NXP_Gov_Notice__c$'
SM = 'NXP_Saved_Search__c$'
M = 'NXP_Saved_Search__c.Matches__r$'
P = 'NXP_Push_Log__c$'
F = 'NXP_Feed_Run__c$'
E = 'NXP_Inbound_Email__c$'
D = 'NXP_Document_Analysis__c$'
L = 'NXP_Log__c$'
U = 'NXP_Usage__c$'
G = 'NXP_GovWin_Alert__c$'

# Market and activity (Nexus Pursuit Hub folder)
R = 'NXP_Reports'
report(R, 'NXP_New_Notices_By_Week_Source', 'NXP - New notices by week and source', 'NXP_Notices', 'Notices created in the last 60 days, by week and source feed.', 'Matrix',
       down=[(N + 'CreatedDate', 'Week')], across=[(N + 'Source_Feed__c', None)], columns=[N + 'Name'], time=(N + 'CreatedDate', 'INTERVAL_LAST60'))
report(R, 'NXP_New_Notices_30_Days', 'NXP - New notices, last 30 days', 'NXP_Notices', 'Notices created in the last 30 days, by type.',
       down=[(N + 'Notice_Type__c', None)], columns=[N + 'Name', N + 'Fit_Score__c'], time=(N + 'CreatedDate', 'INTERVAL_LAST30'))
report(R, 'NXP_New_Notices_By_Fit_Band', 'NXP - New notices by fit band', 'NXP_Notices', 'Notices created in the last 30 days, by fit score band.',
       down=[(N + 'Fit_Band__c', None)], columns=[N + 'Name'], time=(N + 'CreatedDate', 'INTERVAL_LAST30'))
report(R, 'NXP_About_To_Miss', 'NXP - High-fit notices due soon, not pushed', 'NXP_Notices', 'Active notices with fit 60 or more, due in the next 14 days, not pushed to TechnoMile.',
       down=[(N + 'Title__c', None)], columns=[N + 'Notice_Id__c', N + 'Agency_Path__c', N + 'Response_Due__c', N + 'Fit_Score__c'],
       filters=[(N + 'Status__c', 'equals', 'Active'), (N + 'Fit_Score__c', 'greaterOrEqual', '60'), (N + 'Pushed__c', 'equals', '0'),
                (N + 'Response_Due__c', 'equals', 'NEXT_N_DAYS:14')], details=True)
report(R, 'NXP_Ebuy_By_Vehicle', 'NXP - eBuy RFQs by vehicle', 'NXP_Notices', 'GSA eBuy RFQs received in the last 90 days, by contract vehicle.',
       down=[(N + 'Contract_Vehicle_Code__c', None)], columns=[N + 'Notice_Id__c', N + 'Title__c', N + 'Response_Due__c'],
       filters=[(N + 'Source_Feed__c', 'equals', 'EMAIL_GSA_eBuy')], time=(N + 'CreatedDate', 'INTERVAL_LAST90'), details=True)
report(R, 'NXP_Match_Outcomes', 'NXP - Match outcomes', 'NXP_Searches_And_Matches', 'Search matches in the last 30 days by what the user did (none, watching, dismissed, pushed).',
       down=[(M + 'User_Action__c', None)], columns=[M + 'Name'], time=(M + 'CreatedDate', 'INTERVAL_LAST30'))
report(R, 'NXP_Matches_By_Search', 'NXP - Matches by saved search', 'NXP_Searches_And_Matches', 'Matches in the last 30 days per saved search, and how many were pushed.',
       down=[(SM + 'Name', None)], across=[(M + 'User_Action__c', None)], fmt='Matrix', columns=[M + 'Name'], time=(M + 'CreatedDate', 'INTERVAL_LAST30'))
report(R, 'NXP_Pushes_By_Month', 'NXP - Pushes by month and source', 'NXP_Push_Logs', 'Successful pushes to TechnoMile by month and where they started.', 'Matrix',
       down=[(P + 'CreatedDate', 'Month')], across=[(P + 'Source__c', None)], columns=[P + 'Name'],
       filters=[(P + 'Status__c', 'equals', 'Success,Linked Existing'), (P + 'Mode__c', 'notEqual', 'Sync'), (P + 'CreatedDate', 'equals', 'LAST_N_MONTHS:6')])
report(R, 'NXP_Pushes_30_Days', 'NXP - Pushes, last 30 days', 'NXP_Push_Logs', 'Successful pushes in the last 30 days, by mode.',
       down=[(P + 'Mode__c', None)], columns=[P + 'Name'],
       filters=[(P + 'Status__c', 'equals', 'Success,Linked Existing'), (P + 'Mode__c', 'notEqual', 'Sync')], time=(P + 'CreatedDate', 'INTERVAL_LAST30'))

# Operations and adoption (Nexus Admin folder)
A = 'NXP_Admin_Reports'
report(A, 'NXP_Feed_Runs_By_Feed', 'NXP Admin - Feed runs by feed', 'NXP_Feed_Runs', 'Feed runs in the last 7 days, by feed and status.', 'Matrix',
       down=[(F + 'Feed_Name__c', None)], across=[(F + 'Status__c', None)], columns=[F + 'Name'], time=(F + 'Started__c', 'INTERVAL_LAST7'))
report(A, 'NXP_Feed_Failures_7_Days', 'NXP Admin - Failed feed runs, last 7 days', 'NXP_Feed_Runs', 'Failed feed runs in the last 7 days.',
       down=[(F + 'Feed_Name__c', None)], columns=[F + 'Name', F + 'Started__c'], filters=[(F + 'Status__c', 'equals', 'Failed')], time=(F + 'Started__c', 'INTERVAL_LAST7'), details=True)
report(A, 'NXP_Records_Per_Day', 'NXP Admin - Records loaded per day', 'NXP_Feed_Runs', 'Records read, created, updated and rejected per day, last 7 days.',
       down=[(F + 'Started__c', 'Day')], columns=[F + 'Name'],
       aggregates=[(F + 'Records_Read__c', 'Sum'), (F + 'Records_Created__c', 'Sum'), (F + 'Records_Updated__c', 'Sum'), (F + 'Records_Rejected__c', 'Sum')],
       time=(F + 'Started__c', 'INTERVAL_LAST7'))
report(A, 'NXP_Push_Results', 'NXP Admin - Push results', 'NXP_Push_Logs', 'Pushes and syncs in the last 30 days, by status.',
       down=[(P + 'Status__c', None)], columns=[P + 'Name'], time=(P + 'CreatedDate', 'INTERVAL_LAST30'))
report(A, 'NXP_Push_Failures', 'NXP Admin - Push failures, last 7 days', 'NXP_Push_Logs', 'Failed pushes and syncs in the last 7 days, with the error.',
       down=[(P + 'Mode__c', None)], columns=[P + 'Gov_Notice__c', P + 'Error__c', P + 'CreatedDate'], filters=[(P + 'Status__c', 'equals', 'Failed')],
       time=(P + 'CreatedDate', 'INTERVAL_LAST7'), details=True)
report(A, 'NXP_Inbound_Emails_By_Status', 'NXP Admin - Inbound emails by status', 'NXP_Inbound_Emails', 'eBuy inbox e-mail in the last 30 days, by status.',
       down=[(E + 'Status__c', None)], columns=[E + 'Name'], time=(E + 'Received__c', 'INTERVAL_LAST30'))
report(A, 'NXP_Emails_Needing_Review', 'NXP Admin - Inbound emails needing review', 'NXP_Inbound_Emails', 'eBuy e-mails marked Needs Review or Failed.',
       down=[(E + 'Status__c', None)], columns=[E + 'Subject__c', E + 'From_Address__c', E + 'Received__c'], filters=[(E + 'Status__c', 'equals', 'Needs Review,Failed')], details=True)
report(A, 'NXP_Documents_By_Status', 'NXP Admin - Document analyses by status', 'NXP_Document_Analyses', 'Files registered in the last 30 days, by Document Reader status.',
       down=[(D + 'Status__c', None)], columns=[D + 'Name'], time=(D + 'CreatedDate', 'INTERVAL_LAST30'))
report(A, 'NXP_Log_By_Day', 'NXP Admin - Log entries by day', 'NXP_Logs', 'Errors, warnings and info entries per day, last 7 days.', 'Matrix',
       down=[(L + 'CreatedDate', 'Day')], across=[(L + 'Level__c', None)], columns=[L + 'Name'], time=(L + 'CreatedDate', 'INTERVAL_LAST7'))
report(A, 'NXP_Recent_Errors', 'NXP Admin - Recent errors', 'NXP_Logs', 'Error entries in the last 7 days, by source.',
       down=[(L + 'Source__c', None)], columns=[L + 'Message__c', L + 'CreatedDate'], filters=[(L + 'Level__c', 'equals', 'ERROR')],
       time=(L + 'CreatedDate', 'INTERVAL_LAST7'), details=True)
report(A, 'NXP_Active_Users_By_Week', 'NXP Admin - Active users by week', 'NXP_Usage', 'Users who opened a Nexus screen, per week (one usage row per user per week).',
       down=[(U + 'Week__c', 'Week')], columns=[U + 'User__c'], aggregates=[(U + 'Views__c', 'Sum')], time=(U + 'Week__c', 'INTERVAL_LAST60'))
report(A, 'NXP_Active_Users_This_Week', 'NXP Admin - Active users this week', 'NXP_Usage', 'Users who opened a Nexus screen this week.',
       down=[(U + 'User__c', None)], columns=[U + 'Screens__c'], aggregates=[(U + 'Views__c', 'Sum')], filters=[(U + 'Week__c', 'equals', 'THIS_WEEK')])
report(A, 'NXP_Activity_By_User', 'NXP Admin - Activity by user', 'NXP_Usage', 'Screen views per user over the last 30 days.',
       down=[(U + 'User__c', None)], columns=[U + 'Week__c'], aggregates=[(U + 'Views__c', 'Sum')], time=(U + 'Week__c', 'INTERVAL_LAST30'))
report(A, 'NXP_Searches_By_User', 'NXP Admin - Saved searches by user', 'NXP_Saved_Searches', 'Active saved searches per owner.',
       down=[(SM + 'Owner_Name__c', None)], columns=[SM + 'Name'], filters=[(SM + 'Active__c', 'equals', '1')])
report(A, 'NXP_Pushes_By_Source', 'NXP Admin - Where pushes come from', 'NXP_Push_Logs', 'Successful pushes in the last 30 days, by where they started.',
       down=[(P + 'Source__c', None)], columns=[P + 'Name'],
       filters=[(P + 'Status__c', 'equals', 'Success,Linked Existing'), (P + 'Mode__c', 'notEqual', 'Sync')], time=(P + 'CreatedDate', 'INTERVAL_LAST30'))
report(A, 'NXP_GovWin_Catch_Rate', 'NXP Admin - GovWin parallel run', 'NXP_GovWin_Alerts', 'GovWin alerts by whether Nexus caught them (Caught by a search, In Nexus no search matched, Not in Nexus).',
       down=[(G + 'Result__c', None)], columns=[G + 'Title__c', G + 'Solicitation_Number__c', G + 'Alert_Date__c'], details=True)
report(A, 'NXP_GovWin_Caught', 'NXP Admin - GovWin alerts caught by a search', 'NXP_GovWin_Alerts', 'GovWin alerts that matched a Nexus saved search.',
       down=[(G + 'Result__c', None)], columns=[G + 'Title__c'], filters=[(G + 'Result__c', 'equals', 'Caught by a search')])
report(A, 'NXP_GovWin_All', 'NXP Admin - GovWin alerts loaded', 'NXP_GovWin_Alerts', 'All GovWin alerts loaded for the parallel run.',
       down=[(G + 'Result__c', None)], columns=[G + 'Title__c'])

# ------------------------------------------------------------------------------------- dashboards
for f, n in {'NXP_Dashboards': 'Nexus Pursuit Hub', 'NXP_Admin_Dashboards': 'Nexus Admin'}.items():
    w(f'{ROOT}/dashboards/{f}.dashboardFolder-meta.xml', H + f'<DashboardFolder {NS}>\n    <name>{n}</name>\n</DashboardFolder>\n')

def comp(row, col, rowspan, colspan, ctype, report, title, sort='RowLabelAscending', summary=None, extra=''):
    x = '        <dashboardGridComponents>\n'
    x += f'            <colSpan>{colspan}</colSpan>\n            <columnIndex>{col}</columnIndex>\n            <dashboardComponent>\n'
    if summary:
        agg, column, grouping = summary
        x += '                <autoselectColumnsFromReport>false</autoselectColumnsFromReport>\n'
    else:
        x += '                <autoselectColumnsFromReport>true</autoselectColumnsFromReport>\n'
    if ctype not in ('Metric', 'Table'):
        x += '                <chartAxisRange>Auto</chartAxisRange>\n'
    if summary:
        x += f'                <chartSummary>\n                    <aggregate>{agg}</aggregate>\n                    <axisBinding>y</axisBinding>\n                    <column>{column}</column>\n                </chartSummary>\n'
    x += f'                <componentType>{ctype}</componentType>\n'
    x += '                <displayUnits>Auto</displayUnits>\n'
    if summary:
        x += f'                <groupingColumn>{grouping}</groupingColumn>\n'
    x += f'                <header>{esc(title)}</header>\n'
    if ctype in ('Metric', 'Table'):
        # Required for metric, gauge and table components (colors for the low/middle/high ranges).
        x += '                <indicatorHighColor>#54C254</indicatorHighColor>\n'
        x += '                <indicatorLowColor>#C25454</indicatorLowColor>\n'
        x += '                <indicatorMiddleColor>#C2C254</indicatorMiddleColor>\n'
    if ctype in ('Bar', 'Column', 'ColumnStacked', 'Donut', 'BarStacked'):
        x += '                <legendPosition>Bottom</legendPosition>\n'
    x += extra
    x += f'                <report>{report}</report>\n'
    if ctype not in ('Metric', 'Table'):
        x += '                <showPercentage>false</showPercentage>\n'
        if ctype == 'Donut':
            x += '                <showTotal>true</showTotal>\n'
        x += '                <showValues>true</showValues>\n'
    if ctype not in ('Metric',):
        x += f'                <sortBy>{sort}</sortBy>\n'
    x += '                <useReportChart>false</useReportChart>\n'
    x += f'            </dashboardComponent>\n            <rowIndex>{row}</rowIndex>\n            <rowSpan>{rowspan}</rowSpan>\n        </dashboardGridComponents>\n'
    return x

def dashboard(folder, name, title, desc, comps):
    x = H + f'<Dashboard {NS}>\n'
    x += '    <backgroundEndColor>#FFFFFF</backgroundEndColor>\n    <backgroundFadeDirection>Diagonal</backgroundFadeDirection>\n    <backgroundStartColor>#FFFFFF</backgroundStartColor>\n'
    x += '    <chartTheme>light</chartTheme>\n    <colorPalette>unity</colorPalette>\n    <dashboardChartTheme>light</dashboardChartTheme>\n    <dashboardColorPalette>unity</dashboardColorPalette>\n'
    x += '    <dashboardGridLayout>\n' + ''.join(comps) + '        <numberOfColumns>12</numberOfColumns>\n        <rowHeight>36</rowHeight>\n    </dashboardGridLayout>\n'
    x += f'    <dashboardType>LoggedInUser</dashboardType>\n    <description>{esc(desc)}</description>\n    <isGridLayout>true</isGridLayout>\n'
    x += f'    <textColor>#000000</textColor>\n    <title>{esc(title)}</title>\n    <titleColor>#000000</titleColor>\n    <titleSize>12</titleSize>\n</Dashboard>\n'
    w(f'{ROOT}/dashboards/{folder}/{name}.dashboard-meta.xml', x)

r = lambda n: 'NXP_Reports/' + n
a = lambda n: 'NXP_Admin_Reports/' + n
dashboard('NXP_Dashboards', 'NXP_Market_Activity', 'Nexus: Market and activity', 'New notices, matches, pushes to TechnoMile, fit, high-fit notices about to be missed, eBuy RFQs. Shows the data the viewer can see.', [
    comp(0, 0, 4, 3, 'Metric', r('NXP_New_Notices_30_Days'), 'New notices (30 days)'),
    comp(0, 3, 4, 3, 'Metric', r('NXP_Match_Outcomes'), 'Search matches (30 days)'),
    comp(0, 6, 4, 3, 'Metric', r('NXP_Pushes_30_Days'), 'Pushed to TechnoMile (30 days)'),
    comp(0, 9, 4, 3, 'Metric', r('NXP_About_To_Miss'), 'High-fit, due in 14 days, not pushed'),
    comp(4, 0, 8, 6, 'ColumnStacked', r('NXP_New_Notices_By_Week_Source'), 'New notices per week, by source'),
    comp(4, 6, 8, 6, 'Bar', r('NXP_Match_Outcomes'), 'What happened to matches (30 days)', 'RowValueDescending'),
    comp(12, 0, 8, 6, 'ColumnStacked', r('NXP_Pushes_By_Month'), 'Pushes to TechnoMile per month'),
    comp(12, 6, 8, 6, 'Bar', r('NXP_New_Notices_By_Fit_Band'), 'Fit score of new notices (30 days)'),
    comp(20, 0, 8, 6, 'Table', r('NXP_About_To_Miss'), 'About to miss: fit 60+, due in 14 days, not pushed'),
    comp(20, 6, 8, 6, 'Bar', r('NXP_Ebuy_By_Vehicle'), 'eBuy RFQs per vehicle (90 days)', 'RowValueDescending'),
    comp(28, 0, 8, 12, 'BarStacked', r('NXP_Matches_By_Search'), 'Matches per saved search, by outcome (30 days)', 'RowValueDescending'),
])
dashboard('NXP_Admin_Dashboards', 'NXP_Operations', 'Nexus: Operations', 'Feed health, records loaded, push results, eBuy inbox, Document Reader and errors. For Nexus admins.', [
    comp(0, 0, 4, 3, 'Metric', a('NXP_Feed_Failures_7_Days'), 'Failed feed runs (7 days)'),
    comp(0, 3, 4, 3, 'Metric', a('NXP_Push_Failures'), 'Push failures (7 days)'),
    comp(0, 6, 4, 3, 'Metric', a('NXP_Emails_Needing_Review'), 'eBuy e-mails needing review'),
    comp(0, 9, 4, 3, 'Metric', a('NXP_Recent_Errors'), 'Errors logged (7 days)'),
    comp(4, 0, 8, 12, 'BarStacked', a('NXP_Feed_Runs_By_Feed'), 'Feed runs by feed and status (7 days)'),
    comp(12, 0, 8, 6, 'Column', a('NXP_Records_Per_Day'), 'Records read per day', summary=('Sum', 'NXP_Feed_Run__c$Records_Read__c', 'NXP_Feed_Run__c$Started__c')),
    comp(12, 6, 8, 6, 'Donut', a('NXP_Push_Results'), 'Push results (30 days)'),
    comp(20, 0, 8, 6, 'Donut', a('NXP_Inbound_Emails_By_Status'), 'eBuy inbox by status (30 days)'),
    comp(20, 6, 8, 6, 'Donut', a('NXP_Documents_By_Status'), 'Document Reader (30 days)'),
    comp(28, 0, 8, 6, 'ColumnStacked', a('NXP_Log_By_Day'), 'Log entries per day'),
    comp(28, 6, 8, 6, 'Table', a('NXP_Recent_Errors'), 'Errors by source (7 days)', 'RowValueDescending'),
])
dashboard('NXP_Admin_Dashboards', 'NXP_Adoption', 'Nexus: Adoption and GovWin cut-over', 'Weekly active users, saved searches per user, where pushes come from, and the GovWin parallel-run catch rate.', [
    comp(0, 0, 4, 3, 'Metric', a('NXP_Active_Users_This_Week'), 'Active users this week'),
    comp(0, 3, 4, 3, 'Metric', a('NXP_Searches_By_User'), 'Active saved searches'),
    comp(0, 6, 4, 3, 'Metric', a('NXP_GovWin_Caught'), 'GovWin alerts caught by a search'),
    comp(0, 9, 4, 3, 'Metric', a('NXP_GovWin_All'), 'GovWin alerts loaded'),
    comp(4, 0, 8, 6, 'Column', a('NXP_Active_Users_By_Week'), 'Weekly active users'),
    comp(4, 6, 8, 6, 'Donut', a('NXP_GovWin_Catch_Rate'), 'GovWin parallel run: did Nexus catch it?'),
    comp(12, 0, 8, 6, 'Bar', a('NXP_Searches_By_User'), 'Saved searches per user', 'RowValueDescending'),
    comp(12, 6, 8, 6, 'Bar', a('NXP_Pushes_By_Source'), 'Where pushes come from (30 days)', 'RowValueDescending'),
    comp(20, 0, 8, 12, 'Table', a('NXP_Activity_By_User'), 'Screen views by user (30 days)', 'RowValueDescending'),
])
print(len(REPORTS), 'reports')
