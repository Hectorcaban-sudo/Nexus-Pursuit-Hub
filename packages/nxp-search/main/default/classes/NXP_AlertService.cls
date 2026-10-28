/**
 * Sends saved-search alerts. Channels:
 *   Salesforce - custom notification (NXP_Match_Alert): bell, mobile push, and Slack/Teams when the
 *                org's Salesforce-for-Slack / Teams integration forwards notifications
 *   Email      - one email per search (real time) or one digest per user (daily/weekly)
 * Slack and Teams selections are honoured through the Salesforce notification channel; see
 * docs/guides/admin-guide.md.
 */
public without sharing class NXP_AlertService {
    private static Id notificationTypeId;

    public static void sendRealTime(
        List<NXP_Search_Match__c> matches,
        Map<Id, NXP_Saved_Search__c> searches,
        Map<Id, NXP_Gov_Notice__c> notices
    ) {
        Map<Id, List<NXP_Search_Match__c>> bySearch = new Map<Id, List<NXP_Search_Match__c>>();
        for (NXP_Search_Match__c m : matches) {
            NXP_Saved_Search__c s = searches.get(m.Saved_Search__c);
            if (s == null || s.Alert_Frequency__c != 'Real Time' || m.Alert_Status__c != 'Pending') {
                continue;
            }
            if (!bySearch.containsKey(s.Id)) {
                bySearch.put(s.Id, new List<NXP_Search_Match__c>());
            }
            bySearch.get(s.Id).add(m);
        }
        if (bySearch.isEmpty()) {
            return;
        }
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<NXP_Search_Match__c> sent = new List<NXP_Search_Match__c>();
        for (Id searchId : bySearch.keySet()) {
            NXP_Saved_Search__c s = searches.get(searchId);
            List<NXP_Search_Match__c> ms = bySearch.get(searchId);
            Set<String> channels = channelSet(s.Channels__c);
            if (
                channels.contains('Salesforce') ||
                channels.contains('Slack') ||
                channels.contains('Teams') ||
                channels.contains('Mobile')
            ) {
                for (NXP_Search_Match__c m : ms) {
                    NXP_Gov_Notice__c n = notices.get(m.Gov_Notice__c);
                    String verb = m.Change_Type__c == 'New' ? 'New match' : 'Updated (' + m.Change_Type__c + ')';
                    notify(s.OwnerId, verb + ' · ' + s.Name, n == null ? '' : summaryLine(n), m.Gov_Notice__c);
                }
            }
            if (channels.isEmpty() || channels.contains('Email')) {
                emails.add(
                    email(
                        s.OwnerId,
                        ms.size() + ' new or updated match(es): ' + s.Name,
                        digestHtml(
                            new List<NXP_Saved_Search__c>{ s },
                            new Map<Id, List<NXP_Search_Match__c>>{ s.Id => ms },
                            notices
                        )
                    )
                );
            }
            for (NXP_Search_Match__c m : ms) {
                sent.add(new NXP_Search_Match__c(Id = m.Id, Alert_Status__c = 'Sent'));
            }
        }
        sendEmails(emails);
        Database.update(sent, false, AccessLevel.SYSTEM_MODE);
    }

    /** Alerts users who follow a notice when it changes (not when it is first created). */
    public static void sendFollowAlerts(
        Map<Id, String> changeTypes,
        Set<Id> newIds,
        Map<Id, NXP_Gov_Notice__c> notices
    ) {
        Set<Id> changed = new Set<Id>(changeTypes.keySet());
        changed.removeAll(newIds);
        if (changed.isEmpty()) {
            return;
        }
        for (NXP_Follow__c f : [
            SELECT OwnerId, Gov_Notice__c
            FROM NXP_Follow__c
            WHERE Gov_Notice__c IN :changed
            LIMIT 5000
        ]) {
            NXP_Gov_Notice__c n = notices.get(f.Gov_Notice__c);
            notify(
                f.OwnerId,
                'Followed notice changed: ' + changeTypes.get(f.Gov_Notice__c),
                n == null ? '' : summaryLine(n),
                f.Gov_Notice__c
            );
        }
    }

    public static String summaryLine(NXP_Gov_Notice__c n) {
        List<String> parts = new List<String>{ n.Title__c == null ? n.Name : n.Title__c };
        if (String.isNotBlank(n.Agency_Path__c)) {
            parts.add(n.Agency_Path__c);
        }
        if (n.Response_Due__c != null) {
            parts.add('due ' + n.Response_Due__c.format('MMM d, yyyy'));
        }
        if (n.Fit_Score__c != null) {
            parts.add('fit ' + n.Fit_Score__c);
        }
        return NXP_Text.truncate(String.join(parts, ' · '), 750);
    }

    public static String digestHtml(
        List<NXP_Saved_Search__c> searches,
        Map<Id, List<NXP_Search_Match__c>> matchesBySearch,
        Map<Id, NXP_Gov_Notice__c> notices
    ) {
        String base = URL.getOrgDomainUrl().toExternalForm();
        String html = '<div style="font-family:Arial,sans-serif;font-size:14px;color:#181818">';
        for (NXP_Saved_Search__c s : searches) {
            List<NXP_Search_Match__c> ms = matchesBySearch.get(s.Id);
            if (ms == null || ms.isEmpty()) {
                continue;
            }
            html +=
                '<h2 style="font-size:16px;color:#032D60;margin:20px 0 8px">' +
                s.Name.escapeHtml4() +
                ' (' +
                ms.size() +
                ')</h2>';
            for (NXP_Search_Match__c m : ms) {
                NXP_Gov_Notice__c n = notices.get(m.Gov_Notice__c);
                if (n == null) {
                    continue;
                }
                String link = base + '/lightning/r/NXP_Gov_Notice__c/' + n.Id + '/view';
                html +=
                    '<div style="border:1px solid #DDDBDA;border-radius:6px;padding:10px 12px;margin:0 0 8px">' +
                    '<a href="' +
                    link +
                    '" style="font-weight:bold;color:#0B5CAB;text-decoration:none">' +
                    (n.Title__c == null ? n.Name : n.Title__c).escapeHtml4() +
                    '</a>' +
                    '<div style="color:#5C6B80;margin-top:4px">' +
                    summaryLine(n).escapeHtml4() +
                    '</div>' +
                    (m.Change_Type__c == 'New' ||
                        m.Change_Type__c == null
                        ? ''
                        : '<div style="color:#8A4B00;margin-top:4px">Changed: ' +
                          m.Change_Type__c.escapeHtml4() +
                          '</div>') +
                    (String.isBlank(n.AI_Summary__c)
                        ? ''
                        : '<p style="margin:6px 0 0">' +
                          NXP_Text.truncate(n.AI_Summary__c, 400).escapeHtml4() +
                          '</p>') +
                    '</div>';
            }
        }
        html += '<p style="color:#5C6B80;font-size:12px">Open the Match Inbox in Nexus Pursuit Hub to push, watch or dismiss these notices.</p></div>';
        return html;
    }

    public static Messaging.SingleEmailMessage email(Id userId, String subject, String html) {
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setTargetObjectId(userId);
        msg.setSaveAsActivity(false);
        msg.setSubject(NXP_Text.truncate('Nexus Pursuit Hub: ' + subject, 255));
        msg.setHtmlBody(html);
        String fromId = NXP_Settings.getString('Alert_OrgWide_Email_Id', null);
        if (String.isNotBlank(fromId)) {
            msg.setOrgWideEmailAddressId(fromId);
        }
        return msg;
    }

    public static void sendEmails(List<Messaging.SingleEmailMessage> emails) {
        if (emails.isEmpty()) {
            return;
        }
        try {
            Messaging.sendEmail(emails, false);
        } catch (Exception e) {
            NXP_Logger.error('NXP_AlertService', 'Alert email failed', e, null);
        }
    }

    public static void notify(Id userId, String title, String body, Id targetId) {
        Id typeId = notificationType();
        if (typeId == null || userId == null) {
            return;
        }
        try {
            Messaging.CustomNotification n = new Messaging.CustomNotification();
            n.setNotificationTypeId(typeId);
            n.setTitle(NXP_Text.truncate(title, 250));
            n.setBody(String.isBlank(body) ? ' ' : body);
            n.setTargetId(targetId);
            n.send(new Set<String>{ String.valueOf(userId) });
        } catch (Exception e) {
            NXP_Logger.warn('NXP_AlertService', 'Custom notification failed: ' + e.getMessage());
        }
    }

    private static Set<String> channelSet(String multi) {
        return String.isBlank(multi) ? new Set<String>() : new Set<String>(multi.split(';'));
    }

    private static Id notificationType() {
        if (notificationTypeId == null) {
            List<CustomNotificationType> types = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = 'NXP_Match_Alert'
                LIMIT 1
            ];
            notificationTypeId = types.isEmpty() ? null : types[0].Id;
        }
        return notificationTypeId;
    }
}
