/**
 * Downloads a notice's SAM.gov attachments (the resourceLinks the feed stores in Resource_Links__c)
 * into Salesforce Files on the notice, where the Document Reader picks up the PDFs.
 *
 * Which notices: Files_Pending__c and either Files_Requested__c (Get SAM.gov files on the notice
 * page) or, while Files_Auto_Download is on, notices that matched a saved search (AI summary
 * requested) or score at least Files_Min_Fit. At most Files_Max_Per_Notice files per notice; files
 * over Files_Max_MB are skipped and stay available on SAM.gov. Amendments download only new links
 * (Files_Fetched__c lists the links already handled).
 *
 * One file per run, to stay inside the 12 MB heap of an asynchronous job, chaining to the next.
 * Each file: one call to sam.gov (Named Credential NXP_SAM_Files), which normally redirects to file
 * storage; that host needs a Remote Site Setting (NXP_SAM_File_Storage ships for s3.amazonaws.com).
 * A short Range request reads the size before the file is downloaded.
 */
public without sharing class NXP_SamFileJob implements Queueable, Database.AllowsCallouts {
    public static final String NAMED_CREDENTIAL = 'NXP_SAM_Files';
    private static final Integer MAX_REDIRECTS = 3;

    public class FileTooLargeException extends Exception {
    }

    public class Download {
        public String fileName;
        public Blob body;
        public Integer size;
    }

    private final List<Id> queue;

    /** Every notice that qualifies (see the class comment). */
    public NXP_SamFileJob() {
        this(null);
    }

    /** These notices, in this order. */
    public NXP_SamFileJob(List<Id> noticeIds) {
        this.queue = noticeIds;
    }

    public static List<Id> pendingIds() {
        String soql = 'SELECT Id FROM NXP_Gov_Notice__c WHERE Files_Pending__c = TRUE AND (Files_Requested__c = TRUE';
        Map<String, Object> binds = new Map<String, Object>();
        if (NXP_Settings.getBoolean('Files_Auto_Download', true)) {
            soql += ' OR Fit_Score__c >= :minFit OR AI_Summary_Status__c IN :requested';
            binds.put('minFit', NXP_Settings.getInteger('Files_Min_Fit', 70));
            binds.put('requested', new List<String>{ 'Pending', 'Complete', 'Failed' });
        }
        soql += ') ORDER BY Files_Requested__c DESC, Fit_Score__c DESC NULLS LAST LIMIT 200';
        List<Id> ids = new List<Id>();
        for (
            NXP_Gov_Notice__c n : (List<NXP_Gov_Notice__c>) Database.queryWithBinds(
                soql,
                binds,
                AccessLevel.SYSTEM_MODE
            )
        ) {
            ids.add(n.Id);
        }
        return ids;
    }

    /** Starts the job when anything is waiting and this transaction can still queue one. */
    public static Boolean startIfNeeded() {
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return false;
        }
        List<Id> ids = pendingIds();
        if (ids.isEmpty()) {
            return false;
        }
        System.enqueueJob(new NXP_SamFileJob(ids));
        return true;
    }

    public void execute(QueueableContext context) {
        List<Id> todo = queue == null ? pendingIds() : new List<Id>(queue);
        // One file per run: a callout can't follow the file save in the same transaction.
        if (!todo.isEmpty()) {
            Id noticeId = todo[0];
            Plan p = plan(noticeId);
            List<Id> next = new List<Id>(todo);
            if (!p.more) {
                next.remove(0);
            }
            try {
                step(p);
            } catch (NXP_HttpClient.CalloutFailureException e) {
                // 429: the SAM.gov daily or hourly limit. Stop; files wait for the next feed run.
                NXP_Logger.warn('NXP_SamFileJob', 'SAM.gov limit reached, files wait: ' + e.getMessage());
                NXP_Logger.flush();
                return;
            }
            // When the Document Reader already used this job's one child Queueable for the new file,
            // the chain stops here and the next feed run carries on.
            if (
                !Test.isRunningTest() &&
                !next.isEmpty() &&
                Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()
            ) {
                System.enqueueJob(new NXP_SamFileJob(next));
            }
        }
        NXP_Logger.flush();
    }

    /** What to do next for one notice. */
    @TestVisible
    private class Plan {
        NXP_Gov_Notice__c notice;
        List<String> links = new List<String>();
        List<String> done = new List<String>();
        String link;
        Boolean more = false;
        Boolean capped = false;
    }

    @TestVisible
    private static Plan plan(Id noticeId) {
        Plan p = new Plan();
        p.notice = new NXP_GovNoticeSelector(AccessLevel.SYSTEM_MODE).byId(noticeId);
        if (p.notice == null) {
            return p;
        }
        p.links = lines(p.notice.Resource_Links__c);
        p.done = lines(p.notice.Files_Fetched__c);
        Set<String> doneSet = new Set<String>(p.done);
        List<String> todo = new List<String>();
        for (String link : p.links) {
            if (!doneSet.contains(link)) {
                todo.add(link);
            }
        }
        Integer maxFiles = NXP_Settings.getInteger('Files_Max_Per_Notice', 10);
        p.capped = !todo.isEmpty() && p.done.size() >= maxFiles;
        if (!todo.isEmpty() && !p.capped) {
            p.link = todo[0];
            p.more = todo.size() > 1 && p.done.size() + 1 < maxFiles;
        }
        return p;
    }

    /** Downloads the planned file (if any) and records the result on the notice. Throws on HTTP 429. */
    @TestVisible
    private static void step(Plan p) {
        NXP_Gov_Notice__c n = p.notice;
        if (n == null) {
            return;
        }
        if (p.link == null) {
            String status = p.capped
                ? 'Downloaded the first ' +
                  p.done.size() +
                  ' of ' +
                  p.links.size() +
                  ' files (Files_Max_Per_Notice). Open SAM.gov for the rest.'
                : n.Files_Status__c;
            save(
                new NXP_Gov_Notice__c(
                    Id = n.Id,
                    Files_Pending__c = false,
                    Files_Requested__c = false,
                    Files_Status__c = status == null ? null : status.left(255)
                )
            );
            return;
        }

        String note;
        try {
            Download d = download(p.link, NXP_Settings.getInteger('Files_Max_MB', 6) * 1024 * 1024);
            insert new ContentVersion(
                Title = d.fileName.contains('.') ? d.fileName.substringBeforeLast('.') : d.fileName,
                PathOnClient = d.fileName,
                VersionData = d.body,
                FirstPublishLocationId = n.Id
            );
        } catch (FileTooLargeException e) {
            note = e.getMessage();
        } catch (NXP_HttpClient.CalloutFailureException e) {
            if (e.statusCode == 429) {
                throw e;
            }
            note = 'A file could not be downloaded: ' + e.getMessage().left(150);
        } catch (CalloutException e) {
            // Usually a file host that isn't allowed yet: the message names it (add a Remote Site Setting).
            note = 'A file could not be downloaded: ' + e.getMessage().left(150);
        }
        if (note != null) {
            NXP_Logger.warn('NXP_SamFileJob', n.Notice_Id__c + ': ' + note);
        }
        p.done.add(p.link);
        Integer filesHere = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :n.Id];
        String status =
            filesHere +
            (filesHere == 1 ? ' file' : ' files') +
            ' on the notice; ' +
            p.done.size() +
            ' of ' +
            p.links.size() +
            ' SAM.gov files handled' +
            (note == null ? '.' : '. ' + note);
        save(
            new NXP_Gov_Notice__c(
                Id = n.Id,
                Files_Fetched__c = String.join(p.done, '\n').left(32768),
                Files_Pending__c = p.more,
                Files_Requested__c = p.more && n.Files_Requested__c == true,
                Files_Status__c = status.left(255)
            )
        );
    }

    /** Downloads one SAM.gov file, following redirects. Throws FileTooLargeException over maxBytes. */
    public static Download download(String link, Integer maxBytes) {
        String host = link.substringAfter('://').substringBefore('/').toLowerCase();
        String url = host == 'sam.gov' ||
            host == 'www.sam.gov'
            ? 'callout:' + NAMED_CREDENTIAL + '/' + link.substringAfter('://').substringAfter('/')
            : link;

        // 1. Ask for the first byte only: the reply gives the size and the file name.
        HttpResponse probe = follow(url, true);
        Download d = new Download();
        d.fileName = fileName(probe.getHeader('Content-Disposition'), link);
        if (probe.getStatusCode() == 200) {
            // The server ignored the range and sent the whole file.
            d.body = probe.getBodyAsBlob();
            d.size = d.body.size();
        } else {
            d.size = totalSize(probe.getHeader('Content-Range'));
            if (d.size != null && d.size > maxBytes) {
                throw new FileTooLargeException(
                    d.fileName +
                        ' is ' +
                        (d.size / 1048576) +
                        ' MB, over the ' +
                        (maxBytes / 1048576) +
                        ' MB limit (Files_Max_MB).'
                );
            }
            // 2. The whole file, from where the redirect pointed.
            HttpResponse full = follow(finalUrl, false);
            d.body = full.getBodyAsBlob();
            d.size = d.body.size();
        }
        if (d.size > maxBytes) {
            throw new FileTooLargeException(
                d.fileName + ' is over the ' + (maxBytes / 1048576) + ' MB limit (Files_Max_MB).'
            );
        }
        return d;
    }

    private static String finalUrl;

    private static HttpResponse follow(String url, Boolean firstByteOnly) {
        String current = url;
        for (Integer i = 0; i <= MAX_REDIRECTS; i++) {
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setEndpoint(current);
            req.setTimeout(120000);
            if (firstByteOnly) {
                req.setHeader('Range', 'bytes=0-0');
            }
            HttpResponse res = new Http().send(req);
            Integer code = res.getStatusCode();
            if (code >= 300 && code < 400 && String.isNotBlank(res.getHeader('Location'))) {
                current = res.getHeader('Location');
                continue;
            }
            if (code == 200 || code == 206) {
                finalUrl = current;
                return res;
            }
            NXP_HttpClient.CalloutFailureException e = new NXP_HttpClient.CalloutFailureException(
                'HTTP ' + code + ' from ' + current.substringBefore('?')
            );
            e.statusCode = code;
            throw e;
        }
        throw new CalloutException('Too many redirects for ' + url.substringBefore('?'));
    }

    @TestVisible
    private static String fileName(String disposition, String link) {
        if (String.isNotBlank(disposition)) {
            Matcher m = Pattern.compile('(?i)filename\\*?=(?:UTF-8\'\')?"?([^";]+)"?').matcher(disposition);
            if (m.find()) {
                String name = EncodingUtil.urlDecode(m.group(1).trim(), 'UTF-8');
                if (String.isNotBlank(name)) {
                    return name.left(250);
                }
            }
        }
        String id = link.substringBefore('?').removeEnd('/download').substringAfterLast('/');
        return ('SAM.gov file ' + id.left(12)).trim();
    }

    @TestVisible
    private static Integer totalSize(String contentRange) {
        // "bytes 0-0/123456"
        if (String.isBlank(contentRange) || !contentRange.contains('/')) {
            return null;
        }
        String total = contentRange.substringAfterLast('/').trim();
        return total.isNumeric() ? Integer.valueOf(total) : null;
    }

    private static List<String> lines(String text) {
        List<String> out = new List<String>();
        if (String.isBlank(text)) {
            return out;
        }
        for (String l : text.split('\n')) {
            if (String.isNotBlank(l)) {
                out.add(l.trim());
            }
        }
        return out;
    }

    private static void save(NXP_Gov_Notice__c n) {
        NXP_TriggerHandler.bypass('NXP_GovNoticeTriggerHandler');
        Database.update(n, AccessLevel.SYSTEM_MODE);
        NXP_TriggerHandler.clearBypass('NXP_GovNoticeTriggerHandler');
    }
}
