/**
 * Daily "problems" e-mail for Nexus admins, so silent failures are caught without opening the
 * Feed Console and Inbound Emails every day. Covers the last 24 hours:
 *   - eBuy e-mails Rejected or Failed, and ones still Needs Review after a day
 *   - no eBuy e-mail at all for Ebuy_Silence_Days (forwarding usually broke)
 *   - failed feed runs, and active feeds that haven't run for three intervals
 *   - pushes that failed after all retries
 *   - documents the Document Reader couldn't read
 *   - the daily AI limit being used up
 * Settings: Admin_Digest_Mode (Problems = only when something failed, Daily = always, Off),
 * Admin_Digest_Recipients (e-mail addresses; blank = active users with the NXP_Admin permission set).
 * Schedule with NXP_AdminDigestJob.scheduleDefaults() (scripts/post-deploy/schedule-jobs.apex).
 */
public without sharing class NXP_AdminDigestJob implements Schedulable {
    public static final String JOB_NAME = 'NXP Admin Digest';
    private static final Integer MAX_ROWS = 10;

    public class Item {
        public String status;
        public String what;
        public String detail;
        public String link;
    }

    public class Section {
        public String title;
        public String linkLabel;
        public List<Item> items = new List<Item>();
        public Integer more = 0;
    }

    public class Digest {
        public List<Section> sections = new List<Section>();
        public Integer problems = 0;
        public List<String> fine = new List<String>();
    }

    /** Every day at 7:00 in the scheduling user's time zone. */
    public static Id scheduleDefaults() {
        return System.schedule(JOB_NAME, '0 0 7 * * ?', new NXP_AdminDigestJob());
    }

    public void execute(SchedulableContext context) {
        run();
    }

    /** Builds and sends the digest. Returns the number of e-mails sent. */
    public static Integer run() {
        String mode = NXP_Settings.getString('Admin_Digest_Mode', 'Problems');
        if (mode == 'Off') {
            return 0;
        }
        Digest d = build(Datetime.now().addDays(-1));
        if (d.problems == 0 && mode != 'Daily') {
            return 0;
        }
        String subject = d.problems == 0
            ? 'no problems in the last 24 hours'
            : d.problems + (d.problems == 1 ? ' problem' : ' problems') + ' in the last 24 hours';
        String body = html(d);
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<String> addresses = NXP_Text.splitList(NXP_Settings.getString('Admin_Digest_Recipients', ''));
        if (!addresses.isEmpty()) {
            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(addresses);
            msg.setSubject(NXP_Text.truncate('Nexus Pursuit Hub: ' + subject, 255));
            msg.setHtmlBody(body);
            String fromId = NXP_Settings.getString('Alert_OrgWide_Email_Id', null);
            if (String.isNotBlank(fromId)) {
                msg.setOrgWideEmailAddressId(fromId);
            }
            emails.add(msg);
        } else {
            for (Id userId : adminUserIds()) {
                emails.add(NXP_AlertService.email(userId, subject, body));
            }
        }
        NXP_AlertService.sendEmails(emails);
        NXP_Logger.flush();
        return emails.size();
    }

    public static Set<Id> adminUserIds() {
        Set<Id> ids = new Set<Id>();
        for (PermissionSetAssignment a : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'NXP_Admin' AND Assignee.IsActive = TRUE
            LIMIT 200
        ]) {
            ids.add(a.AssigneeId);
        }
        return ids;
    }

    public static Digest build(Datetime since) {
        Digest d = new Digest();
        String base = Url.getOrgDomainUrl().toExternalForm();
        ebuy(d, since, base);
        feeds(d, since, base);
        pushes(d, since, base);
        documents(d, since, base);
        ai(d);
        for (Section s : d.sections) {
            d.problems += s.items.size() + s.more;
        }
        return d;
    }

    private static void ebuy(Digest d, Datetime since, String base) {
        Section s = section('eBuy e-mail', 'Open in Inbound Emails');
        Integer total = 0;
        for (NXP_Inbound_Email__c e : [
            SELECT Id, Subject__c, RFQ_Number__c, Status__c, Status_Detail__c, Received__c
            FROM NXP_Inbound_Email__c
            WHERE
                (Status__c IN ('Rejected', 'Failed')
                AND Received__c >= :since)
                OR (Status__c = 'Needs Review'
                AND Received__c < :since)
            ORDER BY Received__c DESC
            LIMIT 200
        ]) {
            total++;
            if (s.items.size() < MAX_ROWS) {
                s.items.add(
                    item(
                        e.Status__c,
                        (String.isBlank(e.RFQ_Number__c) ? '(no RFQ number)' : e.RFQ_Number__c) +
                            ' · ' +
                            (String.isBlank(e.Subject__c) ? '(no subject)' : e.Subject__c),
                        e.Status__c == 'Needs Review'
                            ? 'Waiting since ' +
                              e.Received__c.format('MMM d h:mm a') +
                              '. ' +
                              firstLine(e.Status_Detail__c)
                            : firstLine(e.Status_Detail__c),
                        base + '/lightning/n/NXP_Inbound_Emails'
                    )
                );
            }
        }
        s.more = total - s.items.size();

        Integer silenceDays = NXP_Settings.getInteger('Ebuy_Silence_Days', 3);
        if (silenceDays != null && silenceDays > 0) {
            List<NXP_Inbound_Email__c> last = [
                SELECT Received__c
                FROM NXP_Inbound_Email__c
                ORDER BY Received__c DESC NULLS LAST
                LIMIT 1
            ];
            // Only once eBuy mail has ever arrived: orgs that don't use eBuy are not warned.
            if (
                !last.isEmpty() &&
                last[0].Received__c != null &&
                last[0].Received__c < Datetime.now().addDays(-silenceDays)
            ) {
                s.items.add(
                    item(
                        'No e-mail',
                        'No eBuy e-mail for ' + silenceDays + ' days',
                        'The last one arrived ' +
                            last[0].Received__c.format('MMM d') +
                            '. Check that eBuy mail is still forwarded to the Nexus eBuy inbox address.',
                        base + '/lightning/n/NXP_Inbound_Emails'
                    )
                );
            }
        }
        Integer ok = [
            SELECT COUNT()
            FROM NXP_Inbound_Email__c
            WHERE Status__c = 'Ingested' AND Received__c >= :since
        ];
        d.fine.add(ok + (ok == 1 ? ' eBuy e-mail' : ' eBuy e-mails') + ' became notices');
        add(d, s);
    }

    private static void feeds(Digest d, Datetime since, String base) {
        Section s = section('Feeds', 'Open the Feed Console');
        Integer total = 0;
        for (NXP_Feed_Run__c r : [
            SELECT Id, Feed_Name__c, Started__c, Error_Log__c
            FROM NXP_Feed_Run__c
            WHERE Status__c = 'Failed' AND Started__c >= :since
            ORDER BY Started__c DESC
            LIMIT 200
        ]) {
            total++;
            if (s.items.size() < MAX_ROWS) {
                s.items.add(
                    item(
                        'Failed',
                        r.Feed_Name__c + ' · ' + r.Started__c.format('MMM d h:mm a') + ' run',
                        firstLine(r.Error_Log__c),
                        base + '/lightning/n/NXP_Feed_Console'
                    )
                );
            }
        }
        s.more = total - s.items.size();

        // Active scheduled feeds that haven't started for three intervals.
        Map<String, Datetime> lastStart = new Map<String, Datetime>();
        for (AggregateResult ar : [
            SELECT Feed_Name__c feedName, MAX(Started__c) lastStarted
            FROM NXP_Feed_Run__c
            GROUP BY Feed_Name__c
        ]) {
            lastStart.put((String) ar.get('feedName'), (Datetime) ar.get('lastStarted'));
        }
        for (NXP_Feed_Config__mdt c : NXP_Feed_Config__mdt.getAll().values()) {
            if (!c.Active__c || c.Channel__c == 'Apex REST') {
                continue;
            }
            Integer interval = c.Interval_Minutes__c == null ? 60 : c.Interval_Minutes__c.intValue();
            Datetime last = lastStart.get(c.DeveloperName);
            if (last == null || last < Datetime.now().addMinutes(-3 * interval)) {
                s.items.add(
                    item(
                        'Not running',
                        c.MasterLabel + ' has not run' + (last == null ? '' : ' since ' + last.format('MMM d h:mm a')),
                        'It is active and should run every ' +
                            interval +
                            ' minutes. Check Setup > Scheduled Jobs for NXP Feed Scheduler.',
                        base + '/lightning/n/NXP_Feed_Console'
                    )
                );
            }
        }
        Integer ok = [SELECT COUNT() FROM NXP_Feed_Run__c WHERE Status__c = 'Succeeded' AND Started__c >= :since];
        d.fine.add(ok + (ok == 1 ? ' feed run' : ' feed runs') + ' succeeded');
        add(d, s);
    }

    private static void pushes(Digest d, Datetime since, String base) {
        Section s = section('Pushes to Opportunity', 'Open the push log');
        Integer total = 0;
        for (NXP_Push_Log__c l : [
            SELECT Id, Gov_Notice__r.Title__c, Attempts__c, Error__c, CreatedDate
            FROM NXP_Push_Log__c
            WHERE Status__c = 'Failed' AND LastModifiedDate >= :since
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ]) {
            total++;
            if (s.items.size() < MAX_ROWS) {
                s.items.add(
                    item(
                        'Failed',
                        l.Gov_Notice__r == null || String.isBlank(l.Gov_Notice__r.Title__c)
                            ? 'Push'
                            : l.Gov_Notice__r.Title__c,
                        firstLine(l.Error__c) +
                        (l.Attempts__c == null ? '' : ' ' + l.Attempts__c.intValue() + ' tries.'),
                        base + '/' + l.Id
                    )
                );
            }
        }
        s.more = total - s.items.size();
        Integer ok = [
            SELECT COUNT()
            FROM NXP_Push_Log__c
            WHERE Status__c IN ('Success', 'Linked Existing') AND CreatedDate >= :since
        ];
        d.fine.add(ok + (ok == 1 ? ' push' : ' pushes') + ' succeeded');
        add(d, s);
    }

    private static void documents(Digest d, Datetime since, String base) {
        Section s = section('Document Reader', 'Open the notice');
        Integer total = 0;
        for (NXP_Document_Analysis__c a : [
            SELECT Id, File_Name__c, Gov_Notice__c, Gov_Notice__r.Title__c, Status_Detail__c
            FROM NXP_Document_Analysis__c
            WHERE Status__c = 'Failed' AND Analyzed__c >= :since
            ORDER BY Analyzed__c DESC
            LIMIT 200
        ]) {
            total++;
            if (s.items.size() < MAX_ROWS) {
                s.items.add(
                    item(
                        'Not read',
                        a.File_Name__c + (a.Gov_Notice__r == null ? '' : ' · ' + a.Gov_Notice__r.Title__c),
                        firstLine(a.Status_Detail__c),
                        base + '/' + a.Gov_Notice__c
                    )
                );
            }
        }
        s.more = total - s.items.size();
        add(d, s);
    }

    private static void ai(Digest d) {
        Integer cap = NXP_Settings.getInteger('AI_Max_Calls_Per_Day', 500);
        NXP_AI_Usage__c u = NXP_AI_Usage__c.getOrgDefaults();
        if (cap == null || cap <= 0 || u == null || u.Day__c == null || u.Calls__c == null) {
            return;
        }
        if (u.Day__c >= Date.today().addDays(-1) && u.Calls__c >= cap) {
            Section s = section('AI', null);
            s.items.add(
                item(
                    'Limit reached',
                    'The daily AI limit of ' + cap + ' calls was used up on ' + u.Day__c.format(),
                    'Summaries and document reading waited for the next day. Raise AI_Max_Calls_Per_Day if this keeps happening.',
                    null
                )
            );
            add(d, s);
        }
    }

    // ------------------------------------------------------------------ e-mail body

    public static String html(Digest d) {
        String h = '<div style="font-family:Arial,sans-serif;font-size:14px;color:#181818;max-width:720px">';
        if (d.problems == 0) {
            h += '<p style="font-size:16px"><strong>No problems in the last 24 hours.</strong></p>';
        } else {
            h +=
                '<p style="font-size:16px;border-left:4px solid #C23934;padding-left:10px"><strong>' +
                d.problems +
                (d.problems == 1 ? ' thing needs' : ' things need') +
                ' a look</strong> (last 24 hours)</p>';
        }
        for (Section s : d.sections) {
            h += '<h3 style="margin:18px 0 6px;font-size:15px">' + esc(s.title) + '</h3>';
            h += '<table style="border-collapse:collapse;width:100%">';
            for (Item i : s.items) {
                h +=
                    '<tr style="border-top:1px solid #EEF1F6"><td style="padding:6px 8px 6px 0;white-space:nowrap;vertical-align:top">' +
                    '<span style="background:#FDECEC;color:#8E1B1B;border-radius:4px;padding:2px 6px;font-size:12px;font-weight:bold">' +
                    esc(i.status) +
                    '</span></td><td style="padding:6px 8px 6px 0">' +
                    esc(i.what) +
                    (String.isBlank(i.detail)
                        ? ''
                        : '<div style="color:#5C6B80;font-size:12px">' + esc(i.detail) + '</div>') +
                    '</td><td style="padding:6px 0;text-align:right;white-space:nowrap;vertical-align:top">' +
                    (i.link == null ||
                        s.linkLabel == null
                        ? ''
                        : '<a href="' + esc(i.link) + '">' + esc(s.linkLabel) + '</a>') +
                    '</td></tr>';
            }
            h += '</table>';
            if (s.more > 0) {
                h += '<p style="color:#5C6B80;font-size:12px">and ' + s.more + ' more</p>';
            }
        }
        if (!d.fine.isEmpty()) {
            h +=
                '<p style="background:#F4F6F9;border-radius:6px;padding:10px 12px;margin-top:18px"><strong>Also checked:</strong> ' +
                esc(String.join(d.fine, ' · ')) +
                '.</p>';
        }
        h += '<p style="color:#5C6B80;font-size:12px">Sent to Nexus admins. Change who gets it and when in Setup &gt; Custom Metadata Types &gt; NXP Setting: Admin_Digest_Mode, Admin_Digest_Recipients, Ebuy_Silence_Days.</p></div>';
        return h;
    }

    private static Section section(String title, String linkLabel) {
        Section s = new Section();
        s.title = title;
        s.linkLabel = linkLabel;
        return s;
    }

    private static void add(Digest d, Section s) {
        if (!s.items.isEmpty()) {
            d.sections.add(s);
        }
    }

    private static Item item(String status, String what, String detail, String link) {
        Item i = new Item();
        i.status = status;
        i.what = what;
        i.detail = detail;
        i.link = link;
        return i;
    }

    private static String firstLine(String text) {
        if (String.isBlank(text)) {
            return '';
        }
        return text.trim().split('\n')[0].left(240);
    }

    private static String esc(String text) {
        return text == null ? '' : text.escapeHtml4();
    }
}
